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
git -C "$tmp" init -q
printf '## Phase 1 — A\n## Phase 2 — B\n## Phase 3 — C\n## Phase 4 — D\n## Phase 5 — E\n' > "$tmp/spec.md"
rundir="$tmp/.superpowers/phase-parallel/spec"
mkdir -p "$rundir"
# 2 and 3 depend on 1; 4 on 2 and 3; 5 on nothing.
printf '1\t-\tline\n2\t1\tline\n3\t1\tline\n4\t2,3\tline\n5\t-\tline\n' > "$rundir/graph.tsv"
ledger="$rundir/run.md"
reset_ledger() { printf '# Phase run — spec: x\n# base: feat/x  requested: all\n\n' > "$ledger"; }
log() { printf '%s\n' "$@" >> "$ledger"; }

# --- usage ---------------------------------------------------------------------

run_in "$SCHED" "$tmp/spec.md" feat/x all 0
assert_rc 2 'cap 0: usage error'
run_in "$SCHED" "$tmp/spec.md" feat/x all x
assert_rc 2 'non-numeric cap: usage error'

# --- a fresh run -----------------------------------------------------------------

reset_ledger
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_rc 0 'fresh run: exits 0'
assert_eq 'start 1|start 5|wait|' "$(joined)" 'fresh run: starts every phase with no unmerged deps, ascending'
run_in "$SCHED" "$tmp/spec.md" feat/x all 1
assert_eq 'start 1|wait|' "$(joined)" 'cap 1: one start'
run_in "$SCHED" "$tmp/spec.md" feat/x 2-4 3
assert_eq 'start 2|start 3|wait|' "$(joined)" 'deps outside the range count as satisfied'

# --- in flight, cap, and integration ----------------------------------------------

log 'phase 1: started — branch phase-1-a' 'phase 5: started — branch phase-5-e' 'phase 5: scout dispatched'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'wait|' "$(joined)" 'phases in flight, nothing ready: wait'

log 'phase 5: verified PASS aaa5' 'phase 1: verified PASS aaa1'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'integrate 5 aaa5|wait|' "$(joined)" 'integrates the first phase to pass verification, one only'

log 'phase 5: integrating — base unchanged, ready aaa5'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'land 5 aaa5|wait|' "$(joined)" 'ready integration: land it, integrate nothing else'

log 'phase 5: merged to base (bbb5)' 'phase 1: integrating — base moved (phase 5), clean merge ccc1'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'wait|' "$(joined)" 'open integration awaiting its verifier: wait'

log 'phase 1: integration verified FAIL — tests' 'phase 1: repair — started (attempt 1/2)' 'phase 1: integration verified PASS ddd1'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'land 1 ddd1|wait|' "$(joined)" 'integration repaired and passed: land'

log 'phase 1: merged to base (eee1)'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'start 2|start 3|wait|' "$(joined)" 'phase 1 merged: its dependents start'

# --- holds -------------------------------------------------------------------------

log 'phase 2: started — branch phase-2-b' 'phase 3: started — branch phase-3-c' \
  'phase 3: held — waits on phase 2 (overlap src/a.ts)'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'wait|' "$(joined)" 'held phase stays held while its blocker builds'
run_in "$STATE" "$tmp/spec.md"
assert_contains "$(printf '3\theld\t2')" "$OUT" 'phase-state reports the hold and its blocker'

log 'phase 2: verified PASS fff2' 'phase 2: integrating — base unchanged, ready fff2' 'phase 2: merged to base (ggg2)'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'rescout 3|wait|' "$(joined)" 'blocker merged: rescout the held phase'

# --- draining ----------------------------------------------------------------------

reset_ledger
log 'phase 1: started — branch phase-1-a' 'phase 5: started — branch phase-5-e' \
  'phase 5: failed — ladder exhausted' 'run: draining — phase 5 ladder exhausted'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'wait|' "$(joined)" 'draining: nothing new starts while phase 1 finishes'
log 'phase 1: verified PASS hhh1'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'integrate 1 hhh1|wait|' "$(joined)" 'draining: in-flight phases still integrate'
log 'phase 1: integrating — base unchanged, ready hhh1' 'phase 1: merged to base (iii1)'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'done|' "$(joined)" 'draining: done once in-flight phases land'
run_in "$STATE" "$tmp/spec.md"
assert_contains "$(printf 'run\tdraining')" "$OUT" 'phase-state reports draining'

log 'phase 5: verified PASS jjj5' 'run: undrained — phase 5 verified PASS'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'integrate 5 jjj5|start 2|start 3|wait|' "$(joined)" 'undrained: the repaired phase integrates and scheduling resumes'

# --- one verification per phase, on the integrated tree --------------------------

