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
         scripts/phase-qa scripts/phase-layout qa-plan-prompt.md qa-walker-prompt.md qa-triage-prompt.md qa-fix-prompt.md \
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
    "no $f wrapper: it would switch a checkout off base, or integrate one phase alone"
done

# --- base in a worktree of its own; the main checkout left to its owner ---------

has '**The main checkout is not the run' 'states that the main checkout is not part of the run'
has '`REPO_ROOT/.worktrees/base`' 'names where the base worktree is'
has '| `base-worktree <path>` | `BASE_WORKTREE` |' 'keeps the base worktree preflight prints'
has '| `design-doc <path>` | `DESIGN_DOC`, replacing the path in the request' "switches to base's copy of the document"
has 'cd "$BASE_WORKTREE"' 'works from the base worktree'
has 'no command in the main checkout' 'runs nothing in the main checkout'
has 'never switches a checkout it does not own' 'does not free base itself when preflight refuses'
has 'fast-forwards base to the batch tip in `BASE_WORKTREE`' 'batches land in the base worktree'
has 'a dirty base
worktree or phase worktree' 'resume: preflight checks the base worktree, not the main checkout'
has 'before base had a worktree of its own' 'resumes a run that kept base in the main checkout'
has 'base worktree: <BASE_WORKTREE>' 'the report says where the base worktree is'
assert_eq '' "$(grep -n 'main checkout is on' "$SKILL" || true)" 'no claim left that the main checkout is on base'
assert_eq '' "$(grep -n 'directory at `REPO_ROOT`' "$SKILL" || true)" 'the controller no longer works from the main checkout'

# --- invocation, scheduling, integration, ladder, drain ------------------------

has 'otherwise **3**' 'CAP defaults to 3'
has '| `MODEL_MAPPING` | a model mapping stated in the request; otherwise the host default' 'the model mapping needs no instruction'
has 'run: models — <MODEL_MAPPING>' 'records the model mapping in the ledger'
has 'top tier fell back to strong at' 'the report says when the top tier fell back'
has '| scout | `scout-prompt.md` | strong; top under platform-guide.md § Scout tier |' 'the scout is strong tier, top in the listed cases'
has '| overlap judge | `overlap-judge-prompt.md` | top |' 'the judge is top tier'
has '| repair | `repair-prompt.md` | top |' 'repair is top tier'
has '| rescue | `rescue-prompt.md` | top |' 'rescue is top tier'
has '| resolver | `resolver-prompt.md` | top |' 'the resolver is top tier'
has 'on the top tier: its reviewer, a task worker whose brief task says `Tier: hard`' 'a hard task worker is top tier'
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

# --- the QA pass ---------------------------------------------------------------

has '| `QA_SCOPE` |' 'the QA scope is an invocation value'
has '`qa` in the request gives `top 5`' 'bare qa means the five most important flows'
has '`no qa` gives `none`' 'a request can decline QA'
has 'ask once, before preflight' 'a silent request is asked before preflight, never after'
has 'run: qa scope — <QA_SCOPE>' 'records the scope in the ledger'
has '## The QA pass' 'has a QA section'
has 'phase-qa" "$DESIGN_DOC" "$BASE" next' 'asks phase-qa what to do next'
has 'After every QA return' 'consults phase-qa after every QA return'
has 'phase-qa" "$DESIGN_DOC" "$BASE" next "$RANGE"' 'the QA conditions are judged on the range of this invocation'
has 'last `run: qa scope` line stands' 'a resume keeps the recorded scope without asking'
has 'only when the request stated a scope or the ledger had none' 'a resume does not re-append the scope'
has 'G1 not rechecked' 'a re-check that could not be done is recorded as such'
has 'what follows the label' 'the lists go into the ledger without their labels'
has '| `skip <reason>` | append `qa: skipped — <reason>`' 'records a skip with its reason'
has '| `walk F' 'walks the flows phase-qa lists'
has 'keeping at most `CAP` walkers out' 'walkers respect the cap'
has '| `fix G` |' 'fixes one group at a time'
has '`BATCH_BRANCH` the QA branch' 'gates run on the QA branch in final mode'
has 'RUN_DIR/qa-gates-evidence.md' 'the gates on QA fixes have their own evidence'
has '| `close` | `phase-qa "$DESIGN_DOC" "$BASE" close`' 'the script writes the done line'
has 'qa: flows defined — <n> found, selected <list>, not walkable <list>, parallel <p>' 'copies the planner lists into the ledger'
has 'qa: triaged — <n> findings, fix <groups>, <s> spec, <o> outside this run' 'copies the triage groups into the ledger'
has 'qa: not landed — <stderr>' 'a refused landing is recorded, not retried'
has 'You never read a flows file, a findings file or the triage' 'the controller stays out of QA artifacts'
has 'Every stage runs once' 'states the bound'
has 'There is never a second fix round' 'no second fix round'
has 'never makes the pull request a draft' 'QA does not change the draft rule'
has 'phase-qa" "$DESIGN_DOC" "$BASE" report' 'the report takes its QA block from phase-qa'
has 'qa-decisions.md' 'QA fix decisions are in the report'
has 'A `qa: skipped` line counts only while' 'a skip is not final across resumes'
has 'at most once per run directory' 'a started pass is never repeated'
has 'A fix is only re-checked where it was found' 'known limit: narrow re-check'
has 'reports them as not walked' 'known limit: tools'
has 'one more fix round' 'rationalization: another round'
has 'I read the code and it looks right' 'rationalization: reading is not walking'

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
printf 'work in progress\n' > "$repo/wip.txt"
run_in "$ROOT/scripts/phase-preflight" "$repo/spec.md" feat/x all
assert_rc 0 'preflight wrapper: a fresh run passes, whatever the main checkout holds'
assert_eq 'yes' "$([ -f "$repo/.superpowers/phase-parallel/spec/run.md" ] && echo yes || echo no)" \
  'preflight wrapper: the ledger lives in the phase-parallel namespace, in the main checkout'
