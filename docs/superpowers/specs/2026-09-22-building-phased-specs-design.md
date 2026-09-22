# Building Phased Specs — Design Spec

**Date:** 2026-09-22
**Scope:** a second skill, `building-phased-specs`, living beside `orchestrating-phased-specs`
in this repository and sharing its scripts.
**Status:** approved shape, not yet planned.

### How to use this document

§1–§5 are the design. §6 is the decision log — an implementation phase that wants to
deviate from a decision must amend §6 first and say why. §7 splits the build into three
phases. §8 records what carries over unchanged from the original spec
(`2026-08-03-orchestrating-phased-specs-design.md`), so this document does not repeat it.

---

## 1. Summary

`orchestrating-phased-specs` works, but for a design document that is already well
defined, structured and researched, most of its cost buys little:

- The **planner** runs `superpowers:writing-plans`, which writes every step with real code.
  Against a researched spec that is mostly the spec re-typed as code blocks, and the
  implementers then write the same code a second time.
- `superpowers:subagent-driven-development` and `superpowers:test-driven-development`
  bring their own machinery (task-brief scripts, review packages, workspace layout,
  per-dispatch overrides) and a test volume sized for discovering a design, not for
  implementing one that is already decided.

`building-phased-specs` keeps what makes the original reliable — a thin controller, a
resumable ledger, a branch per phase, subagents for every piece of work, one whole-branch
review with a fix wave, a fresh verifier that judges by exit codes, exactly one repair —
and replaces the plan-writing and Superpowers execution with:

1. a **scout** that grounds the phase against the real repository and writes a short
   **brief** (no code),
2. a **phase lead** that dispatches one **task worker** per task, then one **reviewer**,
   then one **fix wave**,
3. a **verifier** that runs the gates *and* checks the phase's deliverables were built
   and tested.

It runs unattended. Drift between the document and the repository, ambiguity, and
medium-to-large implementation problems are resolved by the agents, recorded, and
surfaced in the final report — never a reason to stop (§4.5).

---

## 2. Scope

### In scope

- Restructuring this repository so two skills share one set of scripts (§5).
- The `building-phased-specs` skill: `SKILL.md`, six dispatch templates, two policy files,
  its own platform guide.
- A new shared script, `phase-finish`, that takes merge bookkeeping off the controller.
- A run-directory namespace so the two skills never share a ledger.
- Cross-referencing descriptions so each skill is invoked deliberately (§4.8).

### Out of scope

- **Changing `orchestrating-phased-specs`' behaviour.** It moves directory and gains a
  cross-referencing description; its loop, templates and ledger are untouched.
- **Any Superpowers dependency.** The new skill must run with Superpowers absent.
- **An upfront whole-document audit** before phase 1. Deferred (§6 D13).
- **Risk-tiered extra review** for sensitive phases. Deferred (§6 D13).
- Everything the original spec already excludes: parallel phases, worktrees, pushing,
  PRs, trunk merges, per-repo configuration, authoring the design document itself.

---

## 3. Architecture

### 3.1 The loop

```
preflight
for each requested phase N, in ascending numeric order:
    phase-start N                               (creates/resumes phase-N-<slug>)

    ① scout      → brief path
    ② phase lead → DONE | BLOCKED
         ├─ task worker × N      one per brief task, sequential
         ├─ reviewer × 1         whole branch, PHASE_BASE_SHA..HEAD
         └─ fix wave             workers, accepted findings only, no re-review
    ③ verifier   → PASS | FAIL + evidence path
         FAIL → repair (once) → verifier again
                still FAIL → halt

    phase-finish N                              (checks, merges, appends ledger)
report
```

### 3.2 Agent topology

```
main session (controller)
├─ Agent: scout
├─ Agent: phase lead
│  ├─ Agent: task worker      one per task
│  ├─ Agent: reviewer         once
│  └─ Agent: fix worker       one per finding group, at most one wave
├─ Agent: verifier
└─ Agent: repair              only on FAIL
```

Three levels, as in the original. Nesting happens only under the phase lead. The lead
never writes code; every line of code is written by a worker, so no agent's context
holds more than one task's implementation.

