# QA Pass for Building Phased Specs in Parallel — Design Spec

**Date:** 2026-11-20
**Scope:** an optional QA pass at the end of a `building-phased-specs-in-parallel` run.
The three sequential skills are not changed.
**Status:** design awaiting the owner's approval, not yet planned.

### How to use this document

§1–§4 are the design. §5 is the decision log: an implementation phase that wants to
deviate from a decision amends §5 first and says why. §6 splits the build into three
phases with their dependencies, so this document is a valid input to the skill it
changes. §7 lists the limits the skill's own `Known limits` section must state.

---

## 1. Summary

A run is verified today by gates, test suites and the integration verifier's acceptance
check. That proves the code passes its checks. Nothing ever uses what was built.

The QA pass adds one step to `Finishing`, between the final check and the report. The
finished work is exercised the way a real user would use it, by sub-agents, with
whatever tool the environment offers. What they find is triaged, the bugs are fixed
once, and each fix is re-checked once. Everything else goes into the report.

The pass is:

- **optional**: the owner chooses at the start of the run whether it runs and how many
  flows it covers;
- **bounded**: one round of discovery, one round of fixes, one targeted re-check, each
  recorded in the ledger so that none can run twice;
- **generic**: the templates describe a method, and the sub-agents choose the tool. A
  flow no tool can exercise is reported as not walked, never as checked.

The controller stays thin. It dispatches the pass's agents with paths, receives capped
returns, and never reads a flow, a finding or a triage file.

---

## 2. Scope

### Goals

- Catch, before the pull request opens, what gates cannot: UI issues and glitches, UX
  issues, broken functionality, implementations that do not match the spec, wrong
  assumptions that only show up in use, and edge cases within reason.
- Fix what is a bug in this run's work, once.
- Report the rest so the owner can act on it: what stayed open, what was noticed during
  the re-check, what traces back to the spec, and what could not be walked.

### Non-goals

- The sequential skills (`building-phased-specs`, `orchestrating-phased-specs`,
  `executing-phased-specs`).
- QA of a run in which a requested phase did not land, or whose final check failed.
- QA of a single phase or batch. The pass runs once, on the base tip, at the end.
- Updating the body of a pull request that a resumed run reuses. `phase-pr` reuses an
  open pull request without rewriting its body today, and that stays.
- Fixing behaviour the run did not touch.

### Anti-goals

The pass has failed, even if it works, when any of these is true:

- It loops: a second discovery round, a second fix round, or a second re-check.
- An agent chases a root cause, or one more issue, past its one attempt.
- A flow is reported as checked when nobody used it.
- The controller reads findings, or decides which issues to fix.
- It runs without the owner having chosen it.

---

## 3. Approaches

Three ways to give a run a QA step were considered.

**A. A pass at the end of the run, inside `Finishing` (chosen).** One planner, walkers,
one triage, fixers and a re-check, on the base tip after every phase has landed. Flows
usually span phases, so the end of the run is the first moment they exist whole. It
shares the run's ledger, report and integration worktree. The cost is one more block in
an already long skill.

**B. QA inside each batch's verification.** The integration verifier, or an agent beside
it, would walk the flows each batch touches. Rejected: it runs on every batch, which is
the cost the owner wants to avoid; a flow that needs three phases cannot be walked until
the third lands; and every batch failure would repeat the walk.

**C. A separate skill, run after the pull request exists.** Rejected: the owner wants the
result before the pull request opens and in the run's own report, and a separate skill
would need the briefs, decisions and ledger of a run it did not start.

The owner asked for A in the request. The rest of this document describes it.

---

## 4. Design

### 4.1 Turning it on and scoping it

A new invocation value:

| Value | Where it comes from |
|---|---|
| `QA_SCOPE` | `qa` in the request gives `top 5`; `qa: top N` gives `top N`; `qa: all` gives `all`; `qa: <words>` gives `focus: <words>`; `no qa` gives `none`. If the request says none of these, ask once, before preflight |

The question is asked together with the other invocation values, before
`phase-preflight` runs, and offers: no QA, the five most important flows, every flow, or
flows the owner names. It is the only new question, and it comes before anything
starts, so "you never stop to ask the user anything after preflight" still holds.
`no qa` exists so that a request can be complete on its own and a scripted launch is
never asked.

