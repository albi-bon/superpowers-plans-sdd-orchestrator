# Building Phased Specs in Parallel — Design Spec

**Date:** 2026-10-02
**Scope:** a fourth skill, `building-phased-specs-in-parallel`, living beside
`building-phased-specs` in this repository and sharing its scripts.
**Status:** approved shape, not yet planned.

### How to use this document

§1–§5 are the design. §6 is the decision log — an implementation phase that wants to
deviate from a decision must amend §6 first and say why. §7 splits the build into four
phases and declares their dependencies, so this document is also a valid input to the
skill it describes. §8 records what carries over unchanged from
`2026-09-22-building-phased-specs-design.md`, so this document does not repeat it.

---

## 1. Summary

`building-phased-specs` runs phases one at a time in a single checkout. Each phase forks
from the current base tip, and base advances only through that phase's merge, so a
merge conflict cannot arise. The price is wall-clock time: on a design document whose
phases form a graph rather than a chain, independent phases still wait for each other.

`building-phased-specs-in-parallel` keeps every per-phase mechanism of
`building-phased-specs` — scout, brief, phase lead, workers, one review, fix wave,
verifier with acceptance check, decision policy, testing policy, resumable ledger, thin
controller — and adds:

1. a **dependency graph**, read from `Depends on` lines in the design document, or
   normalised by a graph agent when the document states it differently;
2. a **scheduler** that starts every phase whose dependencies are merged, up to a cap of
   concurrent phases (default 3), each in its own **git worktree**;
3. a **runtime independence check**: a phase the document calls independent is held
   back when its scout finds it needs something an in-flight phase is building, or when
   an overlap judge finds it and an in-flight phase both making major changes to the
   same domain. Shared files alone only send the phase to the judge;
4. **batch integration**: built phases queue, and whenever the verifier is free every
   queued phase is merged onto one batch branch off base, textual conflicts are resolved
   by a resolver agent, the combined tree is verified once — gates, acceptance check,
   and a pin on the phase behind any failure — and only then lands on base, so base
   only ever holds verified trees (amended, §3.6);
5. an **escalation ladder** — repair, then rescue — before a failing phase stops the
   run, and a **drain** instead of an immediate halt: nothing new starts, in-flight
   phases finish and land, then the run stops;
6. **pushes and a pull request** (amended, §3.9): each finished phase branch and every
   landed base is pushed to `origin`, and the run ends by opening a pull request from
   base, after a final full-suite check when the last batch did not run every suite.

It runs unattended, like `building-phased-specs`. Nobody is asked anything after
preflight.

---

## 2. Scope

### In scope

- The `building-phased-specs-in-parallel` skill: `SKILL.md`, dispatch templates, policy
  files, platform guide, wrapper scripts.
- New shared scripts: `parse-deps`, `phase-state`, `phase-schedule`, `phase-overlap`,
  `phase-worktree`, `phase-batch`, `phase-land`, `phase-push`, `phase-pr` (§4). The
  original `phase-integrate`, which merged base into one phase, was removed when batch
  integration replaced it.
- A run-directory namespace, `phase-parallel`, so this skill never shares a ledger with
  the other three.
- `install.sh` learns the `parallel` skill argument.
- Cross-referencing descriptions so loose phrasing still routes to
  `building-phased-specs` and this skill fires on explicit request (§4.10).

### Out of scope

- **Changing the other three skills' behaviour.** `building-phased-specs` gains one
  sentence in its description; nothing else in it changes.
- **Parallel tasks inside one phase.** The phase lead still runs its workers one at a
  time. Parallelism is between phases only.
- **Semantic independence analysis beyond shared files.** The runtime check starts from
  shared files, judged by the overlap judge, plus the scout's judgement (§3.4). Coupling
  through unchanged files is caught by the integration gates, not predicted.
- **Retrying a drained run automatically.** Re-invoking is the retry (§4.8).
- Everything `building-phased-specs` already excludes except pushing and opening a PR
  (§3.9): merging into trunk, per-repository configuration, authoring the design
  document.

---

## 3. Architecture

### 3.1 The loop

The main checkout stays on `BASE` for the whole run. The controller and every script
run there. Each phase gets a branch `phase-<N>-<slug>` and a worktree at
`<repo>/.worktrees/phase-<N>-<slug>/`; every agent working on that phase works only
inside that worktree.

```
preflight                                    (shared checks + worktree checks)
graph:  parse-deps → graph.tsv               (graph agent if the doc has no Depends on lines)
loop until phase-schedule reports nothing running and nothing to do:
    phase-schedule → actions: land K | verify K | build K | fail N | repair N | rescue N
                              | batch N@sha … | rescout N | start N | wait | done
      start N      → phase-worktree start N → ① scout
      rescout N    → phase-worktree refresh N → ① scout
      batch …      → phase-batch open (§3.6)
      build K      → phase-batch build K
      verify K     → integration verifier on batch K
      land K       → phase-land K (pushes base)
      repair/rescue N → ladder (§3.7)
    when any agent returns, advance its phase or batch:
      ① scout done   → phase-overlap N  → clear: ② phase lead │ prereq: held
                                           │ overlap: judge → run: ② │ hold: held
      ② lead DONE    → queued; phase-push N
      resolver / integration verifier → §3.6
final check (unless the last batch ran every full suite), report, phase-pr (§3.9; draft
when a phase did not land or the final check failed)
```

Agents are dispatched in the background; the controller waits for completion
notifications rather than blocking on one agent. Events are handled one at a time, so
two phases never pass the overlap check or the integration step at the same moment.

