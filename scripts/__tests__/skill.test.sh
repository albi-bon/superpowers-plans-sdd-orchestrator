#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../.." && pwd)
SKILL="$ROOT/SKILL.md"
BODY=$(cat "$SKILL" 2>/dev/null || true)

has() { assert_contains "$1" "$BODY" "SKILL.md: $2"; }

assert_eq 'yes' "$([ -f "$SKILL" ] && echo yes || echo no)" 'SKILL.md exists'

# --- frontmatter -----------------------------------------------------------

assert_eq '---' "$(head -n 1 "$SKILL" 2>/dev/null || true)" 'starts with YAML frontmatter'
has 'name: orchestrating-phased-specs' 'frontmatter names the skill'
has 'description: Use when' 'description states triggering conditions'
has 'phases 2 to 6' 'description carries the natural trigger phrasing'

# --- the permission-mode requirement, stated where it cannot be missed -----

assert_contains 'bypass-permissions' "$(sed -n '1,25p' "$SKILL")" \
  'SKILL.md: permission-mode requirement appears in the opening lines'
has 'cannot be read from inside a skill' 'says why permission mode is not checked'

# --- every script and template it depends on -------------------------------

for f in scripts/phase-preflight scripts/parse-phases scripts/phase-run-dir \
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
has 'merged' 'the ledger records a merged state per phase'
has 'Resume' 'documents resume'
has 'repair attempt per phase' 'exactly one repair attempt'
has 'halt' 'documents halting'
has 'nothing pushed, no PR opened' 'the run ends at a report'

# --- the model table -------------------------------------------------------

has 'name a model explicitly' 'requires an explicit model on every dispatch'
has 'mid-tier' 'the verifier takes a mid-tier model'

# --- the four known limits -------------------------------------------------

has 'Known limits' 'has a known-limits section'
has 'parks on a prompt' 'limit 1: wrong permission mode stalls rather than fails'
has 'compounds across phases' 'limit 2: one review per phase, and it compounds'
has 'nothing between tasks' 'limit 2 states there is no per-task review'
has 'working tree is busy' 'limit 3: the working tree is busy for the whole run'
has 'depth' 'limit 4: nesting depth is a platform assumption'

finish
