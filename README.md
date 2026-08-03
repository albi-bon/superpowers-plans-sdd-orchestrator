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

Being built phase by phase against `docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md`.

| Phase | Scope | State |
|---|---|---|
| 1 | `scripts/parse-phases`, `scripts/phase-run-dir`, test harness | planned |
| 2 | Dispatch templates | not planned |
| 3 | `SKILL.md`, the orchestration loop | not planned |

## Tests

```bash
bash scripts/__tests__/run-tests.sh
```

No test framework, no package manager — plain bash. `shellcheck` is used for linting.
