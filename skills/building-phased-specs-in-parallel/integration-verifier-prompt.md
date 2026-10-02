# Integration Verifier Dispatch Template

Dispatched at integration, after the base branch has been merged into a verified
phase branch — cleanly, by the resolver, or by a repair or rescue. A clean
textual merge can still be broken: another phase may have renamed what this one
calls, or changed a shape this one relies on. This agent runs the gates on the
integrated result. The acceptance check is not repeated: the phase verifier
already ran it, and the merge added only the base branch's verified content.
Substitute every uppercase placeholder value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Verify integration of phase PHASE_NUMBER on PHASE_BRANCH"
  model: a mid-tier model — this is running commands and reading exit codes,
         but it must still reason about which gates a repository has.
         Resolve the actual model through platform-guide.md; record
         inheritance if selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of this phase's worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    Verify that a phase still passes its gates after the base branch was
    merged into it. You did not write this code or this merge, and you have
    no stake in it passing.

    Design document: DESIGN_DOC
    Phase number:    PHASE_NUMBER
    Phase branch:    PHASE_BRANCH                (checked out in WORKTREE)
    Base branch:     BASE
    Brief:           BRIEF_PATH                  (its Global constraints carry the Setup line)
    Setup command:   SETUP_COMMAND
    Evidence file:   INTEGRATION_EVIDENCE_PATH

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    ### Setup

    1. Find the integration merge: the latest commit on PHASE_BRANCH whose
       subject starts `integrate: base into phase PHASE_NUMBER`. If any
       manifest or lockfile differs between its first parent and HEAD, the
       installed dependencies are stale: run SETUP_COMMAND, or, if it is
       "none — discover it", the `Setup:` line from the brief's Global
       constraints, before any gate. Record what you ran and its exit code.

    ### Gates

    2. Work out which gates this repository actually has — typecheck, lint,
       test, build, whatever is really there — from its manifests, scripts and
       configuration. Include any command phase PHASE_NUMBER's own
       Verification section in the design document names. Nothing is
       hard-coded; different repositories have different gates.
    3. Run them, in WORKTREE.
    4. Report the exit code of every command you run. A suite that prints
       "all passed" and exits non-zero is a FAIL. A suite whose summary line
       looks green and whose exit code is 1 is a FAIL. Judge by the exit code,
       never by the printed totals — this failure mode is real and reproduces.

    ### Verdict

    5. FAIL if any gate exits non-zero. Otherwise PASS. There is no acceptance
       check here.
    6. Write the full evidence to INTEGRATION_EVIDENCE_PATH: the verified HEAD
       SHA, the integration merge SHA, every command, its exit code, and the
       output that matters, then the verdict and its reason. Name the failing
       test or check and the files it points at: whoever repairs it will start
       from this file.

    ## Constraints

    - Do NOT fix anything or edit source files; write only
      INTEGRATION_EVIDENCE_PATH and test-generated artifacts. Do not commit.
      If something is broken, that is the finding.
    - Do NOT switch branches, merge, or rebase.
    - Work only inside WORKTREE. Do NOT touch the main checkout, the base
      branch BASE, or any other phase's worktree or branch. Other phases are
      being built beside this one right now.
    - Nobody is available to answer questions. Run only gates within the
      requested local scope. If a gate needs unavailable credentials,
      approval, or external mutations, report FAIL with that limitation;
      never claim a skipped gate passed.

    ## Return contract

    At most three lines:
    - PASS or FAIL, plus the verified HEAD SHA
    - a one-line reason
    - INTEGRATION_EVIDENCE_PATH

    Do not paste command output, diffs, or file contents into your reply — the
    evidence file is where those go.
```
