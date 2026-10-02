# ① Scout Dispatch Template

Dispatched once per phase, before any code is written, and again when a held
phase is released. The scout makes the phase's worktree runnable, grounds the
phase against it, and writes the brief the phase lead executes from.
Substitute every uppercase placeholder value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Ground phase PHASE_NUMBER of DESIGN_DOC_BASENAME"
  model: the most capable model available — grounding is judgment: deciding
         which drift matters and how to adapt to it. Resolve the actual model
         through platform-guide.md; record inheritance if selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of this phase's worktree; use it for every shell working directory)
    Platform guide: PLATFORM_GUIDE_PATH (absolute path; read it first)
    Read applicable repository instructions. All artifact paths below are absolute.

    You are grounding ONE phase of a phased design document and writing the
    brief that the rest of the phase is built from.

    Design document: DESIGN_DOC
    Phase number:    PHASE_NUMBER
    Phase title:     PHASE_TITLE
    Run directory:   RUN_DIR
    Brief:           BRIEF_PATH
    Decisions file:  DECISIONS_PATH
    Decision policy: DECISION_POLICY_PATH   (read it before you start)
    Phase branch:    PHASE_BRANCH           (checked out in WORKTREE)
    Base branch:     BASE
    Setup command:   SETUP_COMMAND
    Merged phases:   MERGED_PHASES          (already merged to BASE)
    In-flight phases: IN_FLIGHT_PHASES      (being built in other worktrees now)

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    0. Make the worktree runnable. If SETUP_COMMAND is a command, run it in
       WORKTREE. Otherwise work out the repository's install step from its
       manifests, lockfiles and documentation, and run that. Judge it by its
       exit code. Record the exact command under the brief's Global
       constraints as `Setup: <command>`, so verifiers can repeat it. A
       worktree is a fresh checkout: nothing is installed until you do it.
    1. Read the whole design document, so you understand the phases either
       side of this one and the decisions that bind all of them.
    2. For each phase in MERGED_PHASES, read `phase-<M>-decisions.md` in
       RUN_DIR. Those phases may have deviated from the document; this phase
       builds on what was actually built, not on what the document predicted.
       Do not read the decisions files of in-flight phases: their work is not
       on BASE and may still change.
    3. Ground the phase. For every concrete claim phase PHASE_NUMBER makes —
       file paths, module and symbol names, function signatures, data shapes,
       dependency names and versions, test infrastructure, and anything an
       earlier phase was supposed to deliver — find it in the repository and
       read it. Do not assume a claim is true because the document states it.
    4. For every mismatch, choose a resolution under the decision policy and
       record it in the brief's Drift table. A missing prerequisite becomes an
       extra task — unless one of IN_FLIGHT_PHASES is building it, according
       to the design document. Then do not build it: record the row with the
       resolution "waits for phase <M>" and report it in your return, and the
       controller holds this phase until phase M lands. A renamed or reshaped
       API is adapted to. Append significant resolutions to DECISIONS_PATH as
       the policy describes. A mismatch is never a reason to stop.
    5. Split the phase into 3 to 10 tasks, ordered so each builds only on
       earlier ones. A task is a coherent slice one agent can implement and
       test in one sitting, touching a small set of files.
    6. Write the brief to exactly BRIEF_PATH, in the shape below.

    If BRIEF_PATH already exists, an earlier scout was interrupted, the run
    was resumed, or the phase was held and has now been released onto a newer
    BASE: check it against the repository, complete or correct it, and keep
    every task checkbox that is already ticked. Skip setup in that case unless
    a manifest or lockfile changed since the brief's `Setup:` line was
    written; the worktree already holds the installed dependencies.

    You write BRIEF_PATH and append to DECISIONS_PATH. You edit no source file
    and make no commit; files your setup command generates are not edits.

    ## Constraints

    - Work only inside WORKTREE. Do NOT touch the main checkout, the base
      branch BASE, or any other phase's worktree or branch. Other phases are
      being built beside this one right now.
    - Do NOT switch branches, create branches, merge, rebase, or push.

    ## The brief

    The controller's independence check reads the backticked paths on every
    Files line and compares them with the phases being built beside this one,
    so list every file a task will create or modify, exactly.

    The brief is the only thing the phase lead and its workers read about this
    phase — they never open the design document. Copy what binds them. The
    brief carries no code, no step lists and no test code: a worker writes the
    code once, against the repository as it finds it.

    ~~~markdown
    # Phase PHASE_NUMBER — PHASE_TITLE

    **Goal:** <one paragraph, from the phase section>
    **Spec:** DESIGN_DOC

    ## Global constraints
    Setup: <the exact install command you ran in step 0>
    <copied from the design document with their exact values: decision-log
    items, platform and portability rules, naming and style rules, anything the
    document states as binding on every phase>

    ## Drift
    | # | Document says | Repository has | Resolution | Significant |
    |---|---|---|---|---|
    <one row per mismatch; "none found" if there are none>

    ## Tasks

    ### - [ ] Task 1 — <title>
    - **Goal:** <one or two sentences>
    - **Files:** <every path in backticks, repository-relative, with its action:
      `src/a.ts` (create), `src/b.ts` (modify)>
    - **Produces:** <exact public names and types later tasks build on, or "nothing public">
    - **Done when:** <observable behaviours, one per line>
    - **Test focus:** <which behaviours need tests; edge and error cases the document names>
    - **Notes:** <what you found while grounding that the worker must know>
    - **Tier:** <mechanical or standard, under the rule below>

    ### - [ ] Task 2 — <title>
    …
    ~~~

    ## Task tier

    Mark a task `Tier: mechanical` only when every statement below is true.
    Otherwise mark it `Tier: standard`.

    - Its Notes name an existing file in the repository whose pattern the task
      copies: the same shape of change, applied to new names or data.
    - Its Produces line is "nothing public", or lists only names that follow
      that pattern exactly.
    - No Drift row with a significant resolution touches its files.
    - It does not touch security, authentication, concurrency, persistence
      schemas or migrations, money, or error-recovery paths.
    - Its Done when lines are checkable by one obvious test each.

    ## Return contract

    At most five lines:
    - BRIEF_PATH
    - the task count
    - the drift count
    - the significant-decision count
    - `prereq-inflight: phase <M>` if a prerequisite this phase needs is being
      built by in-flight phase M, otherwise `prereq-inflight: none`
    If you must return BLOCKED under the decision policy — a setup that
    cannot succeed with the repository's own tooling is case 2 — return the
    single line `BLOCKED — <reason>` instead.

    Do not paste the brief, code, or document text into your reply. The
    controller reading it must survive many more phases, and everything you
    print stays in its context for the rest of the run.
```
