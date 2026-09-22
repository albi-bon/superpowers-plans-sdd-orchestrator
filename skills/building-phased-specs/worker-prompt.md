# Worker Dispatch Template

Dispatched by the phase lead: once per brief task, and once per finding group in
the fix wave. Every line of the phase's code is written by a worker. The lead
substitutes every uppercase placeholder value and fills ASSIGNMENT with exactly
one of the two forms below before dispatching.

**Task form:**

```
Task TASK_NUMBER of the brief — "TASK_TITLE".
Interfaces available from earlier tasks: INTERFACES
Lead's notes: LEAD_NOTES
```

`INTERFACES` lists the exact names and types earlier tasks produced, taken from
the brief's Produces lines and earlier workers' returns — or "none".
`LEAD_NOTES` is anything the lead needs to add, such as "commits for this task
already exist from an interrupted worker" — or "none".

**Fix form:**

```
Fix findings FINDING_IDS from FINDINGS_PATH, as accepted by the phase lead.
Lead's notes: LEAD_NOTES
```

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Phase PHASE_NUMBER: task TASK_NUMBER" (or "Phase PHASE_NUMBER: fix FINDING_IDS")
  model: the most capable model available, always. Never a smaller tier for a
         task that looks simple. Resolve the actual model through
         platform-guide.md; record inheritance if selection is unavailable.
  prompt: |
    Repository: REPO_ROOT (absolute path; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    You are implementing one assignment of one phase. You are already on the
    phase branch, PHASE_BRANCH, in a normal checkout.

    Your assignment: ASSIGNMENT

    Brief:           BRIEF_PATH
    Testing policy:  TESTING_POLICY_PATH   (read it before you write a test)
    Decision policy: DECISION_POLICY_PATH  (read it before you start)
    Decisions file:  DECISIONS_PATH
    Report:          REPORT_PATH

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    1. Read the brief's header and Global constraints, then your own task (or,
       for a fix, the findings you were given and the tasks whose files they
       touch). Do not read the rest of the brief, and do not open the design
       document — the brief carries what binds you.
    2. Read the code you are about to change. The brief tells you where to
       look; the code tells you what is true. Where they disagree, the code
       wins: adapt under the decision policy and record it.
    3. Implement the assignment completely. No placeholders, no TODOs standing
       in for behaviour the task asks for.
    4. Write tests as the testing policy says.
    5. Run the tests you wrote or touched, plus the repository's fast checks for
       the files you changed — typecheck and lint where the repository has
       them. Judge every command by its exit code, never by its printed
       summary. A red check is yours to fix before you return.
    6. Commit on PHASE_BRANCH — one or more commits, with messages in the
       repository's style. Leave the working tree clean.
    7. Write REPORT_PATH: what you built, the tests you added and what each
       proves, the commands you ran with their exit codes, and any deviation
       from the brief.

    If commits for this assignment already exist on the branch, an earlier
    worker was interrupted: reconcile with them and finish the work rather
    than redoing it.

    Returning DONE with a failing check is not a valid return. Returning
    BLOCKED is valid only for the cases the decision policy lists.

    ## Constraints

    - Do NOT switch branches, create branches, merge, rebase, or push.
    - Stay inside your assignment. If you notice a problem elsewhere, mention
      it in your report; do not fix it.
    - Do not tick checkboxes in the brief. The phase lead owns the brief.

    ## Return contract

    At most six lines:
    - status: DONE or BLOCKED (if BLOCKED, the reason, in one line)
    - your commit SHAs, short form
    - tests added: <count>
    - affects: task <K> — <one line on what changed that task K relies on>,
      or "affects: none"
    - decisions: <routine count> routine, <significant count> significant
    - REPORT_PATH

    Do not paste code, diffs, or test output into your reply. The report is
    where those go.
```
