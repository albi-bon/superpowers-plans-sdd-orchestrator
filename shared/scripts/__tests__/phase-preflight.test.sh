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

finish
