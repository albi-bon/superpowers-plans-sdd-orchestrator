# Platform guide: Claude Code and Codex

Read this once before preflight. The phase workflow and return contracts are the
same on both hosts. Template envelopes (`Subagent (general-purpose)`, `model`,
`prompt`) describe intent; translate them to tools actually exposed by the host.

## Shared prerequisites

- Bash, Git with `git worktree`, and the target repository's own test, build and
  install dependencies. No other skill is required.
- Native nested agents: controller → phase lead → worker/reviewer. This is
  three agent levels, or two edges below the root. Every other role is a direct
  child of the controller and spawns nothing; only the phase lead nests.
  Workers and the reviewer are leaves. Check exposed depth limits; do not infer
  them from a brand.
- **Concurrent capacity of `1 + 2 × CAP` agents**: the controller, plus up to
  `CAP` phases each running one controller-level agent (scout, overlap judge,
  lead, repair, rescue, resolver or integration verifier) and, under
  a lead, one worker or reviewer. If the host allows fewer, lower `CAP` before starting and
  say so; never exceed the host's limit by queueing blind.
- **Background dispatch**: the controller dispatches agents without blocking on
  them and is notified, or can wait, as each one finishes. It handles returns
  one at a time. A host that can only run one blocking agent at a time runs this
  skill correctly but sequentially; use `building-phased-specs` there instead.
- Permission to edit files inside the repository — including
  `<repo>/.worktrees/` and `<repo>/.superpowers/` — update Git metadata, create
  and remove worktrees, run the repository's install command, run tests, and
  write ignored run-directory files. The skill cannot change sandbox rules or
  grant approvals. Report missing capabilities before preflight whenever they
  are observable.

Use the host's bounded wait/result tools and required progress-update cadence.
A spawn acknowledgement is not completion. Do not launch a duplicate agent
because an existing one is taking time; reconcile its status and persisted
output. A host may end a background lead's turn while the worker it dispatched
is still running, so the lead hands back without a status: wait for that
worker's own report before dispatching a lead again, so two agents never work
one task. Release finished agents if the host counts retained agents against its
limit.

Every agent works in its phase's worktree, never in the main checkout. Give
each one the absolute `WORKTREE` path and absolute artifact paths; never rely on
an inherited working directory.

## Model tiers

| Role | Tier |
|---|---|
| scout, overlap judge, phase lead, reviewer, repair, rescue, resolver | most capable |
| worker: task the brief marks `Tier: standard`, and every fix | most capable |
| worker: task the brief marks `Tier: mechanical` | mid-tier |
| integration verifier (gates and acceptance check, once per phase), graph agent | mid-tier |

There is no cheap tier in this workflow. The scout assigns each task's tier
under the criteria in `scout-prompt.md`; the lead applies it and does not
downgrade a `standard` task. Fix-wave workers always use the most capable tier.

## Claude Code

Installation: `./install.sh` (or `./install.sh claude parallel`) links
`skills/building-phased-specs-in-parallel/` into
`~/.claude/skills/building-phased-specs-in-parallel`. `CLAUDE_SKILLS_DIR`
overrides the parent destination.

Use the exposed Agent tool (Task on older hosts) with a general-purpose agent,
the substituted template prompt, and an explicit model. Map the most capable
tier to `opus` and the mid-tier to `sonnet`; honor a user-selected mapping
instead. Do not use read-only agent types (Explore, Plan) for any role: the
scout writes the brief, and verifiers write evidence.

Dispatch agents in the background so several phases run at once; Claude Code
notifies the controller as each finishes. Do not pass the Agent tool's own
worktree isolation option: this skill creates and names its worktrees itself
with `phase-worktree`, and an agent must work in the one it is given.

Nested-agent support depends on the installed version and configuration. The
current documentation describes `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`; where
supported it must allow at least two layers below the main conversation. Do not
change this setting automatically. See [Claude Code subagents](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents).

Configure allowed operations before an unattended run — including the
repository's install command, which every phase's scout runs in a fresh
worktree. Bypass-permissions is not a requirement and the skill must not enable
it itself.

## Codex

Installation: `./install.sh codex parallel` links the skill into
`~/.agents/skills/building-phased-specs-in-parallel`. `CODEX_SKILLS_DIR`
overrides the parent destination. Restart or refresh skill discovery if the
skill does not appear.

Use native agent tools, not `create_thread` or separate user-visible tasks as
workers. Tool names and fields vary by Codex surface:

- With `collaboration.spawn_agent`, map description to a unique `task_name`,
  substituted prompt to `message`, and tier to an available `model`. Set
  `fork_turns: "none"` for fresh context. Spawn without waiting, then use the
  host's agent notifications and wait tools to receive each result as it
  finishes.
- With another native `spawn_agent` schema, use its declared message, model,
  context, wait, and lifecycle fields. Never pass fields from the other schema.
- Choose the strongest available model for every most-capable role in the
  table above, and a capable mid-tier model for the mid-tier roles. Resolve
  actual IDs from the live tool schema or session configuration; do not
  hard-code a model generation. If explicit model selection is unavailable,
  inherit and record that fact.

Fresh agents need a self-contained prompt: absolute worktree, template, brief
and artifact paths; phase and base identity; return contract; and the model
mapping when they dispatch children. They must read applicable repository
instructions. Do not fork the entire conversation to convey this setup.

Respect the active sandbox and approval policy. Report required approvals,
missing nested-agent support or insufficient concurrency as blockers. Do not
disable safeguards or substitute shell-launched agents to evade a native-tool
restriction.
