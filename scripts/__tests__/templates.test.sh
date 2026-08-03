#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../.." && pwd)

# has FILE NEEDLE MESSAGE — the template file must contain NEEDLE verbatim.
# NEEDLE must be free of '*', '?' and '[' — assert_contains globs.
has() { assert_contains "$2" "$(cat "$ROOT/$1")" "$1: $3"; }

exists() {
  assert_eq 'yes' "$([ -f "$ROOT/$1" ] && echo yes || echo no)" "$1 exists"
}

# --- planner-prompt.md -----------------------------------------------------

exists planner-prompt.md
has planner-prompt.md 'superpowers:writing-plans' 'names the skill the planner must invoke'
has planner-prompt.md 'phase PHASE_NUMBER only' 'scopes the plan to one phase'
has planner-prompt.md 'Read the whole design document' 'planner reads the whole document for context'
has planner-prompt.md 'Do NOT present the execution-choice menu' 'override 1: no execution menu'
has planner-prompt.md 'Do NOT execute the plan' 'override 2: no execution'
has planner-prompt.md 'Global Constraints' 'copies cross-cutting constraints into the plan'
has planner-prompt.md 'Commit the plan file' 'planner commits the plan'
has planner-prompt.md 'PLAN_PATH' 'writes to the exact path it was given'
has planner-prompt.md 'Return ONLY the plan file path' 'return contract is the path alone'

# --- repair-prompt.md ------------------------------------------------------

exists repair-prompt.md
has repair-prompt.md 'EVIDENCE_PATH' 'receives the evidence file path'
has repair-prompt.md 'PLAN_PATH' 'receives the plan path'
has repair-prompt.md 'PHASE_BRANCH' 'receives the phase branch'
has repair-prompt.md 'Do NOT switch branches' 'stays on the phase branch'
has repair-prompt.md 'exit code' 'repairs against exit codes, not printed totals'
has repair-prompt.md 'six lines' 'return contract is capped'

# --- executor-prompt.md ----------------------------------------------------

exists executor-prompt.md
has executor-prompt.md 'superpowers:subagent-driven-development' 'names the skill the executor must invoke'
has executor-prompt.md 'PLAN_PATH' 'receives the plan path'
has executor-prompt.md 'PHASE_BRANCH' 'receives the phase branch'
has executor-prompt.md 'DECISIONS_PATH' 'receives the decisions file path'

# The three overrides of subagent-driven-development.
has executor-prompt.md 'Do NOT create or verify a worktree' 'override 1: no worktree'
has executor-prompt.md 'superpowers:using-git-worktrees' 'override 1 names the routing it disables'
has executor-prompt.md 'Do NOT invoke superpowers:finishing-a-development-branch' 'override 2: no branch finishing'
has executor-prompt.md 'Do NOT switch branches' 'override 3: no branch switching'
has executor-prompt.md 'supersede' 'overrides are stated as superseding the skill'

# The two user directives, verbatim.
has executor-prompt.md \
  'Only perform one round of review. After applying any patches/fixes from the first' \
  'directive 1 present verbatim, line 1'
has executor-prompt.md \
  'review, do not run a second pass — mark the task done.' \
  'directive 1 present verbatim, line 2'
has executor-prompt.md \
  "I'm going to be afk. If you hit a situation where you would normally stop and ask for" \
  'directive 2 present verbatim, line 1'
has executor-prompt.md \
  'direction, pick the option you' \
  'directive 2 present verbatim, line 2'
# Directive 2's closing sentence wraps across two lines in the design document,
# and the template copies it byte for byte, so no single contiguous substring
# spans the wrap. Assert the two fragments the wrap actually produces; Task 6
# Step 6's diff against the spec is what guarantees the whole block.
has executor-prompt.md 'and summarise the' 'directive 2 present verbatim, line 3a'
has executor-prompt.md 'decisions taken at the end.' 'directive 2 present verbatim, line 3b'
has executor-prompt.md 'write that summary to DECISIONS_PATH' 'the decisions summary goes to a file, not the reply'

has executor-prompt.md 'ten lines' 'return contract is capped'
has executor-prompt.md 'BLOCKED' 'return contract carries a status'

# --- verifier-prompt.md ----------------------------------------------------

exists verifier-prompt.md
has verifier-prompt.md 'EVIDENCE_PATH' 'receives the evidence file path'
has verifier-prompt.md 'PHASE_BRANCH' 'receives the phase branch'
has verifier-prompt.md 'DESIGN_DOC' 'receives the design document'
has verifier-prompt.md 'did not write this code' 'states that the verifier is independent'
has verifier-prompt.md 'Verification' 'reads the phase Verification section'
has verifier-prompt.md 'no verification of its own' 'handles a phase with no Verification section'
has verifier-prompt.md 'Report the exit code of every command' 'the exit-code rule'
has verifier-prompt.md 'exits non-zero is a FAIL' 'an all-green print with a non-zero exit is a FAIL'
has verifier-prompt.md 'Do NOT fix anything' 'the verifier does not repair'
has verifier-prompt.md 'three lines' 'return contract is capped'

# --- rules binding on every template --------------------------------------

for t in planner-prompt.md repair-prompt.md executor-prompt.md verifier-prompt.md; do
  has "$t" 'general-purpose' 'dispatches a general-purpose subagent'
  has "$t" 'model:' 'names a model explicitly'
  assert_eq '' "$(grep -n 'paste' "$ROOT/$t" | grep -iv 'do not paste' || true)" \
    "$t: never asks an agent to paste an artifact into its return value"
done

finish
