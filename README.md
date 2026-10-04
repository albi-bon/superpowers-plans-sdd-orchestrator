# Phased-spec skills

Four Claude Code and Codex skills that run the phases of a phased design document
end to end, unattended, one branch per phase, merging each into a base branch:

| Skill | Use it for | Per phase |
|---|---|---|
| `building-phased-specs` | Design documents that are already researched and decided — the everyday path | a scout grounds the phase and writes a short brief; a phase lead has one worker build each task, one reviewer review the branch, and a fix wave apply the accepted findings; a verifier checks gates and deliverables |
| `building-phased-specs-in-parallel` | The same per-phase work, when the document's phases form a graph rather than a chain | as `building-phased-specs`, but every phase whose `Depends on` phases have landed starts at once (up to 3 by default) in its own git worktree; a phase sharing code files with one in flight goes to an overlap judge, which holds it only when both make major changes to the same domain; each verified phase merges the moved base into itself, has conflicts resolved and gates re-run, then lands; a failing phase gets a repair and a rescue, then the run drains |
| `orchestrating-phased-specs` | Exploratory specs that benefit from a full implementation plan | writes a Superpowers plan, executes it with `subagent-driven-development`, verifies |
| `executing-phased-specs` | The same plan-driven path, trying inline execution | writes a Superpowers plan; one executor implements every task itself with `executing-plans`, then dispatches one fresh reviewer over the phase and runs one fix round; verifies |

All four share the scripts in `shared/scripts/`, keep a resumable ledger, and end
at a report — nothing pushed, no PR opened. The sequential three run exactly one
repair attempt per phase; the parallel skill allows a repair and a rescue. Each
skill keeps its runs in its own run directory (`.superpowers/phase-builder/`,
`.superpowers/phase-orchestrator/`, `.superpowers/phase-executor/` and
`.superpowers/phase-parallel/`).

## Install

```bash
./install.sh                      # every skill, Claude Code
./install.sh claude building      # one skill (building, orchestrating, executing or parallel)
./install.sh codex                # every skill, Codex
./install.sh all all              # every skill, both hosts
```

Symlinks `skills/<name>/` into the host's skills directory, so edits here are
live. Claude uses `~/.claude/skills`; Codex uses `~/.agents/skills`. Override
those with `CLAUDE_SKILLS_DIR` or `CODEX_SKILLS_DIR`. Re-running the installer
over an older install that linked the repository root repoints it. Existing
non-symlink destinations are preserved. Refresh skill discovery or restart the
host if a skill is not visible.

`orchestrating-phased-specs` and `executing-phased-specs` also need Superpowers
installed.
`building-phased-specs` needs nothing beyond Bash, Git and nested agents;
`building-phased-specs-in-parallel` also needs background agents and room for
`1 + 2 × cap` of them at once. Read
each skill's `platform-guide.md` for dispatch, model mapping and permissions.

## Invoke

Invoking by name is deterministic:

```
/building-phased-specs phases 2 to 6 of docs/specs/example-design.md on branch feat/example
/building-phased-specs-in-parallel phases 2 to 6 of docs/specs/example-design.md on branch feat/example up to 3 in parallel
/orchestrating-phased-specs phases 2 to 6 of docs/specs/example-design.md on branch feat/example
/executing-phased-specs phases 2 to 6 of docs/specs/example-design.md on branch feat/example
```

In Codex, mention the skill as `$building-phased-specs`. With looser wording —
"work on phases 2 to 6 of …" — the descriptions route to
`building-phased-specs`. `building-phased-specs-in-parallel` fires when you ask
for the phases in parallel, concurrently or in worktrees, or name it;
`orchestrating-phased-specs` fires only when you ask for plan-driven execution
("… with plans") or name it, and `executing-phased-specs` only when you ask for
those plans executed inline or name it.

## Layout

```
shared/scripts/          parse-phases, phase-run-dir, phase-preflight, phase-start, phase-finish,
                         and for the parallel skill parse-deps, phase-state, phase-schedule,
                         phase-overlap, phase-worktree, phase-integrate, phase-land
shared/scripts/__tests__ the shell test suite for scripts, installer and every skill
skills/<name>/           SKILL.md, dispatch templates, platform guide
skills/<name>/scripts/   thin wrappers that set the skill's run-directory namespace
docs/superpowers/specs/  the design documents for every skill
```

## Tests

```bash
bash shared/scripts/__tests__/run-tests.sh
shellcheck shared/scripts/* skills/*/scripts/* install.sh shared/scripts/__tests__/*.sh
```

No test framework, no package manager — plain bash.

## Status

The shell suite verifies scripts, installation and Git-state behaviour in
temporary repositories, and checks every skill's templates structurally. Live
multi-phase runs are the real verification; see each design document's
verification sections.
