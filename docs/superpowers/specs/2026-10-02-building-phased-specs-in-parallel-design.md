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
   back when its brief touches files an in-flight phase touches, or when its scout finds
   it needs something an in-flight phase is building;
4. an **integration step** that merges the moved base into a verified phase branch,
   resolves textual conflicts with a resolver agent, re-runs the gates on the integrated
   result, and only then lands the phase on base — so base only ever holds verified
   trees;
5. an **escalation ladder** — repair, then rescue — before a failing phase stops the
   run, and a **drain** instead of an immediate halt: nothing new starts, in-flight
   phases finish and land, then the run stops.

It runs unattended, like `building-phased-specs`. Nobody is asked anything after
preflight.

---

## 2. Scope

### In scope

- The `building-phased-specs-in-parallel` skill: `SKILL.md`, dispatch templates, policy
  files, platform guide, wrapper scripts.
- New shared scripts: `parse-deps`, `phase-schedule`, `phase-overlap`, `phase-worktree`,
  `phase-integrate`, `phase-land` (§4).
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
- **Semantic independence analysis.** The runtime check is file-level plus the scout's
  judgement (§3.4). Coupling through unchanged files is caught by the integration gates,
  not predicted.
- **Retrying a drained run automatically.** Re-invoking is the retry (§4.8).
- Everything `building-phased-specs` already excludes: pushing, PRs, trunk merges,
  per-repository configuration, authoring the design document.

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
    phase-schedule → actions: start N | rescout N | integrate N | wait | done
      start N      → phase-worktree start N → ① scout
      rescout N    → phase-worktree refresh N → ① scout
      integrate N  → phase-integrate N (§3.6)
    when any agent returns, advance its phase:
      ① scout done   → phase-overlap N  → clear: ② phase lead │ clash: held
      ② lead DONE    → ③ verifier
      ③ PASS         → queued for integration
      ③ FAIL         → ladder (§3.7)
      resolver / integration verifier → §3.6
