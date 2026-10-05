# Platform guide: Claude Code and Codex

Read this once before preflight. The phase workflow and return contracts are the
same on both hosts. Template envelopes (`Subagent (general-purpose)`, `model`,
`prompt`) describe intent; translate them to tools actually exposed by the host.

## Shared prerequisites

- Bash, Git, and the target repository's own test/build dependencies. No other
  skill is required.
- Native nested agents, sharing the target checkout: controller → phase lead →
  worker/reviewer. This is three agent levels, or two edges below the root.
  Scout, verifier and repair are direct children of the controller and spawn
  nothing; only the phase lead nests. Workers and the reviewer are leaves. Check
  exposed depth/capacity limits; do not infer them from a brand.
- Enough capacity for the controller, the phase lead, and one worker
  concurrently. Dispatch sequentially. Await completion before branch changes or
  the next role. Release finished agents if the host counts retained agents
  against its limit; use the host's actual lifecycle tools.
- Permission to edit the target checkout, update Git metadata, run tests, and
  write ignored run-directory files. The skill cannot change sandbox rules or
  grant approvals. Report missing capabilities before preflight whenever they are
  observable.

Use the host's bounded wait/result tools and required progress-update cadence.
A spawn acknowledgement is not completion. Do not launch a duplicate agent
because an existing one is taking time; reconcile its status and persisted output.

## Model tiers

| Role | Tier |
|---|---|
| scout, phase lead, reviewer, repair | most capable |
| worker: task the brief marks `Tier: standard`, and every fix | most capable |
| worker: task the brief marks `Tier: mechanical` | mid-tier |
| verifier | mid-tier |

There is no cheap tier in this workflow. The scout assigns each task's tier
under the criteria in `scout-prompt.md`; the lead applies it and does not
downgrade a `standard` task. Fix-wave workers always use the most capable tier.


## Check discipline and the command guard

Workers run only the brief's `Checks:` — the tests related to the files they
changed and a typecheck — and the verifier runs the `Full suites:` once. The
templates make that likely, not certain: a worker that reaches for the root
test command anyway costs minutes of every phase.

A repository can enforce it with a Claude Code `PreToolUse` hook on Bash of
its own. On a `phase-<N>-<slug>` branch it refuses whole-suite and
production-build commands unless they start with `FULL_CHECKS=1`, which only
the verifier templates mention; it refuses a test command identical to one
that already finished on the same tree; and it appends every check it sees to
`<git common dir>/agent-checks.log`, in the format the header of
`shared/scripts/phase-metrics` gives. The skill neither installs nor requires
it. With or without it, each landing appends a `metrics` line to the ledger:
lines of source and test the phase added, and the log's counts when there is
one.

## Claude Code

Installation: `./install.sh` (or `./install.sh claude building`) links
`skills/building-phased-specs/` into `~/.claude/skills/building-phased-specs`.
`CLAUDE_SKILLS_DIR` overrides the parent destination.

Use the exposed Agent tool (Task on older hosts) with a general-purpose agent,
the substituted template prompt, and an explicit model. Map the most capable
tier to `opus` and the mid-tier to `sonnet`; honor a user-selected mapping
instead. Do not use read-only agent types (Explore, Plan) for any role: the scout
writes the brief, and the verifier writes evidence.

Nested-agent support depends on the installed version and configuration. The
current documentation describes `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`; where
supported it must allow at least two layers below the main conversation. Do not
change this setting automatically. See [Claude Code subagents](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents).

Configure allowed operations before an unattended run; bypass-permissions is not
a requirement and the skill must not enable it itself.

## Codex

Installation: `./install.sh codex building` links the skill into
`~/.agents/skills/building-phased-specs`. `CODEX_SKILLS_DIR` overrides the parent
destination. Restart or refresh skill discovery if the skill does not appear.

Use native agent tools, not `create_thread` or separate user-visible tasks as
workers. Tool names and fields vary by Codex surface:

- With `collaboration.spawn_agent`, map description to a unique `task_name`,
  substituted prompt to `message`, and tier to an available `model`. Set
  `fork_turns: "none"` for fresh context. Receive results via the host's agent
  notifications and wait tools.
- With another native `spawn_agent` schema, use its declared message, model,
  context, wait, and lifecycle fields. Never pass fields from the other schema.
- Choose the strongest available model for every most-capable role in the
  table above, and a capable mid-tier model for the verifier and for
  `Tier: mechanical` task workers. Resolve actual IDs from the live tool
  schema or session configuration; do not hard-code a model generation. If
  explicit model selection is unavailable, inherit and record that fact.

Fresh agents need a self-contained prompt: absolute repository, template, brief
and artifact paths; phase and base identity; return contract; and the model
mapping when they dispatch children. They must read applicable repository
instructions. Do not fork the entire conversation to convey this setup.

Respect the active sandbox and approval policy. Report required approvals or
missing nested-agent support as blockers. Do not disable safeguards or substitute
shell-launched agents to evade a native-tool restriction.