### 3.3 Models

| Dispatch | Model | Why |
|---|---|---|
| scout | most capable | Grounding is judgment: deciding which drift matters and how to adapt |
| phase lead | most capable | A controller adjudicating review findings unattended |
| task worker | most capable, always | Owner's call (D5). No per-task tiering |
| reviewer | most capable | The only review the phase gets |
| fix worker | most capable | Same role as a task worker |
| verifier | mid-tier | Runs commands and reads exit codes; must still reason about which gates exist |
| repair | most capable | Fresh eyes on something the whole phase did not get right |

Tiers resolve to host models through the skill's platform guide (`opus` / `sonnet` on
Claude Code). Every dispatch names its model explicitly.

### 3.4 ① Scout

**Input:** design doc path, phase number and title, run directory, brief path, repository
root.

**Job:**

1. Read the whole design document, so it understands the phases either side of this one
   and the decisions that bind all of them.
2. Read earlier phases' `phase-*-decisions.md` in the run directory. Earlier phases may
   have deviated from the document; this phase builds on what was actually built.
3. **Ground** every concrete claim the phase makes against the repository: file paths,
   module and symbol names, function signatures, data shapes, dependency names and
   versions, test infrastructure, and anything an earlier phase was supposed to deliver.
   Read code; do not assume.
4. For every mismatch, **choose a resolution** that best preserves the document's intent
   and its decision log, and record it in the brief's drift table. A missing prerequisite
   becomes an extra task. A renamed or reshaped API is adapted to. A contradiction inside
   the document is resolved in favour of the decision log, then the more specific
   statement. This is never a reason to block (§4.5).
5. **Split** the phase into 3–10 tasks and write the brief (§4.2).

The scout writes only the brief. It edits no source and commits nothing.

**Return contract (≤ 4 lines):** brief path, task count, drift count, significant-decision
count.

### 3.5 ② Phase lead

**Input:** brief path, phase branch, `PHASE_BASE_SHA`, run directory, decisions path,
policy file paths, template paths for worker and reviewer.

**Job:**

1. Read the brief. It is the lead's plan; the lead does not read the design document.
2. For each unchecked task, in order: dispatch one **task worker** (§3.6) with the brief
   path, the task number, and the interfaces earlier tasks produced (taken from the brief
   and from earlier worker returns — never by reading their code). On `DONE`, tick the
   task's checkbox in the brief. If the worker reports that its work **affects a later
   task**, update that task in the brief before dispatching it.
3. After the last task, dispatch one **reviewer** (§3.7).
4. **Adjudicate** the findings file: accept or reject each critical and important
   finding, with a one-line reason. Minor findings are deferred to the report unless a
   fix is trivial and inside an accepted group's files.
5. Group accepted findings by area and dispatch one **fix worker** per group,
   sequentially. That is the fix wave. There is no second review; the verifier is the
   gate after it.
6. Write every decision it made to the decisions file (§4.5).

The lead edits nothing but the brief's checkboxes and task notes, and the decisions file.

**Return contract (≤ 10 lines):** `DONE` or `BLOCKED`; commit range `SHORT..SHORT`;
review outcome in one line (critical / important / minor found, accepted, fixed);
deferred count; significant-decision count; decisions path. On `BLOCKED`, what blocked it.

### 3.6 Task worker

**Input:** brief path, task number, interfaces available from earlier tasks, testing
policy path, decision policy path, decisions path, report path.

**Job:**

1. Read the brief's header and global constraints, then its own task. Nothing else from
   the brief.
2. Read the code it is about to change. The brief tells it where to look; the code tells
   it what is true.
3. Implement the task.
4. Write tests according to the testing policy (§4.3).
5. Run the tests it touched plus the repository's fast checks for the touched files
   (typecheck, lint). A red check is fixed before returning. `DONE` with a red check is
   not a valid return.
6. Commit on the phase branch, one or more commits, conventional messages.
7. Write its report (what was built, tests added, deviations) to the report path.

