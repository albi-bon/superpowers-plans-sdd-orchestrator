#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
SCHED="$here/../phase-schedule"
STATE="$here/../phase-state"
export PHASE_RUN_NAMESPACE=phase-parallel
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
run_in() {
  set +e
  OUT=$(cd "$tmp" && "$@" 2>&1)
  RC=$?
  set -e
}
joined() { printf '%s\n' "$OUT" | tr '\t' ' ' | tr '\n' '|'; }
sched() { run_in "$SCHED" "$tmp/spec.md" feat/x "${1:-all}" "${2:-3}"; }
state_of() { # state_of N|batch K — the row from phase-state, space-separated
  run_in "$STATE" "$tmp/spec.md"
  if [ "$1" = batch ]; then
    printf '%s\n' "$OUT" | awk -F'\t' -v k="$2" '$1 == "batch" && $2 == k' | tr '\t' ' '
  else
    printf '%s\n' "$OUT" | awk -F'\t' -v n="$1" '$1 == n' | tr '\t' ' '
  fi
}
git -C "$tmp" init -q
printf '## Phase 1 — A\n## Phase 2 — B\n## Phase 3 — C\n## Phase 4 — D\n## Phase 5 — E\n## Phase 6 — F\n' > "$tmp/spec.md"
rundir="$tmp/.superpowers/phase-parallel/spec"
mkdir -p "$rundir"
# 2 and 3 depend on 1; 4 on 2 and 3; 5 and 6 on nothing.
printf '1\t-\tline\n2\t1\tline\n3\t1\tline\n4\t2,3\tline\n5\t-\tline\n6\t-\tline\n' > "$rundir/graph.tsv"
ledger="$rundir/run.md"
reset_ledger() { printf '# Phase run — spec: x\n# base: feat/x  requested: all\n\n' > "$ledger"; }
log() { printf '%s\n' "$@" >> "$ledger"; }
exec_line() { # exec_line N SHA
  printf 'phase %s: executed — a0a0a0a..%s, review 0/0/0 (0 fixed, 0 deferred), 0 significant\n' "$1" "$2" >> "$ledger"
}

# --- usage ---------------------------------------------------------------------

sched all 0
assert_rc 2 'cap 0: usage error'
sched all x
assert_rc 2 'non-numeric cap: usage error'

# --- a fresh run -----------------------------------------------------------------

reset_ledger
sched all 3
assert_rc 0 'fresh run: exits 0'
assert_eq 'start 1|start 5|start 6|wait|' "$(joined)" 'fresh run: starts every phase with no unmerged deps, ascending'
sched all 1
assert_eq 'start 1|wait|' "$(joined)" 'cap 1: one start'
sched 2-4 3
assert_eq 'start 2|start 3|wait|' "$(joined)" 'deps outside the range count as satisfied'

# --- queueing and batching --------------------------------------------------------

log 'phase 1: started — branch phase-1-a' 'phase 5: started — branch phase-5-e' \
  'phase 6: started — branch phase-6-f' 'phase 5: scout dispatched'
sched
assert_eq 'wait|' "$(joined)" 'phases in flight, nothing ready: wait'

exec_line 5 aaa5
exec_line 1 aaa1
sched
assert_eq 'batch 5@aaa5 1@aaa1|wait|' "$(joined)" 'no batch open: every queued phase forms one batch, in queue order'
assert_contains '5 queued aaa5 ' "$(state_of 5)" 'phase-state: an executed phase is queued at the end of its range'

log 'batch 1: opened — phases 5@aaa5 1@aaa1'
sched
assert_eq 'build 1|wait|' "$(joined)" 'an open batch is built'
assert_contains '1 batched  ' "$(state_of 1)" 'phase-state: a phase in the open batch is batched'
assert_contains 'batch 1 open - 5,1 -' "$(state_of batch 1)" 'phase-state: the batch row lists its members'

exec_line 6 aaa6
log 'phase 5: batched — batch 1, clean merge bbb5' 'phase 1: batched — batch 1, conflict in 2 files'
sched
assert_eq 'build 1|wait|' "$(joined)" 'a merge waiting on the resolver: build reprints the conflict; a phase queued meanwhile waits for the next batch'
assert_contains 'batch 1 conflict 1 ' "$(state_of batch 1)" 'phase-state: the batch reports the conflicting phase'