report
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
│  ├─ Agent: verifier
│  ├─ Agent: repair              ladder attempt 1
│  ├─ Agent: rescue              ladder attempt 2
│  ├─ Agent: resolver            only on a textual conflict at integration
│  └─ Agent: integration verifier
```

Three agent levels, as in `building-phased-specs`. Only the phase lead nests. At most
one agent runs per phase at the controller level, plus the lead's one worker, so the
host must allow `1 + 2 × CAP` concurrent agents.

### 3.3 Models

| Dispatch | Tier |
|---|---|
| scout, phase lead, reviewer, repair, rescue, resolver | most capable |
| task worker | the brief's tier: mid-tier for `Tier: mechanical`, most capable otherwise |
| fix worker | most capable |
| verifier, integration verifier, graph agent | mid-tier |

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
  Lockfiles do not count: `package-lock.json`, `npm-shrinkwrap.json`, `pnpm-lock.yaml`,
  `yarn.lock`, `bun.lockb`, `Cargo.lock`, `go.sum`, `poetry.lock`, `uv.lock`,
  `Gemfile.lock`, `composer.lock`. They are regenerated at integration, never
  hand-merged.
- **In-flight prerequisite.** The scout is given the list of in-flight phases with their
  titles. If grounding finds a prerequisite missing from the repository that one of them
  is building, it returns `prereq-inflight: phase <M>`.

Either signal **holds** the phase: `phase-overlap` appends
`phase <N>: held — waits on phase <M> (<reason>)`. A clear result appends nothing and
the controller dispatches the phase lead.

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

The controller integrates **one phase at a time**, in the order phases reached
`verified PASS`. Other phases keep building meanwhile. Base moves only through
`phase-land`, which the controller never runs while another integration is open, so an
integrated SHA cannot go stale during its own integration.

1. `phase-integrate N VERIFIED_SHA`, in the phase's worktree:
   - refuses a dirty worktree, or a branch HEAD other than `VERIFIED_SHA`;
   - base tip already an ancestor of HEAD — base never moved since the fork: prints
     `ready <sha>`, go to step 4;
   - otherwise runs `git merge --no-ff BASE -m "integrate: base into phase <N>"`:
     - clean: prints `merged <sha>`; go to step 3;
     - conflict: leaves the merge in progress, writes the conflicted paths and the
       phases merged into base since the fork (read from `merge: phase <M> — …` commit
       subjects) to `<run-dir>/phase-<N>-conflicts.md`, prints `conflict`; go to step 2.
2. **Resolver.** Works in the worktree with the merge in progress. Reads the conflicts
   file, phase N's brief and decisions, and each listed phase M's brief and decisions.
   Keeps the behaviour of both sides. Regenerates lockfiles with the repository's
   package manager. Runs fast checks on the touched files. Commits the merge. Records
   decisions in phase N's decisions file — significant when either phase's behaviour
   changed. Returns `RESOLVED <sha>`, or `UNRESOLVED` after running `git merge --abort`,
   which puts the worktree back at the verified SHA.
3. **Integration verifier.** Gates only — typecheck, lint, test, build — on the
   integrated HEAD. If the merge changed a manifest or lockfile, it runs the setup first.
   No acceptance check; the phase verifier already did that and the merge added only
   base's verified content. Evidence goes to `phase-<N>-integration-evidence.md`.
   `PASS <sha>` → step 4. `FAIL` → ladder (§3.7), with the conflicts file and merged
   phases' briefs in the attempt's context.
4. `phase-land N SHA`, in the main checkout (§4.6). Base fast-forwards in content to
   exactly the verified tree, with a `--no-ff` merge commit for history.

### 3.7 The escalation ladder

Every phase has a budget of **two attempts**, shared between phase verification and
integration.

| Attempt | Agent | Mandate |
|---|---|---|
| 1 | **repair** | Scoped fix of what the evidence names. Never weakens, skips or deletes the check that caught it. |
| 2 | **rescue** | Fresh eyes with a wider mandate: reads both evidence files, the repair's report, the brief and decisions. May change approach, rework a task, re-scope against the current base, build a missing prerequisite, or redo the integration merge. Every departure from the brief is significant. |

- Phase-verify FAIL → repair → verify → rescue → verify → drain.
- Integration-verify FAIL → the next unused attempt → integration verify again.
- Resolver `UNRESOLVED` → rescue directly, if unused. A repair is a scoped fix and an
  unresolved merge is not one. Rescue redoes the integration merge itself.
- Budget spent and still failing → the phase is **failed** and the run **drains**.

The ledger records each start before the dispatch:
`phase <N>: repair — started (attempt 1/2)`, `phase <N>: rescue — started (attempt 2/2)`.

### 3.8 Drain

Draining means: `phase-schedule` emits no `start` and no `rescout`; every in-flight phase
continues through verification and integration and lands; then the run stops and
reports. Base ends at the last landed phase, verified. Phases that depend on the failed
phase never start. Held phases waiting on it stay held.

Drain triggers:

- a phase's ladder is exhausted;
- `BLOCKED` from a scout, phase lead, resolver or rescue (the decision policy's list);
- a non-zero exit from `phase-worktree`, `phase-integrate` or `phase-land`.

The controller appends `run: draining — phase <N> <reason>` before anything else.

A preflight refusal stops the run before anything starts, as today.

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
| Integration evidence | `<run-dir>/phase-<N>-integration-evidence.md` |
| Rescue report | `<run-dir>/phase-<N>-rescue-report.md` |
| Worktree | `<repo>/.worktrees/phase-<N>-<slug>/` |
| Phase branch | `phase-<N>-<slug>` |

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
| `lead-prompt.md`, `worker-prompt.md`, `reviewer-prompt.md`, `verifier-prompt.md` | `REPO_ROOT` becomes `WORKTREE`. Each states: never touch the main checkout, `BASE`, or another phase's worktree or branch. |
| `repair-prompt.md` | Optional integration context: the conflicts file and merged phases' briefs and decisions. |
| `rescue-prompt.md` (new) | §3.7. The one agent besides the resolver allowed to run `git merge BASE` in its worktree, and only to redo an integration. Return: `FIXED` or `STILL_BROKEN`, root cause, commands re-run with exit codes, commit SHAs, significant count. |
| `resolver-prompt.md` (new) | §3.6 step 2. Return: `RESOLVED <sha>` or `UNRESOLVED`, conflicted file count, significant count. |
| `integration-verifier-prompt.md` (new) | §3.6 step 3. Return: `PASS` or `FAIL` plus SHA, one-line reason, evidence path. |
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

run: started — cap 3
graph: 2→{} 3→{2} 4→{2} 5→{3,4} 6→{5} (source: line)
phase 2: started — branch phase-2-shell, worktree .worktrees/phase-2-shell
phase 2: scout dispatched
phase 2: grounded — brief phase-2-brief.md, 6 tasks, 3 drift, 1 significant
…
phase 4: held — waits on phase 3 (overlap src/api.ts)
phase 3: merged to base (4c5d6e7)
phase 4: released — phase 3 merged
phase 5: integrating — base moved (phase 4), clean merge 1a2b3c4
phase 5: conflict — 3 files vs phase 4, resolver dispatched
phase 5: resolved 5d6e7f8
phase 5: integration verified PASS 5d6e7f8
phase 5: merged to base (9a0b1c2)
run: draining — phase 6 ladder exhausted
```

