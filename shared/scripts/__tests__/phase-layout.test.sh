#!/usr/bin/env bash
# phase-layout, and the scripts that follow it: a new run names its worktrees
# and branches after itself, so two runs share a repository; a ledger from
# before that keeps the legacy names until it finishes.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
LAYOUT="$here/../phase-layout"
RUNDIR="$here/../phase-run-dir"
WT="$here/../phase-worktree"
BATCH="$here/../phase-batch"
LAND="$here/../phase-land"
PUSH="$here/../phase-push"
QA="$here/../phase-qa"
export PHASE_RUN_NAMESPACE=phase-parallel
export PHASE_RUN_ANCHOR=main
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
origin="$tmp/origin.git"
run_in() { # run_in DIR COMMAND…
  local dir=$1
  shift
  set +e
  OUT=$(cd "$dir" && "$@" 2>&1)
  RC=$?
  set -e
}
key() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
git -C "$repo" symbolic-ref HEAD refs/heads/main
git init -q --bare "$origin"
git -C "$repo" remote add origin "$origin"
printf '# Example\n## Phase 1 — One\n## Phase 2 — Two\n' > "$repo/spec.md"
for name in live alpha beta; do cp "$repo/spec.md" "$repo/$name.md"; done
git -C "$repo" add -A
git -C "$repo" commit -qm initial
mkdir -p "$repo/.worktrees"
printf '*\n' > "$repo/.worktrees/.gitignore"
commit_in() { # commit_in DIR FILE CONTENT
  printf '%s\n' "$3" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -qm "$2"
}

# --- resolution -------------------------------------------------------------------

run_in "$repo" "$LAYOUT"
assert_rc 2 'no document: usage error'
run_in "$tmp" "$LAYOUT" "$repo/alpha.md"
assert_rc 2 'outside a repository: refused'

run_in "$repo" "$LAYOUT" "$repo/gone/alpha.md"
assert_rc 0 'no ledger yet: exits 0, and the document need not exist where it is named'
assert_eq 'run-scoped' "$(key layout)" 'no ledger yet: the layout a new run gets'
assert_eq 'alpha' "$(key run)" 'the run is named after the document'
assert_eq "$repo/.worktrees/alpha" "$(key worktrees)" 'run-scoped: worktrees under .worktrees/<run>'
assert_eq "$repo/.worktrees/alpha/base" "$(key base-worktree)" 'run-scoped: base worktree'
assert_eq "$repo/.worktrees/alpha/integration" "$(key integration-worktree)" 'run-scoped: integration worktree'
assert_eq '@alpha' "$(key branch-suffix)" 'run-scoped: branches end in @<run>'
assert_eq 'phase-qa@alpha' "$(key qa-branch)" 'run-scoped: QA branch'

run_in "$repo" "$RUNDIR" "$repo/alpha.md"
alpha_rundir=$OUT
printf '# Phase run — spec: x\n# base: feat/a  requested: all\n# layout: run-scoped\n\n' > "$alpha_rundir/run.md"
run_in "$repo" "$LAYOUT" "$repo/alpha.md"
assert_eq 'run-scoped' "$(key layout)" 'a ledger with the layout line: run-scoped'

run_in "$repo" "$RUNDIR" "$repo/live.md"
live_rundir=$OUT
printf '# Phase run — spec: x\n# base: feat/live  requested: all\n\n' > "$live_rundir/run.md"
run_in "$repo" "$LAYOUT" "$repo/live.md"
assert_eq 'legacy' "$(key layout)" 'a ledger without the layout line: legacy'
assert_eq "$repo/.worktrees" "$(key worktrees)" 'legacy: worktrees directly under .worktrees'
assert_eq "$repo/.worktrees/base" "$(key base-worktree)" 'legacy: .worktrees/base'
assert_eq "$repo/.worktrees/integration" "$(key integration-worktree)" 'legacy: .worktrees/integration'
assert_eq '' "$(key branch-suffix)" 'legacy: branches carry no suffix'
assert_eq 'phase-qa-live' "$(key qa-branch)" 'legacy: QA branch phase-qa-<run>'

for bad in base integration; do
  run_in "$repo" "$LAYOUT" "$repo/$bad.md"
  assert_rc 2 "a new run named '$bad' is refused: it would nest in the legacy worktrees"
done
run_in "$repo" "$LAYOUT" "$repo/odd..name.md"
assert_rc 2 'a new run whose name cannot be in a branch name is refused'

# --- the legacy layout, end to end ------------------------------------------------
# What the controller of a run started before this layout calls next.

