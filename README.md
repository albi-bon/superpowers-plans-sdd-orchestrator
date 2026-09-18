# orchestrating-phased-specs

A Claude Code and Codex skill that runs multiple phases of a phased design document end to end:
per phase it writes an implementation plan, executes it with
`superpowers:subagent-driven-development`, verifies the result, and merges it into a
base branch — unattended.

This repository **is** the skill: `SKILL.md` and `scripts/` live at the root.

## Install

```bash
./install.sh        # Claude Code (existing default)
./install.sh codex  # Codex
./install.sh all    # Both hosts
```

Symlinks the selected host's skill folder at this checkout, so edits here are live
and the skill stays git-tracked. Claude uses `~/.claude/skills`; Codex uses
`~/.agents/skills`. Override those parent directories with `CLAUDE_SKILLS_DIR` or
`CODEX_SKILLS_DIR`, respectively. Existing non-symlink destinations are preserved.
Refresh skill discovery or restart the host if the skill is not visible.

Install Superpowers in each host too. Read [platform-guide.md](platform-guide.md)
for dispatch/model mapping, required Superpowers helpers, nested-agent capability,
and permissions. This workflow needs controller → executor → worker nesting and
shared access to one checkout. It does not grant permissions or modify host settings.

In either host, invoke the skill with the design document, phases, and base branch:

> Use orchestrating-phased-specs to work on phases 2 to 6 of
> docs/superpowers/specs/example-design.md on branch feat/example.

Scripts resolve from the installed skill directory; their working directory must
be the target repository. `phase-start` creates or resumes a phase branch after
preflight. Preflight preserves the existing run directory layout and refuses a
ledger belonging to another spec or base instead of reusing its progress.

## Status

Built in one pass against `docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md`.

| Piece | State |
|---|---|
| `scripts/parse-phases`, `scripts/phase-run-dir`, `scripts/phase-preflight`, `scripts/phase-start` | done, unit-tested |
| `planner-prompt.md`, `executor-prompt.md`, `verifier-prompt.md`, `repair-prompt.md` | done, structurally tested |
| `SKILL.md` — the orchestration loop | done, structurally tested |

**Not yet proven end to end.** The shell suite verifies installation and Git-state behavior in temporary
repositories, not real model dispatch. A live multi-phase run and interrupted
resume still need validation in each host. See the spec's §9 for the limits it ships with.

## Tests

```bash
bash scripts/__tests__/run-tests.sh
```

No test framework, no package manager — plain bash. `shellcheck` is used for linting.
