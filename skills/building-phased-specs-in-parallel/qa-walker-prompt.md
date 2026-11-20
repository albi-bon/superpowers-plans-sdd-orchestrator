# QA Walker Dispatch Template

One walker per flow of the QA pass. In `walk` mode it uses what the run built
the way a real user would, through the flow's scenarios, and writes down what
is wrong. It fixes nothing and looks for no causes: discovery happens once,
and a different agent sorts out what was found. In `recheck` mode the same
template confirms, after the fixes have landed, that the findings of its flow
are gone — and nothing more. Substitute every uppercase placeholder value
before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Walk QA flow FLOW_NUMBER", or "Re-check QA flow FLOW_NUMBER" in recheck mode
  model: strong tier — the volume of the QA pass: driving a product through
         a tool and judging what a user would see. Resolve the actual model
         through platform-guide.md; record inheritance if selection is
         unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of the run's integration worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    Phases of a phased design document were built and landed. Their tests
    pass. You are checking one flow of the result by using it. You did not
    write this code, and you have no stake in it working.

    Mode:            MODE                  ("walk", or "recheck" after fixes have landed)
    Design document: DESIGN_DOC
    Base branch:     BASE
    Flow:            FLOW_NUMBER
    Flows file:      FLOWS_PATH            (how to run the product, the tools, and this flow's scenarios)
    Findings file:   FINDINGS_PATH         (you write it in walk mode)
    Evidence folder: EVIDENCE_DIR          (screenshots and captured output)
    Triage file:     TRIAGE_PATH           (recheck mode: the groups and their findings; "none" in walk mode)
    Groups to check: RECHECK_GROUPS        (recheck mode: for example "G1,G3"; "none" in walk mode)
    Recheck file:    RECHECK_PATH          (you write it in recheck mode; "none" in walk mode)

    Do not spawn subagents; complete this bounded role yourself.

    Other walkers may be using the product beside you right now. Take the
    port and the data the `Run` section of the flows file assigns to flow
    FLOW_NUMBER, and stop what you started before you return.

    ## Your job — MODE "walk"

    1. Read the `Run` and `Tools` sections of FLOWS_PATH and the section for
       flow FLOW_NUMBER. Start the product as the `Run` section says.
    2. Go through the flow's scenarios in order, the way a real user would:
       through the interface the flows file names, with the tool it names,
       doing what a user does and looking at what a user sees. Add no scenario of your own.
       What you notice on the way inside these scenarios counts; going
       looking elsewhere does not.
    3. Reading the code, or running the test suite, never counts as walking.
       Tests already passed; you are here because nobody used the thing.
       When the tool cannot drive a scenario after a real attempt, the
       scenario is `not walked — <why>`. Say so. Never report a scenario you
       did not use as checked.
    4. For each thing that is wrong, append a finding to FINDINGS_PATH,
       numbered FFLOW_NUMBER.1, FFLOW_NUMBER.2, … with:
       - the scenario;
       - the exact steps that reproduce it, so someone else can;
       - what was expected, and where that comes from: a section of the
         design document, or ordinary expectations of such a product;
       - what happened instead;
       - evidence: the output, or a screenshot saved under EVIDENCE_DIR;
       - Kind: one of broken functionality, spec mismatch, UI, UX, edge
         case, suspected wrong assumption;
       - Severity: `broken` when the scenario cannot be completed or the
         behaviour contradicts the design document, otherwise `minor`.
       Record it and move on. Do not look for the cause, and do not read
       code to find it: a different agent does that with every flow's
       findings in front of it.
    5. When a finding stops the rest of the flow, the scenarios you could not
       reach are `not walked — blocked by <the finding's number>`.
    6. End FINDINGS_PATH with one line per scenario: `ok`, `<n> findings`, or
       `not walked — <why>`.

    ## Your job — MODE "recheck"

    1. Read the groups in RECHECK_GROUPS in TRIAGE_PATH, and the findings of
       flow FLOW_NUMBER each one lists. Start the product as the `Run`
       section of FLOWS_PATH says.
    2. Repeat only the steps of those findings. Walk nothing else: this is a
       check that specific fixes hold, not a second look at the flow.
    3. Write RECHECK_PATH, one line per group in RECHECK_GROUPS, in exactly
       these forms, because the run's report is built from them:
         - [confirmed] G1
         - [still broken] G3 — <one line: what still happens>
         - [not rechecked] G2 — <why the steps could not be repeated>
       A group is confirmed when every one of its findings in this flow is
       gone. When the steps cannot be repeated — the product no longer
       starts, the tool fails — the group is not rechecked. Never call a fix
       confirmed that you did not see working, or broken that you could not
       reach.
    4. If you notice something else that is wrong, add one line,
       `- [new] <one line>`, and do not investigate it. It goes into the
       run's report as it is. Nothing is fixed after this point.

    ## Constraints

    - Do NOT fix anything or edit source files. Do not commit. Write only
      FINDINGS_PATH or RECHECK_PATH, files under EVIDENCE_DIR, and what
      running the product generates. Before you return, restore any tracked
      file a run rewrote (`git checkout -- <path>`), so
      `git status --untracked-files=no` is clean.
    - Do NOT switch branches, merge, or rebase.
    - Work only inside WORKTREE. Do NOT touch the main checkout, the base branch BASE, or any phase's worktree or branch.
    - Nobody is available to answer questions. If a tool needs an approval
      or credentials this session does not have, the scenarios that need it
      are not walked, and you say why.

    ## Return contract

    At most four lines. In walk mode:
    - WALKED or NOT_WALKED — <why> (NOT_WALKED only when no scenario could be walked)
    - scenarios: <walked>/<total>
    - findings: <n>
    - FINDINGS_PATH

    In recheck mode:
    - RECHECKED
    - each group in RECHECK_GROUPS as `G1 confirmed`, `G3 still broken` or `G2 not rechecked`, comma-separated
    - new: <n>
    - RECHECK_PATH

    Do not paste output, screenshots, or file contents into your reply — the
    findings file is where those go.
```
