#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
WT="$here/../phase-worktree"
export PHASE_RUN_NAMESPACE=phase-parallel
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
run_in() {
  set +e
  OUT=$(cd "$tmp" && "$@" 2>&1)
  RC=$?
  set -e
}
git -C "$tmp" init -q
git -C "$tmp" config user.email test@example.com
git -C "$tmp" config user.name Test
git -C "$tmp" symbolic-ref HEAD refs/heads/feat/x
printf '## Phase 1 — First\n## Phase 2 — Second\n' > "$tmp/spec.md"
git -C "$tmp" add spec.md
git -C "$tmp" commit -qm initial
rundir="$tmp/.superpowers/phase-parallel/spec"
mkdir -p "$rundir"
ledger="$rundir/run.md"
printf '# Phase run — spec: x\n# base: feat/x  requested: all\n# layout: run-scoped\n\n' > "$ledger"
wt1="$tmp/.worktrees/spec/phase-1-first"

run_in "$WT" "$tmp/spec.md" feat/x bogus 1
assert_rc 2 'unknown subcommand: usage error'
run_in "$WT" "$tmp/spec.md" feat/x start
assert_rc 2 'start without a phase: usage error'

run_in "$WT" "$tmp/spec.md" feat/x start 1
assert_rc 0 'start: exits 0'
assert_eq "$wt1" "$OUT" 'start: prints the worktree path'
assert_eq 'phase-1-first@spec' "$(git -C "$wt1" branch --show-current)" "start: worktree is on the phase branch named after the run"
assert_eq 'feat/x' "$(git -C "$tmp" branch --show-current)" 'start: main checkout stays on base'
assert_contains 'phase 1: started — branch phase-1-first@spec, worktree .worktrees/spec/phase-1-first' "$(cat "$ledger")" 'start: ledger line'
run_in "$WT" "$tmp/spec.md" feat/x path 1
assert_eq "$wt1" "$OUT" 'path: the same worktree'
assert_eq '' "$(git -C "$tmp" status --porcelain)" 'start: .worktrees stays out of git status'

run_in "$WT" "$tmp/spec.md" feat/x start 1
assert_rc 0 'start again: idempotent'
assert_eq '1' "$(grep -c '^phase 1: started' "$ledger")" 'start again: no second ledger line'

rm -rf "$wt1"
run_in "$WT" "$tmp/spec.md" feat/x start 1
assert_rc 0 'start after the directory vanished: re-attaches'
assert_eq 'phase-1-first@spec' "$(git -C "$wt1" branch --show-current)" 're-attached worktree is on the phase branch'

git -C "$tmp" branch phase-2-second@spec
run_in "$WT" "$tmp/spec.md" feat/x start 2
assert_rc 14 'branch unknown to the ledger: refused'
git -C "$tmp" branch -D -q phase-2-second@spec
printf 'phase 2: started — branch phase-2-second\n' >> "$ledger"
run_in "$WT" "$tmp/spec.md" feat/x start 2
assert_rc 18 'ledger knows the phase but the branch is gone: refused'
grep -v '^phase 2' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"

# --- refresh -------------------------------------------------------------------

printf 'phase 1: held — waits on phase 2 (overlap a)\n' >> "$ledger"
printf 'base\n' > "$tmp/base.txt"; git -C "$tmp" add base.txt; git -C "$tmp" commit -qm 'base advances'
run_in "$WT" "$tmp/spec.md" feat/x refresh 1
assert_rc 0 'refresh: exits 0'
assert_eq "$(git -C "$tmp" rev-parse feat/x)" "$(git -C "$wt1" rev-parse HEAD)" 'refresh: branch fast-forwarded to base'
assert_contains 'phase 1: released — phase 2 merged' "$(cat "$ledger")" 'refresh: release recorded with the blocker'
printf 'x\n' > "$wt1/x.txt"; git -C "$wt1" add x.txt; git -C "$wt1" commit -qm x
run_in "$WT" "$tmp/spec.md" feat/x refresh 1
assert_rc 21 'refresh of a branch with its own commits: refused'

