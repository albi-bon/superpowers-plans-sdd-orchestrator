#!/usr/bin/env bash
# phase-qa: the QA pass's branch, its one next action, landing, closing, the
# status line's stage and the report block.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
QA="$here/../phase-qa"
export PHASE_RUN_NAMESPACE=phase-parallel
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
origin="$tmp/origin.git"
run_in() {
  set +e
  OUT=$(cd "$repo" && "$@" 2>&1)
  RC=$?
  set -e
}
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
git -C "$repo" symbolic-ref HEAD refs/heads/feat/x
git init -q --bare "$origin"
git -C "$repo" remote add origin "$origin"
printf '# Example — Design Spec\n## Phase 1 — One\n## Phase 2 — Two\n' > "$repo/spec.md"
printf 'shared\n' > "$repo/shared.txt"
git -C "$repo" add spec.md shared.txt
git -C "$repo" commit -qm initial
rundir="$repo/.superpowers/phase-parallel/spec"
ledger="$rundir/run.md"
iwt="$repo/.worktrees/integration"
log() { printf '%s\n' "$@" >> "$ledger"; }
reset_ledger() { # start the ledger again, then append the lines given
  mkdir -p "$rundir"
  printf '# Phase run — spec: %s\n# base: feat/x  requested: 1-2\n\n' "$repo/spec.md" > "$ledger"
  [ "$#" -eq 0 ] || log "$@"
}
qa() { run_in "$QA" "$repo/spec.md" feat/x "$@"; }
tip() { git -C "$repo" rev-parse --short "$1"; }
commit_in() { # commit_in DIR FILE CONTENT
  printf '%s\n' "$3" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -qm "$2"
}

# --- open ---------------------------------------------------------------------------

reset_ledger 'run: invoked — cap 3'
b=$(tip feat/x)
qa open
assert_rc 0 'open: exits 0'
assert_eq "opened $b" "$OUT" 'open: prints the base tip'
assert_eq 'phase-qa-spec' "$(git -C "$iwt" branch --show-current)" 'open: the integration worktree is on the QA branch, named after the run'
assert_contains "qa: opened — phase-qa-spec at $b" "$(cat "$ledger")" 'open: recorded'

printf 'left by a walker\n' >> "$iwt/shared.txt"
qa open
assert_rc 0 'open again: exits 0'
assert_eq '' "$(git -C "$iwt" status --porcelain --untracked-files=no)" 'open again: tracked changes are discarded'
assert_eq '1' "$(grep -c '^qa: opened' "$ledger")" 'open again: the same tip is not recorded twice'
log 'qa: skipped — the product could not be started'
qa open
assert_eq '2' "$(grep -c '^qa: opened' "$ledger")" 'open after a skip: recorded again'

commit_in "$repo" two.txt two
b2=$(tip feat/x)
qa open
assert_eq "$(git -C "$repo" rev-parse feat/x)" "$(git -C "$repo" rev-parse phase-qa-spec)" 'open: an unused QA branch follows base'
assert_contains "qa: opened — phase-qa-spec at $b2" "$(cat "$ledger")" 'open: the new tip is recorded'

log 'qa: flows defined — 1 found, selected 1, not walkable -, parallel yes'
commit_in "$iwt" fix.txt fix
f=$(tip phase-qa-spec)
qa open
assert_eq "$f" "$(tip phase-qa-spec)" 'open: once flows are defined the branch is never moved'

reset_ledger 'run: invoked — cap 3'
qa open
assert_rc 14 'open: refuses a QA branch the ledger does not account for'
git -C "$iwt" switch -q --detach feat/x
git -C "$repo" branch -q -D phase-qa-spec
log 'batch 1: opened — phases 1@abc1234'
qa open
assert_rc 17 'open: refuses while a batch is open'
qa nonsense
assert_rc 2 'an unknown subcommand is a usage error'

# --- next, status, close: one pass from start to end -------------------------------

