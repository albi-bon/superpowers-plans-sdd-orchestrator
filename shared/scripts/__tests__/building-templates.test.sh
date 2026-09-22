#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../../../skills/building-phased-specs" && pwd)

# has FILE NEEDLE MESSAGE — the file must contain NEEDLE verbatim.
# NEEDLE must be free of '*', '?' and '[' — assert_contains globs.
has() { assert_contains "$2" "$(cat "$ROOT/$1" 2>/dev/null)" "$1: $3"; }

exists() {
  assert_eq 'yes' "$([ -f "$ROOT/$1" ] && echo yes || echo no)" "$1 exists"
}

TEMPLATES='scout-prompt.md lead-prompt.md worker-prompt.md reviewer-prompt.md verifier-prompt.md repair-prompt.md'

# --- decision-policy.md ----------------------------------------------------

exists decision-policy.md
has decision-policy.md 'Resolve, record, continue' 'states the default: decide and keep going'
has decision-policy.md '[significant]' 'defines the significant decision line'
has decision-policy.md '[routine]' 'defines the routine decision line'
has decision-policy.md 'changes a public API, a data model or' 'defines what makes a decision significant'
has decision-policy.md 'This is the complete' 'the BLOCKED list is stated as complete'
has decision-policy.md 'It is exhaustive' 'the BLOCKED list is stated as exhaustive'
has decision-policy.md 'Missing credentials, access, or a required host approval' 'BLOCKED case 1'
has decision-policy.md 'cannot be installed with the' 'BLOCKED case 2'
has decision-policy.md 'The host cannot nest agents' 'BLOCKED case 3'
has decision-policy.md 'destructive or outside the repository' 'BLOCKED case 4'
has decision-policy.md 'A design problem is never on this list' 'design problems never block'

# --- testing-policy.md -----------------------------------------------------

exists testing-policy.md
has testing-policy.md 'Done when' 'tests follow the task Done when'
has testing-policy.md 'public surface' 'tests drive the public surface'
has testing-policy.md 'system boundaries' 'mocks only at system boundaries'
has testing-policy.md 'fail once' 'each core behaviour test is seen failing once'
has testing-policy.md 'Static copy, labels' 'bans copy and label assertions'
has testing-policy.md 'snapshots' 'bans snapshots'
has testing-policy.md 'restate the implementation' 'bans implementation-mirroring tests'
has testing-policy.md 'exit code' 'judges by exit code'

# --- scout-prompt.md -------------------------------------------------------

exists scout-prompt.md
has scout-prompt.md 'Read the whole design document' 'reads the whole document'
has scout-prompt.md 'phase-*-decisions.md' 'reads earlier phases decisions'
has scout-prompt.md 'Do not assume a claim is true' 'grounds claims in the code'
has scout-prompt.md 'never a reason to stop' 'drift never stops the scout'
has scout-prompt.md '## Global constraints' 'the brief carries global constraints'
has scout-prompt.md '## Drift' 'the brief carries a drift table'
has scout-prompt.md '**Produces:**' 'tasks carry their produced interfaces'
has scout-prompt.md '**Done when:**' 'tasks carry observable done-when'
has scout-prompt.md '**Test focus:**' 'tasks carry a test focus'
has scout-prompt.md 'no code, no step lists' 'the brief carries no code'
has scout-prompt.md 'edit no source file' 'the scout edits no source'
has scout-prompt.md 'BRIEF_PATH already exists' 'the scout resumes an existing brief'
has scout-prompt.md 'four lines' 'return contract is capped'

# --- lead-prompt.md --------------------------------------------------------

exists lead-prompt.md
has lead-prompt.md 'WORKER_TEMPLATE_PATH' 'receives the worker template'
has lead-prompt.md 'REVIEWER_TEMPLATE_PATH' 'receives the reviewer template'
has lead-prompt.md 'PHASE_BASE_SHA' 'receives the phase base for the review range'
has lead-prompt.md 'do not read the code' 'the lead stays out of the code'
has lead-prompt.md 'one worker' 'one worker per task'
has lead-prompt.md '### - [x] Task K' 'the lead ticks the brief checkbox'
has lead-prompt.md 'affects: task' 'the lead updates later tasks from worker returns'
has lead-prompt.md 'dispatch one reviewer' 'exactly one reviewer'
has lead-prompt.md '## Adjudication' 'the lead records its adjudication'
has lead-prompt.md 'Fix wave' 'one fix wave'
has lead-prompt.md 'Do not review again' 'no re-review after the fix wave'
has lead-prompt.md 'with no exceptions' 'every worker uses the most capable tier'
has lead-prompt.md 'first unticked task' 'the lead resumes from the brief'
has lead-prompt.md 'ten lines' 'return contract is capped'

