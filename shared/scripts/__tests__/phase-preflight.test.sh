#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

PRE="$here/../phase-preflight"
FIX="$here/fixtures"

# The slug of phase 2 in the session-tracker fixture. Written out once here so
# every branch-collision test names the same branch the script will compute.
P2_BRANCH='phase-2-shell-surface-model-structure-no-visual-change'

run_in() {
  dir=$1
  shift
  set +e
  OUT=$(cd "$dir" && "$@" 2>&1)
  RC=$?
  set -e
}

# new_repo — a throwaway repository on branch main with the fixture spec
# committed as spec-design.md. Prints its resolved absolute path.
# `symbolic-ref` before the first commit forces the branch name regardless of
# the machine's init.defaultBranch, so the trunk-detection tests are stable.
# `pwd -P` resolves /var → /private/var on macOS; bash's `cd` keeps the logical
# path it was given, so the flag is what does the resolving.
new_repo() {
  d=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name Test
  git -C "$d" symbolic-ref HEAD refs/heads/main
  cp "$FIX/session-tracker-headings.md" "$d/spec-design.md"
  git -C "$d" add -A
  git -C "$d" commit -qm init
  printf '%s\n' "$d"
}

repos=""
cleanup() { for r in $repos; do rm -rf "$r"; done; }
trap cleanup EXIT
track() { repos="$repos $1"; }

# --- the happy path --------------------------------------------------------

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/spec-design.md" feat/tracker '2 to 6'
assert_rc 0 'happy path: exits 0'
assert_contains 'preflight ok' "$OUT" 'happy path: reports ok'
assert_eq 'feat/tracker' "$(git -C "$r" rev-parse --abbrev-ref HEAD)" \
  'happy path: created the base branch and switched to it'
assert_eq 'yes' "$([ -d "$r/.superpowers/phase-orchestrator/spec-design" ] && echo yes || echo no)" \
  'happy path: created the run directory'

# Idempotent: running it again on the now-existing base branch must succeed.
run_in "$r" "$PRE" "$r/spec-design.md" feat/tracker '2 to 6'
assert_rc 0 'second run on an existing base: exits 0'
assert_eq 'feat/tracker' "$(git -C "$r" rev-parse --abbrev-ref HEAD)" \
  'second run: still on the base branch'

# --- refusals, one per check ----------------------------------------------

run_in "$(dirname "$r")" "$PRE"
assert_rc 2 'no arguments: exits 2'
assert_contains 'usage:' "$OUT" 'no arguments: prints usage'

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/absent-design.md" feat/x all
assert_rc 2 'missing design document: exits 2'
assert_contains 'no such design document' "$OUT" 'missing document: message names the problem'

outside=$(cd "$(mktemp -d)" && pwd -P); track "$outside"
cp "$FIX/session-tracker-headings.md" "$outside/spec-design.md"
run_in "$outside" "$PRE" "$outside/spec-design.md" feat/x all
assert_rc 10 'outside a git repository: exits 10'
assert_contains 'not inside a git repository' "$OUT" 'outside a repo: message names the problem'

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/spec-design.md" main all
assert_rc 12 'base is main: exits 12'
assert_contains 'refusing to run against trunk' "$OUT" 'base main: message names the problem'
assert_eq 'main' "$(git -C "$r" rev-parse --abbrev-ref HEAD)" \
  'base main: refused before touching git state'

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/spec-design.md" master all
assert_rc 12 'base is master: exits 12'

r=$(new_repo); track "$r"
printf 'uncommitted\n' > "$r/stray.txt"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x all
assert_rc 11 'dirty working tree: exits 11'
assert_contains 'working tree not clean' "$OUT" 'dirty tree: message names the problem'

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x '2-99'
assert_rc 4 'absent phase number: exits 4'
assert_contains '99' "$OUT" 'absent phase: message names the missing number'
assert_eq 'main' "$(git -C "$r" rev-parse --abbrev-ref HEAD)" \
  'absent phase: refused before creating the base branch'

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x 'two'
assert_rc 2 'malformed range: exits 2'

r=$(new_repo); track "$r"
cp "$FIX/no-phases.md" "$r/spec-design.md"
git -C "$r" commit -qam 'no phases'
run_in "$r" "$PRE" "$r/spec-design.md" feat/x all
assert_rc 3 'document with no phase headings: exits 3'

# No main and no master to branch from.
r=$(new_repo); track "$r"
git -C "$r" branch -m main trunkless
run_in "$r" "$PRE" "$r/spec-design.md" feat/x all
assert_rc 13 'no main or master to create the base from: exits 13'
assert_contains 'does not exist' "$OUT" 'no trunk: message names the problem'

# --- check 7: phase branch with no ledger entry ---------------------------

r=$(new_repo); track "$r"
git -C "$r" branch "$P2_BRANCH"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x '2-3'
assert_rc 14 'unexplained phase branch: exits 14'
assert_contains "$P2_BRANCH" "$OUT" 'unexplained branch: message names the branch'
assert_contains 'ledger' "$OUT" 'unexplained branch: message explains why it was refused'