### 3.2 Agent topology

```
main session (controller)
├─ Agent: graph                  once, only when the doc has no Depends on lines
├─ per in-flight phase (up to CAP at once):
│  ├─ Agent: scout
│  ├─ Agent: phase lead
│  │  ├─ Agent: task worker      one per task, sequential
│  │  ├─ Agent: reviewer         once
│  │  └─ Agent: fix worker       one per finding group, at most one wave
│  ├─ Agent: repair              ladder attempt 1
│  └─ Agent: rescue              ladder attempt 2
├─ for the open batch (one at a time):
│  ├─ Agent: resolver            only on a textual conflict merging a phase in
│  └─ Agent: integration verifier  the batch's one verification; also the final check
```

Three agent levels, as in `building-phased-specs`. Only the phase lead nests. At most
one agent runs per phase at the controller level, plus the lead's one worker; the open
batch adds one, for phases that count against the cap and run nothing themselves, so
the host must allow `1 + 2 × CAP` concurrent agents.

### 3.3 Models

| Dispatch | Tier |
|---|---|
| scout, phase lead, reviewer, repair, rescue, resolver | most capable |
| task worker | the brief's tier: mid-tier for `Tier: mechanical`, most capable otherwise |
| fix worker | most capable |
| integration verifier, graph agent | mid-tier |

Tiers resolve to host models through the platform guide (`opus` / `sonnet` on Claude
Code). Every dispatch names its model explicitly.

### 3.4 Scheduling and the independence check

**Ready.** A requested phase is ready when every dependency in the graph is merged to
base (or lies outside the requested range — §3.5), it has not started, the run is not
draining, and fewer than `CAP` phases are in flight. `phase-schedule` emits ready phases
in ascending numeric order.

**In flight** means started and not yet merged, not held, and not failed. A phase
waiting in the integration queue is in flight; a held phase is not, since it runs no
agent.

**Cap.** Default 3. The invocation may override it: `… up to 4 in parallel`. A cap of 1
reproduces `building-phased-specs`' sequential order, in worktrees.

**Independence check.** After a phase's scout returns, `phase-overlap` compares that
phase against every other in-flight phase:

- **File overlap.** The paths on the new brief's `Files:` lines, against each in-flight
  phase's brief `Files:` paths and its actual `git diff --name-only <fork>..HEAD`.
  Files integration settles by regenerating or merging never count: lockfiles,
  translation catalogues, generated agent-instruction files, markdown docs and rules,
  generated code, ORM migration metadata, and tests (the list is in the script's
  header). An owner adds patterns in `.phase-overlap-ignore` at the repository root or
  `overlap-ignore` in the run directory; `!` re-includes.
- **In-flight prerequisite.** The scout is given the list of in-flight phases with their
  titles. If grounding finds a prerequisite missing from the repository that one of them
  is building, it returns `prereq-inflight: phase <M>`.

An in-flight prerequisite **holds** the phase: `phase-overlap` appends
`phase <N>: held — waits on phase <M> (prereq-inflight)`. A file overlap is a signal,
not a verdict: merge conflicts are integration's job. `phase-overlap` prints
`overlap <M>[,<M>…] <paths>`, writes every pair to `phase-<N>-overlap.tsv`, and the
controller dispatches the **overlap judge** (`overlap-judge-prompt.md`, most capable,
read-only). It reads both sides' briefs and writes `phase-<N>-overlap-verdict.md`. It
holds only when both phases make a major change to the same domain — both reshape the
same data model, state machine, store shape or core function's contract — and runs when
unsure. `RUN` appends `phase <N>: overlap judged — runs beside phase <M> (<reason>)`,
which keeps the phase active; `HOLD <M>` appends
`phase <N>: held — waits on phase <M> (domain: <reason>)`. A clear result appends
nothing and the controller dispatches the phase lead.

**Release.** When phase M lands, `phase-schedule` emits `rescout N` for every phase held
on M. A held phase has a brief and no commits, so `phase-worktree refresh` fast-forwards
its branch to the new base tip and the scout runs again; it updates the existing brief
against the new base. The overlap check then runs again. A `rescout` counts against the
cap like a `start`. A phase held on a phase that fails is never released and is reported
as held.

The later of two clashing phases is always the one held: the earlier one was clear when
it was checked. A held phase is never checked against another held phase, so holds
cannot form a cycle.

### 3.5 The dependency graph

**Source of truth: the design document.** `parse-deps` reads each phase section, from
its heading to the next phase heading, for one line of these shapes (bold optional,
case-insensitive, `Phase` prefix optional):

```
**Depends on:** Phase 2, Phase 3
Depends on: 2, 3
**Depends on:** none
```

- At least one phase has a `Depends on` line: a phase without one depends on the phase
  with the next lower number in the document. The first phase depends on nothing.
- No phase has one: the controller dispatches the **graph agent** once. It reads the
  whole document — a dependency section, table, diagram or prose — and writes
  `<run-dir>/graph.tsv`. Its result is listed among the run's significant decisions.
- Either way the canonical graph is `<run-dir>/graph.tsv`, one line per phase:
  `<N><TAB><comma-separated deps or -><TAB><source>`, where source is
  `line` (from a `Depends on` line), `default` (the next-lower rule) or `agent`.
- `parse-deps --validate` refuses a cycle, a dependency on a phase number absent from
  the document, and a self-dependency.
- A dependency outside the requested range counts as satisfied. It is logged in the
  ledger; if the work is actually missing, the scout's grounding finds it and records
  the resolution.
