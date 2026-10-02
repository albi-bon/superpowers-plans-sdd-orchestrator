# Repair Dispatch Template

The first of a phase's two attempts. Dispatched at most once per phase, after a
verifier or integration verifier FAIL. There is never a second repair: if this
one does not hold, the rescue agent takes the phase with a wider mandate, and
after that the phase has failed. Substitute every uppercase placeholder value
before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Repair phase PHASE_NUMBER after a failed verification"
  model: the most capable model available — this is fresh eyes on something a
         whole phase of work did not get right. Resolve the actual model
         through platform-guide.md; record inheritance if selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of this phase's worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    A phase of a phased design document was implemented and then failed
    verification. You are fixing it. You get one attempt.

    Phase branch:    PHASE_BRANCH          (checked out in WORKTREE)
    Base branch:     BASE
    Evidence:        EVIDENCE_PATH         (what failed, and how)
    Brief:           BRIEF_PATH            (what the phase was supposed to build)
    Decisions file:  DECISIONS_PATH
    Testing policy:  TESTING_POLICY_PATH
    Decision policy: DECISION_POLICY_PATH
    Integration:     INTEGRATION_CONTEXT

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    0. If INTEGRATION_CONTEXT is not "none", the failure came from
       integrating BASE into this phase: PHASE_BRANCH already holds a merge of
       BASE, and EVIDENCE_PATH is the integration evidence. INTEGRATION_CONTEXT
       names the conflicts file and the briefs and decisions files of the
       phases merged into BASE since this phase began. Read them: the fix
       must keep both this phase's behaviour and theirs.
    1. Read the evidence file first. It names the commands that were run,
       their exit codes, the failing output, and any deliverable marked
       `missing`.
    2. Read the brief's header, Global constraints, and only the tasks the
       failure touches.
    3. Diagnose and fix the root cause. A `missing` deliverable is built, with
       tests as the testing policy says. Do not paper over a failure by
       weakening, skipping, or deleting the check that caught it.
    4. Re-run the failing commands yourself and confirm each one now exits 0.
       A command that prints an all-green summary and exits non-zero has NOT
       passed — judge by the exit code, never by the printed totals.
    5. Commit your fix on PHASE_BRANCH and leave the working tree clean.
    6. Record any decision you took in DECISIONS_PATH under the decision
       policy.

    ## Constraints

    - Do NOT switch branches, create branches, merge, rebase, or push. The
      controller owns integration; you own this branch's contents.
    - Work only inside WORKTREE. Do NOT touch the main checkout, the base
      branch BASE, or any other phase's worktree or branch. Other phases are
      being built beside this one right now.
    - Stay inside the phase's scope. Fixing the failure is the job; improving
      neighbouring code is not.
    - Return STILL_BROKEN only when you could not make the failing checks
      pass, or for a case the decision policy's BLOCKED list names.

    ## Return contract

    At most six lines:
    - status: FIXED or STILL_BROKEN
    - the one-line root cause
    - the commands you re-ran and their exit codes
    - your commit SHAs
    - decisions: <significant count> significant

    Do not paste diffs, file contents, or test output into your reply.
```