log 'phase 1: resolver dispatched' 'phase 1: resolved ccc1'
sched
assert_eq 'build 1|wait|' "$(joined)" 'resolved: carry on building'
log 'batch 1: built ddd1'
sched
assert_eq 'verify 1 ddd1|wait|' "$(joined)" 'built: verify the batch'
log 'batch 1: verifier dispatched'
sched
assert_eq 'verify 1 ddd1|wait|' "$(joined)" 'verifier out: still the verify action, which the controller skips as dispatched'
log 'batch 1: verified PASS — full suites all — ddd1'
sched
assert_eq 'land 1 ddd1|wait|' "$(joined)" 'passed: land the batch'
assert_contains 'batch 1 landable ddd1 5,1 all' "$(state_of batch 1)" 'phase-state: landable at the pass sha, full suites recorded'

log 'phase 5: merged to base (eee5)' 'phase 1: merged to base (eee1)' 'batch 1: landed (eee1)'
sched
assert_eq 'batch 6@aaa6|start 2|start 3|wait|' "$(joined)" 'landed: a lone queued phase goes alone, and dependents start'
assert_contains 'batch 1 landed ddd1 5,1 all' "$(state_of batch 1)" 'phase-state: the batch is landed'
assert_contains '1 merged eee1 ' "$(state_of 1)" 'phase-state: its phases are merged'

# --- a failure pinned on one phase -------------------------------------------------

reset_ledger
log 'phase 1: started — branch phase-1-a' 'phase 5: started — branch phase-5-e' 'phase 6: started — branch phase-6-f'
exec_line 1 aaa1
exec_line 5 aaa5
exec_line 6 aaa6
log 'batch 1: opened — phases 1@aaa1 5@aaa5 6@aaa6' 'batch 1: built bbb1' \
  'batch 1: verified FAIL — pinned on phase 5 — acceptance: charge-once missing'
sched
assert_eq 'batch 1@aaa1 6@aaa6|wait|' "$(joined)" 'pinned: the rest are rebuilt without it; its repair waits while they are queued'
assert_contains '5 failing aaa5 ' "$(state_of 5)" 'phase-state: the pinned phase is failing at its queued sha'
assert_contains ' repair 1' "$(state_of 5)" 'phase-state: its next step is the repair'
assert_contains '1 queued aaa1 ' "$(state_of 1)" 'phase-state: the rest are queued again'
assert_contains 'batch 1 failed 5 ' "$(state_of batch 1)" 'phase-state: the batch failed, pinned on phase 5'

log 'batch 2: opened — phases 1@aaa1 6@aaa6'
sched
assert_eq 'build 2|wait|' "$(joined)" 'the rebuilt batch builds; the repair still waits for it'
log 'batch 2: built ccc2' 'batch 2: verified PASS — full suites partial — ccc2'
sched
assert_eq 'land 2 ccc2|wait|' "$(joined)" 'the rebuilt batch passes: land'
log 'phase 1: merged to base (ddd1)' 'phase 6: merged to base (ddd6)' 'batch 2: landed (ddd6)'
sched
assert_eq 'repair 5 aaa5|start 2|start 3|wait|' "$(joined)" 'its mates landed: the repair starts against that base'

log 'phase 5: repair — started (attempt 1/2)' 'phase 5: repair dispatched'
sched
assert_eq 'start 2|start 3|wait|' "$(joined)" 'a repair under way: the phase is active'
assert_contains '5 active ' "$(state_of 5)" 'phase-state: repairing is active'
log 'phase 2: started — branch phase-2-b'
exec_line 2 aaa2
log 'phase 5: executed — repaired, HEAD fff5'
sched
assert_eq 'batch 2@aaa2 5@fff5|start 3|wait|' "$(joined)" 'repaired: requeued at its HEAD, batched with whatever else is queued'
grep -v '^phase 5: executed — repaired' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"
log 'phase 5: executed — still broken, HEAD fff5'
sched
assert_eq 'batch 5@fff5|start 3|wait|' "$(joined)" 'a repair that returned still broken is verified alone, so it cannot fail a batch'
grep -v '^phase 2: ' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"

log 'batch 3: opened — phases 5@fff5' 'batch 3: built ggg3' 'batch 3: verified FAIL — pinned on phase 5 — tests'
sched
assert_eq 'rescue 5 fff5|start 2|start 3|wait|' "$(joined)" 'a second failure takes the rescue'
log 'phase 5: rescue — started (attempt 2/2)' 'phase 5: executed — repaired, HEAD hhh5' \
  'batch 4: opened — phases 5@hhh5' 'batch 4: built iii4' 'batch 4: verified FAIL — pinned on phase 5 — tests'
