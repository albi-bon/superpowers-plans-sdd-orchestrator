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

finish
