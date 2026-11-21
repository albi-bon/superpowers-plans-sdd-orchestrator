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
# Base gets its own worktree, <main checkout>/.worktrees/<run>/base. The main
# checkout is never switched and never has to be clean; the document is read
# from base's copy, so the owner can move the main checkout mid-run.

wt_pre() { # wt_pre DIR ARGS… — preflight as the parallel skill's wrapper runs it
  dir=$1
  shift
  run_in "$dir" env PHASE_BASE_CHECKOUT=worktree PHASE_RUN_ANCHOR=main \
    PHASE_RUN_NAMESPACE=phase-parallel "$PRE" "$@"
}

r=$(new_repo); track "$r"
bw="$r/.worktrees/spec-design/base"
printf 'work in progress\n' > "$r/stray.txt"
wt_pre "$r" "$r/spec-design.md" feat/tracker '2 to 6'
assert_rc 0 'worktree mode: a dirty main checkout does not refuse the run'
assert_eq 'main' "$(git -C "$r" branch --show-current)" 'worktree mode: the main checkout is not switched'
assert_eq '?? stray.txt' "$(git -C "$r" status --porcelain)" \
  'worktree mode: the main checkout keeps its changes, and .worktrees and .superpowers stay out of git status'
assert_eq 'feat/tracker' "$(git -C "$bw" branch --show-current 2>/dev/null)" \
  "worktree mode: base is created and checked out in the run's own .worktrees/<run>/base"
assert_contains "base-worktree $bw" "$OUT" 'worktree mode: prints the base worktree'
assert_contains "integration-worktree $r/.worktrees/spec-design/integration" "$OUT" \
  "worktree mode: prints the run's integration worktree"
assert_contains "design-doc $bw/spec-design.md" "$OUT" "worktree mode: prints the document's path on base"
led="$r/.superpowers/phase-parallel/spec-design/run.md"
assert_eq "# Phase run — spec: $bw/spec-design.md" "$(sed -n 1p "$led" 2>/dev/null)" \
  "worktree mode: the ledger lives in the main checkout and names base's copy of the document"
assert_eq '# layout: run-scoped' "$(sed -n 3p "$led" 2>/dev/null)" \
  'worktree mode: a new ledger records the run-scoped layout'

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

# A base worktree that exists on another branch is never switched: it may be
# another run's. Here an earlier run of the same document left it, and its
# ledger was moved aside.
r=$(new_repo); track "$r"
bw="$r/.worktrees/spec-design/base"
wt_pre "$r" "$r/spec-design.md" feat/a 2
rm -rf "$r/.superpowers"
wt_pre "$r" "$r/spec-design.md" feat/b 2
assert_rc 13 'worktree mode: a base worktree on another branch is refused'
assert_contains "is on 'feat/a', not 'feat/b'" "$OUT" 'base worktree on another branch: message names both branches'
assert_contains 'git worktree remove' "$OUT" 'base worktree on another branch: message gives the command'
assert_eq 'feat/a' "$(git -C "$bw" branch --show-current 2>/dev/null)" 'base worktree on another branch: not switched'
assert_eq 'no' "$(git -C "$r" show-ref --verify --quiet refs/heads/feat/b && echo yes || echo no)" \
  'base worktree on another branch: the new base is not created'
printf 'theirs\n' > "$bw/stray.txt"
wt_pre "$r" "$r/spec-design.md" feat/b 2
assert_rc 13 'a dirty base worktree on another branch: refused as on another branch, not asked to be cleaned'
rm "$bw/stray.txt"
git -C "$bw" switch -q --detach
wt_pre "$r" "$r/spec-design.md" feat/b 2
assert_rc 13 'worktree mode: a detached base worktree is refused too'
assert_eq '' "$(git -C "$bw" branch --show-current)" 'detached base worktree: left detached'