**Return contract (≤ 6 lines):** `DONE` or `BLOCKED`; commit SHAs; tests added (count);
`affects: task K — <one line>` or `affects: none`; decision count; report path.

A fix worker is a task worker whose "task" is a group of accepted findings, passed as the
findings file path plus the finding IDs.

### 3.7 Reviewer

One review per phase, over `PHASE_BASE_SHA..HEAD` — not trunk. Earlier phases are already
integrated and out of scope.

**Input:** brief path, the design document path and phase number, `PHASE_BASE_SHA`,
decisions path, testing policy path, findings path.

**Looks for, in order:** correctness bugs; deliverables in the phase section or brief that
were not built or were built differently without a recorded decision; recorded
significant decisions that contradict the decision log; security and data-integrity
problems; tests that violate the testing policy — missing coverage of a behaviour, or
tests of copy, layout and implementation details that should not exist; dead code and
debugging leftovers.

Breadth is proportionate to the phase: it is the only review the phase gets, and an early
task's defect has had every later task built on top of it.

Findings go to the findings file with an ID, a severity (`critical` / `important` /
`minor`), a file and line, the problem, and the suggested fix. It edits nothing.

**Return contract (≤ 3 lines):** counts per severity; findings path.

### 3.8 ③ Verifier

As in the original (exit codes, never printed totals; evidence file; no edits; no
commits), plus an **acceptance check**:

For each deliverable and verification item in the phase's section of the design
document, and each task's "done when" in the brief: is it implemented, and is it
exercised by a test? One line each in the evidence file — `met`, `met, untested`, or
`missing`. A `missing` deliverable with no recorded decision explaining its absence is a
`FAIL`. `met, untested` is recorded but does not fail the phase.

**Return contract (≤ 3 lines):** `PASS` or `FAIL` plus the verified HEAD SHA; a one-line
reason; evidence path.

### 3.9 Repair

As in the original, reading the brief instead of a plan: evidence first, then the brief,
then only the code the failure touches. Fix the root cause; never weaken, skip or delete
the check that caught it. Exactly one attempt per phase. It does its own work and spawns
no agents.

### 3.10 Merge

`phase-finish` (§4.7) replaces the controller's hand-run merge sequence. Structurally,
conflicts cannot arise, for the reasons the original spec gives; the script still checks
the exit code and fails loudly.

---

## 4. Mechanics

### 4.1 Paths

| Artifact | Path |
|---|---|
| Run directory | `<repo-root>/.superpowers/phase-builder/<spec-basename>/` |
| Ledger | `<run-dir>/run.md` |
| Brief | `<run-dir>/phase-<N>-brief.md` |
| Decisions | `<run-dir>/phase-<N>-decisions.md` |
| Task reports | `<run-dir>/phase-<N>-task-<K>-report.md` |
| Review findings | `<run-dir>/phase-<N>-review.md` |
| Verifier evidence | `<run-dir>/phase-<N>-evidence.md` |
| Phase branch | `phase-<N>-<slug>` |

Everything except the code lives in the git-ignored run directory. Nothing workflow-shaped
is committed; the design document stays the only committed source of intent.

### 4.2 The brief

```markdown
# Phase <N> — <title>

**Goal:** <one paragraph, from the phase section>
**Spec:** <absolute design doc path>

## Global constraints
<copied from the design document with exact values: decision log items, platform and
portability rules, anything stated as binding on every phase>

## Drift
| # | Document says | Repository has | Resolution | Significant |
|---|---|---|---|---|

## Tasks

### - [ ] Task 1 — <title>
- **Goal:** <one or two sentences>
- **Files:** <create / modify, with paths>
- **Produces:** <exact public names and types later tasks build on>
- **Done when:** <observable behaviours, one per line>
- **Test focus:** <which behaviours need tests; which edge cases the document names>
- **Notes:** <gotchas found while grounding; updated by the lead when an earlier task
  affects this one>
```

No code, no step lists, no test code. The worker writes the code once, against the
repository as it finds it.

The brief is a **living document**: the lead ticks checkboxes and edits later tasks'
notes. Together with `git log`, the checkboxes are how an interrupted lead resumes.

