#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../../../skills/orchestrating-phased-specs" && pwd)

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
has planner-prompt.md 'Commit the whole plan directory' 'planner commits the directory'
has planner-prompt.md 'PLAN_PATH' 'writes to the exact path it was given'
has planner-prompt.md 'Return ONLY the plan file path' 'return contract is the path alone'

# Override 3: the plan is a directory — a ledger plus one file per task.
has planner-prompt.md 'Three overrides of superpowers:writing-plans' 'the override count is stated'
has planner-prompt.md 'Split the plan across files' 'override 3: the plan is a directory'
has planner-prompt.md 'task-<N>.md' 'override 3: one file per task, named by number'
has planner-prompt.md 'Produces' 'override 3: the ledger carries the interface map'
has planner-prompt.md 'No task steps in the ledger' 'override 3: task steps never live in the ledger'
has planner-prompt.md 'Global constraints bind this task' 'override 3: the verbatim pointer line'
has planner-prompt.md 'regardless of size' 'override 3: every plan splits, unconditionally'
has planner-prompt.md 'across the whole directory' 'override 3: self-review covers every file'

# --- repair-prompt.md ------------------------------------------------------

exists repair-prompt.md
has repair-prompt.md 'EVIDENCE_PATH' 'receives the evidence file path'
has repair-prompt.md 'PLAN_PATH' 'receives the plan path'
has repair-prompt.md 'PHASE_BRANCH' 'receives the phase branch'
has repair-prompt.md 'Do NOT switch branches' 'stays on the phase branch'
has repair-prompt.md 'exit code' 'repairs against exit codes, not printed totals'
has repair-prompt.md 'six lines' 'return contract is capped'
has repair-prompt.md 'task-<N>.md' 'reads only the task files the failure touches'

# --- executor-prompt.md ----------------------------------------------------

exists executor-prompt.md
has executor-prompt.md 'superpowers:subagent-driven-development' 'names the skill the executor must invoke'
has executor-prompt.md 'PLAN_PATH' 'receives the plan path'
has executor-prompt.md 'PHASE_BRANCH' 'receives the phase branch'
has executor-prompt.md 'DECISIONS_PATH' 'receives the decisions file path'

# The five overrides of subagent-driven-development.
has executor-prompt.md 'Do NOT create or verify a worktree' 'override 1: no worktree'
has executor-prompt.md 'superpowers:using-git-worktrees' 'override 1 names the routing it disables'
has executor-prompt.md 'Do NOT invoke superpowers:finishing-a-development-branch' 'override 2: no branch finishing'
has executor-prompt.md 'Do NOT switch branches' 'override 3: no branch switching'
has executor-prompt.md 'Do NOT review between tasks' 'override 4: no per-task review'
has executor-prompt.md 'exactly ONE review' 'override 4 names what replaces the per-task loop'
has executor-prompt.md 'whole-branch review after the final task' 'override 4 places the single review at the end'
has executor-prompt.md 'Do not re-review after that wave' 'override 4 caps the fix wave'
has executor-prompt.md 'breadth proportionate to the phase' 'override 4 compensates by widening the one review'
has executor-prompt.md 'fix it before you dispatch the next task' 'override 4 keeps failing task checks blocking'
has executor-prompt.md 'Five overrides' 'the override count is stated'
has executor-prompt.md 'Read the ledger once' 'override 5: exactly one plan-level read'
has executor-prompt.md 'scripts/task-brief' 'override 5: names the script it disables'
has executor-prompt.md 'task-<N>.md' 'override 5: the task file is the brief'
has executor-prompt.md 'task-<N>-report.md' 'override 5: reports stay in the workspace'
has executor-prompt.md 'Produces column' 'override 5: cross-task interfaces come from the ledger'
has executor-prompt.md 'scoped to the ledger' 'override 5: the conflict scan is scoped'
has executor-prompt.md 'supersede' 'overrides are stated as superseding the skill'

# Decisions remain within the actual request; no fabricated user quotation.
has executor-prompt.md 'does not grant additional permission' 'decisions do not expand authorization'
has executor-prompt.md 'Write that summary to DECISIONS_PATH' 'decisions persist in the report file'

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
