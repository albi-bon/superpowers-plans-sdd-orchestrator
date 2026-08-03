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
    Write the plan to: PLAN_PATH

    ## Your job

    1. Read the whole design document, so you understand the phases either side
       of yours and the decisions that constrain them.
    2. Write a plan for phase PHASE_NUMBER only. Nothing from any other phase
       belongs in it. If phase PHASE_NUMBER depends on work an earlier phase
       delivered, treat that work as already present — it is.
    3. Invoke superpowers:writing-plans and follow it.
    4. Save the plan to exactly PLAN_PATH. Do not choose your own filename and
       do not save it anywhere else — the orchestrator hands this exact path to
       the agent that executes it.
    5. Copy the design document's cross-cutting constraints — the decision log,
       the platform and portability rules, anything the document states as
       binding on every phase — into the plan's `## Global Constraints` block,
       with their exact values. The agent executing your plan will never read
       the design document.
    6. Commit the plan file.

    ## Two overrides of superpowers:writing-plans

    These supersede that skill's own ending. It is not a preference.

    - Do NOT present the execution-choice menu at the end ("Subagent-Driven /
      Inline Execution"). Nobody is there to answer it. The orchestrator has
      already chosen.
    - Do NOT execute the plan, or any part of it. A separate agent does that.

    ## Return contract

    Return ONLY the plan file path, on one line, and nothing else. No summary,
    no plan text, no commit log. The orchestrator that reads your reply must
    survive several more phases, and everything you print stays in its context
    for the rest of the run.
```