nx() { qa next; assert_eq "$1" "$OUT" "next: $2"; }
st() { qa status; assert_eq "$1" "$OUT" "status: $2"; }
T=$(printf '\t')

reset_ledger 'run: invoked — cap 3'
nx 'done' 'no scope recorded'
log 'run: qa scope — none'
nx 'done' 'scope none'
log 'run: qa scope — top 5' 'phase 1: merged to base (aaa1)'
nx 'skip phase 2 did not land' 'a requested phase is missing'
st '' 'nothing while the pass cannot run'
log 'phase 2: merged to base (aaa1)' 'batch 1: landed (aaa1)' 'run: final check FAIL — unit suite'
nx 'skip the final check failed' 'the final check failed'
log 'qa: skipped — the final check failed'
nx 'done' 'a skip that still counts ends the pass'
log 'run: final check PASS aaa1'
nx 'open' 'a later final check supersedes the skip'
log 'qa: opened — phase-qa-spec at aaa1'
nx 'plan' 'opened'
st 'planning' 'opened'
log 'qa: planner dispatched'
nx 'plan' 'the same action while the planner has no outcome'
log 'qa: flows defined — 7 found, selected 1, 2,3,4,5, not walkable 4, parallel yes'
nx 'walk 1 2 3 5' 'selected flows minus the not walkable one, spaces in the list ignored'
log 'qa flow 1: walker dispatched' 'qa flow 1: walked — 0 findings'
nx 'walk 2 3 5' 'a walked flow is not walked again'
st "walking${T}1${T}4" 'one of four'
log 'qa flow 2: walked — 3 findings' 'qa flow 3: not walked — the simulator would not boot' 'qa flow 5: walked — 1 findings'
nx 'triage' 'every flow has an outcome'
st 'triaging' 'before the triaged line'
log 'qa: triaged — 4 findings, fix G1@2 G2@5 G3@2, 5, 1 spec, 2 outside this run'
nx 'fix 1' 'the first group'
log 'qa group 1: fixer dispatched' 'qa group 1: fixed 3c4d5e6'
nx 'fix 2' 'one group at a time, in order'
st "fixing${T}1${T}3" 'one of three'
log 'qa group 2: not fixed — did not reproduce'
nx 'fix 3' 'a group that was not fixed is not retried'
log 'qa group 3: fixed 5e6f7a8'
nx 'verify 5e6f7a8' 'gates on the last fix'
st 'verifying' 'before the verified line'
log 'qa: verified PASS — 5e6f7a8'
nx 'land 5e6f7a8' 'verified'
st 'landing' 'before the landed line'
log 'qa: landed (5e6f7a8)'
nx 'recheck 2 5' 'the flows of the fixed groups'
qa close
assert_rc 18 'close: refuses while the pass is not over'
log 'qa flow 2: rechecked — G1 confirmed, G3 still broken, 1 new'
nx 'recheck 5' 'a rechecked flow is not rechecked again'
st "rechecking${T}1${T}2" 'one of two'
log 'qa flow 5: rechecked — G3 confirmed, 0 new'
nx 'close' 'nothing left'
before=$(cat "$ledger")
qa next
qa status
assert_eq "$before" "$(cat "$ledger")" 'next and status write nothing'
qa close
assert_rc 0 'close: exits 0'
assert_eq 'qa: done — 1 confirmed, 1 still broken, 1 not fixed, 1 new, 1 spec' "$(tail -n 1 "$ledger")" 'close: counts from the ledger; a group still broken in one flow is still broken'
assert_eq 'qa: done — 1 confirmed, 1 still broken, 1 not fixed, 1 new, 1 spec' "$OUT" 'close: prints the line it recorded'
nx 'done' 'closed'
st '' 'nothing once the pass is done'
qa close
assert_rc 17 'close: refuses a second done line'

# --- next and close: the other ways a pass ends -------------------------------------

