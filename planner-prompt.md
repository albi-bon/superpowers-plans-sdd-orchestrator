# ① Planner Dispatch Template

Dispatched once per phase, before anything is executed. Substitute every
`ANGLE_BRACKET_CAPS` value before dispatching.

```
Subagent (general-purpose):
  description: "Plan phase PHASE_NUMBER of DESIGN_DOC_BASENAME"
  model: the most capable model available — writing a plan from a spec is design
         judgment, and every downstream cost compounds from its quality. An
         omitted model silently inherits the session's.
  prompt: |
    You are writing the implementation plan for ONE phase of a phased design
    document.

    Design document: DESIGN_DOC
    Phase number:    PHASE_NUMBER
    Phase title:     PHASE_TITLE
    Write the plan to: PLAN_PATH   (a plan.md inside a directory you create)

    ## Your job

    1. Read the whole design document, so you understand the phases either side
       of yours and the decisions that constrain them.
    2. Write a plan for phase PHASE_NUMBER only. Nothing from any other phase
       belongs in it. If phase PHASE_NUMBER depends on work an earlier phase
       delivered, treat that work as already present — it is.
    3. Invoke superpowers:writing-plans and follow it.
    4. Save the ledger to exactly PLAN_PATH and the task files beside it, as
       override 3 describes. Do not choose your own filename and do not save it
       anywhere else — the orchestrator hands this exact path to the agent that
       executes it.
    5. Copy the design document's cross-cutting constraints — the decision log,
       the platform and portability rules, anything the document states as
       binding on every phase — into the ledger's `## Global Constraints` block,
       with their exact values. The agent executing your plan will never read
       the design document.
    6. Commit the whole plan directory.

    ## Three overrides of superpowers:writing-plans

    These supersede that skill wherever the two disagree. They are
    requirements, not preferences.

    1. Do NOT present the execution-choice menu at the end ("Subagent-Driven /
       Inline Execution"). Nobody is there to answer it. The orchestrator has
       already chosen.
    2. Do NOT execute the plan, or any part of it. A separate agent does that.
    3. Split the plan across files. PLAN_PATH is a `plan.md` inside a directory
       you create, and one file per task sits beside it. A single-file plan is
       superseded, and so is that skill's instruction to save plans to
       `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`.

       PLAN_PATH — the ledger — holds the header that skill mandates (goal,
       architecture, tech stack), the `## Global Constraints` block, the
       `## File Structure` map, and a `## Tasks` table, in that order:

       ```markdown
       ## Tasks

       | # | Title | File | Produces |
       |---|-------|------|----------|
       | 1 | Shell scaffold | task-1.md | `createShell(opts: ShellOpts): Shell` |
       | 2 | Surface model  | task-2.md | `Surface`, `attach(s: Surface): void` |
       ```

       The Produces column carries each task's public surface — the exact names
       and types later tasks build on. It is what lets the agent executing this
       plan give task N the interfaces tasks 1 to N-1 produced without opening a
       task file. No task steps in the ledger, ever.

       Each task goes in `task-<N>.md` beside the ledger, numbered to match the
       table, holding exactly what that skill's Task Structure defines — Files,
       Interfaces, and the checkbox steps with their real code. Every task file
       opens with these two lines, verbatim:

       ```markdown
       > Global constraints bind this task — read the `plan.md` beside this file,
       > § Global Constraints, before you start.
       ```

       A pointer, not a copy: no task file repeats the constraints block, and
       nothing cross-task belongs in a task file.

       Split every plan this way regardless of size. One shape means the agent
       executing it never has to work out which shape it got.

       Your self-review — spec coverage, placeholder scan, type consistency —
       runs across the whole directory, not the ledger alone.

    ## Return contract

    Return ONLY the plan file path, on one line, and nothing else. No summary,
    no plan text, no commit log. The orchestrator that reads your reply must
    survive several more phases, and everything you print stays in its context
    for the rest of the run.
```