sched
assert_eq 'fail 5|start 2|start 3|wait|' "$(joined)" 'a third failure: both attempts used, fail the phase'
assert_eq '2' "$(state_of 5 | cut -d' ' -f5)" 'phase-state: two ladder attempts counted'

# --- a failure nobody could pin -----------------------------------------------------

reset_ledger
log 'phase 1: started — branch phase-1-a' 'phase 5: started — branch phase-5-e' 'phase 6: started — branch phase-6-f'
exec_line 1 aaa1
exec_line 5 aaa5
log 'batch 1: opened — phases 1@aaa1 5@aaa5' 'batch 1: built bbb1' \
  'batch 1: verified FAIL — not pinned — integration suite: checkout flow times out'
exec_line 6 aaa6
sched
assert_eq 'batch 1@aaa1|wait|' "$(joined)" 'not pinned: its phases are verified one by one, earliest first, before anything else'
assert_contains '5 queued aaa5 ' "$(state_of 5)" 'phase-state: an unpinned batch requeues every phase'
assert_contains ' solo 1' "$(state_of 5)" 'phase-state: flagged solo'
log 'batch 2: opened — phases 1@aaa1' 'batch 2: built ccc2' 'batch 2: verified PASS — full suites all — ccc2' \
  'phase 1: merged to base (ddd1)' 'batch 2: landed (ddd1)'
sched
assert_eq 'batch 5@aaa5|start 2|wait|' "$(joined)" 'the next solo phase goes alone too'
log 'batch 3: opened — phases 5@aaa5' 'batch 3: built eee3' 'batch 3: verified FAIL — pinned on phase 5 — integration suite'
sched
assert_eq 'repair 5 aaa5|batch 6@aaa6|start 2|wait|' "$(joined)" 'a solo failure is pinned on its phase; normal batching resumes'

# --- a one-phase batch is always pinned --------------------------------------------

reset_ledger
log 'phase 5: started — branch phase-5-e'
exec_line 5 aaa5
log 'batch 1: opened — phases 5@aaa5' 'batch 1: built bbb1' 'batch 1: verified FAIL — not pinned — base-only test fails'
sched
assert_eq 'repair 5 aaa5|start 1|start 6|wait|' "$(joined)" 'a batch of one recorded not pinned is pinned on its phase, so it cannot loop'
log 'phase 6: started — branch phase-6-f'
exec_line 6 aaa6
log 'batch 2: opened — phases 5@aaa5 6@aaa6' 'phase 6: batched — batch 2, conflict in 1 files' \
  'phase 6: unresolved — clash' 'batch 2: built ccc2' 'batch 2: verified FAIL — not pinned — unclear'
assert_contains ' repair 2' "$(state_of 5)" 'a batch left with one phase after an unresolved merge is pinned on it'
assert_contains 'batch 2 failed 5 ' "$(state_of batch 2)" 'phase-state: the batch row shows the implied pin'

# --- pins written with spaces, and abandoned batches -----------------------------------

reset_ledger
log 'phase 1: started — branch phase-1-a' 'phase 5: started — branch phase-5-e' 'phase 6: started — branch phase-6-f'
exec_line 1 aaa1
exec_line 5 aaa5
exec_line 6 aaa6
log 'batch 1: opened — phases 1@aaa1 5@aaa5 6@aaa6' 'batch 1: built bbb1' 'batch 1: verified FAIL — pinned on phase 1, 5 — two failures'
assert_contains '5 failing aaa5 ' "$(state_of 5)" 'a pin list with a space after the comma pins every phase in it'
log 'batch 2: opened — phases 6@aaa6' 'batch 2: abandoned — base moved under the batch'
sched
assert_eq 'repair 1 aaa1|repair 5 aaa5|batch 6@aaa6|wait|' "$(joined)" 'an abandoned batch requeues its phases, unflagged'
assert_contains 'batch 2 abandoned ' "$(state_of batch 2)" 'phase-state: the batch is abandoned'

# --- a ladder attempt keeps its batch -------------------------------------------------

log 'phase 1: repair — started (attempt 1/2)'
assert_contains '1 active ' "$(state_of 1)" 'repair started: active'
assert_eq '1' "$(state_of 1 | cut -d' ' -f7)" 'repair started: the batch column still names the failing batch'

# --- the resolver gives up on a phase --------------------------------------------------

reset_ledger
log 'phase 1: started — branch phase-1-a' 'phase 5: started — branch phase-5-e'
exec_line 1 aaa1
exec_line 5 aaa5
log 'batch 1: opened — phases 1@aaa1 5@aaa5' 'phase 1: batched — batch 1, clean merge bbb1' \
  'phase 5: batched — batch 1, conflict in 1 files' 'phase 5: unresolved — both rewrite the session store'
