# orchestrating-phased-specs

A Claude Code skill that runs multiple phases of a phased design document end to end:
per phase it writes an implementation plan, executes it with
`superpowers:subagent-driven-development`, verifies the result, and merges it into a
base branch — unattended.

This repository **is** the skill: `SKILL.md` and `scripts/` live at the root.

## Install

```bash
./install.sh
```

Symlinks `~/.claude/skills/orchestrating-phased-specs` at this checkout, so edits here
are live and the skill stays git-tracked.

## Status

Built in one pass against `docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md`.

| Piece | State |
|---|---|
| `scripts/parse-phases`, `scripts/phase-run-dir`, `scripts/phase-preflight` | done, unit-tested |
| `planner-prompt.md`, `executor-prompt.md`, `verifier-prompt.md`, `repair-prompt.md` | done, structurally tested |
| `SKILL.md` — the orchestration loop | done, structurally tested |

**Not yet proven end to end.** No real multi-phase run has been executed against
this skill; the first one is the proof. See the spec's §9 for the limits it ships with.

## Tests

```bash
bash scripts/__tests__/run-tests.sh
```

No test framework, no package manager — plain bash. `shellcheck` is used for linting.
