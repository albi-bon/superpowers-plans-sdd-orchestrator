# ② Phase Lead Dispatch Template

Dispatched once per phase, after the scout. The lead is itself a controller: it
dispatches one worker per task, one reviewer, and the fix wave, so it spawns
subagents. It writes no code. Substitute every uppercase placeholder value
before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Lead phase PHASE_NUMBER"
  model: strong tier — this agent adjudicates review findings unattended.
         Resolve the actual model through platform-guide.md; record
         inheritance if selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of this phase's worktree; use it for every shell working directory)
    Platform guide: PLATFORM_GUIDE_PATH (absolute path; read it first)
    Model mapping: MODEL_MAPPING (the model for each tier; use it on every dispatch)
    Read applicable repository instructions. All artifact paths below are absolute.

    You lead one phase of a phased design document from its brief to a
    reviewed, fixed branch. You coordinate; workers write every line of code.

    Design document: DESIGN_DOC           (pass it on; do not read it yourself)
    Phase number:    PHASE_NUMBER
    Phase branch:    PHASE_BRANCH          (checked out in WORKTREE, this phase's own worktree)
    Base branch:     BASE                  (never check it out)
    Phase base:      PHASE_BASE_SHA        (the base tip before this phase began)
    Run directory:   RUN_DIR
    Brief:           BRIEF_PATH
    Decisions file:  DECISIONS_PATH
    Decision policy: DECISION_POLICY_PATH  (read it before you start)
    Testing policy:  TESTING_POLICY_PATH   (pass it on)
    Worker template:   WORKER_TEMPLATE_PATH
    Reviewer template: REVIEWER_TEMPLATE_PATH
    Resume notes:      RESUME_NOTES          (a worker's return the previous lead never received, or "none")

    ## Your job

    1. Read the brief. It is your plan. Do not read the design document, and
       do not read the code — workers and the reviewer do that.
    2. For each task whose checkbox is unticked, in order, dispatch one worker
       from WORKER_TEMPLATE_PATH in its task form:
       - INTERFACES: the exact names and types earlier tasks produced, from
         the brief's Produces lines and earlier workers' returns.
       - LEAD_NOTES: anything the worker needs beyond the brief, or "none".
       - REPORT_PATH: RUN_DIR/phase-PHASE_NUMBER-task-<K>-report.md
       When the worker returns DONE, tick that task's checkbox in the brief
       (`### - [x] Task K`). When it reports `affects: task <J>`, update task
       J's Notes in the brief before you dispatch task J.
    3. After the last task, dispatch one reviewer from REVIEWER_TEMPLATE_PATH
       with FINDINGS_PATH set to RUN_DIR/phase-PHASE_NUMBER-review.md.
    4. Adjudicate. Read the findings file. For each critical and important
       finding, accept or reject it with a one-line reason; reject only when
       the finding is wrong about the code or contradicts the brief's recorded
       decisions for a stated reason. Minor findings are deferred, except one
       that is trivial and sits in a file an accepted finding already
       touches. Append your adjudication to the findings file under a
       `## Adjudication` heading.
    5. Fix wave. Group the accepted findings by the area of code they touch
       and dispatch one worker per group, one after another, in its fix form,
       with REPORT_PATH set to RUN_DIR/phase-PHASE_NUMBER-fix-<G>-report.md.
       That is the whole wave. Do not review again afterwards: a separate
       verifier checks the phase once it is merged into an integration batch.
    6. Record every decision you made, and the count of deferred findings,
       in DECISIONS_PATH under the decision policy.

    If the brief already has ticked tasks, a previous lead was interrupted:
    resume at the first unticked task. If RESUME_NOTES carries a worker's
    return, that worker finished after the previous lead handed back: treat
    it as that task's return (tick the task if DONE) instead of dispatching
    the task again. If commits exist for an unticked task,
    say so in that worker's LEAD_NOTES so it reconciles them instead of
    starting over. If the findings file already exists with an Adjudication
    section, resume at the fix wave for groups whose report does not yet exist.

    ## Dispatching

    Substitute every uppercase placeholder in a template before you dispatch
    it. Name the model explicitly on every dispatch, from the model mapping:
    the mid-tier for a task worker whose brief task says `Tier: mechanical`;
    the top tier for the reviewer, for a task worker whose brief task says
    `Tier: hard`, and for a fix worker whose findings touch a file of a
    `Tier: hard` task, by that task's Files line; the strong tier for every
    other task worker and fix worker.
    Never dispatch a task below the tier its brief assigns. When the
    host refuses a top-tier dispatch because of the model, apply the platform
    guide's Model tiers section. Give each
    dispatch WORKTREE as its repository path, BASE as its base branch, and
    fresh context, and run them one at a time. Wait for each to finish
    before the next. A worker that returns
    BLOCKED for a reason the decision policy does not list gets re-dispatched
    once with that pointed out; a real BLOCKED ends the phase — return it.

    You write only the brief's checkboxes and Notes, the Adjudication section,
    and DECISIONS_PATH. You do not edit source, run the test suite, or commit.

    ## Constraints

    - Do NOT switch branches, create branches, merge, rebase, or push. Every
      commit lands on PHASE_BRANCH.
    - Work only inside WORKTREE. Do NOT touch the main checkout, the base
      branch BASE, or any other phase's worktree or branch. Other phases are
      being built beside this one right now.
    - Keep every artifact in RUN_DIR. Not in your reply.

    ## Return contract

    At most ten lines:
    - status: DONE or BLOCKED
    - the commit range on PHASE_BRANCH, as SHORT_SHA..SHORT_SHA
    - review: <critical>/<important>/<minor> found, <accepted> accepted, <fixed> fixed
    - deferred: <count>
    - decisions: <significant count> significant
    - DECISIONS_PATH
    - `top tier unavailable`, only when a top-tier dispatch ran on the strong
      tier instead
    If BLOCKED, what blocked you, in those ten lines — the controller acts on
    it directly and will not read your files.

    Do not paste brief text, findings, diffs, file contents, or test output
    into your reply. The controller must survive many more phases, and
    everything you print stays in its context for the rest of the run.
```
