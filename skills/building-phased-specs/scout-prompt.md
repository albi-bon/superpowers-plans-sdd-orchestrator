# ① Scout Dispatch Template

Dispatched once per phase, before any code is written. The scout grounds the
phase against the repository and writes the brief the phase lead executes from.
Substitute every uppercase placeholder value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Ground phase PHASE_NUMBER of DESIGN_DOC_BASENAME"
  model: the most capable model available — grounding is judgment: deciding
         which drift matters and how to adapt to it. Resolve the actual model
         through platform-guide.md; record inheritance if selection is unavailable.
  prompt: |
    Repository: REPO_ROOT (absolute path; use it for every shell working directory)
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

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    1. Read the whole design document, so you understand the phases either
       side of this one and the decisions that bind all of them.
    2. Read every `phase-*-decisions.md` in RUN_DIR from earlier phases. Earlier
       phases may have deviated from the document; this phase builds on what
       was actually built, not on what the document predicted.
    3. Ground the phase. For every concrete claim phase PHASE_NUMBER makes —
       file paths, module and symbol names, function signatures, data shapes,
       dependency names and versions, test infrastructure, and anything an
       earlier phase was supposed to deliver — find it in the repository and
       read it. Do not assume a claim is true because the document states it.
    4. For every mismatch, choose a resolution under the decision policy and
       record it in the brief's Drift table. A missing prerequisite becomes an
       extra task. A renamed or reshaped API is adapted to. Append significant
       resolutions to DECISIONS_PATH as the policy describes. A mismatch is
       never a reason to stop.
    5. Split the phase into 3 to 10 tasks, ordered so each builds only on
       earlier ones. A task is a coherent slice one agent can implement and
       test in one sitting, touching a small set of files.
    6. Write the brief to exactly BRIEF_PATH, in the shape below.

    If BRIEF_PATH already exists, an earlier scout was interrupted or the run
    was resumed: check it against the repository, complete or correct it, and
    keep every task checkbox that is already ticked.

    You write BRIEF_PATH and append to DECISIONS_PATH. You edit no source file
    and make no commit.

    ## The brief

    The brief is the only thing the phase lead and its workers read about this
    phase — they never open the design document. Copy what binds them. The
    brief carries no code, no step lists and no test code: a worker writes the
    code once, against the repository as it finds it.

    ~~~markdown
    # Phase PHASE_NUMBER — PHASE_TITLE

    **Goal:** <one paragraph, from the phase section>
    **Spec:** DESIGN_DOC

    ## Global constraints
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
    - **Files:** <create / modify, with repository-relative paths>
    - **Produces:** <exact public names and types later tasks build on, or "nothing public">
    - **Done when:** <observable behaviours, one per line>
    - **Test focus:** <which behaviours need tests; edge and error cases the document names>
    - **Notes:** <what you found while grounding that the worker must know>

    ### - [ ] Task 2 — <title>
    …
    ~~~

    ## Return contract

    At most four lines:
    - BRIEF_PATH
    - the task count
    - the drift count
    - the significant-decision count

    Do not paste the brief, code, or document text into your reply. The
    controller reading it must survive many more phases, and everything you
    print stays in its context for the rest of the run.
```