bw="$repo/.worktrees/spec/base"
spec="$bw/spec.md"
assert_contains "base-worktree $bw" "$OUT" 'preflight wrapper: prints the base worktree'
assert_contains "design-doc $spec" "$OUT" "preflight wrapper: prints base's copy of the document"
assert_eq 'feat/x' "$(git -C "$bw" branch --show-current 2>/dev/null)" 'preflight wrapper: base is checked out in its own worktree'
assert_eq 'main' "$(git -C "$repo" branch --show-current)" 'preflight wrapper: the main checkout is not switched'
assert_eq '?? wip.txt' "$(git -C "$repo" status --porcelain)" 'preflight wrapper: the main checkout keeps its work in progress'

# From here on the controller works from the base worktree, with base's copy
# of the document; every wrapper still finds the one run directory.
run_in() { set +e; OUT=$(cd "$bw" && "$@" 2>&1); RC=$?; set -e; }
run_in "$ROOT/scripts/phase-run-dir" "$spec"
assert_eq "$repo/.superpowers/phase-parallel/spec" "$OUT" 'run-dir wrapper: the main checkout run directory, from the base worktree'
run_in "$ROOT/scripts/parse-deps" --write "$spec"
assert_eq 'graph: 1→{} 2→{} (source: line)' "$OUT" 'parse-deps wrapper: graph recorded'
assert_eq 'yes' "$([ -f "$repo/.superpowers/phase-parallel/spec/graph.tsv" ] && echo yes || echo no)" \
  'parse-deps wrapper: the graph is written beside the ledger'
run_in "$ROOT/scripts/phase-schedule" "$spec" feat/x all 3
assert_eq "$(printf 'start 1\nstart 2\nwait')" "$OUT" 'schedule wrapper: independent phases start together'
run_in "$ROOT/scripts/phase-worktree" "$spec" feat/x start 1
wt=$OUT
assert_eq "$repo/.worktrees/spec/phase-1-one" "$wt" 'worktree wrapper: phase worktrees sit beside the base worktree'
assert_eq '' "$(git -C "$bw" status --porcelain)" 'the base worktree holds no run files'
printf 'left behind\n' > "$wt/stray.txt"
run_in "$ROOT/scripts/phase-preflight" "$spec" feat/x all
assert_rc 11 'preflight wrapper: refuses a dirty phase worktree'
assert_contains "$wt" "$OUT" 'preflight wrapper: names the dirty worktree'
rm "$wt/stray.txt"
git -C "$repo" switch -q -c elsewhere
git -C "$repo" rm -q spec.md
git -C "$repo" commit -qm 'the owner moves the main checkout on'
run_in "$ROOT/scripts/phase-preflight" "$repo/spec.md" feat/x all
assert_rc 0 'preflight wrapper: resumes with the first request path after the main checkout moved on'
assert_contains "design-doc $spec" "$OUT" "preflight wrapper: a resume prints base's copy again"

# A second run in the same repository, while the first is in flight: its own
# base, integration and phase worktrees and branches, and the first run's
# dirty phase worktree does not refuse it.
git -C "$repo" switch -q main
cp "$repo/spec.md" "$repo/second.md"
git -C "$repo" add second.md
git -C "$repo" commit -qm 'a second spec'
printf 'left behind\n' > "$wt/stray.txt"
run_in() { set +e; OUT=$(cd "$repo" && "$@" 2>&1); RC=$?; set -e; }
run_in "$ROOT/scripts/phase-preflight" "$repo/second.md" feat/y all
assert_rc 0 "two runs: the second's preflight passes beside the first's dirty phase worktree"
bw2="$repo/.worktrees/second/base"
assert_contains "base-worktree $bw2" "$OUT" 'two runs: the second has its own base worktree'
assert_contains "integration-worktree $repo/.worktrees/second/integration" "$OUT" \
  'two runs: the second has its own integration worktree'
assert_eq 'feat/x' "$(git -C "$bw" branch --show-current)" "two runs: the first run's base worktree is not switched"
assert_eq 'feat/y' "$(git -C "$bw2" branch --show-current)" "two runs: the second run's base is in its own worktree"
run_in "$ROOT/scripts/phase-worktree" "$bw2/second.md" feat/y start 1
assert_eq "$repo/.worktrees/second/phase-1-one" "$OUT" 'two runs: the same phase number gets a worktree of its own'
assert_eq 'phase-1-one@second' "$(git -C "$OUT" branch --show-current)" 'two runs: and a branch of its own'
assert_eq 'phase-1-one@spec' "$(git -C "$wt" branch --show-current)" "two runs: the first run's phase branch is untouched"
run_in "$ROOT/scripts/phase-layout" "$bw2/second.md"
assert_contains 'qa-branch phase-qa@second' "$OUT" 'layout wrapper: prints the run-scoped names'
rm "$wt/stray.txt"

finish