- The ledger records the graph once:
  `graph: 2→{} 3→{2} 4→{2} 5→{3,4} (source: line)`.

On resume the existing `graph.tsv` is reused, never regenerated.

### 3.6 Integration

Amended (batch integration). The original design integrated **one phase at a time**:
base was merged into the phase branch in its worktree, the integrated phase was
verified, and it landed, before the next queued phase began. When several phases
finished during one verification, each then paid for its own run of the slow suites.
They are now integrated in batches.

**Queue and batch.** A phase whose lead returned `DONE` queues. While a batch is being
built or verified, phases that finish queue up. When no batch is open, `phase-schedule`
emits `batch` with every queued phase, in queue order. It never waits for more phases:
a lone queued phase goes alone. At most one batch is open, and base moves only when a
batch lands, so base cannot move under a batch. Other phases keep building meanwhile.

1. `phase-batch open N@SHA …` checks each phase branch is at its queued SHA, records
   `batch <K>: opened — phases <N>@<sha> …`, and creates `phase-batch-<K>` at the base
   tip in one integration worktree, `<repo>/.worktrees/integration`, reused by every
   batch so its installed dependencies carry over. It merges the phases onto the batch
   branch one after another, each with `git merge --no-ff <sha> -m "merge: phase <N> —
   <title>"` — the subject base's history has always used, so a landed batch reads on
   base exactly like phases landed one by one. It prints:
   - `built K <sha>`: every phase is in; go to step 3;
   - `conflict K N M,…`: the merge of phase N is left in progress; the conflicted paths
     and the phases on the other side (merged into base since N forked, then earlier
     in the batch) are in `<run-dir>/phase-<N>-conflicts.md`; go to step 2;
   - `empty K`: every phase left the batch.
2. **Resolver.** Works in the integration worktree with the merge in progress. Reads the
   conflicts file, phase N's brief and decisions, and each other-side phase's brief and
   decisions. Keeps the behaviour of both sides. Regenerates lockfiles, generated files
   and migration metadata with the repository's own commands. Runs fast checks on the
   touched files. Commits the merge. Records decisions in phase N's decisions file.
   Returns `RESOLVED <sha>` — `phase-batch build K` carries on — or `UNRESOLVED` after
   `git merge --abort`: phase N leaves the batch, which carries on without it, and goes
   to the rescue once the batch closes (§3.7).
3. **Integration verifier**, once per batch: every gate the repository has — typecheck,
   lint, the root test suite, a separate integration suite needing a database or
   Docker, an end-to-end suite when its infrastructure can be started, build — and the
   acceptance check on every batch phase's deliverables. It reinstalls dependencies
   only when a manifest or lockfile changed since the integration worktree's last
   install. `full suite: once per phase` skips a slow suite every batch phase already
   had run in an earlier batch. On a failure it **pins** each failing item on a phase:
   a missing acceptance item on its phase; a failing test or check on the phase whose
   merge commit changed the files the failure points at, when exactly one batch phase
   did. In a batch of one, every failure is pinned on it. It appends to
   `batch-<K>-evidence.md` and returns PASS or FAIL with the SHA, whether every full
   suite ran, and the pin.
4. **PASS** → `phase-land K SHA` fast-forwards base to the batch tip (§4.6) and pushes
   base. **FAIL, pinned** → the pinned phases go to the ladder; the batch's other phases
   queue again and form the next batch, verified again without them, so base never
   holds a tree that was not itself verified. **FAIL, not pinned** → every phase of the
   batch queues again flagged `solo` and is verified alone, earliest first; the one
   that fails alone is pinned by definition. A phase requeued after a repair that
   returned `STILL_BROKEN`, or by an owner fix on resume, is also verified alone, so it
   cannot fail a batch. A failed batch with one phase left in it is pinned on that
   phase whatever the verdict, so a solo batch can never loop.
5. A script refusal on a built or passed batch — base moved under it, the batch branch
   moved — records `batch <K>: abandoned — <reason>`; its phases queue again, unflagged.
   `phase-batch` discards tracked changes a verifier left in the integration worktree,
   and aborts a merge of its own it never recorded, so a crash there cannot wedge the
   run. `phase-land` re-run after an interrupted landing finishes recording it.

The original design rejected landing several phases under one shared check because it
"puts unverified trees on base and blurs which phase failed". Batch integration keeps
both properties: a batch lands only on its own PASS, a failure is pinned before anything
lands, and an unclear failure splits the batch rather than guessing.

### 3.7 The escalation ladder

Every phase has a budget of **two attempts**, each followed by verification in a later
batch. Both repair and rescue first merge the current base into the phase branch, so
they work on the tree the phase will next be verified on; an attempt starts only when no
batch is open and the phases that shared the failing batch have landed or moved on.

| Attempt | Agent | Mandate |
|---|---|---|
| 1 | **repair** | Scoped fix of what the evidence names. Never weakens, skips or deletes the check that caught it. |
| 2 | **rescue** | Fresh eyes with a wider mandate: reads both evidence files, the repair's report, the brief and decisions. May change approach, rework a task, re-scope against the current base, build a missing prerequisite, or redo the integration merge. Every departure from the brief is significant. |

- Batch FAIL pinned on the phase → repair → requeued, verified in a later batch →
  rescue → requeued, verified → drain.
- Resolver `UNRESOLVED` → rescue directly, if unused. A repair is a scoped fix and an
  unresolved merge is not one. The rescue merges base, which by then holds the phases
  it clashed with, and resolves the conflicts itself.
