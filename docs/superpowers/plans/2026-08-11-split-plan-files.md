# Split Plan Files Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make this skill's planner write each phase plan as a directory — one thin ledger plus one file per task — and make its executor consume that shape without ever reading the whole plan.

**Architecture:** Every change is prose in four dispatch templates this repository already owns (`planner-prompt.md`, `executor-prompt.md`, `repair-prompt.md`, `SKILL.md`), enforced by string assertions in the existing plain-bash test files. No new scripts, no changes to the upstream `superpowers` skills — the new rules ride in as overrides beside the ones already there.

**Tech Stack:** Markdown dispatch templates; bash test files under `scripts/__tests__/` using the `assert.sh` helpers (`assert_eq`, `assert_contains`) and the per-file `has` wrappers.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-11-split-plan-files-design.md`.
- Plan path shape: `docs/superpowers/plans/<date>-<spec-slug>-phase-<N>-<slug>/plan.md`; task files are `task-<N>.md` **siblings** of `plan.md` in that same directory.
- `assert_contains` matches with a shell `case` glob: a needle passed to `has` must contain no `*`, `?`, or `[`.
- `templates.test.sh` ends with a loop asserting no template contains the word `paste` outside the phrase `do not paste`. New template prose must not use the word "paste" at all.
- Every template keeps its existing `general-purpose` dispatch line and its explicit `model:` line — the same loop asserts both.
- The full test command is `bash scripts/__tests__/run-tests.sh`; a single file runs as `bash scripts/__tests__/templates.test.sh`.
- Override numbering is append-only: the planner's new rule is **override 3**, the executor's is **override 5**. Existing prose that references "Override 4" keeps its number.

---

### Task 1: Planner override 3 — the plan is a directory

**Files:**
- Modify: `planner-prompt.md`
- Modify: `docs/superpowers/specs/2026-08-11-split-plan-files-design.md` (pointer-line correction)
- Test: `scripts/__tests__/templates.test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the on-disk plan contract every later task depends on — `PLAN_PATH` is a `plan.md` inside a directory; task files are `task-<N>.md` siblings; the ledger's `## Tasks` table has columns `# | Title | File | Produces`; each task file opens with the verbatim line `> Global constraints bind this task — read the `plan.md` beside this file,` / `> § Global Constraints, before you start.`

- [ ] **Step 1: Correct the spec's pointer line**

The spec twice writes the pointer as `../plan.md`, which was carried over from a layout option that was not chosen. Task files are siblings of `plan.md`, so `../plan.md` points at the wrong directory. Replace both occurrences with wording that does not depend on the reader's working directory.

In `docs/superpowers/specs/2026-08-11-split-plan-files-design.md`, replace this block:

````markdown
```markdown
# Task 3: Surface attachment

> Global constraints bind this task — read `../plan.md`
> § Global Constraints before you start.
```
````

with:

````markdown
```markdown
# Task 3: Surface attachment

> Global constraints bind this task — read the `plan.md` beside this file,
> § Global Constraints, before you start.
```
````

and in the same file replace:

```markdown
A pointer, not a copy. The ledger is deliberately thin, so the extra read is
```

with:

```markdown
A pointer, not a copy — and a cwd-independent one, since task files sit beside
the ledger, not below it. The ledger is deliberately thin, so the extra read is
```

- [ ] **Step 2: Write the failing assertions**

In `scripts/__tests__/templates.test.sh`, the planner block currently ends with these two lines:

```bash
has planner-prompt.md 'PLAN_PATH' 'writes to the exact path it was given'
has planner-prompt.md 'Return ONLY the plan file path' 'return contract is the path alone'
```

Change the existing commit assertion and add the override-3 assertions. Replace this line:

```bash
has planner-prompt.md 'Commit the plan file' 'planner commits the plan'
```

with:

```bash
has planner-prompt.md 'Commit the whole plan directory' 'planner commits the directory'
```

and insert these directly after the `Return ONLY the plan file path` line:

```bash
# Override 3: the plan is a directory — a ledger plus one file per task.
has planner-prompt.md 'Three overrides of superpowers:writing-plans' 'the override count is stated'
has planner-prompt.md 'Split the plan across files' 'override 3: the plan is a directory'
has planner-prompt.md 'task-<N>.md' 'override 3: one file per task, named by number'
has planner-prompt.md 'Produces' 'override 3: the ledger carries the interface map'
has planner-prompt.md 'No task steps in the ledger' 'override 3: task steps never live in the ledger'
has planner-prompt.md 'Global constraints bind this task' 'override 3: the verbatim pointer line'
has planner-prompt.md 'regardless of size' 'override 3: every plan splits, unconditionally'
has planner-prompt.md 'across the whole directory' 'override 3: self-review covers every file'
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash scripts/__tests__/templates.test.sh`

Expected: FAIL. Eight new `FAIL` lines plus the changed commit assertion — `expected to contain: [Split the plan across files]`, `[Three overrides of superpowers:writing-plans]`, `[Commit the whole plan directory]`, and so on. The file exits 1.

- [ ] **Step 4: Rewrite the planner's job list and overrides**

In `planner-prompt.md`, replace this line:

```
    Write the plan to: PLAN_PATH
```

with:

```
    Write the plan to: PLAN_PATH   (a plan.md inside a directory you create)
```

Replace job steps 4 to 6 — currently:

```
    4. Save the plan to exactly PLAN_PATH. Do not choose your own filename and
       do not save it anywhere else — the orchestrator hands this exact path to
       the agent that executes it.
    5. Copy the design document's cross-cutting constraints — the decision log,
       the platform and portability rules, anything the document states as
       binding on every phase — into the plan's `## Global Constraints` block,
       with their exact values. The agent executing your plan will never read
       the design document.
    6. Commit the plan file.
```

with:

```
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
```

Replace the overrides section — currently:

```
    ## Two overrides of superpowers:writing-plans

    These supersede that skill's own ending. It is not a preference.

    - Do NOT present the execution-choice menu at the end ("Subagent-Driven /
      Inline Execution"). Nobody is there to answer it. The orchestrator has
      already chosen.
    - Do NOT execute the plan, or any part of it. A separate agent does that.
```

with:

````
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
````

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash scripts/__tests__/templates.test.sh`

Expected: PASS — every assertion `ok`, the summary line reports `0 failed`, exit 0.

- [ ] **Step 6: Run the whole suite**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: PASS — `all test files passed`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add planner-prompt.md scripts/__tests__/templates.test.sh docs/superpowers/specs/2026-08-11-split-plan-files-design.md
git commit -m "feat: planner writes a plan directory, not a single file"
```

---

### Task 2: Executor override 5 — read the ledger, never the plan

**Files:**
- Modify: `executor-prompt.md`
- Test: `scripts/__tests__/templates.test.sh`

**Interfaces:**
- Consumes: the plan contract Task 1 produced — `PLAN_PATH` is the ledger; task files are `task-<N>.md` siblings; the ledger's `## Tasks` table carries a `Produces` column.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing assertions**

In `scripts/__tests__/templates.test.sh`, update the section comment above the executor's override assertions — currently:

```bash
# The four overrides of subagent-driven-development.
```

to:

```bash
# The five overrides of subagent-driven-development.
```

Then insert these assertions directly after the existing line:

```bash
has executor-prompt.md 'fix it before you dispatch the next task' 'override 4 keeps failing task checks blocking'
```

The new assertions:

```bash
has executor-prompt.md 'Five overrides' 'the override count is stated'
has executor-prompt.md 'Read the ledger once' 'override 5: exactly one plan-level read'
has executor-prompt.md 'scripts/task-brief' 'override 5: names the script it disables'
has executor-prompt.md 'task-<N>.md' 'override 5: the task file is the brief'
has executor-prompt.md 'task-<N>-report.md' 'override 5: reports stay in the workspace'
has executor-prompt.md 'Produces column' 'override 5: cross-task interfaces come from the ledger'
has executor-prompt.md 'scoped to the ledger' 'override 5: the conflict scan is scoped'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/__tests__/templates.test.sh`

Expected: FAIL. Seven new `FAIL` lines — `expected to contain: [Five overrides]`, `[Read the ledger once]`, `[scripts/task-brief]`, and the rest. The file exits 1.

- [ ] **Step 3: Add override 5 to the executor template**

In `executor-prompt.md`, replace this preamble paragraph:

```
Override 4 disables that skill's per-task review loop: the phase is reviewed
once, whole, at the end. Read its rationale before weakening it — it is the
difference between a phase that takes an evening and one that takes a day.
```

with:

```
Override 4 disables that skill's per-task review loop: the phase is reviewed
once, whole, at the end. Read its rationale before weakening it — it is the
difference between a phase that takes an evening and one that takes a day.
Override 5 tells this agent what shape the plan arrives in — a ledger plus one
file per task — and is why it never reads the plan whole.
```

Replace this line:

```
    Plan:            PLAN_PATH
```

with:

```
    Plan:            PLAN_PATH     (the ledger — see override 5)
```

Replace the overrides heading:

```
    ## Four overrides of superpowers:subagent-driven-development
```

with:

```
    ## Five overrides of superpowers:subagent-driven-development
```

Then append override 5 after override 4's final paragraph — the one ending
`fix it before you dispatch the next task.` — and before the
`## One directive from the person this run is for` heading:

```
    5. The plan is a directory, not a file. PLAN_PATH is its ledger: the
       header, the `## Global Constraints` block, the `## File Structure` map,
       and a `## Tasks` table naming one `task-<N>.md` file per task, beside it.
       Read the ledger once. That is the whole of your plan-level reading — do
       not read the task files as a set, and do not open one you are not
       adjudicating a finding against.

       Do NOT run that skill's `scripts/task-brief`. Task N's brief already
       exists, written by the planner, at `task-<N>.md` beside the ledger — give
       the implementer that path as its brief. Run against a ledger, that script
       finds no `Task N` heading and exits 3.

       The implementer's report still belongs in the workspace
       `scripts/sdd-workspace` prints, as `task-<N>-report.md` — never beside
       the task file, because the plan directory is committed to git.

       The interfaces every dispatch owes its implementer come from the ledger's
       Produces column, not from reading earlier task files.

       That skill's pre-flight conflict scan is scoped to the ledger: the Global
       Constraints against the task table, nothing deeper. It cannot scan tasks
       you have not read, and its only exit is a question for a human partner
       who, here, is afk.

       `scripts/sdd-workspace` and `scripts/review-package` take PLAN_PATH
       unchanged. Both use it only to name the workspace directory, so the
       ledger's path works as-is.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/__tests__/templates.test.sh`

Expected: PASS — every assertion `ok`, `0 failed`, exit 0. In particular the file's closing loop still reports `executor-prompt.md: never asks an agent to paste an artifact into its return value` as `ok`, since the new prose does not use that word.

- [ ] **Step 5: Run the whole suite**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: PASS — `all test files passed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add executor-prompt.md scripts/__tests__/templates.test.sh
git commit -m "feat: executor consumes the plan ledger, not the whole plan"
```

---

### Task 3: Repair and SKILL.md catch up with the directory shape

**Files:**
- Modify: `repair-prompt.md`
- Modify: `SKILL.md`
- Test: `scripts/__tests__/templates.test.sh`
- Test: `scripts/__tests__/skill.test.sh`

**Interfaces:**
- Consumes: the plan contract Task 1 produced (`plan.md` ledger, `task-<N>.md` siblings, `## Tasks` table) and the executor rules Task 2 added.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing assertions**

In `scripts/__tests__/templates.test.sh`, add to the repair block, directly after this line:

```bash
has repair-prompt.md 'six lines' 'return contract is capped'
```

the assertion:

```bash
has repair-prompt.md 'task-<N>.md' 'reads only the task files the failure touches'
```

In `scripts/__tests__/skill.test.sh`, add to the loop-and-ledger block, directly after this line:

```bash
has 'run.md' 'names the ledger file'
```

these assertions:

```bash
has 'phase-<N>-<slug>/plan.md' 'the plan is a directory whose ledger is plan.md'
has 'one file per task' 'the paths table says task files sit beside the ledger'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: FAIL — `templates.test.sh` reports `expected to contain: [task-<N>.md]` for `repair-prompt.md`, `skill.test.sh` reports `expected to contain: [phase-<N>-<slug>/plan.md]` and `[one file per task]`, and the runner prints `2 test file(s) FAILED` and exits 1.

- [ ] **Step 3: Point the repair agent at the ledger**

In `repair-prompt.md`, replace this job step:

```
    2. Read the plan to understand what the phase was meant to deliver.
```

with:

```
    2. Read the plan to understand what the phase was meant to deliver.
       PLAN_PATH is a ledger: the header, the `## Global Constraints` block, and
       a `## Tasks` table naming one `task-<N>.md` file per task, beside it.
       Read the ledger, then only the task files the failure touches.
```

- [ ] **Step 4: Update the paths table, the ledger examples, and the limits in SKILL.md**

In `SKILL.md`, replace this row of the paths table:

```markdown
| Plan | `docs/superpowers/plans/<date>-<spec-slug>-phase-<N>-<slug>.md` |
```

with:

```markdown
| Plan | `docs/superpowers/plans/<date>-<spec-slug>-phase-<N>-<slug>/plan.md` |
```

and add this sentence directly below that table, before the `Order within a phase:` line:

```markdown
The plan is a directory: `plan.md` is its ledger — goal, global constraints, file
structure, and a table of tasks — with one file per task beside it, `task-1.md`,
`task-2.md`, and so on. `planner-prompt.md` override 3 specifies it and
`executor-prompt.md` override 5 consumes it. You hand around the `plan.md` path
and never open any of it.
```

In the ledger example block, replace these two lines:

```
phase 2 (Shell & surface model): plan docs/superpowers/plans/…-phase-2-shell.md
```

```
phase 3 (Takeovers & interstitials): plan docs/superpowers/plans/…-phase-3-takeovers.md
```

with:

```
phase 2 (Shell & surface model): plan docs/superpowers/plans/…-phase-2-shell/plan.md
```

```
phase 3 (Takeovers & interstitials): plan docs/superpowers/plans/…-phase-3-takeovers/plan.md
```

Then add a fifth entry to the `## Known limits` list, after limit 4 (`Nesting depth is a platform assumption, not a guarantee.`):

```markdown
5. **Nothing checks that a plan was actually split.** A planner that ignores
   override 3 writes one `plan.md` holding every task; the executor reads it
   whole and the run succeeds at the old cost. The saving is a convention, not a
   mechanism. The executor's pre-flight conflict scan is scoped to the ledger for
   the same reason it is cheap — no agent compares two task files before
   execution starts, and the phase's single whole-branch review is the only net
   under a plan that contradicts itself.
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: PASS — `all test files passed`, exit 0. Note that `skill.test.sh`'s existing loop re-checks that every referenced path exists on disk; no path was added, so it stays green.

- [ ] **Step 6: Commit**

```bash
git add repair-prompt.md SKILL.md scripts/__tests__/templates.test.sh scripts/__tests__/skill.test.sh
git commit -m "feat: repair and the skill doc describe the plan directory"
```