# --- worker-prompt.md ------------------------------------------------------

exists worker-prompt.md
has worker-prompt.md 'Task form' 'has a task form'
has worker-prompt.md 'Fix form' 'has a fix form, used for the fix wave'
has worker-prompt.md 'the most capable model available, always' 'always the most capable model'
has worker-prompt.md 'the code tells you what is true' 'the code beats the brief'
has worker-prompt.md 'TESTING_POLICY_PATH' 'receives the testing policy'
has worker-prompt.md 'exit code' 'judges checks by exit code'
has worker-prompt.md 'Returning DONE with a failing check is not a valid return' 'no DONE on red'
has worker-prompt.md 'Commit on PHASE_BRANCH' 'the worker commits'
has worker-prompt.md 'affects: task' 'reports effects on later tasks'
has worker-prompt.md 'smallest change that resolves the finding' 'a fix stays the size of its finding'
has worker-prompt.md 'six lines' 'return contract is capped'

# --- reviewer-prompt.md ----------------------------------------------------

exists reviewer-prompt.md
has reviewer-prompt.md 'PHASE_BASE_SHA..HEAD' 'reviews the phase range, not trunk'
has reviewer-prompt.md 'did not write this' 'states that the reviewer is independent'
has reviewer-prompt.md 'critical' 'defines critical'
has reviewer-prompt.md 'important' 'defines important'
has reviewer-prompt.md 'minor' 'defines minor'
has reviewer-prompt.md 'testing policy' 'checks tests against the policy'
has reviewer-prompt.md 'Do NOT edit, fix, or commit' 'the reviewer edits nothing'
has reviewer-prompt.md 'three lines' 'return contract is capped'

# --- verifier-prompt.md ----------------------------------------------------

exists verifier-prompt.md
has verifier-prompt.md 'did not write this code' 'states that the verifier is independent'
has verifier-prompt.md 'no verification of its own' 'handles a phase with no Verification section'
has verifier-prompt.md 'Report the exit code of every command' 'the exit-code rule'
has verifier-prompt.md 'looks green and whose exit code is 1 is a FAIL' 'an all-green print with a non-zero exit is a FAIL'
has verifier-prompt.md 'Acceptance check' 'runs the acceptance check'
has verifier-prompt.md 'met, untested' 'grades untested deliverables'
has verifier-prompt.md '— not implemented' 'grades missing deliverables'
has verifier-prompt.md 'decision that removed or replaced it' 'an unexplained missing item fails'
has verifier-prompt.md 'Do NOT fix anything' 'the verifier does not repair'
has verifier-prompt.md 'a mid-tier model' 'the verifier is mid-tier'
has verifier-prompt.md 'three lines' 'return contract is capped'

# --- repair-prompt.md ------------------------------------------------------

exists repair-prompt.md
has repair-prompt.md 'EVIDENCE_PATH' 'receives the evidence'
has repair-prompt.md 'BRIEF_PATH' 'receives the brief'
has repair-prompt.md 'You get one attempt' 'one attempt'
has repair-prompt.md 'weakening, skipping, or deleting the check' 'never weakens the check'
has repair-prompt.md 'exit code' 'repairs against exit codes'
has repair-prompt.md 'six lines' 'return contract is capped'

# --- rules binding on every template --------------------------------------

for t in $TEMPLATES; do
  has "$t" 'general-purpose' 'dispatches a general-purpose subagent'
  has "$t" 'model:' 'names a model explicitly'
  has "$t" '## Return contract' 'states a return contract'
  has "$t" 'REPO_ROOT' 'receives the repository root'
  assert_eq '' "$(grep -n 'paste' "$ROOT/$t" | grep -iv 'do not paste' || true)" \
    "$t: never asks an agent to paste an artifact into its return value"
  assert_eq '' "$(grep -n 'superpowers:' "$ROOT/$t" || true)" \
    "$t: depends on no Superpowers skill"
done

for t in scout-prompt.md lead-prompt.md worker-prompt.md repair-prompt.md; do
  has "$t" 'DECISION_POLICY_PATH' 'receives the decision policy'
done
for t in scout-prompt.md worker-prompt.md reviewer-prompt.md verifier-prompt.md repair-prompt.md; do
  has "$t" 'Do not spawn subagents' 'is a leaf and spawns nothing'
done

finish
