# QA Fixer Dispatch Template

One fixer per `fix` group of the QA triage, dispatched one after another in
the triage's order, on the run's QA branch. Each gets one attempt at one
group. There is no second fix round: a group that is not fixed goes into the
run's report, and so does a fix the re-check later finds still broken. The
gates run once after the last fixer, and the fixes land only if they pass.
Substitute every uppercase placeholder value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Fix QA group GGROUP_NUMBER"
  model: top tier, the most capable model available — a bug a whole run of
         builds, reviews and gates did not catch, with one attempt to fix
         it. Resolve the actual model through platform-guide.md; record
         inheritance if selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of the run's integration worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    Phases of a phased design document were built and landed, then used by
    agents acting as real users. What they found was sorted into groups by
    cause. You are fixing one group. You get one attempt.

    Group:           GGROUP_NUMBER
    QA branch:       QA_BRANCH             (checked out in WORKTREE)
    Start commit:    START_SHA             (the QA branch's tip when you were dispatched)
    Base branch:     BASE
    Triage file:     TRIAGE_PATH           (the group, its findings and its fix plan)
    Run directory:   RUN_DIR               (the findings files the triage names are here)
    Flows file:      FLOWS_PATH            (how to run the product: its `Run` section)
    Phases:          PHASES                (one line per phase the run built: number, title, brief path, decisions path)
    Decisions file:  DECISIONS_PATH
    Testing policy:  TESTING_POLICY_PATH
    Decision policy: DECISION_POLICY_PATH

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    0. Check whether this group was already fixed. If `git log START_SHA..HEAD`
       already has a commit whose subject starts with `qa: GGROUP_NUMBER —`, an
       earlier dispatch of this role made it and was interrupted before it
       could report. Discard uncommitted changes (`git reset --hard`),
       re-run that commit's checks, and return it as FIXED. Otherwise
       discard uncommitted changes and start at step 1.
    1. Read group GGROUP_NUMBER in TRIAGE_PATH: its findings, its fix plan,
       and what the triage says earlier groups change. Read the findings it
       names, in RUN_DIR. Other groups are not yours, whatever you notice in
       them.
    2. Reproduce the finding first, the cheapest way that proves it: a
       failing test, or the walker's steps with the `Run` section of
       FLOWS_PATH. If it does not reproduce, change nothing and return
       NOT_FIXED — did not reproduce.
    3. Fix the root cause. Follow the fix plan; where the plan is wrong
       about the cause, fix the real one and record that in DECISIONS_PATH
       under the decision policy. Add the regression test the plan names,
       as the testing policy says. Do not paper over a failure by
       weakening, skipping, or deleting the check that caught it.
    4. If the only way to fix it is changing what the design document asked for,
       that is not yours to decide. Change nothing and return
       NOT_FIXED — needs a spec change: <one line>. It goes to the owner.
    5. Run the check that failed and the tests related to the files you
       changed, and confirm each exits 0. A command that prints an
       all-green summary and exits non-zero has NOT passed — judge by the
       exit code. Do not run a whole suite or a production build: the gates
       run once, after every group is done.
    6. Commit on QA_BRANCH as `qa: GGROUP_NUMBER — <the group's title>` and
       leave the working tree clean.
    7. When the fix does not hold — the finding still reproduces, or a
       related test you cannot make pass — do not try a second approach.
       Run `git reset --hard START_SHA`, leave QA_BRANCH at START_SHA, and
       return NOT_FIXED with what you learned.

    ## Constraints

    - Do NOT switch branches, create branches, merge, rebase, or push. The
      controller owns the branch; you own this group's change on it.
    - Work only inside WORKTREE. Do NOT touch the main checkout, the base branch BASE, or any phase's worktree or branch.
    - Stay inside the group. Fixing its findings is the job; improving
      neighbouring code, or fixing something else you noticed, is not.
    - Never build what a phase outside PHASES is meant to deliver.
    - Nobody is available to answer questions. Return NOT_FIXED rather than
      guess at something only the owner can decide.

    ## Return contract

    At most five lines:
    - FIXED <short commit SHA> or NOT_FIXED — <one-line reason>
    - the one-line root cause, or what you learned
    - the commands you re-ran and their exit codes
    - decisions: <significant count> significant

    Do not paste diffs, file contents, or test output into your reply.
```
