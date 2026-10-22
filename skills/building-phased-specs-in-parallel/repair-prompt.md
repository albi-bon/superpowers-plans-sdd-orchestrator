# Repair Dispatch Template

The first of a phase's two attempts. Dispatched at most once per phase, after a
batch's integration verifier FAIL pinned on this phase, once the phases
verified beside it have landed. There is never a second repair: if this one
does not hold, the rescue agent takes the phase with a wider mandate, and
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

    A phase of a phased design document was implemented, merged into an
    integration batch with other phases, and the batch failed verification
    with the failure pinned on this phase. You are fixing it.
    You get one attempt.

    Phase number:    PHASE_NUMBER
    Phase branch:    PHASE_BRANCH          (checked out in WORKTREE)
    Base branch:     BASE
    Evidence:        EVIDENCE_PATH         (the batch's evidence: what failed, and which failures are pinned on this phase)
    Brief:           BRIEF_PATH            (what the phase was supposed to build)
    Decisions file:  DECISIONS_PATH
    Testing policy:  TESTING_POLICY_PATH
    Decision policy: DECISION_POLICY_PATH
    Integration:     INTEGRATION_CONTEXT   (brief and decisions paths of the phases verified beside this one, or "none")

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    0. Bring BASE in first, so you fix the tree this phase will next be
       verified on. If `git merge-base --is-ancestor BASE HEAD` fails, run
       `git merge --no-ff BASE -m "integrate: base into phase PHASE_NUMBER"`.
       On conflicts, resolve every path so both sides' behaviour holds:
       regenerate lockfiles with the repository's package manager rather than
       merging them by hand, regenerate generated files and ORM migration
       metadata with the repository's own commands (this phase's migration
       rebuilt on top of the base's latest), keep both sides' translation
       keys, and conclude the merge. If a manifest or lockfile changed, run
       the brief's `Setup:` line before any check. If INTEGRATION_CONTEXT is
       not "none", read those briefs and decisions: the phases verified beside
       this one are on BASE now, and the fix must keep their behaviour and
       this phase's.
    1. Read the evidence file. It names the commands that were run, their
       exit codes, the failing output, any deliverable marked `missing`, and
       the phase each failure is pinned on. The failures pinned on
       PHASE_NUMBER are your job; the others are not.
    2. Read the brief's header, Global constraints, and only the tasks the
       failure touches.
    3. Diagnose and fix the root cause. A `missing` deliverable is built, with
       tests as the testing policy says. Do not paper over a failure by
       weakening, skipping, or deleting the check that caught it.
    4. Re-run what failed and confirm each one now exits 0: the failing tests
       themselves (the files or names the evidence points at) and the brief's
       `Checks:` over the files you changed. Do not re-run a whole suite from
       the brief's `Full suites:` line; the next batch's verifier runs it.
       Keep the fix confined to what the failure needs.
       A command that prints an all-green summary and exits non-zero has NOT
       passed — judge by the exit code, never by the printed totals.
    5. Commit your fix on PHASE_BRANCH and leave the working tree clean.
    6. Record any decision you took in DECISIONS_PATH under the decision
       policy.

    ## Constraints

    - Do NOT switch branches, create branches, rebase, or push. The only
      merge you may run is the one in step 0, of BASE into PHASE_BRANCH. The
      controller owns integration; you own this branch's contents.
    - Work only inside WORKTREE. Do NOT touch the main checkout, the base
      branch BASE, the integration worktree, or any other phase's worktree or
      branch. Other phases are being built beside this one right now.
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
