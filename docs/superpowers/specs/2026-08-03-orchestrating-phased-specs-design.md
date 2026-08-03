# Orchestrating Phased Specs — Design Spec

**Date:** 2026-08-03
**Scope:** a new global skill at `~/.claude/skills/orchestrating-phased-specs/`.
**Status:** approved design, not yet planned.

### How to use this document

§1–§5 are the design. §6 is the decision log — an implementation phase that wants to
deviate from a decision must amend §6 first and say why. §7 splits the build into three
phases, each its own plan and its own commit. §8 records the platform assumptions this
design rests on and how to re-verify them.

---

## 1. Summary

A design spec written in phases currently costs one manual session per phase, three times
over: open a fresh session and invoke `superpowers:writing-plans` against phase N, open
another fresh session and point `superpowers:subagent-driven-development` at the plan it
produced, then do the git bookkeeping by hand and start again for phase N+1.

This skill collapses that into one invocation:

```
Let's work on phases 2 to 6 of docs/superpowers/specs/2026-08-03-session-tracker-redesign-design.md
  on branch feat/session-tracker-redesign
```

The orchestrator runs in the main session and does almost nothing itself: git branch/merge,
a ledger append, and three subagent dispatches per phase. It never reads a plan, a diff, or
a test log. Those live in files; dispatches carry paths; return values are capped at a few
lines. That discipline is what lets one session survive six chained `subagent-driven-development`
runs without its context collapsing.

The predecessor for this idea is the deprecated `bmad-story-automator`, which drove the
same shape of loop by spawning nested `claude --dangerously-skip-permissions` processes
inside tmux panes. Nearly all of its complexity — pane scraping, idle detection, acceptance
screens, watcher windows, status polling — existed to work around not being able to spawn a
subagent from a subagent. That constraint no longer holds (§8.1), so none of that machinery
is rebuilt here.

---

## 2. Scope

### In scope

- `~/.claude/skills/orchestrating-phased-specs/` — the whole skill: `SKILL.md`, four
  dispatch templates, two bash scripts
- Parsing a phased design document into phase numbers, titles and slugs
- Preflight validation, branch lifecycle, merge, and a resumable run ledger
- Per-phase verification and a single repair attempt

### Out of scope

- **Parallel phase execution.** Phases share one base branch and one working tree.
- **Worktrees, tmux, or `claude -p` child processes.** §6 D2, §6 D3.
- **Cron or scheduled resume.** Resume is re-invoking the skill; §4.4.
- **Pushing, opening a PR, or merging to trunk.** The run ends at a report; §6 D8.
- **A per-repo configuration file.** The verifier subagent derives the project's gates.
- **Authoring the design spec itself.** That is `superpowers:brainstorming`. This skill
  starts from a spec that already has a phases section.
- **Changing `writing-plans` or `subagent-driven-development`.** Both are consumed as-is,
  with per-dispatch overrides (§3.3, §3.4) rather than edits.

---

## 3. Architecture

### 3.1 The loop

```
preflight
for each requested phase N, in ascending numeric order:
    git switch <base> && git switch -c phase-N-<slug>

    ① planner subagent   → plan file path
    ② executor subagent  → status block
    ③ verifier subagent  → PASS | FAIL + evidence file path
         FAIL → repair subagent (once) → re-verify
                still FAIL → halt the run

    git switch <base> && git merge --no-ff phase-N-<slug>
    append to ledger
report
```

The orchestrator holds: the spec path, the base branch name, the phase list, and the
ledger path. Nothing else accumulates across phases.

### 3.2 Agent topology

```
main session (orchestrator)
├─ Agent: planner      invokes superpowers:writing-plans
├─ Agent: executor     invokes superpowers:subagent-driven-development
│  ├─ Agent: implementer      SDD's own per-task fan-out
│  ├─ Agent: task-reviewer
│  └─ Agent: final-reviewer
├─ Agent: verifier
└─ Agent: repair (only on FAIL)
```

Depth 3 (orchestrator → executor → implementer) is the design's one load-bearing platform
assumption. See §8.1.

### 3.3 ① Planner dispatch

**Input:** design doc path, phase number, phase title, target plan path.

**Instructions:**