After preflight the controller appends `run: qa scope — <QA_SCOPE>` to the ledger. On a
resume, a scope stated in the request wins, otherwise the ledger's last `run: qa scope`
line is used, and the question is asked only when neither exists.

The scope limits which flows are walked, not which are listed. The planner lists every
user-facing flow the run touched, ranks them, and selects by scope:

- `top N`: the N highest-ranked flows.
- `all`: every flow.
- `focus: <words>`: the flows the owner's words describe. Words that match no flow are
  said so in the plan and in the report.

### 4.2 Where it sits in `Finishing`

`Finishing` becomes four steps: final check, QA pass, report, pull request.

The pass runs when all of these are true:

- `QA_SCOPE` is not `none`;
- every requested phase is merged;
- the final check passed, or was skipped for a reason other than "no batch landed";
- the ledger has no `qa: done` line, and no `qa: skipped` line that still counts
  (§4.7).

Otherwise the controller appends `qa: skipped — <reason>` (not for `none`, which needs
no line) and goes on to the report.

The pass covers what the requested phases deliver. When `RANGE` is part of the
document, a flow that also needs a phase outside it is walked as far as the requested
phases take it, and a flow that cannot start without such a phase is
`not walkable — needs phase <N>, not in this run`.

### 4.3 The stages

Every stage runs once. Its outcome line in the ledger is what says it ran, and no stage
has an action that leads back to an earlier one (§4.6).

All QA agents work in the run's integration worktree, `.worktrees/<run>/integration`. It
already has the repository's dependencies installed, and no batch is open at this
point. The pass starts with `phase-qa open` (§4.8), which puts that worktree on a new
branch at the base tip: `phase-qa@<run>`, where `<run>` is the name of the run
directory, so two runs in one repository never share it (`phase-qa-<run>` in a ledger
from before runs were named). This document calls it the QA
branch.

**Stage 1 — Define the flows.** The controller dispatches the **QA planner**. It reads
the design document, the briefs and decisions of the run's phases, and the run's diff,
and writes `RUN_DIR/qa-flows.md`:

- how to make the product runnable and start it, tried once so the walkers do not
  rediscover it: setup (the `SETUP_MARKER` rule the integration verifier uses), seed
  data, start and stop commands, and test credentials the repository provides;
- the interaction tools available in this environment and what each can drive;
- whether several walkers can use the product at the same time (own ports, own data), or
  must go one after another;
- every user-facing flow the run touched, ranked by how central it is to the spec's
  goals, how much the run changed it, and what it costs when broken;
- for each selected flow: its scenarios (the main path, the obvious variations, and at
  most three edge cases), the tool that will drive it, or `not walkable — <why>` when no
  available tool can;
- an index at the top, one line per flow, in a fixed form the report is built from:
  `- [selected] F2 — checkout`, `- [not walkable] F4 — share sheet: <why>`,
  `- [not selected] F6 — export`.

Flows are numbered `F1`, `F2`, … in rank order.

A run that changed nothing user-facing yields no flows. The pass then ends with
`qa: done — nothing to walk`.

**Stage 2 — Walk the flows.** One **QA walker** per selected, walkable flow, up to `CAP`
at a time when the planner said they can run side by side, otherwise one at a time. A
walker uses the product through the outermost interface a real user touches (the
command line, the app in a simulator, the page in a browser, the public API for a
library) and goes through its flow's scenarios. For each finding it records, in
`RUN_DIR/qa-flow-<F>-findings.md`:

- the scenario and the exact steps that reproduce it;
- what was expected, and where that expectation comes from (a section of the spec, a
  brief, or ordinary expectations of such a product);
- what happened instead, with evidence (output, or a screenshot saved under
  `RUN_DIR/qa-evidence/`);
- a kind (broken functionality, spec mismatch, UI, UX, edge case, suspected wrong
  assumption) and a severity: `broken` when the scenario cannot be completed or the
  behaviour contradicts the spec, otherwise `minor`.

Every scenario ends as `ok`, `<n> findings` or `not walked — <why>`. A walker edits no
source file, diagnoses no cause, fixes nothing and adds no scenario of its own. When a
finding blocks the rest of a flow, the remaining scenarios are `not walked — blocked by
<finding>`. Reading the code, or running the test suite, never counts as walking: when
the tool cannot drive a scenario, the scenario is not walked, and the walker says so.