### 4.3 Testing policy (`testing-policy.md`)

Passed to every worker and to the reviewer. Tests exist to prove behaviour a user or
caller relies on, and to keep proving it.

**Write:**
- One test per behaviour in the task's "done when" and per acceptance criterion the
  phase names — a user flow, a command's effect, an endpoint's contract, a function's
  observable result.
- The edge and error cases the design document names explicitly.
- A regression test for every bug hit while building the task.

**How:**
- Through the public surface: the route, the command, the component as a user drives it,
  the exported function. Not private helpers.
- Mock only at system boundaries: network, clock, randomness, filesystem, third-party
  services. Never mock the module under test or its in-repo collaborators.
- Each core behaviour test must be **seen failing once**, by running it before the
  implementation exists or by breaking the implementation briefly. A test that has never
  failed has not been shown to test anything.
- Follow the repository's existing test conventions and helpers.

**Do not write:**
- Assertions on static copy, labels, headings, placeholder text, element order, layout,
  CSS classes or styling — unless the text *is* the behaviour (a validation message
  the user must see, an error code a caller branches on).
- Markup or component snapshots.
- "Renders without crashing" and "is defined" tests.
- Tests that restate the implementation — asserting that a function called its own
  internals, or that a mock returned what it was told to return.

A handful of tests per task is normal. Dozens means the policy is being ignored.

### 4.4 The ledger

Same identity header and append-only rule as the original. Lines:

```markdown
phase 2 (Shell & surface model): started — branch phase-2-shell-surface-model
phase 2: grounded — brief phase-2-brief.md, 6 tasks, 3 drift, 1 significant
phase 2: executed — a1b2c3d..9f8e7d6, 14 commits, review 0/2/5 (2 fixed, 5 deferred), 2 significant
phase 2: verified PASS 9f8e7d6
phase 2: merged to base (4c5d6e7)
```

### 4.5 Decisions and blocking (`decision-policy.md`)

Passed to every agent except the verifier. The run is unattended; nobody will answer.

**Resolve, record, continue.** Faced with drift, ambiguity, a contradiction, or an
implementation problem of any size, pick the option most faithful to the document's
intent and decision log — then the repository's existing conventions, then the simplest
option that satisfies both — implement it, and record it:

```
- [significant] <what was decided> — instead of <alternative> — because <reason>
- [routine] …
```

A decision is **significant** if it changes a public API, a data model or schema, a
user-visible behaviour, a phase's scope, or departs from a decision-log item. Everything
else is routine. Significant decisions are counted in every return contract and listed in
the final report, so the owner can audit them after the run.

**`BLOCKED` is reserved for work that cannot proceed or must not.** The complete list:

1. Missing credentials, access, or a required host approval.
2. A required tool, service or runtime that is absent and cannot be installed within the
   repository's own tooling.
3. The host cannot nest agents (the lead cannot dispatch workers).
4. The only way forward is destructive or outside the repository's scope: dropping or
   rewriting real data, rewriting shared git history, touching production or external
   systems, spending money.

Nothing else blocks. A design problem, however large, is resolved and recorded. The
templates state this list verbatim and state that it is exhaustive.

### 4.6 Resume

Re-invoking the skill with the same spec and base is the resume, as in the original.
The phase-level rules map across:

- `started` with no `grounded` → re-dispatch the scout; if a brief already exists at the
  path, the scout checks it against the repository and completes or reuses it.
- `grounded` with no `executed` → dispatch the lead. It resumes from the brief's
  checkboxes and `git log`, never replaying ticked tasks. A task left unticked with
  commits on the branch is reconciled by its worker, not redone from scratch.
- `executed` without a current `verified PASS` → verifier.
- Repair and merge reconciliation as in the original.

### 4.7 `phase-finish`

`phase-finish DESIGN_DOC BASE N VERIFIED_SHA`:

1. Refuses a dirty working tree.
2. Refuses if the phase branch's HEAD is not `VERIFIED_SHA`.
3. Switches to `BASE` and runs `git merge --no-ff phase-<N>-<slug> -m "merge: phase <N> — <title>"`.
4. On a non-zero merge exit: runs `git merge --abort`, switches back to the phase branch,
   exits non-zero naming the failure.
5. Appends `phase <N>: merged to base (<sha>)` to the ledger.
6. Prints one line.

The controller runs it and reads the one line. The controller's per-phase footprint is
then: two script lines, four or five capped returns, and a handful of ledger appends —
small enough for 15+ phase runs, with the ledger and `git log` as the recovery map after
compaction.

### 4.8 Invoking the right skill

- **Deterministic:** invoke by name. Claude Code: `/building-phased-specs phases 2-6 of
  <doc> on <branch>`. Codex: `$building-phased-specs …`.
- **Loose phrasing:** the two descriptions point at each other.
  - `building-phased-specs`: *Use when the user asks to run, build or work on phases of a
    phased design document directly from the document — e.g. "work on phases 2 to 6 of
    \<spec\>". Grounds each phase, splits it into tasks, and executes them with
    subagents. For plan-driven execution through Superpowers writing-plans and
    subagent-driven-development, use orchestrating-phased-specs instead.*
  - `orchestrating-phased-specs`: *Use only when the user explicitly asks for plan-driven
    phase execution — writing a Superpowers implementation plan per phase and running it
    with subagent-driven-development — or names this skill. For running phases directly
    from the design document, use building-phased-specs.*

  Plain "work on phases X to Y" therefore goes to `building-phased-specs` (D11).

---

## 5. Repository structure

```
shared/scripts/
  parse-phases  phase-run-dir  phase-preflight  phase-start  phase-finish
  __tests__/
skills/orchestrating-phased-specs/
  SKILL.md  planner-prompt.md  executor-prompt.md  verifier-prompt.md  repair-prompt.md
  platform-guide.md
  scripts/            thin wrappers: namespace phase-orchestrator
skills/building-phased-specs/
  SKILL.md
  scout-prompt.md  lead-prompt.md  worker-prompt.md  reviewer-prompt.md
  verifier-prompt.md  repair-prompt.md
  testing-policy.md  decision-policy.md
  platform-guide.md
  scripts/            thin wrappers: namespace phase-builder
install.sh            installs one or both skills, for one or both hosts
README.md
docs/
```

**Wrappers, not symlinks and not an environment variable the controller must remember.**
Each skill's `scripts/<name>` is a few lines: resolve its own real directory with
`pwd -P`, export `PHASE_RUN_NAMESPACE`, and `exec` the shared script. `phase-run-dir`
reads the namespace, defaulting to `phase-orchestrator` so the original skill's run
directories stay where they are. A controller that loses context after compaction still
calls `$SKILL_DIR/scripts/phase-preflight`, and still gets the right namespace.

`install.sh` gains a skill argument (`orchestrating`, `building`, `all`; default `all`)
alongside the host argument. Re-running it repoints an existing
`~/.claude/skills/orchestrating-phased-specs` symlink from the repository root to
`skills/orchestrating-phased-specs/`, which its existing replace-a-symlink path already
handles.

---

## 6. Decision log