- Read the whole design document for context; write a plan for **phase N only**.
- Invoke `superpowers:writing-plans`.
- Save to the exact path given (§4.2), do not choose your own filename.
- Copy the spec's cross-cutting constraints into the plan's `## Global Constraints` block.
- Commit the plan file.

**Two overrides of `writing-plans`' own ending:**

1. Do **not** present the execution-choice menu ("Subagent-Driven / Inline Execution").
2. Do **not** execute the plan.

**Return contract:** the plan file path on one line, nothing else.

### 3.4 ② Executor dispatch

**Input:** plan file path, phase branch name, run directory path, decisions-file path.

**Instructions:** invoke `superpowers:subagent-driven-development` against the plan.

**Three overrides of that skill's defaults:**

1. **Do not create or verify a worktree.** SDD's Setup step routes through
   `superpowers:using-git-worktrees`. You are already on an isolated phase branch in a
   single checkout. Without this override the executor forks a worktree the orchestrator
   cannot see and merges nothing back.
2. **Do not invoke `superpowers:finishing-a-development-branch`.** That is SDD's terminal
   state. Integration belongs to the orchestrator.
3. **Do not switch branches.** Everything commits to the phase branch you were handed.

**Two user directives, passed verbatim, stated as superseding the skill's own rules:**

> 1. Only perform one round of review. After applying any patches/fixes from the first
>    review, do not run a second pass — mark the task done.
> 2. I'm going to be afk. If you hit a situation where you would normally stop and ask for
>    direction, pick the option you'd normally tag as recommended, and summarise the
>    decisions taken at the end.

Directive 2's summary is written to the decisions file in the run directory, **not** returned.

**Return contract**, capped at roughly ten lines: status (`DONE` | `BLOCKED`), commit range,
review outcome, counts of parked and deferred findings, decisions-file path.

### 3.5 ③ Verifier dispatch

A fresh agent that did not write the code.

**Input:** design doc path, phase number, phase branch name, evidence-file path.

**Instructions:**

- Read the phase's own **Verification** section in the design doc. If the phase has none,
  run the repository's standard gates and say in the evidence file that the phase specified
  no verification of its own.
- Determine and run the project's gates (typecheck, lint, test, build — whatever the repo
  actually has).
- **Report the exit code of every command.** A suite that prints all-green and exits
  non-zero is a FAIL.
- Write full evidence — commands, exit codes, relevant output — to the evidence file.

**Return contract:** `PASS` or `FAIL`, a one-line reason, and the evidence file path.

Rationale for a third agent rather than trusting the executor's own gate: directive 1 caps
review at a single round, so the executor's internal quality gate is weaker than stock SDD's.
And an agent invested in the work it just wrote rationalises a non-zero exit code away —
this is a documented, reproducing failure mode in at least one target repo, where the client
suite prints `Test Files 214 passed` and exits 1. A fresh agent reports it.

### 3.6 Repair

On `FAIL`, one fresh agent (§4.7) receives the evidence file path, the plan path, and the
phase branch. It fixes and commits. Then the verifier runs once more. Green → merge.
Red → halt (§4.5).

Exactly one repair attempt. A second is how an unattended run burns an afternoon converging
on nothing.

### 3.7 Merge

```bash
git switch <base>
git merge --no-ff phase-N-<slug> -m "merge: phase N — <title>"
```

**Merge conflicts cannot arise, structurally.** Each phase branch forks from the *current*
base tip, and base advances only through these merges, so the phase branch's fork point is
always the merge base. `--no-ff` keeps each phase legible as one merge commit. Phase branches
are **kept** after merging — free per-phase rollback points at zero cost.

The orchestrator still checks the merge's exit code and halts on a non-zero one. A structural
impossibility that happens anyway is exactly the kind of thing an unattended run must not
plough through.

---

## 4. Mechanics

### 4.1 Invocation and phase parsing

Accepted range forms: `2 to 6`, `2-6`, `2,4,5`, a single `3`, or `all`.

`scripts/parse-phases <design-doc>` emits one record per phase found. A heading qualifies when
it has 2–4 leading `#`, then `Phase`, then an integer, then a dash separator, then a non-empty
title. Output columns, tab-separated: number, title, slug (title lowercased, runs of
non-alphanumerics collapsed to `-`, leading and trailing `-` trimmed).

