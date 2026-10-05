#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../../../skills/building-phased-specs-in-parallel" && pwd)
BUILDING=$(cd "$here/../../../skills/building-phased-specs" && pwd)

# has FILE NEEDLE MESSAGE — the file must contain NEEDLE verbatim.
# NEEDLE must be free of '*', '?' and '[' — assert_contains globs.
has() { assert_contains "$2" "$(cat "$ROOT/$1" 2>/dev/null)" "$1: $3"; }

exists() {
  assert_eq 'yes' "$([ -f "$ROOT/$1" ] && echo yes || echo no)" "$1 exists"
}

# Templates an agent works in a phase worktree from.
WORKTREE_TEMPLATES='scout-prompt.md lead-prompt.md worker-prompt.md reviewer-prompt.md
repair-prompt.md rescue-prompt.md resolver-prompt.md
integration-verifier-prompt.md overlap-judge-prompt.md'
TEMPLATES="$WORKTREE_TEMPLATES graph-prompt.md"

# --- policies --------------------------------------------------------------

exists testing-policy.md
assert_eq 'yes' \
  "$(cmp -s "$ROOT/testing-policy.md" "$BUILDING/testing-policy.md" && echo yes || echo no)" \
  'testing-policy.md is byte-identical to the building-phased-specs copy'

exists decision-policy.md
blocked_section() { sed -n '/^## When to return BLOCKED/,$p' "$1"; }
assert_eq "$(blocked_section "$BUILDING/decision-policy.md")" \
  "$(blocked_section "$ROOT/decision-policy.md")" \
  'decision-policy.md: the BLOCKED section matches building-phased-specs word for word'
has decision-policy.md 'building-phased-specs-in-parallel' 'names this skill'
has decision-policy.md 'Resolve, record, continue' 'states the default: decide and keep going'
has decision-policy.md '## The worktree boundary' 'adds the worktree boundary rule'
has decision-policy.md 'another phase' 'forbids touching other phases'
has decision-policy.md 'main checkout' 'forbids touching the main checkout'
has decision-policy.md 'It is exhaustive' 'the BLOCKED list is stated as exhaustive'
has decision-policy.md 'Missing credentials, access, or a required host approval' 'BLOCKED case 1'
has decision-policy.md 'cannot be installed with the' 'BLOCKED case 2'
has decision-policy.md 'The host cannot nest agents' 'BLOCKED case 3'
has decision-policy.md 'destructive or outside the repository' 'BLOCKED case 4'

# --- scout-prompt.md -------------------------------------------------------

exists scout-prompt.md
has scout-prompt.md 'SETUP_COMMAND' 'receives the setup command'
has scout-prompt.md 'Make the worktree runnable' 'runs setup before grounding'
has scout-prompt.md 'Setup: <' 'records the setup command in the brief'
has scout-prompt.md 'MERGED_PHASES' 'receives the merged phases'
has scout-prompt.md 'Do not read the decisions files of in-flight phases' 'reads merged phases decisions only'
has scout-prompt.md 'IN_FLIGHT_PHASES' 'receives the in-flight phases'
has scout-prompt.md 'prereq-inflight: phase <M>' 'reports an in-flight prerequisite'
has scout-prompt.md 'prereq-inflight: none' 'reports no in-flight prerequisite'
has scout-prompt.md 'Skip setup in that case' 'a re-scout skips setup'
has scout-prompt.md 'every path in backticks' 'Files lines carry backticked paths for the overlap check'
has scout-prompt.md 'Do not assume a claim is true' 'grounds claims in the code'
has scout-prompt.md 'never a reason to stop' 'drift never stops the scout'
has scout-prompt.md 'BRIEF_PATH already exists' 'the scout resumes an existing brief'
has scout-prompt.md 'Tier: mechanical' 'assigns task tiers'
has scout-prompt.md 'five lines' 'return contract is capped'

# --- lead-prompt.md --------------------------------------------------------

exists lead-prompt.md
has lead-prompt.md 'WORKER_TEMPLATE_PATH' 'receives the worker template'
has lead-prompt.md 'REVIEWER_TEMPLATE_PATH' 'receives the reviewer template'
has lead-prompt.md 'PHASE_BASE_SHA' 'receives the phase base for the review range'
has lead-prompt.md 'dispatch WORKTREE as its repository path' 'passes the worktree to its children'
has lead-prompt.md '`Tier: mechanical`' 'applies the brief tier'
has lead-prompt.md 'Never downgrade a task the brief marks `standard`' 'never downgrades a standard task'
has lead-prompt.md 'Do not review again' 'no re-review after the fix wave'
has lead-prompt.md 'first unticked task' 'the lead resumes from the brief'
has lead-prompt.md 'RESUME_NOTES' 'takes a worker return the previous lead never received'
has lead-prompt.md 'instead of dispatching
    the task again' 'never dispatches a second worker for a finished task'