# Same branch, but this spec's ledger accounts for phase 2: reuse, do not refuse.
# The .gitignore is written alongside the ledger because the clean-tree check
# runs before phase-run-dir does: a hand-made .superpowers/ with nothing ignoring
# it is untracked content, and preflight would refuse with 11 for that reason
# instead of reaching the check under test. A real resume always has it already.
r=$(new_repo); track "$r"
git -C "$r" branch "$P2_BRANCH"
led="$r/.superpowers/phase-orchestrator/spec-design"
mkdir -p "$led"
printf '*\n' > "$r/.superpowers/phase-orchestrator/.gitignore"
{
  printf '# Phase run — spec: %s/spec-design.md\n' "$r"
  printf '# base: feat/x  requested: 2-3\n\n'
  printf 'phase 2 (Shell & surface model): plan docs/plans/p2.md\n'
} > "$led/run.md"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x '2-3'
assert_rc 0 'phase branch with a matching ledger entry: exits 0'

# A branch for a phase the ledger does not mention is still refused, even when
# a ledger exists for other phases.
r=$(new_repo); track "$r"
git -C "$r" branch "$P2_BRANCH"
led="$r/.superpowers/phase-orchestrator/spec-design"
mkdir -p "$led"
printf '*\n' > "$r/.superpowers/phase-orchestrator/.gitignore"
{
  printf '# Phase run — spec: %s/spec-design.md\n' "$r"
  printf '# base: feat/x  requested: 3\n\n'
  printf 'phase 3 (Takeovers): plan docs/plans/p3.md\n'
} > "$led/run.md"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x '2-3'
assert_rc 14 'ledger mentions another phase only: still exits 14'

# Identity refusals happen before changing branches or overwriting the ledger.
r=$(new_repo); track "$r"
run_in "$r" "$PRE" spec-design.md feat/first 2
assert_rc 0 'relative spec path: initializes identity'
led="$r/.superpowers/phase-orchestrator/spec-design/run.md"
saved=$(cat "$led")
run_in "$r" "$PRE" "$r/spec-design.md" feat/second 2
assert_rc 15 'same spec on another base: refused'
assert_eq 'feat/first' "$(git -C "$r" branch --show-current)" 'identity refusal leaves branch unchanged'
assert_eq "$saved" "$(cat "$led")" 'identity refusal preserves ledger'
run_in "$r" "$PRE" "$r/spec-design.md" feat/first 2
assert_rc 0 'absolute path resumes relative-path invocation'

mkdir "$r/other"
cp "$r/spec-design.md" "$r/other/spec-design.md"
git -C "$r" add other
git -C "$r" commit -qm 'another spec with the same basename'
run_in "$r" "$PRE" "$r/other/spec-design.md" feat/first 2
assert_rc 15 'same basename, different spec: refused'
assert_eq "$saved" "$(cat "$led")" 'basename collision preserves ledger'

# --- PHASE_BASE_CHECKOUT=worktree ------------------------------------------
# Base gets its own worktree, <main checkout>/.worktrees/base. The main
# checkout is never switched and never has to be clean; the document is read
# from base's copy, so the owner can move the main checkout mid-run.

wt_pre() { # wt_pre DIR ARGS… — preflight as the parallel skill's wrapper runs it
  dir=$1
  shift
  run_in "$dir" env PHASE_BASE_CHECKOUT=worktree PHASE_RUN_ANCHOR=main \
    PHASE_RUN_NAMESPACE=phase-parallel "$PRE" "$@"
}

r=$(new_repo); track "$r"
bw="$r/.worktrees/base"
printf 'work in progress\n' > "$r/stray.txt"
wt_pre "$r" "$r/spec-design.md" feat/tracker '2 to 6'
assert_rc 0 'worktree mode: a dirty main checkout does not refuse the run'
assert_eq 'main' "$(git -C "$r" branch --show-current)" 'worktree mode: the main checkout is not switched'
assert_eq '?? stray.txt' "$(git -C "$r" status --porcelain)" \
  'worktree mode: the main checkout keeps its changes, and .worktrees and .superpowers stay out of git status'
assert_eq 'feat/tracker' "$(git -C "$bw" branch --show-current 2>/dev/null)" \
  'worktree mode: base is created and checked out in .worktrees/base'
assert_contains "base-worktree $bw" "$OUT" 'worktree mode: prints the base worktree'
assert_contains "design-doc $bw/spec-design.md" "$OUT" "worktree mode: prints the document's path on base"
led="$r/.superpowers/phase-parallel/spec-design/run.md"
assert_eq "# Phase run — spec: $bw/spec-design.md" "$(sed -n 1p "$led" 2>/dev/null)" \
  "worktree mode: the ledger lives in the main checkout and names base's copy of the document"

wt_pre "$r" "$r/spec-design.md" feat/tracker '2 to 6'
assert_rc 0 'worktree mode, second run: exits 0'
wt_pre "$bw" spec-design.md feat/tracker '2 to 6'
assert_rc 0 'worktree mode: resumes from inside the base worktree'
assert_contains "run-dir $r/.superpowers/phase-parallel/spec-design" "$OUT" \
  'worktree mode: the same run directory from inside the base worktree'
