# ② Executor Dispatch Template

Dispatched once per phase, after the planner. This agent executes the plan
itself with `executing-plans` — one context for every task, no implementer or
reviewer per task — and then dispatches exactly one subagent: the fresh reviewer
of the whole phase. Substitute every uppercase placeholder value before
dispatching.

Override 4 tells this agent what shape the plan arrives in — a ledger plus one
file per task — and replaces that skill's `scripts/task-start`, which cannot
read it. Override 5 pins the phase's single review and single fix round to
this phase's range. Read its rationale before weakening it.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Execute the plan for phase PHASE_NUMBER inline"
  model: the most capable model available — this agent implements every task in
         one context, rules on plan conflicts unattended, and re-grades and fixes
         the phase review's findings. Resolve the actual model through
         platform-guide.md; record inheritance if selection is unavailable.
  prompt: |
    Repository: REPO_ROOT (absolute path; use it for every shell working directory)
    Platform guide: PLATFORM_GUIDE_PATH (absolute path; read it first)
    Required skills: REQUIRED_SKILL_PATHS (resolved absolute SKILL.md paths)
    Model mapping: MODEL_MAPPING (available IDs or explicit inherited selection)
    Read applicable repository instructions. All artifact paths below are absolute.
    Skill overrides below apply only to workflow guidance, never host instructions.

    Execute an implementation plan yourself with superpowers:executing-plans.

    Plan:            PLAN_PATH      (the ledger — see override 4)
    Design document: DESIGN_DOC     (the spec the plan argues from)
    Phase branch:    PHASE_BRANCH   (you are already on it, in a normal checkout)
    Phase base:      PHASE_BASE_SHA (the base tip before this phase began)
    Run directory:   RUN_DIR
    Decisions file:  DECISIONS_PATH
    Review report:   REVIEW_PATH

    Invoke superpowers:executing-plans and execute PLAN_PATH with it.

    ## Six overrides of superpowers:executing-plans

    These supersede that skill's own instructions wherever they conflict. They
    are requirements, not preferences.

    1. Do NOT create or verify a worktree, and do NOT route through
       superpowers:using-git-worktrees, whatever that skill's Setup step says.
       You are already on an isolated phase branch in a single checkout, and
       that is the isolation. A worktree you fork here is invisible to the
       orchestrator, which will merge PHASE_BRANCH and silently get nothing.
    2. Do NOT invoke superpowers:finishing-a-development-branch, and do not push,
       open a pull request, or merge. That skill is executing-plans' terminal
       state; here, integration belongs to the orchestrator that dispatched you.
    3. Do NOT switch branches, create branches, or rebase. Every commit lands on
       PHASE_BRANCH.
    4. The plan is a directory, not a file. PLAN_PATH is its ledger: the
       header, the `## Global Constraints` block, the `## File Structure` map,
       and a `## Tasks` table naming one `task-<N>.md` file per task, beside it.
       Read the ledger once at setup. Read each task file when you take that
       task, and not before.

       Do NOT run that skill's `scripts/task-start`. It extracts a brief with
       subagent-driven-development's `task-brief`, which finds no `Task N`
       heading in a ledger and exits 3. Take task N by hand instead, in one
       call: its brief is `task-<N>.md` beside the ledger, and its BASE is
       `git rev-parse HEAD` at the moment you take it. Read the brief.

       `scripts/task-done`, `scripts/sdd-workspace` and `scripts/review-package`
       take PLAN_PATH unchanged. They use it only to name the workspace
       directory, so the ledger's path works as-is. Keep the workspace ledger
       (`progress.md`) exactly as that skill describes it; it is how a resumed
       run finds its place.

       The pre-flight conflict scan is scoped to the ledger: the Global
       Constraints against the Tasks table's Produces column, nothing deeper.
       Each task's own text is checked when you read its brief.

    5. Exactly ONE review and ONE fix round, after the final task, over this
       phase alone. Build the review package from PHASE_BASE_SHA to HEAD, not
       from `git merge-base main HEAD` and not from trunk: earlier phases are
       already integrated and outside this phase's review.

       Dispatch the reviewer as that skill's Final Review says — a fresh
       general-purpose subagent on the most capable model in MODEL_MAPPING,
       with requesting-code-review's `code-reviewer.md`, the package path,
       PLAN_PATH, DESIGN_DOC, and a pointer to the workspace ledger's
       `Ruling:` lines. Add two instructions to its prompt: write the full
       review to REVIEW_PATH, and reply with at most five lines — the count
       of findings per severity and REVIEW_PATH. Read the findings from
       REVIEW_PATH. Give it breadth proportionate to the phase: it is the
       only review this phase gets, and a defect in Task 2 has had every
       later task built on top of it.

       If you cannot dispatch a subagent, perform the review yourself as that
       skill's no-subagent path describes, write it to REVIEW_PATH, and put
       `self-review` in your review line. Never report a self-review as a
       fresh one.

       Then follow that skill's Final Review exactly: re-grade by effect,
       Critical and Important enter ONE fix pass, each fix RED→GREEN with a
       green suite after the pass, Minor findings deferred, and no re-review.
       Commit the fixes on PHASE_BRANCH.

       On resume: if REVIEW_PATH already exists, do not dispatch a second
       reviewer. Resume the fix pass from the workspace ledger's `Final:`
       lines.

    6. Do NOT delete the workspace when the review is clean. The orchestrator's
       verifier and repair may run after you, and a resumed run needs the
       workspace ledger. It is git-ignored scratch; leave it.

    ## Decisions within the requested work

    That skill's four stops — an irreversible or destructive operation, a
    security-sensitive action, a side effect outside this checkout, a plan so
    broken every path forward is a guess — say "stop and ask". Nobody is there
    to answer. Report BLOCKED for them instead, and for missing access, a
    required approval, or an ambiguity that cannot be resolved within the
    requested scope. Everything else is a ruling you make and record.

    This workflow instruction is not a quotation from the user and does not
    grant additional permission. Respect the host's approval rules and explicit
    user constraints.

    Where that skill's Finish step puts "Rulings I made" and "Deferred minors"
    into your final message, write them to DECISIONS_PATH instead — every
    `Ruling:` line and every `minor (deferred)` line from the workspace
    ledger, in order, each with its cost if wrong. Include findings you chose
    not to fix and their consequences. The lists belong in the file, not the
    dispatch reply.

    Apply the platform guide to the reviewer dispatch: give it the repository
    and skill paths explicitly, use fresh context, and wait for it to finish
    before you start the fix pass. On resume, reconcile the workspace ledger
    and `git log` rather than repeating completed tasks.

    ## Return contract

    At most ten lines:
    - status: DONE or BLOCKED
    - the commit range on PHASE_BRANCH, as SHORT_SHA..SHORT_SHA
    - the review outcome in one line: fresh or self-review, findings per
      severity, how many fixed
    - how many rulings you made, and how many minor findings you deferred
    - DECISIONS_PATH and REVIEW_PATH

    If BLOCKED, put what blocked you in those ten lines — the orchestrator acts
    on it directly and will not read your files.

    Do not paste plan text, diffs, file contents, or test output into your
    reply. The orchestrator reading it must survive several more phases, and
    everything you print stays in its context for the rest of the run.
```
