# ③ Verifier Dispatch Template

Dispatched once per phase after the phase lead, and once more after a repair. A
fresh agent that did not write the code: the workers checked their own tasks and
the fix wave was never re-reviewed, and an agent invested in code it just wrote
rationalises a non-zero exit code away. Substitute every uppercase placeholder
value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Verify phase PHASE_NUMBER on PHASE_BRANCH"
  model: a mid-tier model — this is running commands and reading exit codes,
         but it must still reason about which gates a repository has and
         whether a deliverable exists. Resolve the actual model through
         platform-guide.md; record inheritance if selection is unavailable.
  prompt: |
    Repository: REPO_ROOT (absolute path; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    Verify one phase of a phased design document. You did not write this code
    and you have no stake in it passing.

    Design document: DESIGN_DOC
    Phase number:    PHASE_NUMBER
    Phase branch:    PHASE_BRANCH     (you are already on it)
    Brief:           BRIEF_PATH       (the phase's tasks and their Done when)
    Decisions file:  DECISIONS_PATH   (choices the agents recorded)
    Evidence file:   EVIDENCE_PATH

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    ### Gates

    1. Read phase PHASE_NUMBER's own Verification section in the design
       document, and check what it asks for. If that phase has no Verification
       section, run the repository's standard gates and state in the evidence
       file that the phase specified no verification of its own.
    2. Work out which gates this repository actually has — typecheck, lint,
       test, build, whatever is really there — from its manifests, scripts and
       configuration. Nothing is hard-coded; different repositories have
       different gates.
    3. Run them.
    4. Report the exit code of every command you run. A suite that prints
       "all passed" and exits non-zero is a FAIL. A suite whose summary line
       looks green and whose exit code is 1 is a FAIL. Judge by the exit code,
       never by the printed totals — this failure mode is real and reproduces.

    ### Acceptance check

    5. List every deliverable and verification item in phase PHASE_NUMBER's
       section of the design document, and every task's Done when in the
       brief. For each, find where it is implemented and whether a test
       exercises it, and mark it with exactly one of:
       - `met` — implemented and exercised by a test
       - `met, untested` — implemented, no test exercises it
       - `missing` — not implemented
       A `missing` item is explained only if DECISIONS_PATH records a
       decision that removed or replaced it; say which line.

    ### Verdict

    6. FAIL if any gate exits non-zero, or if any item is `missing` without a
       recorded decision explaining it. Otherwise PASS. `met, untested` is
       recorded but does not fail the phase.
    7. Write the full evidence to EVIDENCE_PATH: the verified HEAD SHA, every
       command, its exit code, and the output that matters, then the
       acceptance table, then the verdict and its reason. Nobody will re-run
       these commands to find out what you saw.

    ## Constraints

    - Do NOT fix anything or edit source files; write only EVIDENCE_PATH and
      test-generated artifacts. Do not commit. If something is broken, that
      is the finding. A different agent repairs it.
    - Do NOT switch branches, merge, or rebase.
    - Nobody is available to answer questions. Run only gates within the
      requested local scope. If a gate needs unavailable credentials,
      approval, or external mutations, report FAIL with that limitation;
      never claim a skipped gate passed.

    ## Return contract

    At most three lines:
    - PASS or FAIL, plus the verified HEAD SHA
    - a one-line reason
    - EVIDENCE_PATH

    Do not paste command output, diffs, or file contents into your reply — the
    evidence file is where those go.
```