The controller appends `phase <N>: <role> dispatched` before every dispatch. With
several agents in flight, these lines are how a compacted controller knows what it is
still waiting for, and how a resumed run knows what to re-dispatch.

The identity header is the shared one, unchanged. Each invocation appends
`run: started — cap <CAP>` (or `run: resumed — cap <CAP>`); a resume may change the cap,
and the latest line applies.

### 4.5 `phase-worktree`

`phase-worktree DESIGN_DOC BASE <subcommand> [N]`

| Subcommand | Behaviour |
|---|---|
| `start N` | Refuses a phase the ledger records as merged. Branch absent: `git worktree add -b phase-<N>-<slug> <path> BASE`, appends `started`. Branch present and the ledger accounts for it: re-attaches it (`git worktree add <path> <branch>`), after `git worktree prune` if a stale entry exists. Branch present and unknown to the ledger: refuses. Prints the worktree path. Idempotent. |
| `refresh N` | Refuses if the branch has commits beyond its fork point. Fast-forwards the branch to `BASE`. Appends `released`. |
| `check` | Lists every phase worktree of this run and refuses (non-zero, names the path) when any is dirty or has a merge in progress that the ledger does not account for. |
| `remove N` | `git worktree remove` for a landed phase. Keeps the branch. |
| `path N` | Prints the worktree path. |

### 4.6 `phase-land`

`phase-land DESIGN_DOC BASE N VERIFIED_SHA`, run in the main checkout on `BASE`:

1. Refuses a dirty main checkout.
2. Refuses if the phase branch HEAD is not `VERIFIED_SHA`.
3. Refuses if the base tip is not an ancestor of `VERIFIED_SHA` — base moved and the
   phase needs integrating again.
4. `git merge --no-ff phase-<N>-<slug> -m "merge: phase <N> — <title>"`.
5. Asserts the merge commit's tree equals `VERIFIED_SHA`'s tree. On a mismatch, or any
   merge failure: `git merge --abort` or `git reset --hard ORIG_HEAD` back to the
   pre-merge base tip, exit non-zero, base unchanged.
6. Appends `phase <N>: merged to base (<sha>)`, removes the worktree, prints one line.

Failed and drained phases keep their worktrees for inspection.

### 4.7 `phase-schedule`, `phase-overlap`, `phase-integrate`

`phase-schedule DESIGN_DOC BASE RANGE CAP` reads `graph.tsv` and the ledger and prints
one action per line: `start <N>`, `rescout <N>`, `integrate <N> <sha>`, then `wait` if
anything is in flight, or `done` if nothing is. It never mutates anything. It emits at
most one `integrate`, and none while an integration is open (an `integrating` or
`conflict` line without a later outcome). The controller dispatches every action that is
not already running per its `dispatched` lines, then waits for the next return.