| # | Decision | Rationale |
|---|---|---|
| **D1** | **A sibling skill, not a mode of the original.** The original stays behaviourally unchanged. | Both are useful: plan-driven for exploratory specs, direct for researched ones. A mode flag would put two loops in one `SKILL.md` and make each harder to follow. |
| **D2** | **A brief, not a plan.** Tasks carry goal, files, interfaces, done-when and test focus — no code. | For a researched spec, a code-bearing plan duplicates the document and then gets written a second time. The worker writes code once, against the repository as it is. |
| **D3** | **The scout is its own agent, separate from the lead.** | Grounding reads a lot of code. Keeping it out of the lead keeps the lead thin across big phases; the brief is the handoff. |
| **D4** | **Every task runs in its own worker; the lead never implements.** Three agent levels. | Owner's call. One agent implementing a large phase accumulates every task's code in its context. |
| **D5** | **Task and fix workers always use the most capable model.** No per-task tiering. | Owner's call, 2026-09-22. Revisit only with evidence from real runs. |
| **D6** | **One whole-branch review, one fix wave, no re-review.** Critical and important findings are fixed; minor ones are deferred to the report. | Owner's call: a review round is needed for reliable output, and the original's measurements show that per-task review is the largest cost. The verifier is the gate after the fix wave. |
| **D7** | **Resolve, record, continue.** `BLOCKED` is limited to the four cases in §4.5, and the list is exhaustive. | Owner's call: the run is unattended and must handle medium-to-large problems itself. The cost — a wrong significant decision surviving the run — is contained by recording each one and listing it in the report. |
| **D8** | **Behaviour-focused testing policy**, shared by workers and reviewer. | Owner's call. Tests that pin copy and layout break on every UI change and prove nothing about behaviour; the "seen failing once" rule keeps the smaller suite honest. |
| **D9** | **No Superpowers dependency.** | The overrides in the original templates exist only to bend Superpowers skills into this shape. Self-contained prompts are shorter and cannot drift when Superpowers changes. |
| **D10** | **Separate run-directory namespace, applied by wrapper scripts.** | The two skills must never read each other's ledger for the same spec. A wrapper cannot be forgotten after compaction; a prefix the controller must remember can. |
| **D11** | **`building-phased-specs` is the default for loose phrasing**; the original requires explicit plan-driven wording or its name. | The new skill is the intended everyday path. Invoking by name is deterministic either way. Changeable by editing two descriptions. |
| **D12** | **The verifier adds an acceptance check.** An unexplained missing deliverable is a `FAIL`. | Replaces the spec-coverage assurance the plan's self-review used to give, at no extra dispatch. |
| **D13** | **Upfront document audit and risk-tiered review are deferred.** | Owner's call. Add them once real runs show whether cross-phase drift or high-risk phases are where failures come from. |

---

## 7. Implementation phases

### Phase 1 — Shared scripts and repository layout

**Goal:** the repository holds two skill directories sharing one set of scripts, and the
original skill still installs and behaves exactly as before.

**Change**
- Move the scripts and their tests to `shared/scripts/`; move the original skill's files
  to `skills/orchestrating-phased-specs/`.
- `phase-run-dir` reads `PHASE_RUN_NAMESPACE`, defaulting to `phase-orchestrator`, and
  rejects a namespace containing `/` or starting with `.`.
- Wrapper scripts for both skills (§5).
- `phase-finish` (§4.7).
- `install.sh` installs either or both skills for either or both hosts.
- Update every test that references the old layout.

**Constraints**
- The original spec's portability rules (its D11) bind every script and wrapper: no `\s`,
  no bracket expressions over multibyte dashes, no interval expressions, bash 3.2.
- The original skill's run-directory path is unchanged.

**Verification**
- The full shell suite passes under macOS `/bin/bash` and BSD `awk`.
- `shellcheck` is clean on every script and wrapper.
- A wrapper called through an installed symlink resolves the shared script and applies its
  namespace; the two namespaces produce different run directories for the same spec.
- `phase-finish` refuses a dirty tree, refuses a HEAD that is not the verified SHA,
  merges `--no-ff`, appends exactly one ledger line, and on a forced merge failure aborts
  the merge and exits non-zero.
- Re-running `install.sh` over an existing root-level install repoints it to
  `skills/orchestrating-phased-specs/`; a non-symlink destination is still refused.

**Done when:** both skill directories install, and the original skill's preflight → start
→ merge path works unchanged from its new location.

### Phase 2 — Templates and policies

**Goal:** six dispatch templates and two policy files that say exactly what each agent
must and must not do.

**Add**
- `scout-prompt.md` (§3.4), `lead-prompt.md` (§3.5), `worker-prompt.md` (§3.6, also used
  for the fix wave), `reviewer-prompt.md` (§3.7), `verifier-prompt.md` (§3.8),
  `repair-prompt.md` (§3.9).
- `testing-policy.md` (§4.3), `decision-policy.md` (§4.5).