**The separator must be matched by alternation or `index()`, never by a bracket expression.**
`[—–-]` is wrong twice over: a byte-oriented `awk` treats the multibyte em and en dashes as
individual bytes rather than characters, and `–-` inside brackets can parse as a range. Match
the three separators as whole strings and take the earliest position. `index()`, `length()`
and `substr()` agree with each other within any one `awk`, so offset arithmetic built from
them is correct whether that `awk` counts bytes or characters.

**Interval expressions (`{2,4}`) are avoided too** — support is not universal across the `awk`
implementations this skill must run under. Count the leading `#` characters instead.

**Phase identity is the number captured from the heading, never an ordinal index into the
list.** A spec whose phases start at 0 makes position and number differ by one, and a
range interpreted positionally silently selects the wrong work — the precise failure that
`bmad-story-automator`'s `parse-story-range` shipped with. A requested phase number that
does not appear in the document is a hard refusal naming the numbers that do.

The script is bash + `awk` and uses `[[:space:]]`, never `\s`. BSD `awk`/`sed` on macOS do
not support `\s`, and the failure is silent: the pattern does not match, the extraction
returns the whole line or nothing, and the caller compares against a value that never
appears.

### 4.2 Paths

| Artifact | Path |
|---|---|
| Run directory | `<repo-root>/.superpowers/phase-orchestrator/<spec-basename>/` |
| Ledger | `<run-dir>/run.md` |
| Executor decisions | `<run-dir>/phase-<N>-decisions.md` |
| Verifier evidence | `<run-dir>/phase-<N>-evidence.md` |
| Plan | `docs/superpowers/plans/<date>-<spec-slug>-phase-<N>-<slug>.md` |
| Phase branch | `phase-<N>-<slug>` |

`scripts/phase-run-dir <design-doc>` resolves and creates the run directory and ensures
it is git-ignored, mirroring `subagent-driven-development`'s `scripts/sdd-workspace`. The
run directory is scratch; the plan is committed product.

### 4.3 Preflight

Every check must pass or the run refuses to start. A refusal names the failed check and
the command that fixes it.

| Check | Why it exists |
|---|---|
| Inside a git repository | Everything downstream is branch-shaped |
| Working tree clean | Uncommitted work would ride into a phase branch and be mislabelled under that phase's commit message |
| `--base` branch resolved — switch to it, or create it off `main` if absent | The base is named in the invocation |
| Base is not `main` / `master` | Never merge unattended work into trunk |
| Design doc exists and every requested phase number is present | Fail at second zero, not at phase 4 |
| No pre-existing branch named `phase-<N>-<slug>` for an unmerged requested phase | A leftover branch means a resume, not a fresh start |

The last check applies to a **fresh** run only. When a ledger for this spec and base already
exists, §4.4's resume rules govern: an existing branch for a phase the ledger has not marked
`merged` is that phase's in-flight work and is reused, not rejected. A branch with no ledger
entry at all is always a refusal — its provenance is unknown.

**Permission mode is documented, not detected.** There is no reliable way to read the
session's permission mode from inside a skill. `SKILL.md` states the requirement in its
opening lines: run in a bypass-permissions session, or with allow-rules covering git, the
test runner, and the skills' scripts. In the wrong mode the run does not fail — it parks
on a prompt mid-phase and looks like a stall. Saying so is the honest mitigation; claiming
a check that does not exist is not.

### 4.4 The ledger and resume

`<run-dir>/run.md`, first two lines carrying identity:

```markdown
# Phase run — spec: docs/superpowers/specs/2026-08-03-session-tracker-redesign-design.md
# base: feat/session-tracker-redesign  requested: 2-6

phase 2 (Shell & surface model): plan docs/superpowers/plans/2026-08-03-…-phase-2-shell.md
phase 2: executed — 11 commits, review clean, 2 minor deferred, decisions phase-2-decisions.md
phase 2: verified PASS
phase 2: merged to base (a1b2c3d)
phase 3 (Takeovers & interstitials): plan docs/superpowers/plans/…-phase-3-takeovers.md
phase 3: executed — 9 commits, 1 parked
phase 3: verified FAIL — rest-arbitration.characterization.test.ts, exit 1
phase 3: repair round 1 — verified PASS
phase 3: merged to base (d4e5f6a)
```

