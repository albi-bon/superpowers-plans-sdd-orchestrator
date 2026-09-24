#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../../../skills/executing-phased-specs" && pwd)
ORCH=$(cd "$here/../../../skills/orchestrating-phased-specs" && pwd)

# has FILE NEEDLE MESSAGE — the template file must contain NEEDLE verbatim.
# NEEDLE must be free of '*', '?' and '[' — assert_contains globs.
has() { assert_contains "$2" "$(cat "$ROOT/$1")" "$1: $3"; }

exists() {
  assert_eq 'yes' "$([ -f "$ROOT/$1" ] && echo yes || echo no)" "$1 exists"
}

# --- shared templates stay in step with orchestrating-phased-specs ----------

for t in planner-prompt.md verifier-prompt.md; do
  exists "$t"
  assert_eq '' "$(diff "$ORCH/$t" "$ROOT/$t" 2>&1)" "$t matches orchestrating-phased-specs"
done

# --- repair-prompt.md ------------------------------------------------------

exists repair-prompt.md
has repair-prompt.md 'executing-plans run' 'names the execution run it follows'
has repair-prompt.md 'EVIDENCE_PATH' 'receives the evidence file path'
has repair-prompt.md 'PLAN_PATH' 'receives the plan path'
has repair-prompt.md 'Do NOT switch branches' 'stays on the phase branch'
has repair-prompt.md 'six lines' 'return contract is capped'

# --- executor-prompt.md ----------------------------------------------------

exists executor-prompt.md
has executor-prompt.md 'superpowers:executing-plans' 'names the skill the executor must invoke'
has executor-prompt.md 'PLAN_PATH' 'receives the plan path'
has executor-prompt.md 'DESIGN_DOC' 'receives the spec for the reviewer'
has executor-prompt.md 'PHASE_BRANCH' 'receives the phase branch'
has executor-prompt.md 'PHASE_BASE_SHA' 'receives the phase base'
has executor-prompt.md 'DECISIONS_PATH' 'receives the decisions file path'
has executor-prompt.md 'REVIEW_PATH' 'receives the review report path'
has executor-prompt.md 'Six overrides' 'the override count is stated'
has executor-prompt.md 'supersede' 'overrides are stated as superseding the skill'

# Overrides 1-3: isolation and integration belong to the orchestrator.
has executor-prompt.md 'Do NOT create or verify a worktree' 'override 1: no worktree'
has executor-prompt.md 'superpowers:using-git-worktrees' 'override 1 names the routing it disables'
has executor-prompt.md 'Do NOT invoke superpowers:finishing-a-development-branch' 'override 2: no branch finishing'
has executor-prompt.md 'Do NOT switch branches' 'override 3: no branch switching'

# Override 4: the split plan, and the script that cannot read it.
has executor-prompt.md 'Read the ledger once' 'override 4: exactly one plan-level read'
has executor-prompt.md 'Do NOT run that skill' 'override 4: disables task-start'
has executor-prompt.md 'scripts/task-start' 'override 4 names the script it disables'
has executor-prompt.md 'exits 3' 'override 4 says why task-start fails'
has executor-prompt.md 'git rev-parse HEAD' 'override 4: BASE is HEAD when the task is taken'
has executor-prompt.md 'scripts/task-done' 'override 4 keeps task-done'
has executor-prompt.md 'Produces column' 'override 4: the conflict scan reads the ledger'

# Override 5: one review, one fix round, scoped to the phase.
has executor-prompt.md 'Exactly ONE review and ONE fix round' 'override 5: the review and fix round'
has executor-prompt.md 'PHASE_BASE_SHA to HEAD' 'override 5: the review range is the phase'
has executor-prompt.md 'most capable model' 'override 5: the reviewer takes the most capable model'
has executor-prompt.md 'code-reviewer.md' 'override 5: the reviewer uses the code-reviewer template'
has executor-prompt.md 'write the full' 'override 5: the review lands in a file'
has executor-prompt.md 'no re-review' 'override 5: no second review'
has executor-prompt.md 'RED→GREEN' 'override 5: each fix is proven by a failing test'
has executor-prompt.md 'self-review' 'override 5: a self-review is labelled as one'
has executor-prompt.md 'do not dispatch a second' 'override 5: resume does not re-dispatch the reviewer'

# Override 6: the workspace outlives the executor.
has executor-prompt.md 'Do NOT delete the workspace' 'override 6: keeps the workspace'

# Unattended decisions.
has executor-prompt.md 'four stops' 'the skill stops become BLOCKED'
has executor-prompt.md 'does not' 'decisions do not expand authorization'
has executor-prompt.md 'write them to DECISIONS_PATH' 'rulings and minors persist in the decisions file'
has executor-prompt.md 'ten lines' 'return contract is capped'
has executor-prompt.md 'BLOCKED' 'return contract carries a status'

# --- rules binding on every template --------------------------------------

for t in planner-prompt.md repair-prompt.md executor-prompt.md verifier-prompt.md; do
  has "$t" 'general-purpose' 'dispatches a general-purpose subagent'
  has "$t" 'model:' 'names a model explicitly'
  assert_eq '' "$(grep -n 'paste' "$ROOT/$t" | grep -iv 'do not paste' || true)" \
    "$t: never asks an agent to paste an artifact into its return value"
done

# --- platform-guide.md -----------------------------------------------------

exists platform-guide.md
has platform-guide.md 'executing-plans' 'names the execution skill to resolve'
has platform-guide.md 'scripts/task-done' 'requires task-done'
has platform-guide.md 'scripts/review-package' 'requires review-package'
has platform-guide.md 'controller → executor →' 'states the nesting depth'
has platform-guide.md 'install.sh claude executing' 'documents the install command'

finish
