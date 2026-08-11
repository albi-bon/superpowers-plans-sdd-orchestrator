# ② Executor Dispatch Template

Dispatched once per phase, after the planner. This agent runs a full
`subagent-driven-development` loop of its own, so it will spawn subagents.
Substitute every `ANGLE_BRACKET_CAPS` value before dispatching.

Override 4 disables that skill's per-task review loop: the phase is reviewed
once, whole, at the end. Read its rationale before weakening it — it is the
difference between a phase that takes an evening and one that takes a day.

```
Subagent (general-purpose):
  description: "Execute the plan for phase PHASE_NUMBER"
  model: the most capable model available — this agent is itself a controller,
         running a review loop and adjudicating findings unattended. An omitted
         model silently inherits the session's.
  prompt: |
    Execute an implementation plan with superpowers:subagent-driven-development.

    Plan:            PLAN_PATH
    Phase branch:    PHASE_BRANCH   (you are already on it, in a normal checkout)
    Run directory:   RUN_DIR
    Decisions file:  DECISIONS_PATH

    Invoke superpowers:subagent-driven-development and execute PLAN_PATH with it.

    ## Four overrides of superpowers:subagent-driven-development

    These supersede that skill's own instructions wherever they conflict. They
    are requirements, not preferences.

    1. Do NOT create or verify a worktree, and do NOT route through
       superpowers:using-git-worktrees, whatever that skill's Setup step says.
       You are already on an isolated phase branch in a single checkout, and
       that is the isolation. A worktree you fork here is invisible to the
       orchestrator, which will merge PHASE_BRANCH and silently get nothing.
    2. Do NOT invoke superpowers:finishing-a-development-branch, and do not push,
       open a pull request, or merge. That skill is subagent-driven-development's
       terminal state; here, integration belongs to the orchestrator that
       dispatched you.
    3. Do NOT switch branches, create branches, or rebase. Every commit lands on
       PHASE_BRANCH.
    4. Do NOT review between tasks. subagent-driven-development pairs every
       implementer with a reviewer and a fix round; that per-task loop is
       disabled here. Implement each task, run the checks the plan names for it,
       commit, and dispatch the next one. The phase gets exactly ONE review: a
       whole-branch review after the final task, whose findings you adjudicate
       and fix in a single wave. Do not re-review after that wave.

       This is a measured cost decision, not a style preference. Per-task review
       runs three serial dispatches where one would do, and the review-plus-fix
       pair costs three to five times the implementation it checks — it is the
       single largest term in a phase's wall clock.

       Two things follow, and you own both. Dispatch the whole-branch review
       with breadth proportionate to the phase, because it is the only review
       the phase gets and a defect in Task 2 has had every later task built on
       top of it. And when a task's own checks fail, that is not a review
       finding to defer — fix it before you dispatch the next task.

    ## One directive from the person this run is for

    This comes from them directly, and it supersedes subagent-driven-development's
    own rules where the two disagree:

    > I'm going to be afk. If you hit a situation where you would normally stop and ask for
    > direction, pick the option you'd normally tag as recommended, and summarise the
    > decisions taken at the end.

    For that summary: write that summary to DECISIONS_PATH — one line
    per decision, naming the choice you took and the alternative you passed
    over. It does not go in your reply.

    Keep every artifact of your own loop — briefs, reports, review packages,
    your ledger — under RUN_DIR or wherever subagent-driven-development puts
    them. Not in your reply.

    ## Return contract

    At most ten lines:
    - status: DONE or BLOCKED
    - the commit range on PHASE_BRANCH, as SHORT_SHA..SHORT_SHA
    - the review outcome in one line
    - how many findings you parked, and how many minor findings you deferred
    - DECISIONS_PATH

    If BLOCKED, put what blocked you in those ten lines — the orchestrator acts
    on it directly and will not read your files.

    Do not paste plan text, diffs, file contents, or test output into your
    reply. The orchestrator reading it must survive several more phases, and
    everything you print stays in its context for the rest of the run.
```