state_of() { # state_of N — the phase's phase-state row, tab-separated
  run_in "$STATE" "$tmp/spec.md"
  printf '%s\n' "$OUT" | awk -F'\t' -v n="$1" '$1 == n' | tr '\t' ' '
}
reset_ledger
log 'phase 1: started — branch phase-1-a' 'phase 5: started — branch phase-5-e' \
  'phase 5: lead dispatched' 'phase 1: lead dispatched' \
  'phase 1: executed — a0a0a0a..aaa1, review 0/1/2 (1 fixed, 2 deferred), 0 significant' \
  'phase 5: executed — b0b0b0b..aaa5, review 0/0/0 (0 fixed, 0 deferred), 1 significant'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'integrate 1 aaa1|wait|' "$(joined)" 'a lead DONE queues the phase for integration at the end of its range, first executed first'
assert_contains '1 queued aaa1 ' "$(state_of 1)" 'phase-state: an executed phase is queued'

log 'phase 1: integrating — base unchanged, ready aaa1'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'wait|' "$(joined)" 'ready is not landable by itself: wait for the integration verifier'
assert_contains '1 integrating ' "$(state_of 1)" 'phase-state: a ready integration of an executed phase stays integrating'

log 'phase 1: integration verifier dispatched' 'phase 1: integration verified FAIL — acceptance: charge-once missing' \
  'phase 1: repair — started (attempt 1/2)' 'phase 1: repair dispatched' 'phase 1: integration verifier dispatched'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'wait|' "$(joined)" 'a failed integration stays open through the ladder: nothing else integrates'
assert_contains '1 integrating ' "$(state_of 1)" 'phase-state: still integrating after a FAIL'
assert_eq '1' "$(state_of 1 | cut -d' ' -f5)" 'phase-state: one ladder attempt used'

log 'phase 1: integration verified FAIL — tests' 'phase 1: rescue — started (attempt 2/2)' \
  'phase 1: integration verified PASS bbb1 (after rescue)'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'land 1 bbb1|wait|' "$(joined)" 'the pass sha is the word after PASS, even with a note after it'
assert_eq '2' "$(state_of 1 | cut -d' ' -f5)" 'phase-state: both ladder attempts counted'

log 'phase 1: merged to base (ccc1)'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'integrate 5 aaa5|start 2|start 3|wait|' "$(joined)" 'the next queued phase integrates once the open one lands'
log 'phase 5: integrating — base moved (phase 1), clean merge ddd5'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'start 2|start 3|wait|' "$(joined)" 'a clean merge waits for the integration verifier'
log 'phase 5: integration verified PASS ddd5'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'land 5 ddd5|start 2|start 3|wait|' "$(joined)" 'the integration verifier passed the merge: land'

# --- a ledger written by the earlier two-verifier flow ---------------------------

reset_ledger
log 'phase 1: started — branch phase-1-a' 'phase 5: started — branch phase-5-e' \
  'phase 1: executed — a0a0a0a..aaa1, review 0/0/0 (0 fixed, 0 deferred), 0 significant' \
  'phase 1: verifier dispatched' \
  'phase 5: executed — b0b0b0b..aaa5, review 0/0/0 (0 fixed, 0 deferred), 0 significant' \
  'phase 5: verifier dispatched' 'phase 5: verified PASS eee5'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'integrate 5 eee5|wait|' "$(joined)" 'earlier flow: verified PASS still queues; a phase verifier still running keeps its phase out of the queue'
assert_contains '1 active ' "$(state_of 1)" 'earlier flow: executed with its phase verifier out is active'
log 'phase 5: integrating — base unchanged, ready eee5'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'land 5 eee5|wait|' "$(joined)" 'earlier flow: ready after a phase verifier pass lands as before'
log 'phase 5: merged to base (fff5)' 'phase 1: verified FAIL — tests' 'phase 1: repair — started (attempt 1/2)'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'wait|' "$(joined)" 'earlier flow: a phase-verifier FAIL under repair waits'
log 'phase 1: executed — repaired, HEAD ggg1'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'integrate 1 ggg1|wait|' "$(joined)" 'a repaired phase requeued at its HEAD integrates'
log 'phase 1: integrating — base moved (phase 5), clean merge hhh1'
assert_contains '1 integrating ' "$(state_of 1)" 'requeued after an earlier-flow verifier: its integration needs the new verifier'

# --- requeue on resume after a drain ----------------------------------------------

reset_ledger
log 'phase 1: started — branch phase-1-a' \
  'phase 1: executed — a0a0a0a..aaa1, review 0/0/0 (0 fixed, 0 deferred), 0 significant' \
  'phase 1: verified PASS aaa1' 'phase 1: integrating — base moved (phase 9), clean merge bbb1' \
  'phase 1: integration verified FAIL — tests' 'phase 1: failed — ladder exhausted' \
  'run: draining — phase 1 ladder exhausted' 'phase 1: executed — owner fix on resume, HEAD ccc1'
run_in "$SCHED" "$tmp/spec.md" feat/x all 3
assert_eq 'integrate 1 ccc1|wait|' "$(joined)" 'resume: a requeued failed phase integrates while draining, nothing starts'
log 'phase 1: integrating — base unchanged, ready ccc1'
assert_contains '1 integrating ' "$(state_of 1)" 'resume: an earlier-flow pass before the failure does not make the new ready landable'

finish
