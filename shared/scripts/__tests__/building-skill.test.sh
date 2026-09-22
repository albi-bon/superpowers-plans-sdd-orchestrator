#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../../../skills/building-phased-specs" && pwd)
OTHER=$(cd "$here/../../../skills/orchestrating-phased-specs" && pwd)
SKILL="$ROOT/SKILL.md"
BODY=$(cat "$SKILL" 2>/dev/null || true)

has() { assert_contains "$1" "$BODY" "SKILL.md: $2"; }

assert_eq 'yes' "$([ -f "$SKILL" ] && echo yes || echo no)" 'SKILL.md exists'

# --- frontmatter and routing between the two skills -------------------------

assert_eq '---' "$(head -n 1 "$SKILL" 2>/dev/null || true)" 'starts with YAML frontmatter'
has 'name: building-phased-specs' 'frontmatter names the skill'
has 'description: Use when' 'description states triggering conditions'
has 'phases 2 to 6' 'description carries the natural trigger phrasing'
has 'use orchestrating-phased-specs instead' 'description points plan-driven requests at the other skill'
desc=$(sed -n '3p' "$SKILL")
assert_eq 'yes' "$([ "${#desc}" -le 1024 ] && echo yes || echo no)" 'description fits the 1024-character limit'
other_desc=$(sed -n '3p' "$OTHER/SKILL.md")
assert_contains 'use building-phased-specs instead' "$other_desc" \
  'orchestrating-phased-specs description points direct requests here'
assert_contains 'explicitly asks for plan-driven' "$other_desc" \
  'orchestrating-phased-specs fires only on explicit plan-driven wording'

# --- every script, template and policy it depends on -------------------------

for f in scripts/phase-preflight scripts/parse-phases scripts/phase-run-dir \
         scripts/phase-start scripts/phase-finish \
         scout-prompt.md lead-prompt.md worker-prompt.md reviewer-prompt.md \
         verifier-prompt.md repair-prompt.md \
         testing-policy.md decision-policy.md platform-guide.md; do
  has "$f" "references $f"
  assert_eq 'yes' "$([ -e "$ROOT/$f" ] && echo yes || echo no)" \
    "SKILL.md: the referenced path $f exists on disk"
done

# --- the loop, the ledger, halting, the report -----------------------------

has 'ascending numeric order' 'phases run in ascending numeric order'
has 'git merge-base' 'records the phase base for the review range'
has 'grounded' 'the ledger records grounding'
has 'executed' 'the ledger records execution'
has 'verified PASS' 'the ledger records verification'
has 'merged to base' 'the ledger records the merge'
has 'repair attempt per phase' 'exactly one repair attempt'
has 'phase-finish' 'merges through phase-finish'
has 'run.md' 'names the ledger file'
has 'Resume' 'documents resume'
has 'Halting' 'documents halting'
has 'Nothing else' 'only the listed conditions halt'
has 'nothing pushed, no PR opened' 'the run ends at a report'
has 'significant decisions' 'the report lists significant decisions'
has 'grep -H' 'the report collects significant decision lines from the run directory'

# --- models ----------------------------------------------------------------

has 'name the model explicitly' 'requires an explicit model on every dispatch'
has 'mid-tier' 'the verifier takes a mid-tier model'
has 'Every worker uses the most capable model' 'workers always use the most capable model'
assert_eq '' "$(grep -in 'haiku\|sonnet' "$ROOT/SKILL.md" || true)" \
  'SKILL.md names no smaller model for any role'

# --- no Superpowers dependency --------------------------------------------

for f in SKILL.md platform-guide.md testing-policy.md decision-policy.md; do
  assert_eq '' "$(grep -n 'superpowers:' "$ROOT/$f" || true)" "$f: depends on no Superpowers skill"
done

# --- known limits ----------------------------------------------------------

has 'Known limits' 'has a known-limits section'
has 'Unattended decisions can be wrong' 'limit: unattended decisions'
has 'One review per phase' 'limit: one review per phase'
has 'parks on a prompt' 'limit: permissions'
has 'working tree is busy' 'limit: busy working tree'
has 'Nesting depth' 'limit: nesting depth'

finish