**Stage 3 — Triage.** Skipped when no walker recorded a finding: the pass then closes.
Otherwise one **QA triage** agent reads every findings file, the flows file,
the design document and the phases' briefs and decisions. It may read code, because
grouping by cause needs it. It writes `RUN_DIR/qa-triage.md`:

- duplicates merged, and findings that share a cause put in one group `G<n>`;
- each group classified as exactly one of
  - `fix`: the implementation is wrong, or does not match the spec or a brief;
  - `spec`: the behaviour is what the spec or a recorded decision asked for, and using
    it shows that was the wrong call. The group carries what is wrong and a proposed
    change. Nothing is changed (§5, Q3);
  - `outside this run`: the behaviour was there before the run and the run did not
    touch it, or it is something a phase outside `RANGE` is meant to deliver. A fixer
    never builds a deliverable of a phase the run was not asked for;
- for each `fix` group, a fix plan: the suspected cause, the files, the approach and the
  regression test to add. Groups are ordered, and two groups that would change the same
  code are merged or placed one after the other, with the later one told what the
  earlier one changes;
- an index at the top, one line per group, in a fixed form the report is built from:
  `- [fix] G1 — <flow>: <one line> (broken)`.

**Stage 4 — Fix.** One **QA fixer** per `fix` group, dispatched one after another in the
triage's order, on the QA branch. A fixer reproduces the finding the cheapest way it can (a
failing test, or the walker's steps), fixes the root cause as planned, adds the
regression test under the testing policy, runs the failing checks and the tests related
to the files it changed, and commits `qa: G<n> — <title>`. It runs no full suite. It has
one attempt and stays inside its group. It returns `NOT_FIXED` and leaves the branch
where it found it when the finding does not reproduce, when the fix does not hold, or
when fixing it would mean changing what the spec asked for. Decisions go to
`RUN_DIR/qa-decisions.md` under the decision policy.

**Gates on the fixes.** When at least one group was fixed, the controller dispatches the
existing integration verifier in `final` mode on the QA branch's tip, with
`RUN_DIR/qa-gates-evidence.md` as its evidence file.

- `PASS`: `phase-qa land` fast-forwards base to that commit, pushes base, leaves the
  integration worktree on the base tip, detached, and deletes the QA branch.
- `FAIL`: nothing lands. Base stays at the tip the final check covered, the QA branch
  is kept and pushed as a backup, and the report lists every fixed group as "fixed on
  the QA branch, not landed" with the branch name and the evidence path. There is no
  repair, and no re-check.

This keeps "base only ever holds trees a verifier passed" true. It costs one more run of
the full suites, and only in a run where QA changed code.

**Stage 5 — Re-check.** After the fixes landed, one walker in `recheck` mode per flow
that has a finding in a fixed group, with the same concurrency rule as stage 2. It
repeats only the steps of those findings and marks each `confirmed` or `still broken`
in `RUN_DIR/qa-flow-<F>-recheck.md`. Anything else it notices is written down as one
line, `new`, and not investigated. It walks nothing else.

Then `phase-qa close` appends `qa: done — …`, with the counts taken from the ledger, and
the controller goes on to the report. A fix the re-check
found still broken stays on base: it passed the gates, and removing it would be a second
fix round.

### 4.4 Templates and tiers

| Dispatch | Template | Tier | Why |
|---|---|---|---|
| QA planner | `qa-plan-prompt.md` (new) | top | one dispatch decides what the whole pass looks at |
| QA walker, modes `walk` and `recheck` | `qa-walker-prompt.md` (new) | strong | the volume of the pass |
| QA triage | `qa-triage-prompt.md` (new) | top | judges cause, class and what gets changed |
| QA fixer | `qa-fix-prompt.md` (new) | top | the same job as a repair |
| gates on the fixes | `integration-verifier-prompt.md` (existing, `final` mode) | mid-tier | unchanged role |

Every QA template follows the rules the template tests already bind on the integration
templates: a general-purpose subagent, an explicit model, `Repository: WORKTREE (absolute
path of the run's integration worktree`, the worktree boundary, `Do not spawn
subagents`, a capped return contract, no pasted artifacts in the return, and no
dependency on a Superpowers skill. The planner, the triage agent and the walkers take no
decision policy, because they decide verdicts and not implementation. The fixer takes
the decision policy and the testing policy.