`phase-overlap DESIGN_DOC BASE N [PREREQ_PHASE]` implements §3.4. It takes the scout's
`prereq-inflight` value as its optional argument, so both signals are decided and
recorded in one place. Prints `clear` or `held <M> <reason>`.

`phase-integrate DESIGN_DOC BASE N VERIFIED_SHA` implements §3.6 step 1. Appends the
`integrating` or `conflict` line. Idempotent: re-run after an interruption, it detects a
merge in progress (prints `conflict`) or base already in HEAD (prints `ready`).

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
- An integration with no outcome line: `phase-integrate` again; it is idempotent.
- Ladder attempts already started stay consumed.
- `run: draining` recorded: the failed phase is verified again first, in case the owner
  fixed it by hand. `PASS` appends `run: resumed — phase <N> verified PASS` and normal
  scheduling resumes; `FAIL` drains again without a new attempt.
- A dirty main checkout or a dirty phase worktree fails preflight and is named. Never
  stash, discard or commit an interrupted agent's changes.

### 4.9 The report

```
RUN COMPLETE — phases 2–6 of …-design.md
graph: 2→{} 3→{2} 4→{2} 5→{3,4} 6→{5} (source: line)   cap 3

phase 2  merged  a1b2c3d..4c5d6e7  review 0/2/5  2 fixed  5 deferred  integration: none needed
phase 3  merged  …                 review 1/1/2  …                    integration: conflict vs 4, resolved  (repair)
phase 4  merged  …                 held on 3 (overlap src/api.ts)     integration: clean
phase 5  FAILED  ladder exhausted — evidence …, worktree .worktrees/phase-5-…
phase 6  not started (depends on 5)

base feat/thing ready — nothing pushed, no PR opened

significant decisions (audit these):
  graph: <line, when the graph agent built it>
  phase 3: <decision line>
  …

run directory: <run-dir>
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
  parse-deps  phase-schedule  phase-overlap  phase-worktree  phase-integrate  phase-land
  __tests__/
skills/building-phased-specs-in-parallel/
  SKILL.md
  scout-prompt.md  lead-prompt.md  worker-prompt.md  reviewer-prompt.md
  verifier-prompt.md  repair-prompt.md  rescue-prompt.md  resolver-prompt.md
  integration-verifier-prompt.md  graph-prompt.md
  testing-policy.md  decision-policy.md  platform-guide.md
  scripts/   thin wrappers, namespace phase-parallel:
             parse-phases  phase-run-dir  phase-preflight  parse-deps  phase-schedule
             phase-overlap  phase-worktree  phase-integrate  phase-land
```

The wrapper `phase-preflight` runs the shared preflight, then `phase-worktree check`.
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
- Base must not be trunk. The run ends at a report: no push, no PR, no trunk merge.
- Phase identity is the heading number, never a position.
- Script portability rules.

Replaced here: single checkout (by worktrees, D5), exactly one repair (by the ladder,
D10), halt (by drain, D11), sequential order (by the graph, D2–D4).

---

## 9. Known limits

Stated in `SKILL.md`, not only here.

1. **Unattended decisions can be wrong**, and now several phases make them at once
   before any lands.
2. **The independence check is file-level.** Two phases that never edit the same file
   but depend on each other's behaviour pass it; the integration gates catch the break
   only as far as tests cover it.
3. **Cost scales with the cap.** Up to `1 + 2 × CAP` agents run at once; rate limits and
   spend grow with them.
4. **One install per worktree.** Disk and time cost of setup, per in-flight phase.
5. **Nested checkouts under `.worktrees/`** are visible to tools the owner runs in the
   main checkout during a run: test runners and file watchers may need `.worktrees`
   excluded.
6. **One review per phase; the brief is a convention; permissions and nesting depth are
   host-controlled** — as in `building-phased-specs`.

---

## 10. Open questions

None. Every question raised during design is resolved in §6.
