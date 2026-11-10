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
  lead, repair or rescue) and, under a lead, one worker or reviewer. The open
  batch runs one more — its resolver or integration verifier — for phases that
  count against `CAP` and run nothing themselves. If the host allows fewer,
  lower `CAP` before starting and say so; never exceed the host's limit by
  queueing blind.
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
- **Pushing and the pull request**: an `origin` remote (preflight refuses
  without one), Git credentials that push without a prompt (the scripts set
  `GIT_TERMINAL_PROMPT=0`, so a missing credential is a recorded failure, not
  a hang), and the GitHub CLI `gh`, authenticated, for the pull request at the
  end. Without `gh` the run still pushes base and reports the command to open
  the pull request by hand. Check `gh auth status` before preflight.

Use the host's bounded wait/result tools and required progress-update cadence.
A spawn acknowledgement is not completion. Do not launch a duplicate agent
because an existing one is taking time; reconcile its status and persisted
output. A host may end a background lead's turn while the worker it dispatched
is still running, so the lead hands back without a status: wait for that
worker's own report before dispatching a lead again, so two agents never work
one task. Release finished agents if the host counts retained agents against its
limit.

Every agent works in its phase's worktree — the resolver and the integration
verifier in the run's integration worktree, `.worktrees/integration` — never in
the main checkout. Give each one the absolute `WORKTREE` path and absolute
artifact paths; never rely on an inherited working directory.

## Model tiers

| Tier | Roles |
|---|---|
| top | overlap judge, reviewer, repair, rescue, resolver; scout in the cases under Scout tier below; worker on a task the brief marks `Tier: hard`; fix worker whose findings touch a file of a `Tier: hard` task |
| strong | scout, phase lead; worker on a task the brief marks `Tier: standard` or gives no Tier line; every other fix worker |
| mid-tier | worker on a task the brief marks `Tier: mechanical`; integration verifier (gates and acceptance check, once per batch; the final check); graph agent |

The top tier is the most capable model the host offers. It takes the work
that costs the most when it is wrong: judgement calls on a whole phase, and
work that later work is built on. The strong tier is the next model down and
carries the rest of the volume: most grounding, leading and most of the code.
There is no cheap tier in this workflow.

The scout assigns each task's tier under the criteria in `scout-prompt.md`.
The lead applies it and never dispatches a task below the tier its brief
assigns.

### Scout tier

The controller dispatches the scout on the top tier when at least one
statement below is true, and on the strong tier otherwise. It decides from the
scheduler's action and the ledger alone.

- The dispatch is a `rescout`: the phase was held, and its brief is corrected
  against a base that moved.
- A phase it depends on directly, by the ledger's `graph:` line, has a
  `grounded` or `executed` ledger line that
  counts one or more `significant`: the document no longer describes what
  that phase built.
- Two or more requested phases depend on it directly, by the ledger's
  `graph:` line: what its brief gets wrong, they inherit.

### The mapping

Resolve the mapping once, before preflight, as one line:
`top=<model>, strong=<model>, mid-tier=<model>`. That line is `MODEL_MAPPING`.
Use it for every dispatch of the run, and name the tier's model explicitly on
each one. The host sections below give the default; the request needs no
model instruction. A mapping the user states in the request replaces the
default for the tiers or roles it names; append a role exception to the line
as `<role>=<model>`.

When the host offers no model above the strong tier's,
top and strong are the same model.

When top is a different model from strong and the host refuses a dispatch on
the top model because of the model — it is not offered, or its usage limit is
spent — dispatch the same role again on the strong model. The controller then
replaces the top model with the strong model everywhere in `MODEL_MAPPING`
for the rest of the run and appends `run: models — <MODEL_MAPPING>` to the
ledger. A lead does the same for its own dispatches and says
`top tier unavailable` in its return; the controller treats that return as a
refusal of its own dispatch.


## Check discipline and the command guard