A six-phase run is long enough to compact the orchestrator's context, and a controller that
loses its place re-dispatches completed work — the most expensive failure mode
`subagent-driven-development` documents. The ledger is the recovery map, and the commits it
names exist in git even when the session's memory does not.

**Resume** is re-invoking the skill with the same spec and base. It reads the ledger and
restarts at the first requested phase without a `merged` line. A phase with a `plan` line
but no `executed` line resumes at the executor, reusing the existing plan. Nothing already
merged is re-planned or re-executed. A ledger whose first line names a different spec is
another run's — leave it and start fresh.

### 4.5 Halting

The run halts on: executor `BLOCKED` that repair does not clear, a second verifier `FAIL`,
a non-zero merge exit code, or a preflight refusal.

On halt: the failing phase's branch is left in place and unmerged, base sits at the end of
the last successful phase, later phases are not started, and the report names the failed
check, the evidence file, and the branch to inspect.

### 4.6 The report

Written to the ledger and printed at the end:

```
RUN COMPLETE — phases 2–6 of 2026-08-03-session-tracker-redesign-design.md

phase 2  merged  a1b2c3d..d4e5f6a  11 commits   1 auto-decision   2 minor deferred
phase 3  merged  d4e5f6a..8f9a0b1   9 commits   0 auto-decisions  1 parked  (1 repair round)
…
base feat/session-tracker-redesign ready — nothing pushed, no PR opened

auto-decisions:  .superpowers/phase-orchestrator/<spec>/phase-N-decisions.md
parked findings: see ledger
```

Directive 1 caps review at one round per task, so residual findings accumulate across
chained phases — phase 3 builds on phase 2's residue. The report surfaces them; it does not
prevent them. That trade is deliberate (§6 D6) and the ledger is what makes it reviewable.

### 4.7 Model selection

`subagent-driven-development` requires every dispatch to name a model explicitly, because an
omitted model inherits the session's — typically the most capable and most expensive one.
The same rule binds here, and the orchestrator's four dispatches are not equal work:

| Dispatch | Model | Why |
|---|---|---|
| ① planner | most capable | Writing a plan from a spec is design judgment, and every downstream cost compounds from its quality |
| ② executor | most capable | It is a controller running its own review loop and adjudicating findings unattended |
| ③ verifier | mid-tier | Runs commands and reads exit codes — mechanical, but not cheap-tier: it must reason about which gates a repo has |
| repair | most capable | Fresh eyes on something a full SDD run did not get right |

The executor's *internal* dispatches are governed by SDD's own Model Selection section, not
by this table. The orchestrator does not reach into them.

---

## 5. Skill file structure

```
~/.claude/skills/orchestrating-phased-specs/
  SKILL.md              orchestration loop, preflight, ledger contract,
                        permission-mode requirement, resume rules, limits
  planner-prompt.md     ① dispatch template
  executor-prompt.md    ② dispatch template — three overrides + two directives verbatim
  verifier-prompt.md    ③ dispatch template — exit codes, not printed totals
  repair-prompt.md      one-shot repair dispatch
  scripts/
    parse-phases        design doc → number, title, slug; validates a requested range
    phase-run-dir       resolve/create run directory, ensure it is git-ignored
    phase-preflight     the §4.3 checks; resolves and switches to the base branch
```

Gerund name, matching the superpowers convention (`writing-plans`, `executing-plans`,
`dispatching-parallel-agents`). Authored with `superpowers:writing-skills`.

`SKILL.md` frontmatter description must carry the trigger phrasing, so the skill fires on
the natural sentence rather than only on an explicit slash invocation:

> Use when the user asks to run multiple phases of a phased design document or spec — e.g.
> "let's work on phases 2 to 6 of \<spec\>" — orchestrating plan-writing and
> subagent-driven execution per phase across a base branch.

---

## 6. Decision log

