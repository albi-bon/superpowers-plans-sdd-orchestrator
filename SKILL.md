---
name: orchestrating-phased-specs
description: Use when the user asks to run multiple phases of a phased design document or spec — e.g. "let's work on phases 2 to 6 of <spec>" — orchestrating plan-writing and subagent-driven execution per phase across a base branch.
---

# Orchestrating Phased Specs

Run the requested phases of a phased design document end to end, unattended: per
phase, write a plan, execute it, verify it, merge it, record it.

**Run this in a bypass-permissions session**, or in one whose allow-rules cover
git, the repository's test runner, and this skill's scripts. Permission mode
cannot be read from inside a skill, so nothing checks this. In the wrong mode the
run does not fail — it parks on a permission prompt mid-phase and is
indistinguishable from a slow phase until someone looks.

**You are a thin controller.** You never read a plan, a diff, or a test log.
Artifacts live in files, dispatches carry paths, return values are capped. This is
not tidiness: everything you paste into a dispatch and everything a subagent
prints back stays resident in your context for the rest of the run and is re-read
every turn — and this session outlives one full `subagent-driven-development` run
per phase.

**Narration:** at most one short line between tool calls. The ledger is the record.

## Invocation

> Let's work on phases 2 to 6 of docs/superpowers/specs/…-design.md on branch feat/thing

From that you need three values, and nothing else:

| Value | Where it comes from |
|---|---|
| `DESIGN_DOC` | the path in the request |
| `BASE` | the branch named in the request. If none was named, ask — do not guess, and never default to trunk |
| `RANGE` | the phases named in the request: `2 to 6`, `2-6`, `2,4,5`, `3`, or `all` |

## Preflight

```bash
scripts/phase-preflight <DESIGN_DOC> <BASE> <RANGE>
```

Every check must pass or the run does not start. On a non-zero exit, stop and
show the script's stderr verbatim — it names the failed check and the command
that fixes it. Do not work around a refusal.

On success it has switched the working tree to `BASE`, creating it off trunk if
it did not exist, and printed the run directory. Then get the phase records:

```bash
scripts/parse-phases <DESIGN_DOC> <RANGE>   # number<TAB>title<TAB>slug, ascending
scripts/phase-run-dir <DESIGN_DOC>          # <run-dir>, git-ignored
```

Hold exactly this much state for the whole run: `DESIGN_DOC`, `BASE`, the phase
records, and `<run-dir>`. Nothing else accumulates across phases.

## The loop

For each requested phase in **ascending numeric order** — the number from the
heading, never a position in the list:

```bash
git switch <BASE> && git switch -c phase-<N>-<slug>
```

Then four dispatches. Every one of them **must name a model explicitly**; an
omitted model inherits this session's, which is the most expensive one.

| # | Dispatch | Template | Model | Why |
|---|---|---|---|---|
| ① | planner | `planner-prompt.md` | most capable | Writing a plan from a spec is design judgment, and every downstream cost compounds from its quality |
| ② | executor | `executor-prompt.md` | most capable | It is itself a controller, running a review loop and adjudicating findings unattended |
| ③ | verifier | `verifier-prompt.md` | mid-tier | Runs commands and reads exit codes — mechanical, but it must still reason about which gates a repository has |
| — | repair | `repair-prompt.md` | most capable | Fresh eyes on something a full execution run did not get right |

The executor's *own* dispatches are governed by `subagent-driven-development`'s
Model Selection. Do not reach into them.

Paths to substitute into the templates:

| Artifact | Path |
|---|---|
| Plan | `docs/superpowers/plans/<date>-<spec-slug>-phase-<N>-<slug>.md` |
| Executor decisions | `<run-dir>/phase-<N>-decisions.md` |
| Verifier evidence | `<run-dir>/phase-<N>-evidence.md` |
| Ledger | `<run-dir>/run.md` |

Order within a phase:

1. **①  planner** → returns the plan path. Append `phase <N> (<title>): plan <path>` to the ledger.
2. **②  executor** → returns `DONE` or `BLOCKED` in ten lines. Append the executed line.
3. **③  verifier** → returns `PASS` or `FAIL` plus the evidence path. Append the verified line.
4. On `FAIL`: dispatch **repair** once, then re-run the verifier. Green → continue. Red → halt.
   **Exactly one repair attempt per phase.** A second is how an unattended run burns an
   afternoon converging on nothing.
5. Merge:

