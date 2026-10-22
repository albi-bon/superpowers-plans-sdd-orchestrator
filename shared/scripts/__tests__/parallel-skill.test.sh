#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../../../skills/building-phased-specs-in-parallel" && pwd)
BUILD=$(cd "$here/../../../skills/building-phased-specs" && pwd)
SKILL="$ROOT/SKILL.md"
BODY=$(cat "$SKILL" 2>/dev/null || true)

has() { assert_contains "$1" "$BODY" "SKILL.md: $2"; }

assert_eq 'yes' "$([ -f "$SKILL" ] && echo yes || echo no)" 'SKILL.md exists'

# --- frontmatter and routing --------------------------------------------------

assert_eq '---' "$(head -n 1 "$SKILL" 2>/dev/null || true)" 'starts with YAML frontmatter'
has 'name: building-phased-specs-in-parallel' 'frontmatter names the skill'
has 'description: Use when' 'description states triggering conditions'
has 'in parallel' 'description fires on parallel phrasing'
has 'use building-phased-specs instead' 'description points one-at-a-time requests at the sequential skill'
desc=$(sed -n '3p' "$SKILL")
assert_eq 'yes' "$([ "${#desc}" -le 1024 ] && echo yes || echo no)" 'description fits the 1024-character limit'
assert_contains 'use building-phased-specs-in-parallel' "$(sed -n '3p' "$BUILD/SKILL.md")" \
  'building-phased-specs description points parallel requests here'

# --- every script, template and policy it depends on ---------------------------

for f in scripts/phase-preflight scripts/parse-phases scripts/phase-run-dir scripts/parse-deps \
         scripts/phase-state scripts/phase-schedule scripts/phase-overlap scripts/phase-worktree \
         scripts/phase-batch scripts/phase-land scripts/phase-push scripts/phase-pr scripts/phase-statusline \
         scout-prompt.md lead-prompt.md worker-prompt.md reviewer-prompt.md \
         repair-prompt.md rescue-prompt.md resolver-prompt.md integration-verifier-prompt.md \
         overlap-judge-prompt.md graph-prompt.md testing-policy.md decision-policy.md platform-guide.md; do
  case "$f" in
    scripts/*) assert_contains "$(basename "$f")" "$BODY" "SKILL.md: references $f" ;;
    *) has "$f" "references $f" ;;
  esac
  assert_eq 'yes' "$([ -e "$ROOT/$f" ] && echo yes || echo no)" "SKILL.md: the referenced path $f exists on disk"
done
assert_eq 'no' "$([ -e "$ROOT/verifier-prompt.md" ] && echo yes || echo no)" \
  'no separate phase verifier template: the integration verifier is the one verification'
for f in phase-start phase-finish phase-integrate; do
  assert_eq 'no' "$([ -e "$ROOT/scripts/$f" ] && echo yes || echo no)" \
    "no $f wrapper: it would switch the main checkout off base, or integrate one phase alone"
done

# --- invocation, scheduling, integration, ladder, drain ------------------------

has 'otherwise **3**' 'CAP defaults to 3'
has 'SETUP_COMMAND' 'takes an optional setup command'
has 'parse-deps" --write' 'records the graph at preflight'
has 'graph agent' 'falls back to the graph agent'
has 'phase-schedule' 'asks the scheduler what to do'
has 'after **every** agent return' 'consults the scheduler after every return'
has 'dispatched' 'records every dispatch in the ledger'
has 'phase-overlap' 'runs the independence check after the scout'
has 'a file overlap is a signal, not a verdict' 'a shared file alone never holds a phase'
has '→ dispatch the overlap judge' 'an overlap result goes to the judge'
has '| overlap judge `RUN` | `phase <N>: overlap judged — runs beside phase' 'a run verdict keeps the phase active in the ledger'
has '| overlap judge `HOLD <M>` | `phase <N>: held — waits on phase <M> (domain:' 'a hold verdict appends the held line'
has 'major changes to the' 'states the owner rule: hold only for major changes to the same domain'
has '.phase-overlap-ignore' 'documents the repository ignore file'
has 'RUN_DIR/overlap-ignore' 'documents the run ignore file'
has 'you never read the briefs or' 'the controller never reads the briefs it passes to the judge'
has 'ORM migration metadata are regenerated' 'integration regenerates generated files and migration metadata'
has 'phase-batch' 'integrates through phase-batch'
has 'phase-land' 'lands through phase-land'
has 'integration verifier' 'batches are verified'
has 'Each batch is verified once, on the combined tree' 'each batch is verified once, on the combined tree'
has 'takes every queued phase into the next batch' 'the next batch takes every queued phase'
has 'a lone queued phase goes alone' 'never waits idle for more phases'
has 'At most one batch is open at' 'one batch at a time, so base cannot move under it'
has 'pins each failing item on a phase' 'the verifier pins a failure on a phase'
has 'the rest queue again' 'a pinned failure rebuilds the rest without the culprit'
has 'verified again without them' 'the rest are verified again before they land'
has 'flagged `solo`' 'an unpinned failure verifies each phase alone'
has '`phase-push "$DESIGN_DOC" "$BASE" N`' 'a finished phase branch is pushed as a backup'
has 'pushes base' 'base is pushed after every landing'
has 'Never force-push' 'never force-pushes'
has 'final check' 'runs a final check before the pull request'
has 'says full
   suites `all`' 'skips the final check when the last batch ran every full suite'
has 'abandoned — base moved' 'a batch base moved under is abandoned and rebuilt'
has 'Take the dispatch values' 'ladder dispatch values are read before the started line'
has 'pull request is a draft' 'a failed final check still hands off a draft pull request'
has 'phase-pr' 'opens the pull request through phase-pr'
has 'PR_TARGET' 'the pull request target is configurable'
has 'never merges the pull
request' 'never merges the pull request'
has 'FULL_SUITE_POLICY' 'the full-suite policy is configurable'
has '`full suite: once per phase`' 'the owner sets the full-suite policy in the request'
has 'SHA is the last word' 'PASS lines end in their SHA'
has 'RESUME_NOTES' 'a lead handed back mid-phase resumes with its worker report'
has 'wait for that worker' 'never two agents on one task'
has 'Runs started under earlier flows' 'finishes ledgers begun before batching'
has 'requeued for batching' 'requeues a phase integrated under the per-phase flow'
has 'followed by verification in a later
batch' 'every ladder attempt is verified in a later batch'
has 'no batch is open and
the phases that shared' 'a ladder attempt waits until its batch mates landed'
has '**two attempts**' 'two ladder attempts'
has 'never a third attempt' 'no third attempt'
has 'straight to rescue' 'an unresolved merge goes to rescue'
has 'run: draining' 'records the drain'
has 'starts and rescouts nothing' 'draining starts nothing new'
has 'one at a time' 'handles returns one at a time'
has 'Resume' 'documents resume'
has 'run: undrained' 'a fixed failure lifts the drain on resume'
has 'pull request: <url>' 'the report ends with the pull request'
has 'significant decisions' 'the report lists significant decisions'
has 'Known limits' 'states known limits'

# --- the wrappers apply this skill's namespace and the worktree check ------------

repo=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$repo" "$repo.origin"' EXIT
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
git -C "$repo" symbolic-ref HEAD refs/heads/main
printf '## Phase 1 — One\n**Depends on:** none\n## Phase 2 — Two\n**Depends on:** none\n' > "$repo/spec.md"
git -C "$repo" add spec.md
git -C "$repo" commit -qm initial
run_in() { set +e; OUT=$(cd "$repo" && "$@" 2>&1); RC=$?; set -e; }

run_in "$ROOT/scripts/phase-preflight" "$repo/spec.md" feat/x all
assert_rc 16 'preflight wrapper: refuses a repository with no origin remote'
assert_contains 'git remote add origin' "$OUT" 'preflight wrapper: says how to add one'
git init -q --bare "$repo.origin"
git -C "$repo" remote add origin "$repo.origin"
run_in "$ROOT/scripts/phase-preflight" "$repo/spec.md" feat/x all
assert_rc 0 'preflight wrapper: a fresh run passes'
assert_eq 'yes' "$([ -f "$repo/.superpowers/phase-parallel/spec/run.md" ] && echo yes || echo no)" \
  'preflight wrapper: the ledger lives in the phase-parallel namespace'
run_in "$ROOT/scripts/parse-deps" --write "$repo/spec.md"
assert_eq 'graph: 1→{} 2→{} (source: line)' "$OUT" 'parse-deps wrapper: graph recorded'
run_in "$ROOT/scripts/phase-schedule" "$repo/spec.md" feat/x all 3
assert_eq "$(printf 'start 1\nstart 2\nwait')" "$OUT" 'schedule wrapper: independent phases start together'
run_in "$ROOT/scripts/phase-worktree" "$repo/spec.md" feat/x start 1
wt=$OUT
printf 'left behind\n' > "$wt/stray.txt"
run_in "$ROOT/scripts/phase-preflight" "$repo/spec.md" feat/x all
assert_rc 11 'preflight wrapper: refuses a dirty phase worktree'
assert_contains "$wt" "$OUT" 'preflight wrapper: names the dirty worktree'

finish
