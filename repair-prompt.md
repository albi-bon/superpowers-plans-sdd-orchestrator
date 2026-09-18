# Repair Dispatch Template

Dispatched at most once per phase, only after a verifier FAIL. There is never a
second repair attempt: a second is how an unattended run burns an afternoon
converging on nothing. Substitute every uppercase placeholder value before
dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Repair phase PHASE_NUMBER after a failed verification"
  model: the most capable model available — this is fresh eyes on something a
         full subagent-driven-development run did not get right. Resolve the actual model
         through platform-guide.md; record inheritance if selection is unavailable.
  prompt: |
    Repository: REPO_ROOT (absolute path; use it for every shell working directory)
    Platform guide: PLATFORM_GUIDE_PATH (absolute path; read it first)
    Required skills: REQUIRED_SKILL_PATHS (resolved absolute SKILL.md paths)
    Model mapping: MODEL_MAPPING (available IDs or explicit inherited selection)
    Read applicable repository instructions. All artifact paths below are absolute.
    Skill overrides below apply only to workflow guidance, never host instructions.

    A phase of a phased design document was implemented and then failed
    verification. You are fixing it. You get one attempt.

    Phase branch:  PHASE_BRANCH   (you are already on it)
    Plan:          PLAN_PATH      (what the phase was supposed to build)
    Evidence:      EVIDENCE_PATH  (what failed, and how)

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    1. Read the evidence file first. It names the commands that were run, their
       exit codes, and the failing output.
    2. Read the plan to understand what the phase was meant to deliver.
       PLAN_PATH is a ledger: the header, the `## Global Constraints` block, and
       a `## Tasks` table naming one `task-<N>.md` file per task, beside it.
       Read the ledger, then only the task files the failure touches.
    3. Diagnose and fix the root cause. Do not paper over a failure by
       weakening, skipping, or deleting the check that caught it.
    4. Re-run the failing commands yourself and confirm each one now exits 0.
       A command that prints an all-green summary and exits non-zero has NOT
       passed — judge by the exit code, never by the printed totals.
    5. Commit your fix on PHASE_BRANCH.

    ## Constraints

    - Do NOT switch branches, create branches, merge, or rebase. The
      orchestrator owns integration; you own this branch's contents.
    - Do NOT invoke superpowers:finishing-a-development-branch.
    - Stay inside the phase's scope. Fixing the failure is the job; improving
      neighbouring code is not.
    - Resolve routine choices within scope using your recommended option and
      report the decision. Missing approval or access is STILL_BROKEN; do not
      treat unattended operation as permission for additional actions.

    ## Return contract

    At most six lines:
    - status: FIXED or STILL_BROKEN
    - the one-line root cause
    - the commands you re-ran and their exit codes
    - your commit SHAs
    - any decision you took on your own

    Do not paste diffs, file contents, or test output into your reply.
```