The integration verifier's template says that in `final` mode the worktree is at base's
tip, detached. Its wording is widened to cover the QA branch's tip. Its behaviour does
not change.

Return contracts, each capped:

| Agent | Return |
|---|---|
| planner | `DEFINED`; the number of flows found; `selected: 1,2,3,5`; `not walkable: 4` or `-`; `parallel: yes` or `no`; the flows path. Or `BLOCKED` |
| walker, `walk` | `WALKED` or `NOT_WALKED — <why>`; scenario and finding counts; the findings path |
| walker, `recheck` | `RECHECKED`; `G<n> confirmed` or `G<n> still broken` per group; a count of new observations; the recheck path |
| triage | `TRIAGED`; the number of findings; the fix groups in fix order, each with the flows its findings came from, as `fix: G1@2 G3@2,5 G4@1`, or `fix: -`; spec and outside-this-run counts; the triage path |
| fixer | `FIXED <sha>` or `NOT_FIXED — <reason>`; the commands it re-ran with exit codes; the count of significant decisions |

The planner's and the triage agent's returns carry flow and group numbers, not only
counts, because the controller copies them into the ledger and `phase-qa next` works
from the ledger alone (§5, Q9). Titles and reasons stay in the files.

A planner that returns `BLOCKED`, or that cannot start the product at all, ends the pass
with `qa: skipped — <reason>`. Nothing in the pass can fail a phase or drain the run.

### 4.5 The ledger

QA lines use their own prefixes, so `phase-state`'s reading of `phase`, `batch` and
`run` lines is unaffected. Example:

```markdown
run: invoked — cap 3
run: qa scope — top 5
…
run: final check PASS 7a8b9c0
qa: opened — phase-qa-thing-design at 7a8b9c0
qa: planner dispatched
qa: flows defined — 7 found, selected 1,2,3,4,5, not walkable 4, parallel yes
qa flow 1: walker dispatched
qa flow 2: walker dispatched
qa flow 2: walked — 3 findings
qa flow 1: walked — 0 findings
qa flow 3: walker dispatched
qa flow 3: not walked — the simulator would not boot
…
qa: triage dispatched
qa: triaged — 9 findings, fix G1@2 G2@5 G3@2,5 G4@1, 1 spec, 2 outside this run
qa group 1: fixer dispatched
qa group 1: fixed 3c4d5e6
qa group 2: fixer dispatched
qa group 2: not fixed — did not reproduce
…
qa: verifier dispatched
qa: verified PASS — 5e6f7a8
qa: landed (5e6f7a8)
push: feat/thing at 5e6f7a8
qa flow 2: recheck dispatched
qa flow 2: rechecked — G1 confirmed, G3 still broken, 1 new
…
qa: done — 2 confirmed, 1 still broken, 1 not fixed, 1 new, 1 spec
```

A flow the planner selected and marked not walkable is in both lists of the
`flows defined` line; no walker is dispatched for it. A `not walked` line comes from a
walker's own `NOT_WALKED` return. The controller appends a `dispatched` line before
every QA dispatch, as it does for every other agent.

### 4.6 What keeps it bounded

The bound is in the ledger and the scripts, so a controller that lost its place after
compaction cannot reopen a stage.

- Each stage's outcome line is written once. `Finishing` reads the ledger and takes the
  first stage without an outcome. Nothing in `Finishing` names an earlier stage as a
  next step.
- `phase-qa next` (§4.8) prints the one action the ledger allows, the way
  `phase-schedule` does for phases. The controller asks it after every QA return.
- A walker has a fixed scenario list. A fixer has one attempt on one group. The
  re-check has a fixed list of findings.
- Every outcome that could invite another round has a place in the report instead: a
  fix that is still broken, a group that was not fixed, fixes that failed the gates, a
  new observation from the re-check.

The skill's `Common rationalizations` table gets rows for the tempting cases: one more
fix round after the re-check, widening the scope because the top flows were clean,
re-running the gates after a `FAIL`, and calling a flow checked after reading its code.

### 4.7 Resume

The existing rule covers the pass: a `dispatched` line with no outcome after it means
that agent is dispatched again. In addition:

- `phase-qa open` is idempotent. With the QA branch already recorded, it puts the
  integration worktree back on it and discards uncommitted tracked changes, as
  `phase-batch` does for a batch.
- A `qa: skipped` line counts only while nothing after it changed what it was decided
  on: no `batch <K>: landed`, `run: final check` or `run: qa scope` line follows it. So
  a run that was drained, fixed by the owner and resumed still gets the pass it was
  asked for. On a resume the controller appends a `run: qa scope` line only when the
  request states a scope, which is how the owner asks again for a pass that was skipped
  because the product could not be started or a tool was not permitted.
- The pass runs at most once per run directory. Once `qa: flows defined` is recorded,
  no resume starts another, whatever lands later. The report's QA block names the
  commit the pass walked.
- If a batch landed after `qa: opened` and before `qa: flows defined`, `next` prints
  `open` again and `phase-qa open` moves the QA branch, which holds nothing of its own
  yet, to the new base tip. If one landed after `qa: flows defined` and before
  `qa: done`, base moved under the
  pass. `phase-qa next` prints `close`, and `phase-qa close` appends
  `qa: done — abandoned, base moved under the pass`. What was found so far is in the
  report; nothing more is fixed or landed.
- A fixer dispatched again starts from the branch tip. Work the earlier fixer did not
  commit is gone, and its commits, if it made any before it was interrupted, are found
  by their `qa: G<n>` subject and kept.
- Stages with an outcome line stay done. A resume never walks, triages or fixes again.
- A resume that states a wider scope after `qa: flows defined` does not reopen the
  plan. The scope is recorded, and the report says the pass ran under the earlier one.

### 4.8 `phase-qa`

A new shared script with a wrapper in the skill's `scripts/`, following the conventions
of `phase-batch` and `phase-land`.