**Constraints**
- Every template states its return contract and its cap, and forbids pasting artifacts
  (code, diffs, test output, brief text) into the return.
- Every template names its model tier; the worker template names the most capable tier
  with no alternative.
- The decision policy's `BLOCKED` list appears verbatim and is stated as exhaustive.
- The verifier keeps the original's exit-code rule word for word in substance.
- No template references a Superpowers skill.

**Verification**
- Structural tests in the style of the existing `templates.test.sh`: placeholders,
  return contracts, caps, model tiers, the `BLOCKED` list, no `superpowers:` references.
- Dispatch the scout for real against one phase of a small real spec with one deliberate
  drift (a renamed function): it writes a brief in the §4.2 shape, records the drift with
  a resolution, and returns within contract, without blocking.
- Dispatch a worker for one brief task: it commits, its tests follow the testing policy,
  and it returns within contract.
- Dispatch the verifier against a branch missing one deliverable: it returns `FAIL` and
  the evidence names the deliverable as `missing`.

**Done when:** each template has been dispatched once and returned within its contract.

### Phase 3 — The loop and the invocation

**Goal:** `SKILL.md` ties it together, the descriptions route correctly, and a real
multi-phase run completes unattended.

**Add / change**
- `skills/building-phased-specs/SKILL.md`: invocation, preflight, the loop (§3.1), paths,
  the ledger (§4.4), resume (§4.6), halting, the report, known limits, common
  rationalizations.
- `skills/building-phased-specs/platform-guide.md`: the original's host guidance minus
  every Superpowers prerequisite; model tier mapping per §3.3.
- Both skills' descriptions per §4.8.
- `README.md` covering both skills and how to invoke each.

**The report** lists, per phase: commit range, commits, review counts, deferred count,
repair rounds — and then **every significant decision** from every phase's decisions
file, one line each, so the owner can audit what the run decided alone.

**Verification**
- Structural tests for `SKILL.md` in the style of `skill.test.sh`.
- A two-phase run over a small real spec completes: both phases grounded, executed,
  reviewed, verified and merged; the ledger is correct; the report lists significant
  decisions.
- Killing the run mid-phase-2, during the lead's task loop, and re-invoking resumes at
  the first unticked task without redoing ticked ones or touching phase 1.
- A forced verifier `FAIL` triggers exactly one repair, then halts if still red, leaving
  the branch unmerged and base at the previous phase.
- A spec with deliberate drift in phase 2 completes without `BLOCKED`, and the drift is
  recorded in the brief and, if significant, in the report.
- The controller's context after the run contains no brief text, no code, no diff and no
  test output.

**Done when:** a real phased spec runs end to end unattended and the ledger reconstructs
the run without the session's memory.

---

## 8. Carried over from the original spec

These hold unchanged; see `2026-08-03-orchestrating-phased-specs-design.md`.

- Thin controller: it never reads a brief, code, a diff or a test log. Artifacts live in
  files, dispatches carry paths, returns are capped.
- Branch per phase in a single checkout; no worktrees (D2 there).
- Halt after exactly one repair attempt (D7 there).
- The run ends at a report: no push, no PR, no trunk merge (D8 there).
- Phase identity is the number in the heading, never a position (D10 there).
- Script portability rules (D11 there).
- Preflight checks, ledger identity and resume by re-invocation.
- Platform assumptions: nested agents to three levels; permission mode is documented,
  not detected.

---

## 9. Known limits

Stated in `SKILL.md`, not only here.

1. **Unattended decisions can be wrong.** A significant decision made in phase 2 is built
   on by every later phase before a human sees it. The report lists every one; nothing
   prevents them.
2. **One review round per phase.** Fixes from the fix wave are checked by the verifier's
   gates and acceptance check, not by a second review. Residual minor findings compound
   across phases.
3. **The brief is a convention.** Nothing mechanically stops a scout from putting code in
   it, or a lead from reading the design document.
4. **Permissions, nesting depth, and a busy working tree** — as in the original.

---

## 10. Open questions

None. Every question raised during design is resolved in §6.