| # | Decision | Rationale |
|---|---|---|
| **D1** | **Thin orchestrator + nested subagents.** The main session does git and bookkeeping only; planning and execution are subagents. | The only shape where one session survives six chained SDD runs. Alternatives considered: headless `claude -p` children (the story-automator model — needed only if nesting failed, and it does not) and cron self-reinvocation (turns a long run into a state machine for no gain over the ledger). |
| **D2** | **Branch per phase, single checkout, no worktrees.** | Owner's call. A worktree per phase costs a dependency install per phase in monorepos and buys isolation the sequential loop does not need. The cost is that the working tree is busy for the run's duration. |
| **D3** | **No tmux, no `claude -p`, no pane scraping.** | Every one of `bmad-story-automator`'s fifteen recorded operational gotchas came from driving child CLI processes. Subagent nesting removes the need entirely. |
| **D4** | **Fully unattended.** No gate after the plan, none before the merge. | Owner's call — the manual gates are the pain being removed. The verifier (§3.5) is the substitute for a human gate before merge. |
| **D5** | **A separate verifier subagent decides merge**, not the executor's own report. | Directive 1 weakens the executor's internal gate, and an agent reviewing its own work rationalises a non-zero exit code. A fresh agent that reads exit codes is the cheapest possible independent gate. |
| **D6** | **The two afk directives are baked into the executor dispatch**, superseding SDD's rules. | Owner's established practice; it works. The cost — residual findings compounding across phases — is bounded by surfacing them in the ledger and the final report. |
| **D7** | **Halt on failure, after exactly one repair attempt.** | Owner's call, over halt-immediately and over skip-and-continue. Phases are usually sequentially dependent; building phase 5 on a broken phase 4 makes the damage harder to locate. One repair catches the common transient; two is how an unattended run burns an afternoon. |
| **D8** | **The run ends at a report.** No push, no PR, no `finishing-a-development-branch`. | Integration into trunk is a decision worth a human. |
| **D9** | **Global skill, project-agnostic.** No hard-coded build commands anywhere. | Reusable across every repo. The verifier derives the gates from the repo and the phase's Verification section. |
| **D10** | **Phase identity is the number in the heading**, never an ordinal index. | A spec starting at Phase 0 makes the two differ. `bmad-story-automator` shipped the positional interpretation and it silently selected the wrong stories. |
| **D11** | **Scripts are bash + `awk`, using `[[:space:]]` and never `\s`.** | BSD `awk`/`sed` on macOS do not support `\s`, and the failure is silent rather than an error. Extended 2026-08-03 while planning Phase 1, same class of bug: no bracket expressions over multibyte dashes (§4.1), no interval expressions, and no bash-4-only syntax (`${v,,}`, associative arrays) since `/bin/bash` on stock macOS is 3.2. |
| **D12** | **All artifacts are files; dispatches carry paths; return values are capped.** | SDD's own warning: everything pasted into a dispatch or printed back stays resident for the rest of the session and is re-read every turn. The orchestrator outlives six SDD runs, so the rule binds harder here than in SDD itself. |
| **D13** | **Permission mode is documented, not detected.** | No reliable API exists. A stated limitation beats a check that cannot work. |
| **D14** | **Preflight is a script (`scripts/phase-preflight`), not prose in `SKILL.md`.** §4.3's checks and the base-branch resolution move into it; `SKILL.md` calls it and refuses the run on a non-zero exit. | Added 2026-08-03 while planning the build. §7 Phase 3 requires one test per §4.3 check; as prose that means invoking the whole skill six times, and the checks would be verified only by the thing they gate. As a script they are unit-tested against throwaway repositories in seconds. Does not weaken D13 — permission mode is still neither checked nor checkable. |

---

## 7. Implementation phases

Each phase is one session: its own plan, its own verification, its own commit.

### Phase 1 — Parsing and run state

**Goal:** the two scripts exist and are correct before any orchestration logic depends on them.

**Add**
- `scripts/parse-phases` — the §4.1 extraction and range validation
- `scripts/phase-run-dir` — the §4.2 run-directory resolution and git-ignore guarantee

**Verification**
- `parse-phases` against `2026-08-03-session-tracker-redesign-design.md` returns exactly
  nine phases numbered 0–8 with correct titles and slugs