- Budget spent and still failing → the phase is **failed** and the run **drains**.

The ledger records each start before the dispatch:
`phase <N>: repair — started (attempt 1/2)`, `phase <N>: rescue — started (attempt 2/2)`.

### 3.8 Drain

Draining means: `phase-schedule` emits no `start` and no `rescout`; every in-flight phase
continues through integration and verification and lands; then the run stops and
reports. Base ends at the last landed phase, verified. Phases that depend on the failed
phase never start. Held phases waiting on it stay held.

Drain triggers:

- a phase's ladder is exhausted;
- `BLOCKED` from a scout, phase lead, resolver or rescue (the decision policy's list);
- a non-zero exit from `phase-worktree`, `phase-batch` or `phase-land`.

The controller appends `run: draining — phase <N> <reason>` before anything else.

A preflight refusal stops the run before anything starts, as today.

### 3.9 Pushing and the pull request

Added with batch integration.

- When a phase lead returns `DONE`, and when a repaired phase is requeued, `phase-push`
  pushes its branch to `origin` as a backup.
- `phase-land` pushes base after every landed batch.
- A failed push is recorded (`push: <branch> failed — …`) and never fails a phase; the
  next push of that branch retries. Nothing is ever force-pushed.
- On `done`: a **final check** — the integration verifier in `final` mode on the base
  tip, every gate and every slow suite, no acceptance check — unless the last landed
  batch already ran every full suite on exactly that tree. Then the report, then
  `phase-pr`, which pushes base and opens a pull request from base into `PR_TARGET`
  (`pr into <branch>` in the invocation, otherwise origin's default branch) with the
  report as its body. It is a draft when a requested phase did not land or the final
  check failed; the report names the failure. An open pull request from base is reused
  on resume. The run never merges it.
- Preflight refuses a repository with no `origin` remote.

---

## 4. Mechanics

### 4.1 Paths

| Artifact | Path |
|---|---|
| Run directory | `<repo>/.superpowers/phase-parallel/<spec-basename>/` |
| Ledger | `<run-dir>/run.md` |
| Graph | `<run-dir>/graph.tsv` |
| Brief, decisions, task/fix reports, review, evidence | as in `building-phased-specs` |
| Conflicts | `<run-dir>/phase-<N>-conflicts.md` |
| Batch evidence | `<run-dir>/batch-<K>-evidence.md`; the final check's is `final-evidence.md` |
| Integration setup marker | `<run-dir>/integration-setup` |
| Report (PR body) | `<run-dir>/report.md` |
| Rescue report | `<run-dir>/phase-<N>-rescue-report.md` |
| Worktree | `<repo>/.worktrees/phase-<N>-<slug>/` |
| Phase branch | `phase-<N>-<slug>` |
| Integration worktree | `<repo>/.worktrees/integration/` |
| Batch branch | `phase-batch-<K>` |

The run directory lives in the main checkout. Agents in worktrees reach it by absolute
path; worktrees hold code only.

`phase-worktree` creates `<repo>/.worktrees/` with a self-ignoring `.gitignore`
containing `*`, the same technique `phase-run-dir` uses. Nothing under `.git/` is edited
by hand and no tracked file changes.

### 4.2 Worktree setup

A fresh worktree has no installed dependencies. The invocation may pass
`setup: <command>` (e.g. `setup: pnpm install --frozen-lockfile`). The scout runs it in
the worktree before grounding; without it, the scout discovers the install step from the
repository's manifests and documentation, and records what it ran in the brief's Notes
under Global constraints so verifiers can repeat it. A re-scout after a hold skips setup
unless the refresh changed a manifest or lockfile.

### 4.3 Templates

The building skill's templates are copied into the new skill directory and changed:

| Template | Change |
|---|---|
| `scout-prompt.md` | `REPO_ROOT` becomes `WORKTREE`. Runs setup (§4.2). Reads the decisions files of phases already merged to base — their code is what it grounds against — and never those of in-flight phases. Receives `IN_FLIGHT_PHASES`. Return gains `prereq-inflight: phase <M>` or `prereq-inflight: none`. |
| `lead-prompt.md`, `worker-prompt.md`, `reviewer-prompt.md` | `REPO_ROOT` becomes `WORKTREE`. Each states: never touch the main checkout, `BASE`, or another phase's worktree or branch. |
| `repair-prompt.md` | Merges base into its phase branch first, then fixes the failures the batch evidence pins on its phase. Optional integration context: the briefs and decisions of the phases batched beside it. |
| `rescue-prompt.md` (new) | §3.7. Like the repair, merges base into its phase branch, here with a wider mandate. Return: `FIXED` or `STILL_BROKEN`, root cause, commands re-run with exit codes, commit SHAs, significant count. |
| `resolver-prompt.md` (new) | §3.6 step 2, in the integration worktree. Return: `RESOLVED <sha>` or `UNRESOLVED`, conflicted file count, significant count. |
| `integration-verifier-prompt.md` (new) | §3.6 step 3; absorbs `verifier-prompt.md`'s acceptance check, which has no separate template here. Pins failures; has a `final` mode. Return: `PASS` or `FAIL` plus SHA, full suites run, pin, one-line reason, evidence path. |
| `graph-prompt.md` (new) | §3.5. Writes `graph.tsv`. Return: path, phase count, edge count. Edits nothing else. |
| `decision-policy.md` | Adds the worktree boundary rule. `BLOCKED` list unchanged. |
| `testing-policy.md` | Unchanged. |

Every return contract stays capped, and every template forbids pasting artifacts into its
return, exactly as in `building-phased-specs`.

### 4.4 The ledger

Same identity header and append-only rule. New and changed lines:

```markdown
# Phase run — spec: /repo/docs/specs/…-design.md
# base: feat/thing  requested: 2-6

run: invoked — cap 3
graph: 2→{} 3→{2} 4→{2} 5→{3,4} 6→{5} (source: line)
phase 2: started — branch phase-2-shell, worktree .worktrees/phase-2-shell
phase 2: scout dispatched
phase 2: grounded — brief phase-2-brief.md, 6 tasks, 3 drift, 1 significant
…
phase 4: held — waits on phase 3 (domain: both reshape the session store)
phase 3: merged to base (4c5d6e7)
phase 4: released — phase 3 merged
push: phase-5-billing at 1f2e3d4
batch 3: opened — phases 4@0a1b2c3 5@1f2e3d4
phase 4: batched — batch 3, clean merge 1a2b3c4
phase 5: batched — batch 3, conflict in 3 files
phase 5: resolved 5d6e7f8
batch 3: built 5d6e7f8
batch 3: verified PASS — full suites all — 5d6e7f8
phase 4: merged to base (1a2b3c4)
phase 5: merged to base (5d6e7f8)
batch 3: landed (5d6e7f8)
push: feat/thing at 5d6e7f8
run: draining — phase 6 ladder exhausted
run: final check skipped — batch 3 ran every full suite
run: PR https://github.com/acme/app/pull/42
```

The controller appends `phase <N>: <role> dispatched` before every dispatch. With
several agents in flight, these lines are how a compacted controller knows what it is
still waiting for, and how a resumed run knows what to re-dispatch.

The identity header is the shared one, unchanged. Each invocation appends
`run: invoked — cap <CAP>`; a resume may change the cap, and the latest line applies.
A failed phase is recorded as `phase <N>: failed — <reason>` before the run's
`run: draining` line; a drain lifted on resume is recorded as
`run: undrained — phase <N> verified PASS`.

### 4.5 `phase-worktree`

`phase-worktree DESIGN_DOC BASE <subcommand> [N]`

| Subcommand | Behaviour |
|---|---|
| `start N` | Refuses a phase the ledger records as merged. Branch absent: `git worktree add -b phase-<N>-<slug> <path> BASE`, appends `started`. Branch present and the ledger accounts for it: re-attaches it (`git worktree add <path> <branch>`), after `git worktree prune` if a stale entry exists. Branch present and unknown to the ledger: refuses. Prints the worktree path. Idempotent. |
| `refresh N` | Refuses if the branch has commits beyond its fork point. Fast-forwards the branch to `BASE`. Appends `released`. |
| `check` | Refuses (non-zero, names the path) when any phase worktree of this run is dirty, or when the integration worktree has uncommitted changes to tracked files other than a resolver's merge in progress for the open batch. |
| `remove N` | `git worktree remove` for a landed phase. Keeps the branch. |
| `path N` | Prints the worktree path. |

### 4.6 `phase-land`

Amended (batch integration). `phase-land DESIGN_DOC BASE K VERIFIED_SHA`, run in the main
checkout on `BASE`:

1. Refuses a dirty main checkout.
2. Refuses if the batch branch `phase-batch-<K>` is not at `VERIFIED_SHA`.
3. Refuses if the base tip is not an ancestor of `VERIFIED_SHA`.
4. Refuses unless `phase-state` reports batch K `landable` at `VERIFIED_SHA`: a
   `batch <K>: verified PASS … — <sha>` line for that commit.
5. `git merge --ff-only phase-batch-<K>`: base ends at exactly the verified commit.
6. For every `merge: phase <N> — …` commit brought in, appends
   `phase <N>: merged to base (<sha>)` and a metrics line, and removes that phase's
   worktree, keeping its branch. Appends `batch <K>: landed (<sha>)`, then pushes base.

Failed and drained phases keep their worktrees for inspection.

### 4.7 The scheduling and integration scripts

`phase-state DESIGN_DOC` reads the ledger and prints each started phase's status —
`active`, `held`, `queued`, `batched`, `failing`, `merged` or `failed`, with ladder
attempts used, a flag (`solo` for a queued phase, the next ladder step for a failing
one) and its batch — then each batch's status: `open`, `conflict`, `built`,
`landable`, `landed`, `failed` or `empty`, with its members and whether every full
suite ran. An `executed` line queues a phase; so does a `verified PASS` line from the
original flow. `phase-schedule`, `phase-overlap`, `phase-batch`, `phase-land` and
`phase-worktree check` all read the ledger through it, so they cannot disagree.

`phase-schedule DESIGN_DOC BASE RANGE CAP` reads `graph.tsv` and `phase-state` and
prints one action per line: `land <K> <sha>`, `verify <K> <sha>`, `build <K>`,
`fail <N>`, `repair <N> <sha>`, `rescue <N> <sha>`, `batch <N>@<sha> …`,
`rescout <N>`, `start <N>`, then `wait` if anything is in flight, or `done` if nothing
is. It never mutates anything.

`phase-overlap DESIGN_DOC BASE N [PREREQ_PHASE]` implements §3.4. It takes the scout's
`prereq-inflight` value as its optional argument, so both signals are decided and
recorded in one place. Prints `clear`, `held <M> prereq-inflight`, or
`overlap <M>[,<M>…] <paths>` for the overlap judge.

`phase-batch DESIGN_DOC BASE open N@SHA … | build K | final` implements §3.6 steps 1–2
and puts the integration worktree on the base tip for the final check. Idempotent: re-run
after an interruption, a merge in progress prints the same `conflict` line, and a phase
already in the batch branch is skipped.

`phase-push DESIGN_DOC BASE N|base` and `phase-pr DESIGN_DOC BASE TARGET|- BODY [draft]`
implement §3.9.

All new scripts follow the shared portability rules: bash 3.2, BSD `awk` and `sed`, no
`\s`, no interval expressions, no bracket expressions over multibyte dashes.

### 4.8 Resume

Re-invoking with the same spec and base is the resume. Preflight refuses a ledger from
another spec or base, as today, and additionally runs `phase-worktree check`.

- Each phase's state comes from its last ledger line and Git, as in
  `building-phased-specs`, plus:
- A role `dispatched` with no outcome line: re-dispatch it. The scout completes an
  existing brief; the lead resumes from ticked tasks; the resolver continues a merge in
  progress.
- A started phase whose worktree directory is gone: `phase-worktree start` re-attaches.
- An open batch with no outcome line: `phase-batch build` again; it is idempotent.
- Ladder attempts already started stay consumed.
- `run: draining` recorded: the failed phase is requeued at its HEAD first, in case the
  owner fixed it by hand, and batched alone and verified again. `PASS` appends `run: undrained — phase <N> verified PASS` and normal
  scheduling resumes; `FAIL` drains again without a new attempt.
- A dirty main checkout or a dirty phase worktree fails preflight and is named. Never
  stash, discard or commit an interrupted agent's changes.

### 4.9 The report

```
RUN COMPLETE — phases 2–6 of …-design.md
graph: 2→{} 3→{2} 4→{2} 5→{3,4} 6→{5} (source: line)   cap 3

phase 2  merged  a1b2c3d..4c5d6e7  review 0/2/5  2 fixed  5 deferred  batch 1 (alone)
phase 3  merged  …                 review 1/1/2  batch 2 failed on 4, landed in batch 3
phase 4  merged  …                 held on 3 (domain: both reshape the session store)  verified after repair
phase 5  FAILED  ladder exhausted — evidence …, worktree .worktrees/phase-5-…
phase 6  not started (depends on 5)

batches: 5 built, 4 landed, 1 failed (pinned)
final check: skipped — batch 4 ran every full suite
base feat/thing pushed at 7a8b9c0

significant decisions (audit these):
  graph: <line, when the graph agent built it>
  phase 3: <decision line>
  …

run directory: <run-dir>
pull request: <url> (draft: phase 5 did not land)
```

### 4.10 Invoking the right skill

- **Deterministic:** `/building-phased-specs-in-parallel phases 2 to 6 of <doc> on
  branch feat/x [up to N in parallel] [setup: <command>]`. Codex:
  `$building-phased-specs-in-parallel …`.
- **Loose phrasing** keeps routing to `building-phased-specs`. This skill's description
  fires when the user asks for phases in parallel, concurrently, or in worktrees, or
  names it. `building-phased-specs`' description gains: *"For running independent
  phases in parallel worktrees, use building-phased-specs-in-parallel instead."*

---

## 5. Repository structure

```
shared/scripts/
  parse-phases  phase-run-dir  phase-preflight  phase-start  phase-finish
  parse-deps  phase-state  phase-schedule  phase-overlap  phase-worktree  phase-batch
  phase-land  phase-push  phase-pr
  __tests__/
skills/building-phased-specs-in-parallel/
  SKILL.md
  scout-prompt.md  lead-prompt.md  worker-prompt.md  reviewer-prompt.md
  verifier-prompt.md  repair-prompt.md  rescue-prompt.md  resolver-prompt.md
  integration-verifier-prompt.md  graph-prompt.md
  testing-policy.md  decision-policy.md  platform-guide.md
  scripts/   thin wrappers, namespace phase-parallel:
             parse-phases  phase-run-dir  phase-preflight  parse-deps  phase-state
             phase-schedule  phase-overlap  phase-worktree  phase-batch  phase-land
             phase-push  phase-pr
```

The wrapper `phase-preflight` refuses a repository with no `origin` remote, runs the
shared preflight, then `phase-worktree check`.
Every other wrapper is the existing three-line shape. The skill has no `phase-start` or
`phase-finish` wrapper: both switch branches in the main checkout, which this skill
never does.

---

## 6. Decision log

| # | Decision | Rationale |
|---|---|---|
| **D1** | **A sibling skill, not a mode of `building-phased-specs`.** | Owner's call. A mode would put worktree paths, scheduling, integration and the ladder into every step of the sequential skill, the everyday path. Duplicated templates are the cost; structural tests keep the shared sections aligned. |
| **D2** | **Dependencies are declared in the document**, by per-phase `Depends on` lines; a graph agent normalises other formats. | Owner's call. Most design documents already carry the graph. A declared graph is deterministic and auditable; the agent covers documents that state it another way. |
| **D3** | **A phase without a `Depends on` line depends on the previous phase.** | Sequential is the safe default. A missing line must never create parallelism the author did not declare. |
| **D4** | **Runtime independence check; a clash holds the phase.** | Owner's call, over running anyway and letting the resolver absorb it. The graph says what the author intended; file overlap and in-flight prerequisites say what the repository needs. Holding costs parallelism on that pair only. |
| **D5** | **Worktrees inside the repository**, under a self-ignoring `.worktrees/`. | Owner's call. No extra host write permissions for unattended runs. All gates run inside worktrees, so the main checkout's tools do not crawl them during the run. |
| **D6** | **Setup per worktree: an invocation `setup:` command, else the scout discovers it.** | Owner's call. A fresh worktree is not runnable; the repository, not this skill, knows how to install. |
| **D7** | **Integration merges base into the phase branch**, in the worktree, before landing. | Conflicts are resolved where the phase's agents work, by an agent that can read both sides, and base never holds an unverified tree. |
| **D8** | **Gates re-run whenever base moved since the fork**, clean merges included. | Owner's call. A clean textual merge can still be semantically broken; without the re-run the break surfaces in a later phase and is blamed on the wrong one. Acceptance is not re-checked: the merge adds only base's verified content. |
| **D9** | **One integration at a time.** | Base moves only through `phase-land`; serialising integration means the SHA being integrated cannot go stale under it. Building continues in parallel; only landing is serial. |
| **D10** | **Two attempts per phase — repair, then rescue — shared across verification and integration.** Replaces "exactly one repair". | Owner's call. With independent phases still progressing, a stuck phase costs less, and a second attempt with a different mandate solves what a scoped fix cannot. A hard cap keeps an unattended run from converging on nothing. |
| **D11** | **Drain, not halt.** | Owner's call. In-flight phases do not depend on the failure, so finishing them leaves the most verified work on base; nothing new builds on an unmerged failure. |
| **D12** | **Cap of 3 concurrent phases by default**, overridable at invocation. | Owner's call. Bounds agent count (`1 + 2 × CAP`), rate limits, disk and install cost. |
| **D13** | **Scheduling decisions live in a script, `phase-schedule`, that reads only the ledger and graph.** | With several agents in flight, a compacted controller is more likely to lose its place. A pure function of on-disk state cannot. |
| **D14** | **Lockfiles are excluded from the overlap check and regenerated at integration.** | Almost every phase touches them; counting them would serialise every run. They are generated artifacts, not hand-written code. |
| **D15** | **File overlap is a signal; an overlap judge decides.** Amends D4. Translation catalogues, generated files, docs and rules, migration metadata and tests are excluded like lockfiles; owners add patterns per repository. | Owner's call, from a live run in a monorepo: nearly every phase shared some file and the file-level check serialised the run. Conflicts are integration's job; what must be avoided is two phases making major changes to the same domain. |
| **D16** | **Batch integration.** Amends D7 and D9. Every phase queued while a verification runs is merged onto one batch branch off base and verified together, once; a lone queued phase goes alone. | Owner's call. Phases often finish during one verification, and each then paid for its own run of the slow suites. One batch at a time keeps D9's guarantee that base cannot move under an integration. |
| **D17** | **A batch failure is pinned on a phase; the rest are rebuilt and verified again without it.** An unpinned failure verifies each phase alone. | Owner's call, over landing the rest unverified. Base only ever holds a tree a verifier passed; a wrong guess would land the broken phase. |
| **D18** | **Repair and rescue merge base into their phase branch and start only after the failing batch's other phases land.** | The attempt then fixes the tree the phase will next be verified on, including the phases it failed beside. Replaces integrating each phase alone before its verification. |
| **D19** | **The run pushes and opens a pull request.** Amends the carried-over "no push, no PR". Phase branches are pushed when built, base after every landing; a final full-suite check runs unless the last batch already ran every suite on that tree; the pull request is a draft when a requested phase did not land, and is never merged. | Owner's call. Pushes back up unattended work as it lands; the pull request is the hand-off to a human. |

---

## 7. Implementation phases

Phases 1 to 3 touch disjoint files and can run in parallel.

### Phase 1 — Graph and scheduling scripts

**Depends on:** none

**Goal:** the run knows its dependency graph and can decide, from disk alone, what to do
next.

**Add**
- `shared/scripts/parse-deps` (§3.5), including `--validate`.
- `shared/scripts/phase-schedule` (§4.7).
- `shared/scripts/phase-overlap` (§3.4, §4.7).
- Their tests, and wrappers in `skills/building-phased-specs-in-parallel/scripts/` for
  these three plus `parse-phases` and `phase-run-dir` (namespace `phase-parallel`).

**Constraints**
- Shared portability rules (§4.7).
- `phase-schedule` mutates nothing.

**Verification**
- `parse-deps`: each accepted line shape; bold and plain; `none`; missing-line default;
  no lines at all reports that the graph agent is needed; cycle, self-dependency and
  unknown dependency refused; out-of-range dependency treated as satisfied.
- `phase-schedule`: ready set respects dependencies, cap, holds and drain; ascending
  order; at most one `integrate`, none while one is open; `rescout` after the blocker
  lands; `done` and `wait` correct.
- `phase-overlap`: brief-vs-brief clash, brief-vs-diff clash, lockfile ignored,
  `PREREQ_PHASE` holds, clear appends nothing, held phases are not compared against.
- `shellcheck` clean; suite passes under macOS `/bin/bash`.

**Done when:** given a ledger and a graph, the scripts print the actions §3.4 and §4.7
describe.

### Phase 2 — Worktree and integration scripts

**Depends on:** none

**Goal:** phases live in worktrees, and a verified phase lands on base only as a
verified tree.

**Add**
- `shared/scripts/phase-worktree` (§4.5), `shared/scripts/phase-integrate` (§3.6, §4.7),
  `shared/scripts/phase-land` (§4.6).
- The skill's `phase-preflight` wrapper (shared preflight, then `phase-worktree check`)
  and wrappers for the three new scripts.
- Their tests, in temporary repositories.

**Constraints**
- Shared portability rules.
- No script switches the main checkout off `BASE` or edits anything under `.git/` by
  hand.

**Verification**
- `phase-worktree`: create; idempotent re-run; re-attach after the directory is deleted;
  refuse an unknown branch; `refresh` refuses a branch with commits; `check` names a
  dirty worktree; `.worktrees/` stays out of `git status`.
- `phase-integrate`: `ready` when base never moved; `merged` on a clean merge; `conflict`
  with the conflicts file listing paths and merged phases; idempotent on re-run.
- `phase-land`: refuses dirty tree, wrong HEAD, and a base that moved; lands with a
  `--no-ff` commit whose tree equals the verified tree; removes the worktree and keeps
  the branch; on forced failure leaves base unchanged.
- `shellcheck` clean.

**Done when:** a scripted two-phase scenario with a deliberate conflict runs start →
integrate → (manual resolution) → land with base correct at every step.

### Phase 3 — Templates and policies

**Depends on:** none

**Goal:** every agent of the skill has a template that says exactly what it may and may
not do, in a worktree.

**Add**
- The copied and changed templates and the four new ones (§4.3), the two policies.

**Constraints**
- Every return contract capped; no artifacts in returns; model tier named on every
  template.
- The `BLOCKED` list verbatim and stated as exhaustive.
- No Superpowers references.

**Verification**
- Structural tests in the style of `building-templates.test.sh`: placeholders,
  `WORKTREE` everywhere `REPO_ROOT` was, boundary rule present, return contracts, caps,
  tiers, `BLOCKED` list.
- A drift test: the sections copied unchanged from `building-phased-specs` still match
  their source.
- Dispatch the resolver for real against a worktree with a two-file conflict: it commits
  a merge that keeps both sides' behaviour and returns within contract.

**Done when:** each new template has been dispatched once and returned within contract.

### Phase 4 — The loop, the invocation, the installer

**Depends on:** Phase 1, Phase 2, Phase 3

**Goal:** `SKILL.md` ties it together, the skill installs, and a real parallel run
completes unattended.

**Add / change**
- `SKILL.md`: invocation, preflight, graph, the loop (§3.1), integration, ladder, drain,
  ledger, resume, report, known limits (§9), common rationalizations.
- `platform-guide.md`: background dispatch and waiting on both hosts; concurrent agent
  capacity `1 + 2 × CAP`; model tiers per §3.3.
- `install.sh` `parallel` argument; `building-phased-specs` description sentence
  (§4.10); README.

**Verification**
- Structural tests for `SKILL.md` and the installer.
- A real run over a small spec with graph `1→{} 2→{1} 3→{1} 4→{2,3}`: phases 2 and 3 run
  concurrently in worktrees, one lands, the other integrates against it, phase 4 starts
  after both, base passes its gates after every landing.
- A spec where phases 2 and 3 are declared independent but touch the same file: 3 is
  held, released after 2 lands, re-scouted, and lands.
- A forced conflict: the resolver resolves it, the integration verifier passes, the
  report says so.
- A forced failure in one of two in-flight phases: repair, rescue, then drain; the other
  phase lands; dependents never start; the report shows both.
- Killing the run with two phases in flight and re-invoking resumes both without
  repeating finished work.
- The controller's context contains no brief text, code, diff or test output.

**Done when:** a real phased spec with independent phases runs end to end unattended
and the ledger reconstructs the run without the session's memory.

---

## 8. Carried over from `building-phased-specs`

These hold unchanged; see `2026-09-22-building-phased-specs-design.md`.

- Thin controller; artifacts in files; capped returns.
- Scout, brief, phase lead, workers, one review, one fix wave, verifier with acceptance
  check — per phase, unchanged in substance.
- Task tiers as the scout assigns them.
- Decision policy, `BLOCKED` list, testing policy.
- Base must not be trunk. No trunk merge. (Pushing and the pull request are added
  here, D19.)
- Phase identity is the heading number, never a position.
- Script portability rules.

Replaced here: single checkout (by worktrees, D5), exactly one repair (by the ladder,
D10), halt (by drain, D11), sequential order (by the graph, D2–D4).

---

## 9. Known limits

Stated in `SKILL.md`, not only here.

1. **Unattended decisions can be wrong**, and now several phases make them at once
   before any lands.
2. **The independence check starts from shared files.** Two phases that never edit the
   same file but depend on each other's behaviour pass it, and the overlap judge can
   call a shared domain minor when it is not; the integration gates catch the break only
   as far as tests cover it.
3. **Cost scales with the cap.** Up to `1 + 2 × CAP` agents run at once; rate limits and
   spend grow with them.
4. **One install per worktree.** Disk and time cost of setup, per in-flight phase.
5. **Nested checkouts under `.worktrees/`** are visible to tools the owner runs in the
   main checkout during a run: test runners and file watchers may need `.worktrees`
   excluded.
6. **One review per phase; the brief is a convention; permissions and nesting depth are
   host-controlled** — as in `building-phased-specs`.
7. **A failed batch costs more verifications**: a pinned failure re-verifies the rest,
   an unpinned one verifies each phase alone, and a rebuilt batch resolves its merge
   conflicts again. A pin by files can miss a phase that breaks another through
   behaviour; the failure is then unpinned and the batch split.
8. **The run pushes** phase branches and base to `origin` as it goes, and opens a pull
   request at the end. It never merges into the target.

---

## 10. Open questions

None. Every question raised during design is resolved in §6.
