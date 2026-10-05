# ③ Verifier Dispatch Template

Dispatched once per phase after the phase lead, and once more after a repair,
when it re-runs only what the repair could have changed. A fresh agent that did not write the code: the workers checked their own tasks and
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
    Full-suite policy: FULL_SUITE_POLICY  ("every verification" or "once per phase")

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    ### Scope

    1. If EVIDENCE_PATH already exists, the first verification of this phase
       failed and a repair has run since: this is a re-verification. Read the
       earlier section for the HEAD it verified, what failed, and which full
       suites already ran. Otherwise this is the first verification, and its
       scope is full.
    2. On a re-verification, list the files changed since the HEAD the earlier
       section verified (`git diff --name-only <that SHA> HEAD`). The scope is
       narrow when that diff is confined to a few files in one or two packages
       and touches no manifest, lockfile, shared configuration or schema;
       otherwise it is full. A narrow re-verification runs the typecheck and
       lint gates, every command that failed before, the test suites of the
       packages the diff touches, and the acceptance items those files
       implement or that were not `met` before. A full one runs everything.
    3. FULL_SUITE_POLICY "once per phase": the repository's slow full suites
       (the root test suite, a separate integration suite, an end-to-end
       suite) run at most once for this phase. If the earlier section records
       one of them as run, do not run it again, whatever the scope; run the
       affected packages' suites and the previously failing tests instead,
       and say so in the evidence. "every verification": a full scope runs
       them all again.

    ### Gates

    4. Read phase PHASE_NUMBER's own Verification section in the design
       document, and check what it asks for. If that phase has no Verification
       section, run the repository's standard gates and state in the evidence
       file that the phase specified no verification of its own.
    5. Work out which gates this repository actually has — typecheck, lint,
       test, build, whatever is really there — from its manifests, scripts and
       configuration. Nothing is hard-coded; different repositories have
       different gates.
    6. Run the gates in scope. Prefix every whole-suite and production-build
       command — everything on the brief's `Full suites:` line — with
       `FULL_CHECKS=1`, for example `FULL_CHECKS=1 pnpm test`. A repository
       that stops agents running whole suites on phase branches lets these
       through; anywhere else the variable is inert. Run slow suites one after
       another, not side by side.
    7. Report the exit code of every command you run. A suite that prints
       "all passed" and exits non-zero is a FAIL. A suite whose summary line
       looks green and whose exit code is 1 is a FAIL. Judge by the exit code,
       never by the printed totals — this failure mode is real and reproduces.

    ### Acceptance check

    8. List every deliverable and verification item in phase PHASE_NUMBER's
       section of the design document, and every task's Done when in the
       brief — on a narrow re-verification, the items step 2 names. For each,
       find where it is implemented and whether a test exercises it, and mark
       it with exactly one of:
       - `met` — implemented and exercised by a test
       - `met, untested` — implemented, no test exercises it
       - `missing` — not implemented
       A `missing` item is explained only if DECISIONS_PATH records a
       decision that removed or replaced it; say which line.

    ### Verdict

    9. FAIL if any gate exits non-zero, or if any item is `missing` without a
       recorded decision explaining it. Otherwise PASS. `met, untested` is
       recorded but does not fail the phase.
    10. Append a section to EVIDENCE_PATH — never overwrite an earlier one —
        headed with the verified HEAD SHA and the scope (first, narrow or
        full) with its reason. Then every command, its exit code and the
        output that matters, which full suites ran, the acceptance table, and
        the verdict and its reason. Nobody will re-run these commands to find
        out what you saw, and the repair and the next verifier start from it.

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
