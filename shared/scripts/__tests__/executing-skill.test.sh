#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../../../skills/executing-phased-specs" && pwd)
SKILL="$ROOT/SKILL.md"
BODY=$(cat "$SKILL" 2>/dev/null || true)

has() { assert_contains "$1" "$BODY" "SKILL.md: $2"; }

assert_eq 'yes' "$([ -f "$SKILL" ] && echo yes || echo no)" 'SKILL.md exists'

# --- frontmatter and routing -----------------------------------------------

assert_eq '---' "$(head -n 1 "$SKILL" 2>/dev/null || true)" 'starts with YAML frontmatter'
has 'name: executing-phased-specs' 'frontmatter names the skill'
has 'description: Use when' 'description states triggering conditions'
has 'phases 2 to 6' 'description carries the natural trigger phrasing'
has 'superpowers:executing-plans' 'description names the execution skill that sets it apart'
has 'use orchestrating-phased-specs' 'description points subagent-driven requests at orchestrating'
has 'use building-phased-specs' 'description points direct requests at building'
desc=$(sed -n '3p' "$SKILL")
assert_eq 'yes' "$([ "${#desc}" -le 1024 ] && echo yes || echo no)" 'description fits the 1024-character limit'

# --- runtime setup ---------------------------------------------------------

has 'platform-guide.md' 'links the host-specific setup guide'
has 'A skill cannot grant permissions' 'respects host permissions'

# --- every script and template it depends on -------------------------------

for f in scripts/phase-preflight scripts/parse-phases scripts/phase-run-dir scripts/phase-start \
         planner-prompt.md executor-prompt.md verifier-prompt.md repair-prompt.md; do
  has "$f" "references $f"
  assert_eq 'yes' "$([ -e "$ROOT/$f" ] && echo yes || echo no)" \
    "SKILL.md: the referenced path $f exists on disk"
done

# --- the loop, the ledger, halting, the report -----------------------------

has 'git merge --no-ff' 'merges each phase branch with --no-ff'
has 'ascending numeric order' 'phases run in ascending numeric order'
has 'run.md' 'names the ledger file'
has 'phase-<N>-<slug>/plan.md' 'the plan is a directory whose ledger is plan.md'
has 'one file per task' 'the paths table says task files sit beside the ledger'
has 'phase-<N>-review.md' 'the paths table names the review report'
has 'one review and one' 'the executor runs one review and one fix round per phase'
has 'merged' 'the ledger records a merged state per phase'
has 'Resume' 'documents resume'
has 'repair attempt per phase' 'exactly one repair attempt'
has 'halt' 'documents halting'
has 'self-review' 'the report flags a phase reviewed by its own author'
has 'nothing pushed, no PR opened' 'the run ends at a report'

# --- the model table -------------------------------------------------------

has 'Name a model explicitly' 'requires an explicit model on every dispatch'
has 'mid-tier' 'the verifier takes a mid-tier model'

# --- known limits ----------------------------------------------------------

has 'Known limits' 'has a known-limits section'
has 'parks on a prompt' 'limit: wrong permission mode stalls rather than fails'
has 'One context builds the whole phase' 'limit: inline execution has no fresh context per task'
has 'compounds across phases' 'limit: one review per phase, and it compounds'
has 'nothing between tasks' 'limit: there is no per-task review'
has 'working tree is busy' 'limit: the working tree is busy for the whole run'
has 'controller → executor → reviewer' 'limit: nesting depth is a platform assumption'

# --- wrappers use their own namespace ---------------------------------------

for s in parse-phases phase-preflight phase-run-dir phase-start; do
  assert_contains 'PHASE_RUN_NAMESPACE=phase-executor' "$(cat "$ROOT/scripts/$s")" \
    "scripts/$s sets the phase-executor namespace"
  assert_eq 'yes' "$([ -x "$ROOT/scripts/$s" ] && echo yes || echo no)" "scripts/$s is executable"
done

finish
