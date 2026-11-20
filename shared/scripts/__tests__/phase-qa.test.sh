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
# As the skill's wrappers set it: the run directory is the main checkout's,
# whichever worktree a script is called from.
export PHASE_RUN_ANCHOR=main
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
# Base lives in its own worktree, where the controller works and QA fixes
# land. The main checkout stays on the owner's branch, with work in progress.
bwt="$repo/.worktrees/base"
spec="$bwt/spec.md"
origin="$tmp/origin.git"
run_in() {
  set +e
  OUT=$(cd "$bwt" && "$@" 2>&1)
  RC=$?
  set -e
}
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
git -C "$repo" symbolic-ref HEAD refs/heads/main
git init -q --bare "$origin"
git -C "$repo" remote add origin "$origin"
printf '# Example — Design Spec\n## Phase 1 — One\n## Phase 2 — Two\n' > "$repo/spec.md"
printf 'shared\n' > "$repo/shared.txt"
git -C "$repo" add spec.md shared.txt
git -C "$repo" commit -qm initial
git -C "$repo" branch feat/x
mkdir -p "$repo/.worktrees"
printf '*\n' > "$repo/.worktrees/.gitignore"
git -C "$repo" worktree add -q "$bwt" feat/x
printf 'work in progress\n' > "$repo/wip.txt"
main_head=$(git -C "$repo" rev-parse HEAD)
rundir="$repo/.superpowers/phase-parallel/spec"
ledger="$rundir/run.md"
iwt="$repo/.worktrees/integration"
log() { printf '%s\n' "$@" >> "$ledger"; }
reset_ledger() { # start the ledger again, then append the lines given
  mkdir -p "$rundir"
  printf '# Phase run — spec: %s\n# base: feat/x  requested: 1-2\n\n' "$spec" > "$ledger"
  [ "$#" -eq 0 ] || log "$@"
}
qa() { run_in "$QA" "$spec" feat/x "$@"; }
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

commit_in "$bwt" two.txt two
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

# --- land ---------------------------------------------------------------------------

reset_ledger 'run: qa scope — all'
qa open
commit_in "$iwt" fix.txt fix
f=$(tip phase-qa-spec)
qa land "$f"
assert_rc 22 'land: refuses a commit the ledger does not show as verified'
log 'qa: verified FAIL — unit suite'
qa land "$f"
assert_rc 22 'land: a FAIL is not a PASS'
log "qa: verified PASS — $f"
printf 'stray\n' > "$bwt/stray.txt"
qa land "$f"
assert_rc 11 'land: refuses a dirty base worktree'
rm "$bwt/stray.txt"
qa land "$(tip feat/x)"
assert_rc 19 'land: refuses a commit the QA branch is not at'
qa land "$f"
assert_rc 0 'land: exits 0'
assert_eq "qa landed on feat/x ($f)" "$OUT" 'land: prints what landed'
assert_eq "$f" "$(tip feat/x)" 'land: base is at the verified commit'
assert_contains "qa: landed ($f)" "$(cat "$ledger")" 'land: recorded'
assert_contains "push: feat/x at $f" "$(cat "$ledger")" 'land: base is pushed'
assert_eq '' "$(git -C "$iwt" branch --show-current)" 'land: the integration worktree is detached'
assert_eq "$f" "$(git -C "$iwt" rev-parse --short HEAD)" 'land: the integration worktree is on the base tip'
assert_eq 'no' "$(git -C "$repo" show-ref --verify --quiet refs/heads/phase-qa-spec && echo yes || echo no)" 'land: the QA branch is deleted'
assert_eq "$f" "$(git -C "$bwt" rev-parse --short HEAD)" 'land: the base worktree is at the verified commit'
assert_eq "$main_head" "$(git -C "$repo" rev-parse HEAD)" 'land: the main checkout is not moved'
assert_eq 'main' "$(git -C "$repo" branch --show-current)" 'land: the main checkout stays on the branch of its owner'
assert_eq 'work in progress' "$(cat "$repo/wip.txt")" 'land: work in progress in the main checkout is untouched'
qa land "$f"
assert_rc 17 'land: refuses a second landing'

# Interrupted after the fast-forward, before the ledger line.
reset_ledger 'run: qa scope — all'
qa open
commit_in "$iwt" fix2.txt fix2
f2=$(tip phase-qa-spec)
log "qa: verified PASS — $f2"
git -C "$bwt" merge -q --ff-only phase-qa-spec
qa land "$f2"
assert_rc 0 'land: a re-run after an interruption finishes the landing'
assert_contains "qa: landed ($f2)" "$(cat "$ledger")" 'land: the re-run records it'

# --- push ---------------------------------------------------------------------------