has lead-prompt.md 'ten lines' 'return contract is capped'

# --- worker-prompt.md ------------------------------------------------------

exists worker-prompt.md
has worker-prompt.md 'Task form' 'has a task form'
has worker-prompt.md 'Fix form' 'has a fix form, used for the fix wave'
has worker-prompt.md "in this phase's own worktree" 'works in its worktree'
has worker-prompt.md '`Tier: mechanical`' 'model follows the brief tier'
has worker-prompt.md 'Returning DONE with a failing check is not a valid return' 'no DONE on red'
has worker-prompt.md 'six lines' 'return contract is capped'

# --- reviewer-prompt.md ----------------------------------------------------

exists reviewer-prompt.md
has reviewer-prompt.md 'PHASE_BASE_SHA..HEAD' 'reviews the phase range, not trunk'
has reviewer-prompt.md 'Do NOT edit, fix, or commit' 'the reviewer edits nothing'
has reviewer-prompt.md 'three lines' 'return contract is capped'

# --- repair-prompt.md ------------------------------------------------------

exists repair-prompt.md
has repair-prompt.md 'INTEGRATION_CONTEXT' 'receives the integration context'
has repair-prompt.md 'You get one attempt' 'one attempt'
has repair-prompt.md 'weakening, skipping, or deleting the check' 'never weakens the check'
has repair-prompt.md 'six lines' 'return contract is capped'

# --- rescue-prompt.md ------------------------------------------------------

exists rescue-prompt.md
has rescue-prompt.md 'EVIDENCE_PATHS' 'receives every evidence file'
has rescue-prompt.md 'REPAIR_REPORT_PATH' 'receives the repair report'
has rescue-prompt.md 'RESCUE_REPORT_PATH' 'writes a rescue report'
has rescue-prompt.md 'CONFLICTS_PATH' 'receives an unresolved conflict'
has rescue-prompt.md 'There is never a third attempt' 'is the last attempt'
has rescue-prompt.md 'significant decision' 'every departure is significant'
has rescue-prompt.md 'git merge --no-ff BASE' 'may redo the integration merge'
has rescue-prompt.md 'weakening, skipping, or deleting' 'never weakens the check'
has rescue-prompt.md 'the most capable model available' 'rescue is most capable'
has rescue-prompt.md 'FIXED or STILL_BROKEN' 'returns FIXED or STILL_BROKEN'
has rescue-prompt.md 'six lines' 'return contract is capped'

# --- resolver-prompt.md ----------------------------------------------------

exists resolver-prompt.md
has resolver-prompt.md 'CONFLICTS_PATH' 'receives the conflicts file'
has resolver-prompt.md 'MERGED_PHASE_BRIEFS' 'receives the merged phases briefs'
has resolver-prompt.md 'both sides' 'keeps both sides behaviour'
has resolver-prompt.md 'Lockfiles are never hand-merged' 'regenerates lockfiles'
has resolver-prompt.md 'Conflicts are expected here' 'expects conflicts between phases that share files'
has resolver-prompt.md 'resolve the sources first, then rerun the generator' 'regenerates generated files'
has resolver-prompt.md "take the
         base branch's metadata and migrations as they are" 'keeps the base migration metadata'
has resolver-prompt.md 'regenerate it with the repository'"'"'s migration generator' 'rebuilds its own migration on top'
has resolver-prompt.md 'keep every key from both sides' 'merges translation catalogues key by key'
has rescue-prompt.md 'ORM migration metadata' 'regenerates migration metadata when it redoes the merge'
has resolver-prompt.md 'git merge --abort' 'aborts an unresolvable merge'
has resolver-prompt.md 'RESOLVED <short merge commit SHA>' 'returns RESOLVED with the SHA'
has resolver-prompt.md 'UNRESOLVED' 'can return UNRESOLVED'
has resolver-prompt.md 'the most capable model available' 'resolver is most capable'
has resolver-prompt.md 'four lines' 'return contract is capped'

# --- overlap-judge-prompt.md -------------------------------------------------

exists overlap-judge-prompt.md
has overlap-judge-prompt.md 'OVERLAP_PATH' 'receives the overlap pairs file'
has overlap-judge-prompt.md 'IN_FLIGHT_BRIEFS' 'receives the in-flight phases briefs'
has overlap-judge-prompt.md 'VERDICT_PATH' 'writes one verdict file'
has overlap-judge-prompt.md 'Hold only when both phases make a **major change to the same domain**' 'states the owner rule'
has overlap-judge-prompt.md 'When you are unsure, run' 'doubt runs, not holds'
has overlap-judge-prompt.md 'hold on the lowest' 'names one phase to hold on'
has overlap-judge-prompt.md 'Read only. You write VERDICT_PATH and nothing else' 'is read-only'
has overlap-judge-prompt.md 'RUN — <one-line reason>, or HOLD <M>' 'returns RUN or HOLD M'
has overlap-judge-prompt.md 'the most capable model available' 'the judge is most capable'
has overlap-judge-prompt.md 'three lines' 'return contract is capped'
assert_eq '' "$(grep -n 'DECISION_POLICY_PATH' "$ROOT/overlap-judge-prompt.md" || true)" \
  'overlap-judge-prompt.md: decides a verdict, not implementation, so takes no decision policy'

