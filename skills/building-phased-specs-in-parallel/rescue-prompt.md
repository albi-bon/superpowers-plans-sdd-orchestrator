# Rescue Dispatch Template

The second and last attempt on a failing phase. Dispatched after a repair did not
make verification pass, or directly when the resolver could not resolve an
integration merge. A repair fixes what the evidence names; the rescue may change
the approach. There is never a third attempt. Substitute every uppercase
placeholder value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Rescue phase PHASE_NUMBER"
  model: the most capable model available — a scoped fix already failed, or
         a merge could not be resolved; this needs fresh judgement on the
         whole phase. Resolve the actual model through platform-guide.md;
         record inheritance if selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of this phase's worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    A phase of a phased design document is failing, and an earlier attempt
    did not fix it. You are the last attempt. You have a wider mandate than
    the repair had: you may change how the phase is built, not only patch
    what failed.

    Design document: DESIGN_DOC            (read phase PHASE_NUMBER's section)
    Phase number:    PHASE_NUMBER
    Phase branch:    PHASE_BRANCH          (checked out in WORKTREE)
    Base branch:     BASE
    Evidence:        EVIDENCE_PATHS        (every verification and integration evidence file so far)
    Repair report:   REPAIR_REPORT_PATH    (what the repair tried, or "none")
    Rescue report:   RESCUE_REPORT_PATH    (you write it)
    Brief:           BRIEF_PATH
    Decisions file:  DECISIONS_PATH
    Integration:     INTEGRATION_CONTEXT   (the merged phases' brief and decisions paths, or "none")
    Conflicts file:  CONFLICTS_PATH        (set when an integration merge was left unresolved, or "none")
    Testing policy:  TESTING_POLICY_PATH
    Decision policy: DECISION_POLICY_PATH  (read it before you start)

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    1. Read every evidence file, newest last, then the repair report. Work out
       why the repair did not hold: a wrong diagnosis, a symptom fixed instead
       of a cause, or a phase whose approach cannot meet its checks.
    2. Read the brief, the decisions file, and phase PHASE_NUMBER's section of
       the design document. If INTEGRATION_CONTEXT is not "none", read the
       merged phases' briefs and decisions too: the failure is in how this
       phase meets their work.
    3. Fix the root cause. You may rework a task's implementation, change an
       approach the brief chose, re-scope a task against the current base,
       or build a missing prerequisite. Every departure from the brief is a
       significant decision; record it in DECISIONS_PATH under the decision
       policy. Do not paper over a failure by weakening, skipping, or deleting
       the check that caught it.
    4. If CONFLICTS_PATH is not "none", the integration merge was aborted and
       PHASE_BRANCH is back at its built commit. Redo it:
       `git merge --no-ff BASE -m "integrate: base into phase PHASE_NUMBER"`,
       resolve every conflict so both sides' behaviour holds, regenerate
       lockfiles with the repository's package manager rather than merging
       them by hand, regenerate generated files and ORM migration metadata
       with the repository's own commands (this phase's migration rebuilt on
       top of the base's latest), and conclude the merge. Adapt this phase's code to the
       base where the two cannot otherwise coexist.
    5. Re-run every failing command from the evidence, plus typecheck, lint
       and the test suites of the packages you changed, and confirm each
       exits 0. The integration verifier runs the rest after you. A command
       that prints an all-green summary and exits non-zero has NOT passed —
       judge by the exit code, never by the printed totals.
    6. Commit your work on PHASE_BRANCH and leave the working tree clean.
    7. Write RESCUE_REPORT_PATH: the root cause, why the repair missed it,
       what you changed and why, and the commands you ran with their exit
       codes.

    ## Constraints

    - Work only inside WORKTREE. Do NOT touch the main checkout, the base
      branch BASE, or any other phase's worktree or branch. Other phases are
      being built beside this one right now.
    - Do NOT switch branches, create branches, rebase, or push. The only
      merge you may run is the integration merge in step 4, of BASE into
      PHASE_BRANCH.
    - Stay inside the phase's scope. Making this phase pass on the current
      base is the job; improving neighbouring code is not.
    - Return STILL_BROKEN only when you could not make the failing checks
      pass, or for a case the decision policy's BLOCKED list names.

    ## Return contract

    At most six lines:
    - status: FIXED or STILL_BROKEN
    - the one-line root cause
    - the commands you re-ran and their exit codes
    - your commit SHAs
    - decisions: <significant count> significant
    - RESCUE_REPORT_PATH

    Do not paste diffs, file contents, or test output into your reply.
```