reset_ledger 'run: qa scope — all'
qa push
assert_rc 0 'push: a missing QA branch is recorded, not fatal'
assert_eq 'push: phase-qa-spec failed — the branch does not exist' "$OUT" 'push: says the branch is missing'
assert_contains 'push: phase-qa-spec failed — the branch does not exist' "$(cat "$ledger")" 'push: the missing branch is in the ledger, so next moves on'
qa open
commit_in "$iwt" fix3.txt fix3
f3=$(tip phase-qa-spec)
qa push
assert_rc 0 'push: exits 0'
assert_eq "push: phase-qa-spec at $f3" "$OUT" 'push: prints what it pushed'
assert_eq "$(git -C "$repo" rev-parse phase-qa-spec)" "$(git -C "$origin" rev-parse refs/heads/phase-qa-spec)" 'push: origin holds the QA branch'
assert_contains "push: phase-qa-spec at $f3" "$(cat "$ledger")" 'push: recorded'
git -C "$repo" remote rename origin away
qa push
assert_rc 0 'push: a failed push still exits 0'
assert_contains 'push: phase-qa-spec failed — ' "$OUT" 'push: the failure is recorded'
git -C "$repo" remote rename away origin

# --- land: the main checkout is elsewhere, or base moved ----------------------------

log "qa: verified PASS — $f3"
git -C "$bwt" switch -q -c elsewhere
qa land "$f3"
assert_rc 13 'land: refuses when the base worktree is not on base'
git -C "$bwt" switch -q feat/x
commit_in "$bwt" moved.txt moved
qa land "$f3"
assert_rc 21 'land: refuses when base moved past what the QA branch was built on'
assert_eq 'yes' "$(git -C "$repo" show-ref --verify --quiet refs/heads/phase-qa-spec && echo yes || echo no)" 'land: a refusal keeps the QA branch'

# --- report -------------------------------------------------------------------------

reset_ledger 'run: invoked — cap 3'
qa report
assert_eq 'qa: not run — not requested' "$OUT" 'report: no scope'
reset_ledger 'run: qa scope — top 5' 'qa: skipped — phase 2 did not land'
qa report
assert_eq 'qa: skipped — phase 2 did not land' "$OUT" 'report: skipped, with its reason'

full_ledger() {
  reset_ledger 'run: qa scope — top 5' 'phase 1: merged to base (aaa1)' 'phase 2: merged to base (aaa1)' \
    'batch 1: landed (aaa1)' 'qa: opened — phase-qa-spec at aaa1' \
    'qa: flows defined — 7 found, selected 1,2,3,4,5, not walkable 4, parallel yes' \
    'qa flow 1: walked — 0 findings' 'qa flow 2: walked — 3 findings' \
    'qa flow 3: not walked — the simulator would not boot' 'qa flow 5: walked — 1 findings' \
    'qa: triaged — 4 findings, fix G1@2 G2@5 G3@2,5, 1 spec, 2 outside this run' \
    'qa group 1: fixed 3c4d5e6' 'qa group 2: not fixed — did not reproduce' 'qa group 3: fixed 5e6f7a8'
}
full_ledger
log 'qa: verified PASS — 5e6f7a8' 'qa: landed (5e6f7a8)' \
  'qa flow 2: rechecked — G1 confirmed, G3 still broken, 1 new' 'qa flow 5: rechecked — G3 confirmed, 0 new' \
  'qa: done — 1 confirmed, 1 still broken, 1 not fixed, 1 new, 1 spec'
cat > "$rundir/qa-flows.md" <<'EOF'
- [selected] F1 — signup
- [selected] F2 — checkout
- [selected] F3 — onboarding
- [not walkable] F4 — share sheet: no available tool can drive the native share sheet
- [selected] F5 — search
- [not selected] F6 — export
- [not selected] F7 — settings

# Flows

qa: done — a line an agent wrote in its own file is not a ledger line
EOF
cat > "$rundir/qa-triage.md" <<'EOF'
- [fix] G1 — checkout: total ignores the second coupon (broken)
- [fix] G2 — search: empty state flashes before results (minor)
- [fix] G3 — checkout: coupon lost on back navigation (broken)
- [spec] G4 — refunds: no way to see store credit — proposed: show the balance on the account page
- [outside this run] G5 — settings: avatar upload fails
- [outside this run] G6 — export: phase 6 delivers it
EOF
printf '%s\n' '- [confirmed] G1' '- [still broken] G3 — lost again after two back steps' \
  '- [new] order summary shows the old total for a moment' > "$rundir/qa-flow-2-recheck.md"
printf '%s\n' '- [confirmed] G3' > "$rundir/qa-flow-5-recheck.md"
before=$(cat "$ledger")
qa report
assert_rc 0 'report: exits 0'
assert_eq "qa: 3 of 7 flows walked on aaa1 (scope: top 5)
  not walked: 2
    flow 3 onboarding — the simulator would not boot
    flow 4 share sheet — no available tool can drive the native share sheet
  not selected: flow 6 export, flow 7 settings
  fixed and confirmed: 1
    G1 checkout: total ignores the second coupon
  still open: 2
    G3 checkout: coupon lost on back navigation — still broken after the fix (broken)
    G2 search: empty state flashes before results — not fixed: did not reproduce (minor)
  new at re-check, not investigated: 1
    flow 2: order summary shows the old total for a moment
  spec questions, nothing changed: 1
    G4 refunds: no way to see store credit — proposed: show the balance on the account page
  outside this run: 2
  details: $rundir/qa-triage.md, $rundir/qa-flows.md" "$OUT" 'report: the whole block'