```bash
git switch <BASE>
git merge --no-ff phase-<N>-<slug> -m "merge: phase <N> — <title>"
```

Conflicts cannot arise structurally — each phase branch forks from the current
base tip and base advances only through these merges, so the fork point is always
the merge base. Check the exit code anyway and halt on non-zero: a structural
impossibility that happens anyway is exactly what an unattended run must not
plough through. Keep phase branches after merging — free rollback points at zero
cost.

6. Append `phase <N>: merged to base (<sha>)` to the ledger.

## The ledger

`<run-dir>/run.md`. Write it as you go, not at the end. Its first two lines carry
its identity:

```markdown
# Phase run — spec: docs/superpowers/specs/…-design.md
# base: feat/thing  requested: 2-6

phase 2 (Shell & surface model): plan docs/superpowers/plans/…-phase-2-shell.md
phase 2: executed — 11 commits, review clean, 2 minor deferred, decisions phase-2-decisions.md
phase 2: verified PASS
phase 2: merged to base (a1b2c3d)
phase 3 (Takeovers & interstitials): plan docs/superpowers/plans/…-phase-3-takeovers.md
phase 3: executed — 9 commits, 1 parked
phase 3: verified FAIL — rest-arbitration.characterization.test.ts, exit 1
phase 3: repair round 1 — verified PASS
phase 3: merged to base (d4e5f6a)
```

A long run compacts this session's context, and a controller that loses its place
re-dispatches completed work — the most expensive failure mode there is. The
ledger is the recovery map, and the commits it names exist in git even when your
memory of them does not. After compaction, trust the ledger and `git log` over
your own recollection.

## Resume

Re-invoking this skill with the same spec and base **is** the resume. Read the
ledger and restart at the first requested phase with no `merged` line:

- A phase with a `plan` line but no `executed` line resumes at the executor,
  reusing the plan that is already on disk. Do not re-plan it.
- A phase with an `executed` line but no `verified PASS` resumes at the verifier.
- Nothing already merged is re-planned or re-executed.
- A ledger whose first line names a different spec is another run's. Leave it
  alone and start fresh.

## Halting

Halt on: an executor `BLOCKED` that repair does not clear, a second verifier
`FAIL`, a non-zero merge exit code, or a preflight refusal.

On halt: leave the failing phase's branch in place and unmerged, leave base at the
end of the last successful phase, start no later phase, and report the failed
check, the evidence file path, and the branch to inspect.

## The report

Write it to the ledger and print it:

```
RUN COMPLETE — phases 2–6 of …-design.md

phase 2  merged  a1b2c3d..d4e5f6a  11 commits   1 auto-decision   2 minor deferred
phase 3  merged  d4e5f6a..8f9a0b1   9 commits   0 auto-decisions  1 parked  (1 repair round)
…
base feat/thing ready — nothing pushed, no PR opened

auto-decisions:  <run-dir>/phase-N-decisions.md
parked findings: see ledger
```

Integration into trunk is a decision worth a human. The run ends here.

## Known limits

State these to your human partner when they matter; do not paper over them.

1. **The wrong permission mode stalls rather than fails.** The run parks on a prompt
   mid-phase and looks like a slow phase until inspected.
2. **Capped review compounds across phases.** The executor runs one review round
   per task, so phase N+1 builds on phase N's residual findings. The ledger and
   the report surface them; nothing prevents them.
3. **The working tree is busy for the whole run.** No worktrees, so the
   repository cannot be used for anything else while phases execute.
4. **Nesting depth is a platform assumption, not a guarantee.** This design needs
   a subagent to spawn subagents, to depth 3. If the executor cannot dispatch its
   own implementers, halt and say so — the design does not degrade gracefully.

## Common rationalizations

| Excuse | Reality |
|--------|---------|
| "I'll read the plan to check the planner did it right" | That is what the verifier and the executor's own review are for. A plan in your context is there for every remaining phase. |
| "The verifier's FAIL looks like a flake, I'll just merge" | The verifier reads exit codes; you did not run the command. One repair attempt, then halt. |
| "Repair almost worked, one more round" | Exactly one. Past it, the failure is structural and another round burns the afternoon. |
| "I'll fix this small thing myself" | Controller fixes skip verification and pollute your context. Dispatch it. |
| "I'll write the whole ledger at the end" | The end is exactly when your context may no longer exist. Append as you go. |
| "Phase 4 failed, but 5 and 6 are independent" | Phases share a base branch and are usually sequentially dependent. Halt. |
