# Phased-spec skills

Two Claude Code and Codex skills that run the phases of a phased design document
end to end, unattended, one branch per phase, merging each into a base branch:

| Skill | Use it for | Per phase |
|---|---|---|
| `building-phased-specs` | Design documents that are already researched and decided — the everyday path | a scout grounds the phase and writes a short brief; a phase lead has one worker build each task, one reviewer review the branch, and a fix wave apply the accepted findings; a verifier checks gates and deliverables |
| `orchestrating-phased-specs` | Exploratory specs that benefit from a full implementation plan | writes a Superpowers plan, executes it with `subagent-driven-development`, verifies |

Both share the scripts in `shared/scripts/`, keep a resumable ledger, run exactly
one repair attempt per phase, and end at a report — nothing pushed, no PR opened.
Each skill keeps its runs in its own run directory
(`.superpowers/phase-builder/` and `.superpowers/phase-orchestrator/`).

## Install

```bash
./install.sh                      # both skills, Claude Code
./install.sh claude building      # one skill
./install.sh codex                # both skills, Codex
./install.sh all all              # both skills, both hosts
```

Symlinks `skills/<name>/` into the host's skills directory, so edits here are
live. Claude uses `~/.claude/skills`; Codex uses `~/.agents/skills`. Override
those with `CLAUDE_SKILLS_DIR` or `CODEX_SKILLS_DIR`. Re-running the installer
over an older install that linked the repository root repoints it. Existing
non-symlink destinations are preserved. Refresh skill discovery or restart the
host if a skill is not visible.

`orchestrating-phased-specs` also needs Superpowers installed.
`building-phased-specs` needs nothing beyond Bash, Git and nested agents. Read
each skill's `platform-guide.md` for dispatch, model mapping and permissions.

## Invoke

Invoking by name is deterministic:

```
/building-phased-specs phases 2 to 6 of docs/specs/example-design.md on branch feat/example
/orchestrating-phased-specs phases 2 to 6 of docs/specs/example-design.md on branch feat/example
```

In Codex, mention the skill as `$building-phased-specs`. With looser wording —
"work on phases 2 to 6 of …" — the descriptions route to
`building-phased-specs`; `orchestrating-phased-specs` fires only when you ask for
plan-driven execution ("… with plans") or name it.

## Layout

```
shared/scripts/          parse-phases, phase-run-dir, phase-preflight, phase-start, phase-finish
shared/scripts/__tests__ the shell test suite for scripts, installer and both skills
skills/<name>/           SKILL.md, dispatch templates, platform guide
skills/<name>/scripts/   thin wrappers that set the skill's run-directory namespace
docs/superpowers/specs/  the design documents for both skills
```

## Tests

```bash
bash shared/scripts/__tests__/run-tests.sh
shellcheck shared/scripts/* skills/*/scripts/* install.sh shared/scripts/__tests__/*.sh
```

No test framework, no package manager — plain bash.

## Status

The shell suite verifies scripts, installation and Git-state behaviour in
temporary repositories, and checks both skills' templates structurally. Live
multi-phase runs are the real verification; see each design document's
verification sections.