git -C "$r" stash -q -u
git -C "$r" switch -q -c elsewhere
git -C "$r" rm -q spec-design.md
git -C "$r" commit -qm 'a branch without the spec'
wt_pre "$r" "$r/spec-design.md" feat/tracker '2 to 6'
assert_rc 0 'worktree mode: resumes after the main checkout moved to a branch without the document'
assert_eq 'elsewhere' "$(git -C "$r" branch --show-current)" 'worktree mode: and leaves it there'
wt_pre "$r" "$r/spec-design.md" feat/other '2 to 6'
assert_rc 15 'worktree mode: the same spec on another base is refused'

printf 'left behind\n' > "$bw/stray.txt"
wt_pre "$r" "$bw/spec-design.md" feat/tracker '2 to 6'
assert_rc 11 'worktree mode: a dirty base worktree is refused'
assert_contains 'base worktree not clean' "$OUT" 'dirty base worktree: message names the problem'

# A base worktree left by an earlier run on another base is moved to this base.
r=$(new_repo); track "$r"
bw="$r/.worktrees/base"
wt_pre "$r" "$r/spec-design.md" feat/a 2
rm -rf "$r/.superpowers"
wt_pre "$r" "$r/spec-design.md" feat/b 2
assert_rc 0 'worktree mode: a new run reuses the base worktree of an earlier one'
assert_eq 'feat/b' "$(git -C "$bw" branch --show-current 2>/dev/null)" 'reused base worktree: now on the new base'

# Base is checked out somewhere the run does not own: refuse, touch nothing.
r=$(new_repo); track "$r"
git -C "$r" switch -q -c feat/x
wt_pre "$r" "$r/spec-design.md" feat/x all
assert_rc 13 'worktree mode: base checked out in the main checkout is refused'
assert_contains "is checked out in $r" "$OUT" 'base in the main checkout: message names the checkout'
assert_contains 'switch' "$OUT" 'base in the main checkout: message gives the command'
assert_eq 'feat/x' "$(git -C "$r" branch --show-current)" 'base in the main checkout: it is not switched'
assert_eq 'no' "$([ -e "$r/.worktrees/base" ] && echo yes || echo no)" 'base in the main checkout: no worktree created'

# A ledger written when base lived in the main checkout names the main
# checkout's copy of the document; it is the same run.
r=$(new_repo); track "$r"
git -C "$r" branch feat/x
led="$r/.superpowers/phase-parallel/spec-design"
mkdir -p "$led"
printf '*\n' > "$r/.superpowers/phase-parallel/.gitignore"
printf '# Phase run — spec: %s/spec-design.md\n# base: feat/x  requested: 2-3\n\n' "$r" > "$led/run.md"
wt_pre "$r" "$r/spec-design.md" feat/x '2-3'
assert_rc 0 'worktree mode: resumes a ledger that names the main checkout copy'
assert_eq "# Phase run — spec: $r/spec-design.md" "$(sed -n 1p "$led/run.md")" 'earlier ledger: left as it was'

# The document the run reads is the one committed on base.
r=$(new_repo); track "$r"
cp "$r/spec-design.md" "$r/new-design.md"
wt_pre "$r" "$r/new-design.md" feat/x all
assert_rc 26 'worktree mode: a document that is not committed is refused'
assert_contains 'not committed on' "$OUT" 'uncommitted document: message names the problem'
assert_eq 'no' "$([ -e "$r/.worktrees/base" ] && echo yes || echo no)" 'uncommitted document: refused before creating anything'
rm "$r/new-design.md"
printf '\nan edit nobody committed\n' >> "$r/spec-design.md"
wt_pre "$r" "$r/spec-design.md" feat/x all
assert_rc 26 'worktree mode: a document with uncommitted edits is refused on a fresh run'
assert_contains 'differs from' "$OUT" 'edited document: message names the problem'
git -C "$r" checkout -q -- spec-design.md
printf 'scratch/\n' > "$r/.gitignore"
git -C "$r" add .gitignore
git -C "$r" commit -qm 'ignore scratch'
mkdir "$r/scratch"
cp "$r/spec-design.md" "$r/scratch/scratch-design.md"
wt_pre "$r" "$r/scratch/scratch-design.md" feat/x all
assert_rc 0 'worktree mode: a git-ignored document is read where it is'
assert_contains "design-doc $r/scratch/scratch-design.md" "$OUT" 'ignored document: its own path is the one to use'

r=$(new_repo); track "$r"
wt_pre "$r" "$r/absent-design.md" feat/x all
assert_rc 2 'worktree mode: a missing document exits 2'
wt_pre "$r" "$r/spec-design.md" main all
assert_rc 12 'worktree mode: base main is refused'
wt_pre "$r" "$r/spec-design.md" feat/x '2-99'
assert_rc 4 'worktree mode: an absent phase number exits 4'
assert_eq 'no' "$([ -e "$r/.worktrees/base" ] && echo yes || echo no)" 'absent phase: refused before creating the base worktree'
git -C "$r" branch -m main trunkless
wt_pre "$r" "$r/spec-design.md" feat/x all
assert_rc 13 'worktree mode: no main or master to create the base from exits 13'

finish
