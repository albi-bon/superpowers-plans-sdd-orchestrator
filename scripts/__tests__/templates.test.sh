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

# --- rules binding on every template --------------------------------------

for t in planner-prompt.md repair-prompt.md; do
  has "$t" 'general-purpose' 'dispatches a general-purpose subagent'
  has "$t" 'model:' 'names a model explicitly'
  assert_eq '' "$(grep -n 'paste' "$ROOT/$t" | grep -iv 'do not paste' || true)" \
    "$t: never asks an agent to paste an artifact into its return value"
done

finish