git -C "$repo" branch feat/live
git -C "$repo" worktree add -q "$repo/.worktrees/base" feat/live
lspec="$repo/.worktrees/base/live.md"
lled="$live_rundir/run.md"
run_in "$repo/.worktrees/base" "$WT" "$lspec" feat/live start 1
lwt=$OUT
assert_eq "$repo/.worktrees/phase-1-one" "$lwt" 'legacy start: .worktrees/phase-<N>-<slug>'
assert_eq 'phase-1-one' "$(git -C "$lwt" branch --show-current)" 'legacy start: branch phase-<N>-<slug>'
commit_in "$lwt" one.txt one
lv1=$(git -C "$lwt" rev-parse --short HEAD)
run_in "$repo/.worktrees/base" "$PUSH" "$lspec" feat/live 1
assert_eq "push: phase-1-one at $lv1" "$OUT" 'legacy push: the legacy phase branch'
run_in "$repo/.worktrees/base" "$BATCH" "$lspec" feat/live open "1@$lv1"
assert_eq "built 1 $(git -C "$repo/.worktrees/integration" rev-parse --short HEAD 2>/dev/null)" "$OUT" \
  'legacy batch: built in .worktrees/integration'
assert_eq 'phase-batch-1' "$(git -C "$repo/.worktrees/integration" branch --show-current)" 'legacy batch: branch phase-batch-<K>'
lb1=$(git -C "$repo/.worktrees/integration" rev-parse --short HEAD)
printf 'batch 1: verified PASS — full suites all — %s\n' "$lb1" >> "$lled"
run_in "$repo/.worktrees/base" "$LAND" "$lspec" feat/live 1 "$lb1"
assert_rc 0 'legacy land: exits 0'
assert_eq "$(git -C "$repo" rev-parse "$lb1")" "$(git -C "$repo/.worktrees/base" rev-parse HEAD)" \
  'legacy land: .worktrees/base moved to the verified batch'
assert_eq 'no' "$([ -d "$lwt" ] && echo yes || echo no)" 'legacy land: the phase worktree is removed'
printf 'run: qa scope — all\n' >> "$lled"
run_in "$repo/.worktrees/base" "$QA" "$lspec" feat/live open
assert_rc 0 'legacy QA: opens'
assert_eq 'phase-qa-live' "$(git -C "$repo/.worktrees/integration" branch --show-current)" \
  'legacy QA: phase-qa-<run> in .worktrees/integration'

# --- two run-scoped runs side by side ----------------------------------------------
# Both run beside the legacy run, open their first batch at once, and never
# meet: separate base and integration worktrees, separate batch branches.

pre() { # pre NAME BASE — preflight as the parallel skill's wrapper runs it
  run_in "$repo" env PHASE_BASE_CHECKOUT=worktree "$here/../phase-preflight" "$repo/$1.md" "$2" all
}
rm -f "$alpha_rundir/run.md"
pre alpha feat/a
assert_rc 0 'run alpha: preflight passes beside the legacy run'
pre beta feat/b
assert_rc 0 'run beta: preflight passes beside alpha and the legacy run'
assert_eq 'feat/live' "$(git -C "$repo/.worktrees/base" branch --show-current)" 'the legacy base worktree is not switched'
for name in alpha beta; do
  spec="$repo/.worktrees/$name/base/$name.md"
  case "$name" in alpha) base=feat/a ;; beta) base=feat/b ;; esac
  run_in "$repo/.worktrees/$name/base" "$WT" "$spec" "$base" start 1
  pwt=$OUT
  commit_in "$pwt" "$name.txt" "$name"
  v=$(git -C "$pwt" rev-parse --short HEAD)
  run_in "$repo/.worktrees/$name/base" "$BATCH" "$spec" "$base" open "1@$v"
  assert_rc 0 "run $name: batch 1 opens, whatever the other runs named theirs"
  iwt="$repo/.worktrees/$name/integration"
  assert_eq "built 1 $(git -C "$iwt" rev-parse --short HEAD 2>/dev/null)" "$OUT" "run $name: built in its own integration worktree"
  assert_eq "phase-batch-1@$name" "$(git -C "$iwt" branch --show-current)" "run $name: on its own batch branch"
done
assert_eq "$(git -C "$repo" rev-parse feat/a)" "$(git -C "$repo" merge-base feat/a phase-batch-1@alpha)" \
  'run alpha: its batch is built on its own base'
assert_eq 'no' "$(git -C "$repo" merge-base --is-ancestor phase-1-one@beta phase-batch-1@alpha && echo yes || echo no)" \
  "run alpha: its batch holds none of beta's work"

finish