pass_ledger() { # pass_ledger <flows-defined tail> [more lines…]
  reset_ledger 'run: qa scope — all' 'phase 1: merged to base (aaa1)' 'phase 2: merged to base (aaa1)' \
    'batch 1: landed (aaa1)' 'qa: opened — phase-qa-spec at aaa1' "qa: flows defined — $1"
  shift
  [ "$#" -eq 0 ] || log "$@"
}
closes() { # closes <expected done line> <message>
  nx 'close' "$2"
  qa close
  assert_eq "$1" "$(tail -n 1 "$ledger")" "close: $2"
}

pass_ledger '2 found, selected 1,2, not walkable -, parallel no'
nx 'walk 1' 'one walker at a time when flows cannot run side by side'
pass_ledger '2 found, selected 1,2, not walkable -, parallel yes' 'qa flow 1: walked — 0 findings' 'qa flow 2: walked — 0 findings'
closes 'qa: done — 2 flows walked, no findings' 'no findings skips triage'
pass_ledger '0 found, selected -, not walkable -, parallel yes'
closes 'qa: done — nothing to walk' 'no flows'
pass_ledger '1 found, selected 1, not walkable -, parallel yes' 'qa flow 1: walked — 2 findings' \
  'qa: triaged — 2 findings, fix -, 1 spec, 1 outside this run'
closes 'qa: done — 0 confirmed, 0 still broken, 0 not fixed, 0 new, 1 spec' 'nothing to fix'
pass_ledger '1 found, selected 1, not walkable -, parallel yes' 'qa flow 1: walked — 1 findings' \
  'qa: triaged — 1 findings, fix G1@1, 0 spec, 0 outside this run' 'qa group 1: not fixed — fix did not hold'
closes 'qa: done — 0 confirmed, 0 still broken, 1 not fixed, 0 new, 0 spec' 'no gates when nothing was fixed'
pass_ledger '1 found, selected 1, not walkable -, parallel yes' 'qa flow 1: walked — 2 findings' \
  'qa: triaged — 2 findings, fix G1@1 G2@1, 0 spec, 0 outside this run' 'qa group 1: fixed 1111111' 'qa group 2: fixed 2222222' \
  'qa: verified FAIL — unit suite'
nx 'push' 'failed gates: back up the branch'
log 'push: phase-qa-spec failed — no route to host'
closes 'qa: done — 0 confirmed, 0 still broken, 0 not fixed, 0 new, 0 spec, 2 fixed but not landed' 'failed gates: no re-check, no second round'
pass_ledger '1 found, selected 1, not walkable -, parallel yes' 'qa flow 1: walked — 1 findings' \
  'qa: triaged — 1 findings, fix G1@1, 0 spec, 0 outside this run' 'qa group 1: fixed 1111111' \
  'qa: verified PASS — 1111111' 'qa: not landed — fast-forward failed'
nx 'push' 'a refused landing is backed up, not retried'
pass_ledger '1 found, selected 1, not walkable -, parallel yes' 'qa flow 1: walked — 1 findings' 'batch 2: landed (bbb2)'
closes 'qa: done — abandoned, base moved under the pass' 'base moved under a started pass'
reset_ledger 'run: qa scope — all' 'phase 1: merged to base (aaa1)' 'phase 2: merged to base (aaa1)' \
  'batch 1: landed (aaa1)' 'qa: opened — phase-qa-spec at aaa1' 'batch 2: landed (bbb2)'
nx 'open' 'base moved before the plan: open again'
reset_ledger 'run: qa scope — all' 'phase 1: merged to base (aaa1)' 'phase 2: merged to base (aaa1)' \
  'batch 1: landed (aaa1)' 'qa: opened — phase-qa-spec at aaa1' 'qa: skipped — the product could not be started'
nx 'done' 'a planner skip ends the pass'
log 'run: qa scope — top 3'
nx 'open' 'the owner asking again supersedes the skip, and the pass starts over from open'

finish
