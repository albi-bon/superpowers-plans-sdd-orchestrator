# QA Triage Dispatch Template

Dispatched once in the QA pass, after every walker has returned with at least
one finding among them. It makes sense of everything that was found: merges
duplicates, groups findings that share a cause, decides what is a bug to fix,
what is a question for the owner and what is not this run's business, and
plans the fixes so they do not collide. It changes nothing. What it decides
is what gets changed, so it runs on the top tier. Substitute every uppercase
placeholder value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Triage the QA findings of BASE"
  model: top tier, the most capable model available — it judges cause and
         class for every finding, and decides what the fixers change.
         Resolve the actual model through platform-guide.md; record
         inheritance if selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of the run's integration worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    Phases of a phased design document were built and landed, and then used
    by agents acting as real users. They wrote down what was wrong, flow by
    flow, without looking for causes. You sort those findings out. There is
    one round of fixes after you and no second one, so what you plan is what
    gets fixed.

    Design document: DESIGN_DOC
    Base branch:     BASE
    Phases:          PHASES                (one line per phase the run built: number, title, brief path, decisions path)
    Flows file:      FLOWS_PATH            (the flows that were walked and their scenarios)
    Findings:        FINDINGS_PATHS        (one file per walked flow)
    Triage file:     TRIAGE_PATH           (you write it)

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    1. Read every file in FINDINGS_PATHS, then FLOWS_PATH, the design
       document's sections for the phases in PHASES, and their briefs and
       decisions files. You may read code: finding which findings share a
       cause needs it. Do not walk anything again and do not run the
       product; discovery is over.
    2. Merge duplicates, and put findings that share a cause in one group:
       G1, G2, … A finding seen in two flows is one group that names both.
    3. Give each group exactly one of these classes:
       - `fix` — the implementation is wrong, or does not match the design
         document or a brief.
       - `spec` — the behaviour is what the design document or a recorded decision asked for,
         and using it shows that was the wrong call. A decisions file that
         records the choice makes it this class, not a bug.
       - `outside this run` — the behaviour was there before the run and the
         run did not touch it, or it is something a phase outside PHASES is meant to deliver.
         A fixer never builds what a phase the run was not asked for
         delivers.
       When a finding is not a problem at all, say so in its group and
       class it `outside this run`.
    4. Nothing is changed for a `spec` group. Write what is wrong in use and
       a proposed change, for the owner to decide: changing what the design
       document asked for is theirs.
    5. For each `fix` group, write a fix plan: the suspected cause, the
       files, the approach, and the regression test to add. Order the
       groups: what blocks a user first. When two groups would change the
       same code, merge them or place one after the other, and tell the later
       one what the earlier one changes. The fixers work one after another
       on one branch, each on one group.
    6. Write TRIAGE_PATH in this order:
       - the index, one line per group, in exactly these forms, because the
         run's report is built from them:
           - [fix] G1 — checkout: total ignores the second coupon (broken)
           - [spec] G4 — refunds: no way to see store credit — proposed: show the balance on the account page
           - [outside this run] G5 — settings: avatar upload fails
         Each line names the flow, then one line a reader understands
         without the findings. A `fix` line ends in `(broken)` when any of
         its findings is `broken`, otherwise `(minor)`.
       - one section per group: its class and why, the findings it holds by
         number with the flow each came from, and for a `fix` group its fix
         plan.

    ## Constraints

    - Read only. You write TRIAGE_PATH and nothing else. Do not edit source
      files, fix anything, or commit.
    - Do NOT switch branches, merge, or rebase.
    - Work only inside WORKTREE. Do NOT touch the main checkout, the base branch BASE, or any phase's worktree or branch.
    - Nobody is available to answer questions. When you are unsure whether
      a group is a bug or a question about the design document, class it
      `spec`: a question the owner answers costs less than a fix nobody
      asked for.

    ## Return contract

    At most five lines:
    - TRIAGED
    - findings: <n>
    - the `fix` groups in fix order, each with the flows its findings came
      from, on one line, as in `fix: G1@2 G3@2,5` — or `fix: -` when there
      are none
    - spec: <n>, outside this run: <n>
    - TRIAGE_PATH

    Do not paste findings, plans, or file contents into your reply — the
    triage file is where those go.
```