| Subcommand | Does |
|---|---|
| `open` | refuses while a batch is open; creates the QA branch at the base tip in the integration worktree, or re-attaches to it; appends `qa: opened — <branch> at <sha>`; prints `opened <sha>` |
| `next [RANGE]` | judges "every requested phase merged" on `RANGE`, the phases this invocation asked for (the ledger header's range without it); reads only the ledger and prints one action: `skip <reason>`, `open`, `plan`, `walk <F>…`, `triage`, `fix <G>`, `verify <sha>`, `land <sha>`, `push`, `recheck <F>…`, `close`, or `done` |
| `close` | appends `qa: done — <summary>`, the summary computed from the ledger |
| `status` | prints the pass's stage and progress for the status line, or nothing when no pass is active |
| `land SHA` | fast-forwards base to the QA branch in the base worktree (`.worktrees/<run>/base`; the main checkout is the owner's and is never touched), refusing unless the ledger shows `qa: verified PASS` for exactly that commit and the base worktree is clean and on base; appends `qa: landed (<sha>)`; pushes base through `phase-push`; puts the integration worktree on the base tip, detached; deletes the QA branch |
| `push` | pushes the QA branch as a backup after a gates `FAIL`, recording the outcome like `phase-push`; a branch that is gone is recorded as a failed push, so `next` always moves on |
| `report` | prints the report's QA block from the ledger, the flows index, the triage index and the recheck files |

Like `phase-schedule`, `next` prints the action whether or not its agent is already
out: the controller skips an action whose `dispatched` line has no outcome while that
agent is running, and dispatches it again on a resume. `next` checks the conditions of
§4.2 itself and prints `skip <reason>` when one fails; the controller appends that as
`qa: skipped — <reason>`.

`next` derives everything from ledger lines: the flows to walk from `flows defined`
(selected, minus not walkable, minus those with an outcome), the fix order and each
group's flows from `triaged`, and the flows to re-check from the groups with a `fixed`
line.

When `phase-qa` refuses, base is unchanged. Then:

| Refusal | Do |
|---|---|
| `open`: a batch is open, or the QA branch exists and the ledger does not account for it (exit 14, as `phase-batch` uses it) | append `qa: skipped — <stderr>` and go on to the report |
| `land`: the base worktree is dirty, missing or not on base | stop and show stderr verbatim, as for `phase-land` exits 11 and 13: the repository was changed under the run, and the owner restores it and resumes |
| `land`: any other refusal | append `qa: not landed — <stderr>`, run `phase-qa push`, and go on to the report. There is no re-check |

After a gates `FAIL` or a `not landed`, the QA branch stays. It belongs to this run's
ledger, so a resume of the same run accepts it, and a run of another spec has a branch
of its own name.

`phase-statusline` shows the pass from `phase-qa status`, for example `qa walking 3/5`
or `qa fixing 2/4`. Without it a status line would show `6/6 merged` and then `idle` for
the whole pass. `phase-state` is not changed: `phase-schedule` and `phase-overlap` read
every row of its output that is not a `run` or `batch` row as a phase, so the QA state
stays out of it.

### 4.9 The report

The report gains a QA block, printed by `phase-qa report`, between the final check line
and the base line:

```
qa: 3 of 7 flows walked on 7a8b9c0 (scope: top 5)
  not walked: 2
    flow 4 share sheet — no available tool can drive the native share sheet
    flow 3 onboarding — the simulator would not boot
  not selected: flow 6 export, flow 7 settings
  fixed and confirmed: 2
    G1 checkout: total ignores the second coupon
    G4 signup: error message hidden behind the keyboard
  still open: 2
    G3 checkout: coupon lost on back navigation — still broken after the fix (broken)
    G2 search: empty state flashes before results — not fixed: did not reproduce (minor)
  new at re-check, not investigated: 1
    flow 2: order summary shows the old total for a moment
  spec questions, nothing changed: 1
    G5 refunds: the spec refunds to store credit only; in use there is no way to see the credit — proposed: show the balance on the account page
  outside this run: 2 (qa-triage.md)
  details: <run-dir>/qa-triage.md, <run-dir>/qa-flows.md
```

When the pass did not run, the block is one line: `qa: not run — not requested`, or
`qa: skipped — <reason>`. When the gates failed on the fixes, the fixed groups are
listed under `fixed on <QA branch>, not landed`, with the evidence path.

The report's significant-decisions list also reads `RUN_DIR/qa-decisions.md`.

### 4.10 The pull request

The pass never changes whether the pull request is a draft (§5, Q2). The existing rule
stands: a draft when a requested phase did not land or the final check failed. Open
issues, spec questions and unlanded fixes are in the report, which is the pull request's
body.

### 4.11 Platform guide

- The model tier table gains the four QA roles.
- A QA section says what the pass needs from the host: the interaction tools the
  walkers will use (a browser automation server, a simulator or emulator and its command
  line, computer use) must be available to sub-agents and allowed in the session's
  permissions before an unattended run. A tool that prompts parks the run, like any
  other missing permission.
- During the pass at most `CAP` walkers run at once, which is inside the
  `1 + 2 × CAP` capacity the run already needs.

---

## 5. Decision log

| # | Decision | Rationale |
|---|---|---|
| **Q1** | **The owner chooses QA at the start: in the request, or by one question before preflight when the request does not say.** | Owner's call. The run stays unattended after preflight, and the owner never forgets the option exists. `no qa` keeps scripted launches free of the question. |
| **Q2** | **QA never makes the pull request a draft.** Open issues are in the report only. | Owner's call. The draft flag keeps its current meaning: a phase did not land, or the final check failed. |
| **Q3** | **A finding that traces back to the spec or a recorded decision is reported with a proposed change and not fixed.** | Owner's call. During the build an agent must decide to keep going; at the end of the run nothing is blocked by waiting for the owner, and changing what the spec asked for is a product decision. |
| **Q4** | **The pass runs only when every requested phase merged and the final check did not fail.** | The pass checks that the plan produced what it was meant to. A run with a missing phase or failing gates already hands the owner a draft with a known problem; walking half a feature would report the gap as findings. |
| **Q5** | **Fixes are made on a QA branch, verified by one `final`-mode gate run, and land only on `PASS`. A `FAIL` lands nothing and starts nothing.** | Base only ever holds a tree a verifier passed. One extra full-suite run is the price, paid only when QA changed code. |
| **Q6** | **The re-check comes after the gates, on the landed tree.** | A re-check of fixes that will not land confirms nothing the owner receives. |
| **Q7** | **Fixers run one after another on one branch.** | No merges between fixes, no extra worktrees or installs. A QA pass rarely has enough fix groups for the wall-clock time to matter, and triage already orders the groups. |
| **Q8** | **A fix the re-check finds still broken stays on base.** | It passed the gates. Reverting it is a second fix round. |
| **Q9** | **The next QA action comes from a script that reads only the ledger.** | The same reason as `phase-schedule`: a compacted controller must not be able to repeat a stage, and here repeating a stage is exactly the loop the owner ruled out. |
| **Q10** | **Bare `qa` means the five highest-ranked flows.** | QA is slow and expensive; the default must be a limit, and `qa: all` is one word away. |
| **Q11** | **At most three edge cases per flow.** | "Within reason" needs a number, or each walker sets its own. |
| **Q12** | **Walkers record a severity, `broken` or `minor`, used only to order the report.** | The owner reads the report to decide what to do before merging; the worst issues come first. |
| **Q13** | **The planner's and the triage agent's returns carry flow and group numbers, and the controller copies them into the ledger.** | Q9 needs `next` to work from the ledger alone, and counts do not say which flow to walk or which group to fix next. Numbers are short; titles and reasons stay in files the controller never reads. |
| **Q14** | **A skip is not final; a started pass is.** A `qa: skipped` line stops counting when a batch lands, a final check runs or the owner states a scope again. Once flows are defined, the run never starts another pass. | A skip means nothing was done, so running the pass later is still the first round. Anything after the plan would be a second one. |
| **Q15** | **The QA branch is named after the run and deleted when it lands.** | Batch branches are cleaned up by the next batch; nothing comes after the pass to clean up for it. A per-run name keeps a branch kept after failed gates from blocking another spec's run. |
| **Q16** | **The third triage class is `outside this run`**: behaviour from before the run, and deliverables of phases outside `RANGE`. | A run is often part of a document. Without it, a finding about a phase nobody asked for would be classed `fix`, and a fixer would start building that phase. |

| **Q17** | **A QA ledger line the script cannot read ends the pass**: `next` prints `close` and the done line names the line. The reading first forgives what a copied return invites (labels with colons, `F`/`G` prefixes, a comma between groups, a hyphen for the dash). | Added after the branch review. Returns are copied into the ledger by a controller; a line read as "no outcome" made `next` repeat an action for ever, which is the loop the owner ruled out. A stopped pass is reported. |
| **Q18** | **A re-check has a third outcome, `not rechecked`.** The fix is listed in the report as fixed, not re-checked. | Added after the branch review. With only `confirmed` and `still broken`, a walker that could not repeat the steps had to claim a verdict it did not have. |
| **Q19** | **A re-dispatched fixer looks for its commit from base**, not from its own start commit. | Added after the branch review. The start commit of a second dispatch already contains the first one's commit. |

Q1 to Q3 are the owner's decisions. Q4 to Q19 are the designer's, open to correction.

---

## 6. Implementation phases

Phases 1 and 2 touch disjoint files and can run in parallel.

### Phase 1 — The `phase-qa` script and the QA state

**Depends on:** none

**Goal:** from the ledger alone, the run knows which QA action comes next, can open and
land the QA branch, and can print the report's QA block.

**Add**
- `shared/scripts/phase-qa` with `open`, `next`, `land`, `push`, `close`, `status` and
  `report` (§4.8), and
  its wrapper in `skills/building-phased-specs-in-parallel/scripts/` under the
  `phase-parallel` namespace.
- The QA segment in `shared/scripts/phase-statusline`, fed by `phase-qa status` (§4.8).
- `shared/scripts/__tests__/phase-qa.test.sh`, and cases in the `phase-statusline` test.

**Constraints**
- The shared portability rules of the existing scripts: macOS `/bin/bash`, `shellcheck`
  clean.
- `next`, `status` and `report` mutate nothing.
- `phase-state` and `phase-schedule` are not changed, and a ledger without QA lines gives
  the same status line as before.

**Verification**
- `next`: prints each action in order for a ledger that advances stage by stage; the
  same action again while its agent's `dispatched` line has no outcome; `skip` with its
  reason when a condition of §4.2 fails; `close` straight after the walk when there are
  no findings; `walk` lists only selected, walkable flows
  not yet walked; `fix` one group at a time, in order; no `verify` when no group was
  fixed; no `recheck` after `verified FAIL` or `not landed`; `done` after `qa: done`;
  `done` after a `qa: skipped` that still counts, and `plan` again after one that a
  later `batch landed`, `run: final check` or `run: qa scope` line superseded;
  `close` when a batch landed after `qa: flows defined`; never an action for a stage that
  has an outcome.
- `open`: refuses while a batch is open; idempotent; exit 14 for an unaccounted branch;
  the branch carries the run's name.
- `land`: refuses without a matching `qa: verified PASS`, on a dirty main checkout, and
  off base; otherwise fast-forwards, records, pushes, detaches the integration worktree
  on the base tip and deletes the QA branch.
- `report`: every block of §4.9, including not run, skipped, nothing to walk, and fixes
  not landed.

**Done when:** given a ledger, a triage index and recheck files, the script prints the
actions of §4.3 and the block of §4.9.

### Phase 2 — The QA templates and the platform guide

**Depends on:** none

**Goal:** every QA role has a dispatch template that states its method, its bounds and
its return contract.

**Add**
- `qa-plan-prompt.md`, `qa-walker-prompt.md`, `qa-triage-prompt.md` and
  `qa-fix-prompt.md` in `skills/building-phased-specs-in-parallel/` (§4.3, §4.4).
- The widened `final`-mode wording in `integration-verifier-prompt.md` (§4.4).
- The QA tiers and the QA section in `platform-guide.md` (§4.11).
- Cases in `shared/scripts/__tests__/parallel-templates.test.sh`.

**Constraints**
- No template names a product type or a specific tool as the way to walk a flow. Tools
  appear only as examples of what an environment may offer.
- The rules bound on every template by the existing tests hold for the new ones.

**Verification**
- Template tests assert, per template: the integration-worktree envelope, the model
  tier, the capped return contract, and the bound that matters for the role. For the
  planner: the scope values, the edge-case cap, `not walkable`. For the walker: both
  modes, records only, never counts reading code as walking, `new` observations are not
  investigated. For triage: the three classes, the index line form, `spec` groups are
  not changed. For the fixer: one attempt, one group, no full suite, `NOT_FIXED` leaves
  the branch where it was.
- The existing suite still passes.

**Done when:** the four templates exist, the tests pass, and each template can be
dispatched from the values §4.3 and §4.4 name.

### Phase 3 — The skill text

**Depends on:** Phase 1, Phase 2

**Goal:** a controller that follows `SKILL.md` runs the pass as designed.

**Add**
- In `skills/building-phased-specs-in-parallel/SKILL.md`: `QA_SCOPE` in the invocation
  table and the question before preflight (§4.1); the scope line after preflight; the QA
  rows in the dispatch table; the QA step in `Finishing` (§4.2, §4.3), driven by
  `phase-qa next`; the QA lines in the ledger example (§4.5); the resume rules (§4.7);
  the QA block in the report (§4.9); the known limits (§7); the rationalization rows
  (§4.6).
- The QA pass in `README.md`'s description of the skill and its example invocation.
- Cases in `shared/scripts/__tests__/parallel-skill.test.sh`.

**Constraints**
- The skill's description in the frontmatter stays within 1024 characters.
- The controller's rules do not loosen: it never reads a QA artifact, and asks nothing
  after preflight.

**Verification**
- Skill tests assert: the invocation value and its default; the question comes before
  preflight; the conditions under which the pass runs; every QA template and
  `phase-qa` are referenced and exist; one round of each stage; the pull request's draft
  rule is unchanged; the report block; the new known limits.
- The whole test suite passes.

**Done when:** the skill text, the README and the tests describe the same pass as this
document.

---

## 7. Known limits

The skill's `Known limits` section states these.

1. **QA judgement can be wrong.** A walker can report a finding that is not a problem,
   and triage can call a bug a spec question or the reverse. The report lists every
   group with its class so the owner can check.
2. **A fix is only re-checked where it was found.** A fix that breaks another flow is
   caught by the gates as far as tests cover it, and not otherwise.
3. **The pass can only use what the environment offers.** Without a tool that drives the
   product, flows are reported as not walked.
4. **It is slow and it costs.** One planner, a walker per flow, a triage agent, a fixer
   per group, one more full-suite run when anything was fixed, and a re-check walker per
   fixed flow.
5. **Fixes that fail the gates are not landed and not retried.** They stay on the QA
   branch, pushed, for the owner.
6. **A resumed run that reuses an open pull request does not update its body.** The
   report on disk and in the terminal is current; the pull request's body may not be.