# --- integration-verifier-prompt.md -----------------------------------------

exists integration-verifier-prompt.md
has integration-verifier-prompt.md 'INTEGRATION_EVIDENCE_PATH' 'writes integration evidence'
has integration-verifier-prompt.md 'SETUP_COMMAND' 'receives the setup command'
has integration-verifier-prompt.md 'manifest or lockfile' 're-runs setup when the merge changed dependencies'
has integration-verifier-prompt.md 'Report the exit code of every command' 'the exit-code rule'
has integration-verifier-prompt.md 'looks green and whose exit code is 1 is a FAIL' 'an all-green print with a non-zero exit is a FAIL'
has integration-verifier-prompt.md 'Acceptance check' 'runs the acceptance check'
has integration-verifier-prompt.md 'met, untested' 'grades untested deliverables'
has integration-verifier-prompt.md 'decision that removed or replaced it' 'an unexplained missing item fails'
has integration-verifier-prompt.md 'MERGED_PHASES' 'knows which phases merged into base since the phase began'
has integration-verifier-prompt.md 'judge them, not those of' 'judges acceptance on this phase alone'
has integration-verifier-prompt.md 'base never moved' 'verifies a ready integration too'
has integration-verifier-prompt.md 'no verification of its own' 'handles a phase with no Verification section'
has integration-verifier-prompt.md 'test:integration' 'runs a separate integration-test suite'
has integration-verifier-prompt.md 'end-to-end' 'runs an end-to-end suite'
has integration-verifier-prompt.md 'A skipped suite never counts' 'a skipped suite is never a pass'
has integration-verifier-prompt.md 'FULL_SUITE_POLICY' 'takes the full-suite policy'
has integration-verifier-prompt.md 'once per phase' 'can keep the full suites to one run per phase'
has integration-verifier-prompt.md 'The scope
       is narrow' 're-verifies a narrow repair narrowly'
has integration-verifier-prompt.md 'never overwrite' 'appends to the evidence, so the next verifier reads what ran'
has integration-verifier-prompt.md "as the line's last word" 'ends its PASS line in the SHA'
has integration-verifier-prompt.md 'Do NOT fix anything' 'the integration verifier does not repair'
has integration-verifier-prompt.md 'a mid-tier model' 'the integration verifier is mid-tier'
has integration-verifier-prompt.md 'three lines' 'return contract is capped'

# --- graph-prompt.md -------------------------------------------------------

exists graph-prompt.md
has graph-prompt.md 'GRAPH_PATH' 'writes the graph file'
has graph-prompt.md 'PHASE_LIST' 'receives the phase list'
has graph-prompt.md 'Never read independence into' 'silence means sequential'
has graph-prompt.md 'agent' 'marks its lines with source agent'
has graph-prompt.md 'a mid-tier model' 'the graph agent is mid-tier'
has graph-prompt.md 'three lines' 'return contract is capped'
assert_eq '' "$(grep -n 'WORKTREE' "$ROOT/graph-prompt.md" || true)" \
  'graph-prompt.md: the graph agent works from the document, not a worktree'

# --- rules binding on every template --------------------------------------

for t in $TEMPLATES; do
  exists "$t"
  has "$t" 'general-purpose' 'dispatches a general-purpose subagent'
  has "$t" 'model:' 'names a model explicitly'
  has "$t" '## Return contract' 'states a return contract'
  if [ "$t" != lead-prompt.md ]; then
    has "$t" 'Do not spawn subagents' 'is a leaf and spawns nothing'
  fi
  assert_eq '' "$(grep -n 'REPO_ROOT' "$ROOT/$t" || true)" \
    "$t: no REPO_ROOT left over from the sequential skill"
  assert_eq '' "$(grep -n 'paste' "$ROOT/$t" | grep -iv 'do not paste' || true)" \
    "$t: never asks an agent to paste an artifact into its return value"
  assert_eq '' "$(grep -n 'superpowers:' "$ROOT/$t" || true)" \
    "$t: depends on no Superpowers skill"
done

for t in $WORKTREE_TEMPLATES; do
  has "$t" "Repository: WORKTREE (absolute path of this phase's worktree" 'works in the phase worktree'
  has "$t" 'Do NOT touch the main checkout, the base' 'states the worktree boundary'
  has "$t" 'BASE' 'names the base branch it must not touch'
done

for t in scout-prompt.md lead-prompt.md worker-prompt.md repair-prompt.md \
         rescue-prompt.md resolver-prompt.md; do
  has "$t" 'DECISION_POLICY_PATH' 'receives the decision policy'
done

finish
