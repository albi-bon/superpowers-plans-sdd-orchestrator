# Split Plan Files — Design

A phase plan becomes a directory: one thin ledger the executor reads, one file
per task the executor never reads. The orchestrator's dispatches keep handing
around a single path.

## The problem

`superpowers:writing-plans` produces one file. For a large phase that file runs
to several thousand lines, and `subagent-driven-development`'s Setup step tells
the executor to read it whole:

> Read the plan once, note its context and Global Constraints, and create a
> todo per task.

That read sits in the executor's context for the entire phase — every task
dispatch, every review adjudication, every fix round re-reads it. It is the
largest fixed cost in a phase that isn't work.

Per-task agents are already shielded: `scripts/task-brief PLAN_FILE N` awk-extracts
one task into its own file, and the skill states outright *"Never make a subagent
read the whole plan file."* So this design is not about implementers. It is about
the one agent that does pay: the executor.

## The shape

`PLAN_PATH` becomes:

```
docs/superpowers/plans/<date>-<spec-slug>-phase-<N>-<slug>/plan.md
```

The directory is the plan. `plan.md` is its ledger. Task files are siblings:

```
docs/superpowers/plans/
└── 2026-08-11-thing-phase-2-shell/
    ├── plan.md        ← ledger
    ├── task-1.md
    ├── task-2.md
    └── task-3.md
```

Every dispatch in this skill still carries exactly one path, as it does today.

### plan.md

Header (goal, architecture, tech stack), `## Global Constraints` copied verbatim
from the spec, `## File Structure`, then:

```markdown
## Tasks

| # | Title | File | Produces |
|---|-------|------|----------|
| 1 | Shell scaffold | task-1.md | `createShell(opts: ShellOpts): Shell` |
| 2 | Surface model  | task-2.md | `Surface`, `attach(s: Surface): void` |
```

No task steps, ever. The **Produces** column is load-bearing:
`subagent-driven-development` requires every dispatch to carry "interfaces and
decisions from earlier tasks that the brief cannot know." That column is how the
executor supplies them without opening a task file — which would re-import the
cost this design removes.

### task-N.md

Exactly `writing-plans`' Task Structure — Files, Interfaces, checkbox steps with
real code, no placeholders — opening with a fixed pointer line:

```markdown
# Task 3: Surface attachment

> Global constraints bind this task — read the `plan.md` beside this file,
> § Global Constraints, before you start.
```

A pointer, not a copy — and a cwd-independent one, since task files sit beside
the ledger, not below it. The ledger is deliberately thin, so the extra read is
cheap, there is one source of truth for the constraints, and the implementer
picks up goal and architecture in the same call. Duplicating the block into every
task file would put the most repair-edited section of a plan in N places.

No cross-task content in a task file.

### Always, never conditionally

Every phase plan is a directory regardless of size. One shape means no detection
logic in the executor, no branch in the override, and no size estimate from the
planner before it has written anything — a judgment it would make badly. A
three-task phase pays three small files.

## The changes

Four templates this repository already owns, plus their tests. No new scripts,
no changes to upstream superpowers skills.

### planner-prompt.md — override 3

Appended after the existing two overrides of `superpowers:writing-plans`:

- `PLAN_PATH` names a file inside a directory the planner creates.
- The split above: ledger contents, task-file contents, the pointer line.
- `writing-plans`' single-file `Save plans to docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
  is superseded.
- Self-review (spec coverage, placeholder scan, type consistency) runs across the
  whole directory.
- Commit the directory.

Return contract unchanged: the `plan.md` path, on one line, alone.

### executor-prompt.md — override 5

The load-bearing half.

- `PLAN_PATH` is the ledger. Read it once — that is the entire plan-level read.
  Never concatenate task files; never read a task file you are not adjudicating.
- **Do NOT run `scripts/task-brief`.** Task N's brief already exists at
  `<plan-dir>/task-<N>.md`; pass that path as the brief. Left alone, the script
  would awk the ledger for a `Task N` heading, find none, and exit 3.
- Report files stay in the SDD workspace (`task-<N>-report.md`), never in the
  plan directory — that one is git-tracked.
- Cross-task interfaces come from the ledger's **Produces** column.
- `subagent-driven-development`'s pre-flight cross-task conflict scan is scoped to
  the ledger: Global Constraints against the task index, nothing deeper. It cannot
  scan tasks it has not read, and its only exit is
  *"present everything you find to your human partner as one batched question"* —
  a human who is afk by this skill's construction.

`scripts/sdd-workspace` and `scripts/review-package` take `PLAN_PATH` unchanged.
Both use it only to name the workspace directory, so `plan.md` works as-is.

### repair-prompt.md

One line: `PLAN_PATH` is the ledger, task files are listed in its Tasks table,
read only the ones the failure touches.

### SKILL.md

The Paths table's `Plan` row takes the directory form. The ledger examples in
§ The ledger point at `plan.md`.

`verifier-prompt.md` is untouched — the verifier never receives the plan.

## Tests

`scripts/__tests__/templates.test.sh`, in its existing `has FILE NEEDLE MESSAGE`
style:

- planner: the directory layout, the ledger's Tasks table, the per-task file
  naming, the constraints pointer line.
- executor: the ledger-only read, the `task-brief` prohibition, the report-file
  placement, the scoped conflict scan.

`executor-prompt.md`'s section heading goes `Four overrides` → `Five overrides`;
its preamble's "Override 4 disables that skill's per-task review loop" keeps its
number, so no other reference moves.

## What this does not do

- No size threshold. See "Always, never conditionally".
- No new scripts. The override is prose in templates this repository owns.
- No changes to `superpowers:writing-plans` or
  `superpowers:subagent-driven-development` themselves. Both are consumed through
  overrides, as this skill already does for four other rules.

## Known limits

1. **The executor loses the deep cross-task conflict scan.** It scans the ledger
   only. Nothing catches two task files that contradict each other before
   execution starts; the phase's single whole-branch review is the net. Accepted
   deliberately — the scan's only action was a question nobody is present to
   answer.
2. **A planner that ignores the override degrades silently.** It writes one
   `plan.md` holding every task, the executor reads it whole, and the run
   succeeds at the old cost. Nothing detects this; the saving is a convention,
   not a mechanism.
