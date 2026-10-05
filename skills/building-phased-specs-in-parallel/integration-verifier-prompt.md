# Integration Verifier Dispatch Template

The one verification a phase gets. Dispatched after `phase-integrate` has brought
the base branch into the phase branch — whether it printed `ready` (base never
moved), `merged`, or the resolver concluded the merge — and again after each
repair or rescue. It runs the gates and the acceptance check on the integrated
tree, which is exactly the tree that lands.

Verifying once, here, replaces a phase verifier on the phase branch followed by
a gates-only integration verifier: in a parallel run base has usually moved, so
the two re-ran the same slow suites for most phases. The acceptance check stays
because gates can be green while a deliverable is missing or wrong. Substitute
every uppercase placeholder value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Verify integrated phase PHASE_NUMBER on PHASE_BRANCH"
  model: a mid-tier model — this is running commands and reading exit codes,
         but it must still reason about which gates a repository has and
         whether a deliverable exists. Resolve the actual model through
         platform-guide.md; record inheritance if selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of this phase's worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    Verify one phase of a phased design document, on its branch with the
    base branch already merged in. You did not write this code or this
    merge, and you have no stake in it passing.

    Design document:   DESIGN_DOC
    Phase number:      PHASE_NUMBER
    Phase branch:      PHASE_BRANCH                (checked out in WORKTREE)
    Base branch:       BASE
    Merged since:      MERGED_PHASES               (phases merged into BASE since this phase began, or "none")
    Brief:             BRIEF_PATH                  (the phase's tasks and their Done when; Global constraints carry the Setup line)
    Decisions file:    DECISIONS_PATH              (choices the agents recorded)
    Setup command:     SETUP_COMMAND
    Full-suite policy: FULL_SUITE_POLICY           ("every verification" or "once per phase")
    Evidence file:     INTEGRATION_EVIDENCE_PATH

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    ### Scope

    1. If INTEGRATION_EVIDENCE_PATH already exists, an earlier verification
       of this phase failed and a repair or rescue has run since: this is a
       re-verification. Read the earlier sections for the HEAD they verified,
       what failed, and which full suites already ran. Otherwise this is the
       first verification, and its scope is full.
    2. On a re-verification, list the files changed since the HEAD the last
       section verified (`git diff --name-only <that SHA> HEAD`). The scope
       is narrow when that diff is confined to a few files in one or two
       packages and touches no manifest, lockfile, shared configuration or
       schema; otherwise it is full. A narrow re-verification runs the
       typecheck and lint gates, every command that failed before, the test
       suites of the packages the diff touches, and the acceptance items those
       files implement or that were not `met` before. A full one runs
       everything.
    3. FULL_SUITE_POLICY "once per phase": the repository's slow full suites
       (the root test suite, a separate integration suite, an end-to-end
       suite) run at most once for this phase. If an earlier section records
       one of them as run, do not run it again, whatever the scope; run the
       affected packages' suites and the previously failing tests instead,
       and say so in the evidence. "every verification": a full scope runs
       them all again.

    ### Setup

    4. Find the integration merge: the latest commit on PHASE_BRANCH whose
       subject starts `integrate: base into phase PHASE_NUMBER`. There is none
       when base never moved since the phase began. If any
       manifest or lockfile differs between its first parent and HEAD, or
       dependencies are missing, run SETUP_COMMAND, or, if it is "none — discover it", the
       `Setup:` line from the brief's Global constraints, before any gate.
       Record what you ran and its exit code.

    ### Gates

    5. Read phase PHASE_NUMBER's own Verification section in the design
       document, and check what it asks for. If that phase has no Verification
       section, say in the evidence that the phase specified
       no verification of its own.
    6. Work out which gates this repository actually has — typecheck, lint,
       test, build, whatever is really there — from its manifests, scripts and
       configuration. Nothing is hard-coded; different repositories have
       different gates. Include every test configuration, not only the root
       unit suite: a separate integration suite (a `test:integration` script,
       a second test-runner config) that needs a database or Docker, and an
       end-to-end suite. Start the services they need with the repository's
       own commands (its compose file, its scripts) and stop them afterwards.
       Run such a suite whenever its infrastructure can be started here; skip
       it only when it cannot, and then record `not run — <why>` in the
       evidence and name it in your reason line. A skipped suite never counts
       as passed.
    7. Run the gates in scope, in WORKTREE.
    8. Report the exit code of every command you run. A suite that prints
       "all passed" and exits non-zero is a FAIL. A suite whose summary line
       looks green and whose exit code is 1 is a FAIL. Judge by the exit code,
       never by the printed totals — this failure mode is real and reproduces.

    ### Acceptance check

    9. List every deliverable and verification item in phase PHASE_NUMBER's
       section of the design document, and every task's Done when in the
       brief. These are this phase's deliverables: judge them, not those of
       the phases in MERGED_PHASES, which were verified when they landed. For
       each, find where it is implemented on the integrated tree and whether
       a test exercises it, and mark it with exactly one of:
       - `met` — implemented and exercised by a test
       - `met, untested` — implemented, no test exercises it
       - `missing` — not implemented, or implemented without a guarantee
         the item states (under concurrency, idempotency, an error case)
       A `missing` item is explained only if DECISIONS_PATH records a
       decision that removed or replaced it; say which line. An item a merged
       phase changed is judged as it now stands; name that phase.

    ### Verdict

    10. FAIL if any gate run exits non-zero, or if any item is `missing`
        without a recorded decision explaining it. Otherwise PASS. `met,
        untested` and a suite recorded `not run` do not fail the phase.
        A gate failure caused by a merged phase's code rather than this
        phase's is still a FAIL; say which phase.
    11. Append a section to INTEGRATION_EVIDENCE_PATH — never overwrite
        earlier ones — headed with the verified HEAD SHA, the integration
        merge SHA (or "base unchanged"), and the scope (first, narrow or full)
        with its reason. Then every command, its exit code and the output that
        matters, which full suites ran, the acceptance table, and the verdict
        and its reason. Name the failing test or check and the files it
        points at: whoever repairs it starts from this file, and the next
        verifier reads it.

    ## Constraints

    - Do NOT fix anything or edit source files; write only
      INTEGRATION_EVIDENCE_PATH and test-generated artifacts. Do not commit.
      If something is broken, that is the finding. A different agent repairs
      it.
    - Do NOT switch branches, merge, or rebase.
    - Work only inside WORKTREE. Do NOT touch the main checkout, the base
      branch BASE, or any other phase's worktree or branch. Other phases are
      being built beside this one right now; give services you start their
      own names or ports where the repository allows it.
    - Nobody is available to answer questions. Run only gates within the
      requested local scope. If a gate needs unavailable credentials,
      approval, or external mutations, report FAIL with that limitation;
      never claim a skipped gate passed.

    ## Return contract

    At most three lines:
    - PASS or FAIL, then the verified HEAD SHA as the line's last word
    - a one-line reason
    - INTEGRATION_EVIDENCE_PATH

    Do not paste command output, diffs, or file contents into your reply — the
    evidence file is where those go.
```