- A range of `2-6` selects phases 2,3,4,5,6 — **not** the 2nd through 6th entries
- `2,4,5`, `3`, and `all` each resolve correctly
- A range naming a phase number absent from the document exits non-zero and names the
  available numbers
- A heading using an en dash, an em dash, and a hyphen each parse
- Both scripts run clean under macOS BSD `awk` — verified by running them, not by inspection
- `phase-run-dir` is idempotent and leaves the directory git-ignored

**Done when:** both scripts are correct against a real spec and a hostile range.

### Phase 2 — Dispatch templates

**Goal:** the four prompt templates say exactly what each subagent must and must not do.

**Add**
- `planner-prompt.md` — §3.3, including both `writing-plans` overrides
- `executor-prompt.md` — §3.4, including all three SDD overrides and both directives verbatim
- `verifier-prompt.md` — §3.5, including the exit-code rule
- `repair-prompt.md` — §3.6

**Constraints**
- Every template states its return contract explicitly and caps it
- No template instructs an agent to paste artifacts into its return value
- The executor template's overrides are stated as superseding the invoked skill, not as
  suggestions — an override phrased as a preference gets ignored

**Verification**
- Dispatch the planner template for real against one phase of a real spec; confirm it
  writes the plan to the given path, commits it, and returns only the path — no execution
  menu, no execution
- Dispatch the verifier template against a known-red branch; confirm FAIL and a non-zero
  exit code in the evidence file
- Dispatch the verifier against a repo whose suite prints all-green and exits non-zero;
  confirm FAIL

**Done when:** each template has been dispatched once and returned within its contract.

### Phase 3 — The orchestration loop

**Goal:** `SKILL.md` ties it together and a real multi-phase run completes.

**Add**
- `SKILL.md` — invocation parsing, preflight (§4.3), the loop (§3.1), ledger contract and
  resume (§4.4), halting (§4.5), the report (§4.6), and the three stated limits (§8)

**Verification**
- Preflight refuses on each of the six §4.3 checks, one test per check
- A two-phase run over a small real spec completes: both phases planned, executed,
  verified, merged, ledger correct, report correct
- Killing the run mid-phase-2 and re-invoking resumes at phase 2's executor without
  re-planning phase 2 or re-touching phase 1
- A forced verifier FAIL triggers exactly one repair, then halts if still red, leaving the
  branch unmerged and base at the previous phase
- The orchestrator's own context after a two-phase run contains no plan text, no diff, and
  no test output

**Done when:** a real phased spec runs end to end unattended and the ledger reconstructs
the run without the session's memory.

---

## 8. Platform assumptions

These are the facts the design rests on. Each names how to re-verify it, because a harness
change invalidates the design rather than degrading it.

1. **A subagent can spawn subagents, to at least depth 3.** Verified 2026-08-03 in this
   harness: a `general-purpose` subagent successfully dispatched its own subagent and
   returned its output. `Explore` and `Plan` agent types exclude the `Agent` tool and cannot
   nest; `general-purpose` and `claude` carry all tools and can. Re-verify by dispatching a
   `general-purpose` agent and asking it to spawn one. **If this ever fails, the design
   reverts to the `claude -p` child-process model and most of §3 is void.**
2. **A subagent can invoke skills.** The executor's whole job is invoking
   `subagent-driven-development`. Verified in the same probe — `Skill` is in the
   `general-purpose` toolset.
3. **Permission mode cannot be read from inside a skill.** If that changes, §4.3's
   documented-not-detected limitation becomes a real preflight check.

---

## 9. Known limits

Stated in `SKILL.md`, not only here.

1. **Wrong permission mode stalls rather than fails.** The run parks on a prompt mid-phase
   and is indistinguishable from a slow phase until inspected.
2. **Capped review compounds across phases.** One review round per task means phase N+1
   builds on phase N's residual findings. The ledger and report surface them; nothing
   prevents them.
3. **The working tree is busy for the whole run.** No worktrees means the repository cannot
   be used for anything else while phases execute.
4. **Nesting depth is a platform assumption, not a guarantee.** §8.1.

---

## 10. Open questions

None. Every question raised during design is resolved in §6.