assert_eq "$before" "$(cat "$ledger")" 'report: writes nothing'

full_ledger
log 'qa: verified FAIL — unit suite' 'push: phase-qa-spec at 5e6f7a8' \
  'qa: done — 0 confirmed, 0 still broken, 1 not fixed, 0 new, 1 spec, 2 fixed but not landed'
qa report
assert_contains "  fixed on phase-qa-spec, not landed: 2
    G1 checkout: total ignores the second coupon
    G3 checkout: coupon lost on back navigation
    gates: $rundir/qa-gates-evidence.md" "$OUT" 'report: fixes that failed the gates are listed as not landed'
assert_contains '  still open: 1
    G2 search' "$OUT" 'report: not landed fixes are not counted as open twice'

rm "$rundir"/qa-flows.md "$rundir"/qa-triage.md "$rundir"/qa-flow-2-recheck.md "$rundir"/qa-flow-5-recheck.md
qa report
assert_rc 0 'report: missing index files do not fail it'
assert_contains '    flow 3 — the simulator would not boot' "$OUT" 'report: a flow without a title is printed by number'
assert_contains '    G2 — not fixed: did not reproduce' "$OUT" 'report: a group without index text is printed by id'

full_ledger
log 'batch 2: landed (bbb2)' 'qa: done — abandoned, base moved under the pass'
qa report
assert_contains '  abandoned: base moved under the pass' "$OUT" 'report: an abandoned pass says so'

# --- the lines a real controller writes: variants, and lines nobody can read ---------

pass_ledger '2 found, selected F1,F2, not walkable -, parallel yes'
nx 'walk 1 2' 'flow numbers written with their F'
log 'qa flow F1: walked — 1 findings' 'qa flow 2: walked - 0 findings'
nx 'triage' 'a flow line with its F, or with a hyphen for the dash, is still an outcome'
log 'qa: triaged — 1 findings, fix: G1@1, G2@2, 0 spec, 0 outside this run'
nx 'fix 1' 'a colon after fix and a comma between groups'
log 'qa group G1: fixed 1111111' 'qa group 2: fixed 2222222' 'qa: verified PASS — full suites all — 2222222'
nx 'land 2222222' 'the verified commit is the last word of the line'
log 'qa: landed (2222222)'
nx 'recheck 1 2' 'both groups were read'
pass_ledger '5 found, selected: 1,2, not walkable: -, parallel: no'
nx 'walk 1' 'colons copied from the return'

pass_ledger '2 found, selected one and two, not walkable -, parallel yes'
closes 'qa: done — stopped: unreadable ledger line: qa: flows defined — 2 found, selected one and two, not walkable -, parallel yes' \
  'a list nobody can read stops the pass instead of looping'
qa report
assert_contains '  stopped: unreadable ledger line: qa: flows defined' "$OUT" 'report: a stopped pass says why'
pass_ledger '1 found, selected 1, not walkable -, parallel yes' 'qa flow 1: strolled about'
closes 'qa: done — stopped: unreadable ledger line: qa flow 1: strolled about' 'an outcome line of no known shape stops the pass'
pass_ledger '1 found, selected 1, not walkable -, parallel yes' 'qa flow 1: walked — 1 findings' \
  'qa: triaged — 1 findings, fix the lot, 0 spec, 0 outside this run'
closes 'qa: done — stopped: unreadable ledger line: qa: triaged — 1 findings, fix the lot, 0 spec, 0 outside this run' \
  'fix groups nobody can read stop the pass instead of being dropped'

pass_ledger '1 found, selected 1, not walkable -, parallel yes' 'qa flow 1: walked — 1 findings' \
  'qa: triaged — 1 findings, fix G1@1, 0 spec, 0 outside this run' 'qa group 1: fixed 1111111' \
  'qa: verified PASS — 1111111' 'qa: landed (1111111)' 'qa flow 1: rechecked — G1 not rechecked, 0 new'
closes 'qa: done — 0 confirmed, 0 still broken, 0 not fixed, 0 new, 0 spec, 1 not re-checked' \
  'a re-check that could not be done is an outcome, and is counted'

# The requested phases are this invocation's, not the ones the ledger was created with.
reset_ledger 'run: qa scope — all' 'phase 1: merged to base (aaa1)' 'batch 1: landed (aaa1)'
qa next 1
assert_eq 'open' "$OUT" 'next RANGE: only the phases of this invocation must have landed'
qa next 1-2
assert_eq 'skip phase 2 did not land' "$OUT" 'next RANGE: a wider range than the header is checked too'
nx 'skip phase 2 did not land' 'without a range the ledger header is used'

# The verified commit is the last word of the line, for land as for next.
git -C "$iwt" switch -q --detach feat/x
git -C "$repo" branch -q -D phase-qa-spec
reset_ledger 'run: qa scope — all'
qa open
commit_in "$iwt" fix4.txt fix4
f4=$(tip phase-qa-spec)
log "qa: verified PASS — full suites all — $f4"
qa land "$f4"
assert_rc 0 'land: reads the verified commit as the last word, as next does'

finish