sched
assert_eq 'build 1|start 6|wait|' "$(joined)" 'unresolved: the batch carries on without it; no rescue while the batch is open'
assert_contains '5 failing aaa5 ' "$(state_of 5)" 'phase-state: an unresolved phase is failing'
assert_contains ' rescue 1' "$(state_of 5)" 'phase-state: an unresolved merge goes straight to the rescue'
log 'batch 1: built ccc1' 'batch 1: verified PASS — full suites all — ccc1' 'phase 1: merged to base (ddd1)' 'batch 1: landed (ddd1)'
sched
assert_eq 'rescue 5 aaa5|start 2|start 3|wait|' "$(joined)" 'the batch landed: the rescue starts'

# --- holds -----------------------------------------------------------------------------

reset_ledger
log 'phase 1: started — branch phase-1-a' 'phase 1: merged to base (aaa1)' \
  'phase 2: started — branch phase-2-b' 'phase 3: started — branch phase-3-c' \
  'phase 3: held — waits on phase 2 (overlap src/a.ts)'
sched 2-4 3
assert_eq 'wait|' "$(joined)" 'held phase stays held while its blocker builds'
assert_contains '3 held 2 ' "$(state_of 3)" 'phase-state reports the hold and its blocker'
log 'phase 2: merged to base (bbb2)'
sched 2-4 3
assert_eq 'rescout 3|wait|' "$(joined)" 'blocker merged: rescout the held phase'

# --- draining --------------------------------------------------------------------------

reset_ledger
log 'phase 1: started — branch phase-1-a' 'phase 5: started — branch phase-5-e' \
  'phase 5: failed — ladder exhausted' 'run: draining — phase 5 ladder exhausted'
sched
assert_eq 'wait|' "$(joined)" 'draining: nothing new starts while phase 1 finishes'
exec_line 1 abc1
sched
assert_eq 'batch 1@abc1|wait|' "$(joined)" 'draining: in-flight phases still batch'
log 'batch 1: opened — phases 1@abc1' 'batch 1: built iii1' 'batch 1: verified PASS — full suites all — iii1' \
  'phase 1: merged to base (jjj1)' 'batch 1: landed (jjj1)'
sched
assert_eq 'done|' "$(joined)" 'draining: done once in-flight phases land'
assert_contains "$(printf 'run\tdraining')" "$(cd "$tmp" && "$STATE" "$tmp/spec.md")" 'phase-state reports draining'

log 'phase 5: executed — owner fix on resume, HEAD kkk5'
sched
assert_eq 'batch 5@kkk5|wait|' "$(joined)" 'resume: a requeued failed phase is batched while draining, nothing starts'
log 'batch 2: opened — phases 5@kkk5' 'batch 2: built lll2' 'batch 2: verified PASS — full suites all — lll2' \
  'run: undrained — phase 5 verified PASS' 'phase 5: merged to base (mmm5)' 'batch 2: landed (mmm5)'
sched
assert_eq 'start 2|start 3|start 6|wait|' "$(joined)" 'undrained: scheduling resumes'

# --- ledgers from earlier flows -----------------------------------------------------------

reset_ledger
log 'phase 1: started — branch phase-1-a' 'phase 5: started — branch phase-5-e' \
  'phase 1: executed — a0a0a0a..aaa1, review 0/0/0 (0 fixed, 0 deferred), 0 significant' \
  'phase 1: verifier dispatched' \
  'phase 5: executed — b0b0b0b..aaa5, review 0/0/0 (0 fixed, 0 deferred), 0 significant' \
  'phase 5: verifier dispatched' 'phase 5: verified PASS eee5'
sched
assert_eq 'batch 5@eee5|start 6|wait|' "$(joined)" 'earlier flow: verified PASS queues; a phase verifier still out keeps its phase active'
assert_contains '1 active ' "$(state_of 1)" 'earlier flow: executed with its phase verifier out is active'
log 'phase 1: verified PASS fff1' 'phase 1: integrating — base unchanged, ready fff1'
assert_contains '1 active ' "$(state_of 1)" 'per-phase flow: an open per-phase integration is active, for the controller to requeue'
log 'phase 1: executed — requeued for batching, HEAD fff1'
assert_contains '1 queued fff1 ' "$(state_of 1)" 'per-phase flow: requeued, it is batched like any phase'

finish
