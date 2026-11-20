# QA Planner Dispatch Template

The first agent of the optional QA pass. Dispatched once, after every requested
phase has landed and the final check is done, when the owner asked for QA. It
works out how a real user reaches what the run built, proves the product
starts, and writes the flows the walkers will go through. Nothing in the pass
looks at anything this agent did not list, which is why it runs on the top
tier. Substitute every uppercase placeholder value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Plan the QA pass of BASE"
  model: top tier, the most capable model available — one dispatch decides
         what the whole QA pass looks at, and a flow it misses is never
         walked. Resolve the actual model through platform-guide.md; record
         inheritance if selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of the run's integration worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    Phases of a phased design document were built, verified and landed on the
    base branch. Gates and tests passed. Nobody has used the result yet. You
    are planning a QA pass: other agents will use what was built the way a
    real user would, one flow each, from the plan you write. You use nothing
    yourself beyond proving that the product starts.

    Design document: DESIGN_DOC
    Base branch:     BASE
    QA branch:       QA_BRANCH             (checked out in WORKTREE, at BASE's tip)
    Phases:          PHASES                (one line per phase the run built: number, title, brief path, decisions path)
    QA scope:        QA_SCOPE              ("top N", "all", or "focus: <the owner's words>")
    Setup command:   SETUP_COMMAND
    Setup marker:    SETUP_MARKER          (the commit the worktree's dependencies were last installed for)
    Flows file:      FLOWS_PATH            (you write it)

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    1. Read the design document's sections for the phases in PHASES, their
       briefs and their decisions files. See what each phase changed: every
       phase landed as one `merge: phase <N> — …` commit on BASE
       (`git log --first-parent`), and `git diff --name-only <merge>^1 <merge>`
       lists its files.
    2. Make the worktree runnable. Run SETUP_COMMAND — or, if it is "none —
       discover it", the `Setup:` line from any phase's brief Global
       constraints — when dependencies are missing, when SETUP_MARKER does
       not exist, or when any manifest or lockfile differs between the commit
       SETUP_MARKER names and HEAD (`git diff --name-only <that SHA> HEAD`).
       After a setup that exits 0, write HEAD's full SHA to SETUP_MARKER.
    3. Work out how a user reaches this product. A flow is something a user
       does from start to finish through the outermost interface a real user touches:
       a command line, a page in a browser, an app in a simulator or
       emulator, an HTTP API a client calls, a library's public API called
       from a script of the user's own. Nothing here assumes one kind of
       product; describe the one in front of you.
    4. List the interaction tools available to you in this session and what
       each can drive: the shell, a browser automation tool, a simulator or
       emulator and its command line, control of the desktop, an HTTP
       client. Those are examples of what an environment may offer, not a
       list to expect. The walkers get the same tools you have.
    5. Start the product once yourself, the way step 3 says a user reaches
       it, and stop it again. Record the exact commands: setup, seed data,
       start, stop, and the test credentials the repository provides. Say
       whether several users of it can run side by side in this worktree
       (own ports, own data) or must go one after another. If the product
       cannot be started at all, return BLOCKED with the command and the
       error.
    6. Rank every flow the run touched: first by how central it is to the
       design document's goals, then by how much the run changed it, then by
       what it costs when broken. Number them F1, F2, … in that order. List
       all of them, then select by QA_SCOPE:
       - "top N": the N highest-ranked flows.
       - "all": every flow.
       - "focus: <words>": the flows those words describe. Say in the flows
         file which of the words match no flow.
       A run that changed nothing a user can reach has no flows. That is a
       valid result: write the file with no flows and return.
    7. For each selected flow, write its scenarios: the main path, the
       obvious variations, and at most three edge cases worth a user's time.
       Give each scenario the steps a user takes and what they should see,
       with the section of the design document it comes from. Name the tool
       that will drive the flow. When no available tool can drive it, mark
       the flow `not walkable — <why>` and write no scenarios: a flow nobody
       can use is reported as not walked, never guessed at.
    8. The pass covers what the phases in PHASES deliver. A flow that also
       needs a phase the run did not build is walked as far as these phases
       take it: end its scenarios there. A flow that cannot start without
       such a phase is `not walkable — needs phase <N>, not in this run`.
    9. Write FLOWS_PATH in this order:
       - the index, one line per flow, in exactly these forms, because the
         run's report is built from them:
           - [selected] F2 — checkout
           - [not walkable] F4 — share sheet: <why>
           - [not selected] F6 — export
       - a `Run` section: the commands and credentials of step 5, and for a
         product that runs side by side, which port or data directory each
         flow number takes;
       - a `Tools` section: step 4;
       - one section per selected flow: its scenarios and its tool.

    ## Constraints

    - Do NOT edit source files, fix anything, or commit. Write only
      FLOWS_PATH, SETUP_MARKER and what running the product generates. Before
      you return, stop what you started and restore any tracked file a setup
      or a run rewrote (`git checkout -- <path>`), so
      `git status --untracked-files=no` is clean.
    - Do NOT switch branches, merge, or rebase.
    - Work only inside WORKTREE. Do NOT touch the main checkout, the base branch BASE, or any phase's worktree or branch.
    - Nobody is available to answer questions. Return BLOCKED only when the
      product cannot be started here, or starting it needs credentials,
      approval or an external system this session does not have. A flow you
      cannot drive is not BLOCKED; it is `not walkable`.

    ## Return contract

    At most six lines:
    - DEFINED, or BLOCKED — <one-line reason>
    - found: <number of flows>
    - selected: <flow numbers, comma-separated, or -> (numbers only, without the F)
    - not walkable: <flow numbers among the selected ones, comma-separated, or ->
    - parallel: yes or parallel: no (whether walkers can use the product side by side)
    - FLOWS_PATH

    Do not paste command output, flows, or file contents into your reply — the
    flows file is where those go.
```