Workers run only the brief's `Checks:` — the tests related to the files they
changed and a typecheck — and the verifier runs the `Full suites:` once per
batch. The templates make that likely, not certain: a worker that reaches for
the root test command anyway costs minutes, and in a parallel run slows every
phase on the machine.

A repository can enforce it with a Claude Code `PreToolUse` hook on Bash of
its own. On a `phase-<N>-<slug>` branch, and on the `phase-batch-<K>` branches
the resolver works on, it refuses whole-suite and
production-build commands unless they start with `FULL_CHECKS=1`, which only
the verifier templates mention; it refuses a test command identical to one
that already finished on the same tree; and it appends every check it sees to
`<git common dir>/agent-checks.log`, in the format the header of
`shared/scripts/phase-metrics` gives. The skill neither installs nor requires
it. With or without it, each landing appends a `metrics` line per phase to
the ledger: lines of source and test the phase added, and the log's counts
when there is one.

Several phases building at once share one machine's cores. Cap the test
runner's worker count per worktree in the repository's own configuration, or
suites slow each other past tool timeouts and flake.

## Claude Code

Installation: `./install.sh` (or `./install.sh claude parallel`) links
`skills/building-phased-specs-in-parallel/` into
`~/.claude/skills/building-phased-specs-in-parallel`. `CLAUDE_SKILLS_DIR`
overrides the parent destination.

Use the exposed Agent tool (Task on older hosts) with a general-purpose agent,
the substituted template prompt, and an explicit model. Map the strong tier
to `opus` and the mid-tier to `sonnet`. Map the top tier to the alias the
Agent tool's `model` option offers above `opus` — `fable` today — and to
`opus` when it offers none. The session's own model does not change this
mapping: a controller running on the top model still dispatches scouts and
leads on `opus`. Do not use read-only agent types (Explore, Plan) for any
role: the scout writes the brief, and verifiers write evidence.

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
worktree, `git push`, and `gh pr create`. Bypass-permissions is not a requirement and the skill must not enable
it itself.

### Watching a run from the status line

`scripts/phase-statusline` prints one line about the run in the session's
repository, or nothing when there is none:

```
feat/x · 2/6 merged · 2 building · 1 queued · batch 3 verifying 2 · 1 repairing · 1 held · 1 left
```

Merged phases of those requested; phases building (scout, judge, lead);
queued for the next batch; the open batch and what it is doing (merging,
resolving, verifying, landing) with its phase count; repairing (failed in a
batch, in or awaiting the ladder); held; failed; not started. It adds
`draining` while the run drains, `idle <age>` when the ledger has not changed
for 15 minutes, and `+N runs` when other runs are active. It reads only the
ledger, through `phase-state`, and always exits 0.

Without a status line of your own, point Claude Code at it in
`~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/skills/building-phased-specs-in-parallel/scripts/phase-statusline"
}
```

With one, pass it the same session JSON and append its output, for example:

```bash
run=$(printf '%s' "$input" | bash ~/.claude/skills/building-phased-specs-in-parallel/scripts/phase-statusline)
[ -n "$run" ] && printf ' · %s' "$run"
```

The skill never edits the owner's settings or status line script.

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
- Choose the strongest available model for the top tier, the next model down
  for the strong tier, and a capable mid-tier model for the mid-tier roles in
  the table above. Resolve actual IDs from the live tool schema or session
  configuration; do not hard-code a model generation. If explicit model
  selection is unavailable, inherit and record that fact.

Fresh agents need a self-contained prompt: absolute worktree, template, brief
and artifact paths; phase and base identity; return contract; and the model
mapping when they dispatch children. They must read applicable repository
instructions. Do not fork the entire conversation to convey this setup.

Respect the active sandbox and approval policy. Report required approvals,
missing nested-agent support or insufficient concurrency as blockers. Do not
disable safeguards or substitute shell-launched agents to evade a native-tool
restriction.
