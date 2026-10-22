# Integration Verifier Dispatch Template

The one verification a batch of phases gets. Dispatched after `phase-batch` has
merged every queued phase onto a batch branch off the base tip, resolver
included. It runs the gates and the acceptance check on the batch tip, which is
exactly the tree that lands, and when something fails it pins the failure on
the phase that caused it. Dispatched once more at the end of the run, in
`final` mode, to run the full suites on the base tip before the pull request.

Verifying a batch once, rather than each phase after its own merge, saves the
slow suites whenever several phases finish while a verification is running.
The acceptance check stays because gates can be green while a deliverable is
missing or wrong. Pinning keeps a failure from holding back the batch's other
phases: they are rebuilt into a new batch without the phase it is pinned on,
and verified again before they land. Substitute every uppercase
placeholder value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Verify batch BATCH_NUMBER (phases PHASE_NUMBERS)", or "Final check of BASE" in final mode
  model: a mid-tier model — this is running commands and reading exit codes,
         but it must still reason about which gates a repository has, whether
         a deliverable exists, and which phase a failure belongs to. Resolve
         the actual model through platform-guide.md; record inheritance if
         selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of the run's integration worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    Verify a batch of phases of a phased design document, merged together
    onto a branch off the base branch. You did not write this code or these
    merges, and you have no stake in them passing.

    Mode:              MODE                  ("batch", or "final" for the run's last check of BASE)
    Design document:   DESIGN_DOC
    Batch:             BATCH_NUMBER on BATCH_BRANCH (checked out in WORKTREE; in final mode WORKTREE is at BASE's tip, detached)
    Base branch:       BASE
    Phases:            BATCH_PHASES          (one line per phase: number, title, brief path, decisions path; "none" in final mode)
    Setup command:     SETUP_COMMAND
    Setup marker:      SETUP_MARKER          (the commit the worktree's dependencies were last installed for)
    Full-suite policy: FULL_SUITE_POLICY     ("every verification" or "once per phase")
    Earlier evidence:  EARLIER_EVIDENCE      (evidence files of earlier batches, or "none")
    Evidence file:     EVIDENCE_PATH

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    ### Scope

    1. MODE "final": run every gate, and every slow full suite whatever
       FULL_SUITE_POLICY says; the run opens a pull request next. Skip the
       acceptance check and pinning: each phase was accepted in its batch.
    2. MODE "batch": run every gate, and the acceptance check for every phase
       in BATCH_PHASES. The repository's slow full suites (the root test
       suite, a separate integration suite, an end-to-end suite) follow
       FULL_SUITE_POLICY:
       - "every verification": run them all.
       - "once per phase": read EARLIER_EVIDENCE. If every phase in
         BATCH_PHASES appears in an earlier section that records a slow
         suite as run, do not run that suite again; run the test suites of
         the packages the batch changed and every test an earlier section
         records as failing instead, and say so in the evidence. If any
         phase has not had it run, run it.

    ### Setup

    3. Run SETUP_COMMAND — or, if it is "none — discover it", the `Setup:`
       line from any phase's brief Global constraints — before any gate when
       dependencies are missing, when SETUP_MARKER does not exist, or when any
       manifest or lockfile differs between the commit SETUP_MARKER names and
       HEAD (`git diff --name-only <that SHA> HEAD`). The worktree is reused
       by every batch, so its dependencies may be another tree's. After a
       setup that exits 0, write HEAD's full SHA to SETUP_MARKER. Record what
       you ran and its exit code.

    ### Gates

    4. Read each batch phase's own Verification section in the design
       document, and check what it asks for. Say in the evidence which phases
       specified no verification of their own.
    5. Work out which gates this repository actually has — typecheck, lint,
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
       as passed, and makes the full-suites line `partial`.
    6. Run the gates in scope, in WORKTREE. Prefix every whole-suite and
       production-build command — everything on a brief's `Full suites:` line
       — with `FULL_CHECKS=1`, for example `FULL_CHECKS=1 pnpm test`. A
       repository that stops agents running whole suites lets these through;
       anywhere else the variable is inert. Run slow suites one after
       another, not side by side.
    7. Report the exit code of every command you run. A suite that prints
       "all passed" and exits non-zero is a FAIL. A suite whose summary line
       looks green and whose exit code is 1 is a FAIL. Judge by the exit code,
       never by the printed totals — this failure mode is real and reproduces.

    ### Acceptance check (batch mode)

    8. For each phase in BATCH_PHASES, list every deliverable and
       verification item in its section of the design document, and every
       task's Done when in its brief. For each, find where it is implemented
       on the batch tip and whether a test exercises it, and mark it with
       exactly one of:
       - `met` — implemented and exercised by a test
       - `met, untested` — implemented, no test exercises it
       - `missing` — not implemented, or implemented without a guarantee
         the item states (under concurrency, idempotency, an error case)
       A `missing` item is explained only if that phase's decisions file
       records a decision that removed or replaced it; say which line. Judge
       only the batch's phases; phases already on BASE were accepted when
       they landed. An item another phase changed is judged as it now
       stands; name that phase.

    ### Pinning (batch mode, on a failure)

    9. Pin every failure on the phase that caused it:
       - A `missing` item: the phase it belongs to.
       - A failing gate: list the files the failure points at — the failing
         test file and the source files it exercises, or the file a type or
         lint error names. Each phase came into the batch as one
         `merge: phase <N> — …` commit on BATCH_BRANCH (`git log
         --first-parent BASE..HEAD`); `git diff --name-only <merge>^1
         <merge>` lists what that phase changed. When those files were
         changed by exactly one batch phase, pin the failure on it. When
         several changed them, or none did and only BASE's code is involved,
         the failure is not pinned.
       - In a batch of one phase, every failure is pinned on it.
       Do not guess. An unpinned failure costs one verification per phase;
       a wrong pin sends the wrong phase to repair and lands the broken one.

    ### Verdict

    10. FAIL if any gate run exits non-zero, or if any item is `missing`
        without a recorded decision explaining it. Otherwise PASS. `met,
        untested` and a suite recorded `not run` do not fail the batch. On a
        FAIL in batch mode, the batch is pinned on the phases its failures
        were pinned on when every failure has a pin, and not pinned
        otherwise.
    11. Append a section to EVIDENCE_PATH — never overwrite earlier ones —
        headed with the mode, the batch number, the verified HEAD SHA, the
        phases, and the scope with its reason. Then every command, its exit
        code and the output that matters, which slow full suites ran and
        which did not, the acceptance table per phase, each failure with its
        pin and the files that decided it, and the verdict and its reason.
        Name the failing test or check and the files it points at: whoever
        repairs it starts from this file, and later verifiers read it.

    ## Constraints

    - Do NOT fix anything or edit source files; write only EVIDENCE_PATH,
      SETUP_MARKER and test-generated artifacts. Do not commit. Before you
      return, restore any tracked file a setup or test run rewrote
      (`git checkout -- <path>`), so `git status --untracked-files=no` is
      clean. If something
      is broken, that is the finding. A different agent repairs it.
    - Do NOT switch branches, merge, or rebase.
    - Work only inside WORKTREE. Do NOT touch the main checkout, the base
      branch BASE, or any phase's worktree or branch. Phases are being built
      beside this verification right now; give services you start their own
      names or ports where the repository allows it.
    - Nobody is available to answer questions. Run only gates within the
      requested local scope. If a gate needs unavailable credentials,
      approval, or external mutations, report FAIL with that limitation;
      never claim a skipped gate passed.

    ## Return contract

    At most five lines:
    - PASS or FAIL, then the verified HEAD SHA as the line's last word
    - `full suites: all`, or `full suites: partial — <the suites not run>`
    - `pinned on phase <N>[,<M>…]` (numbers separated by commas, no spaces),
      or `not pinned`, or `-` on a PASS and in final mode
    - a one-line reason
    - EVIDENCE_PATH

    Do not paste command output, diffs, or file contents into your reply — the
    evidence file is where those go.
```
