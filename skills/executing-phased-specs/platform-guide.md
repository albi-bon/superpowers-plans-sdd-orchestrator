# Platform guide: Claude Code and Codex

Read this once before preflight. The phase workflow and return contracts are the
same on both hosts. Template envelopes (`Subagent (general-purpose)`, `model`,
`prompt`) describe intent; translate them to tools actually exposed by the host.

## Shared prerequisites

- Bash, Git, and the target repository's own test/build dependencies.
- Superpowers installed and discoverable on this host. Resolve `writing-plans`,
  `executing-plans`, `test-driven-development`, `verification-before-completion`,
  `systematic-debugging`, and `requesting-code-review` to their actual `SKILL.md`
  paths, and `requesting-code-review`'s `code-reviewer.md` beside it. Inspect the
  installed skills: this workflow requires `executing-plans`' `scripts/task-done`
  and the sibling `subagent-driven-development`'s `scripts/sdd-workspace` and
  `scripts/review-package`, which `executing-plans` calls. It does not use
  `executing-plans`' `scripts/task-start`. If a required script is absent, stop
  and report the incompatible dependency rather than inventing paths or
  installing silently.
- Native nested agents, sharing the target checkout: controller → executor →
  reviewer. This is three agent levels, or two edges below the root. Planner,
  verifier, and repair are direct children of the controller. They should not
  spawn helpers; only the executor needs nesting, for exactly one reviewer per
  phase, which is a leaf. Check exposed depth/capacity limits; do not infer them
  from a brand.
- Enough capacity for the controller, executor, and one reviewer concurrently.
  Dispatch sequentially. Await completion before branch changes or the next role.
  Release finished agents if the host counts retained agents against its limit;
  use the host's actual lifecycle tools, not an invented close operation.
- Permission to edit the target checkout, update Git metadata, run tests, and write
  ignored evidence. The skill cannot change sandbox rules or grant approvals.
  Report missing capabilities before preflight whenever they are observable.

Use the host's bounded wait/result tools and required progress-update cadence.
A spawn acknowledgement is not completion. Do not launch a duplicate worker
because an existing one is taking time; reconcile its status and persisted output.

## Claude Code

Installation: `./install.sh` or `./install.sh claude executing` links
`skills/executing-phased-specs/` into `~/.claude/skills/executing-phased-specs`.
`CLAUDE_SKILLS_DIR` overrides the parent destination for tests or a project
installation.

Use the exposed Agent tool (Task on older hosts) with a general-purpose agent,
the substituted template prompt, and an explicit supported model. Map the most
capable tier to `opus`, the mid-tier to `sonnet`, and mechanical worker tasks to
`haiku` when those aliases are available; honor a user-selected mapping instead.
Do not use the read-only Plan agent for the planner: it must write and commit.

Use the host's skill invocation mechanism, or read the resolved `SKILL.md` and
follow it if no invocation tool exists. Give workers the actual skill paths.
Configure allowed operations before an unattended run; bypass-permissions is
not a requirement and the skill must not enable it itself.

Nested-agent support depends on the installed version and configuration. The
current documentation describes `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`; where
supported it must allow at least two layers below the main conversation. Do not
change this setting automatically. See [Claude Code subagents](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents).

## Codex

Installation: `./install.sh codex executing` links the skill into
`~/.agents/skills/executing-phased-specs`. `CODEX_SKILLS_DIR` overrides the
parent destination. `./install.sh all` installs both hosts. Restart or refresh
skill discovery if the skill does not appear. See [Codex skills](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills).

Read the required skills using their resolved `SKILL.md` paths; a tool named
`Skill` is not required. Use native agent tools, not `create_thread` or separate
user-visible tasks as workers. Tool names and fields vary by Codex surface:

- With `collaboration.spawn_agent`, map description to a unique `task_name`,
  substituted prompt to `message`, and tier to an available `model`. Set
  `fork_turns: "none"` for fresh context and explicit model overrides. Use
  `send_message` for active-agent coordination and `followup_task` to resume an
  idle agent when those tools are exposed; receive results via the host's agent
  notifications and wait tools.
- With another native `spawn_agent` schema, use its declared message, model,
  context, wait, and lifecycle fields. Never pass fields from the other schema.
- Choose the strongest available model for planner/executor/repair and the
  executor's reviewer, and a capable mid-tier model for verifier. Resolve actual IDs from the live tool schema or
  session configuration; do not hard-code a model generation. If explicit model
  selection is unavailable, inherit and record that fact rather than inventing
  a model parameter.

Fresh agents need a self-contained prompt: absolute repository, skill/template,
plan, and artifact paths; phase/base identity; relevant scope and decisions;
return contract; and model mapping when they dispatch children. They must read
applicable repository instructions. Do not fork the entire conversation merely
to convey this setup, or assume it is inherited.

Respect the active sandbox and approval policy. Open/run the task in the target
repository with appropriate workspace access; a projectless session may lack
write access even when it can read the repository. Report required approvals or
missing nested-agent support as blockers. Do not disable safeguards or substitute
shell-launched agents to evade a native-tool restriction.