# The legacy layout: a ledger written before runs were named, without the
# layout line, keeps .worktrees/base. Another run in the same repository
# builds beside it and leaves its base worktree alone.
r=$(new_repo); track "$r"
git -C "$r" branch feat/live
legacy_bw="$r/.worktrees/base"
mkdir -p "$r/.worktrees"
printf '*\n' > "$r/.worktrees/.gitignore"
git -C "$r" worktree add -q "$legacy_bw" feat/live
led="$r/.superpowers/phase-parallel/spec-design"
mkdir -p "$led"
printf '*\n' > "$r/.superpowers/phase-parallel/.gitignore"
printf '# Phase run — spec: %s/spec-design.md\n# base: feat/live  requested: 2-3\n\n' "$legacy_bw" > "$led/run.md"
wt_pre "$r" "$legacy_bw/spec-design.md" feat/live '2-3'
assert_rc 0 'legacy ledger: resumes'
assert_contains "base-worktree $legacy_bw" "$OUT" 'legacy ledger: keeps .worktrees/base'
assert_contains "integration-worktree $r/.worktrees/integration" "$OUT" 'legacy ledger: keeps .worktrees/integration'
assert_eq '' "$(grep 'layout' "$led/run.md")" 'legacy ledger: no layout line is added on resume'
cp "$r/spec-design.md" "$r/other-design.md"
git -C "$r" add other-design.md
git -C "$r" commit -qm 'a second spec'
wt_pre "$r" "$r/other-design.md" feat/new 2
assert_rc 0 'a new run beside a legacy one: exits 0'
assert_contains "base-worktree $r/.worktrees/other-design/base" "$OUT" 'a new run beside a legacy one: its own base worktree'
assert_eq 'feat/live' "$(git -C "$legacy_bw" branch --show-current)" "a new run beside a legacy one: the legacy base worktree is not switched"
assert_eq 'feat/new' "$(git -C "$r/.worktrees/other-design/base" branch --show-current)" 'a new run beside a legacy one: its base is in its own worktree'
rm -rf "$r/.superpowers/phase-parallel/other-design"
wt_pre "$r" "$r/other-design.md" feat/live 2
assert_rc 13 "a run on a base another run's worktree holds: refused"
assert_contains 'give this run a base branch of its own' "$OUT" "base held by another run: message says why, without a switch command"

# Base is checked out somewhere the run does not own: refuse, touch nothing.
r=$(new_repo); track "$r"
git -C "$r" switch -q -c feat/x
wt_pre "$r" "$r/spec-design.md" feat/x all
assert_rc 13 'worktree mode: base checked out in the main checkout is refused'
assert_contains "is checked out in $r" "$OUT" 'base in the main checkout: message names the checkout'
assert_contains 'switch' "$OUT" 'base in the main checkout: message gives the command'
assert_eq 'feat/x' "$(git -C "$r" branch --show-current)" 'base in the main checkout: it is not switched'
assert_eq 'no' "$([ -e "$r/.worktrees/spec-design/base" ] && echo yes || echo no)" 'base in the main checkout: no worktree created'

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
assert_contains "base-worktree $r/.worktrees/base" "$OUT" 'earlier ledger: the legacy base worktree'

# The document the run reads is the one committed on base.
r=$(new_repo); track "$r"
cp "$r/spec-design.md" "$r/new-design.md"
wt_pre "$r" "$r/new-design.md" feat/x all
assert_rc 26 'worktree mode: a document that is not committed is refused'
assert_contains 'not committed on' "$OUT" 'uncommitted document: message names the problem'
assert_eq 'no' "$([ -e "$r/.worktrees" ] && echo yes || echo no)" 'uncommitted document: refused before creating anything'
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
assert_eq 'no' "$([ -e "$r/.worktrees" ] && echo yes || echo no)" 'absent phase: refused before creating the base worktree'
git -C "$r" branch -m main trunkless
wt_pre "$r" "$r/spec-design.md" feat/x all
assert_rc 13 'worktree mode: no main or master to create the base from exits 13'

finish