# --- check ---------------------------------------------------------------------

run_in "$WT" "$tmp/spec.md" feat/x check
assert_rc 0 'check: clean worktrees pass'
printf 'dirty\n' > "$wt1/dirty.txt"
run_in "$WT" "$tmp/spec.md" feat/x check
assert_rc 11 'check: dirty worktree refused'
assert_contains "$wt1" "$OUT" 'check: names the dirty worktree'

# Another run in the same repository: its own worktrees and branches, and
# this run's dirty worktree is none of its business.
cp "$tmp/spec.md" "$tmp/other.md"
git -C "$tmp" add other.md
git -C "$tmp" commit -qm 'a second spec'
other_led="$tmp/.superpowers/phase-parallel/other/run.md"
mkdir -p "$(dirname "$other_led")"
printf '# Phase run — spec: y\n# base: feat/y  requested: all\n# layout: run-scoped\n\n' > "$other_led"
git -C "$tmp" branch feat/y feat/x
run_in "$WT" "$tmp/other.md" feat/y start 1
assert_rc 0 'two runs: the second starts the same phase number'
assert_eq "$tmp/.worktrees/other/phase-1-first" "$OUT" "two runs: in its own run's directory"
assert_eq 'phase-1-first@other' "$(git -C "$OUT" branch --show-current)" 'two runs: on a branch of its own'
run_in "$WT" "$tmp/other.md" feat/y check
assert_rc 0 "two runs: the other run's dirty worktree does not refuse this one"
rm "$wt1/dirty.txt"
printf 'dirty\n' > "$tmp/.worktrees/other/phase-1-first/dirty.txt"
run_in "$WT" "$tmp/spec.md" feat/x check
assert_rc 0 "two runs: nor the other way round"
rm "$tmp/.worktrees/other/phase-1-first/dirty.txt"

# --- remove --------------------------------------------------------------------

run_in "$WT" "$tmp/spec.md" feat/x remove 1
assert_rc 0 'remove: exits 0'
assert_eq 'no' "$([ -d "$wt1" ] && echo yes || echo no)" 'remove: directory gone'
assert_eq 'yes' "$(git -C "$tmp" show-ref --verify --quiet refs/heads/phase-1-first@spec && echo yes || echo no)" 'remove: branch kept'

# --- the legacy layout ------------------------------------------------------
# A ledger from before runs were named has no layout line: it keeps
# .worktrees/phase-<N>-<slug> and branch phase-<N>-<slug> until it finishes.

cp "$tmp/spec.md" "$tmp/live.md"
git -C "$tmp" add live.md
git -C "$tmp" commit -qm 'a legacy spec'
live_led="$tmp/.superpowers/phase-parallel/live/run.md"
mkdir -p "$(dirname "$live_led")"
printf '# Phase run — spec: z\n# base: feat/x  requested: all\n\n' > "$live_led"
legacy_wt="$tmp/.worktrees/phase-2-second"
run_in "$WT" "$tmp/live.md" feat/x start 2
assert_rc 0 'legacy: start exits 0'
assert_eq "$legacy_wt" "$OUT" 'legacy: the worktree is .worktrees/phase-<N>-<slug>'
assert_eq 'phase-2-second' "$(git -C "$legacy_wt" branch --show-current)" 'legacy: the branch is phase-<N>-<slug>'
assert_contains 'phase 2: started — branch phase-2-second, worktree .worktrees/phase-2-second' "$(cat "$live_led")" 'legacy: ledger line'
printf 'dirty\n' > "$legacy_wt/dirty.txt"
run_in "$WT" "$tmp/live.md" feat/x check
assert_rc 11 'legacy: check still refuses its own dirty worktree'
run_in "$WT" "$tmp/spec.md" feat/x check
assert_rc 0 "legacy: a run-scoped run is not refused by the legacy run's dirty worktree"
rm "$legacy_wt/dirty.txt"

finish
