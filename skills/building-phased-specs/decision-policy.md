# Decision policy

Every agent in a `building-phased-specs` run reads this file, except the verifier.
The run is unattended. Nobody will answer a question, so you never ask one.

## Resolve, record, continue

When you hit drift between the design document and the repository, an ambiguity,
a contradiction, or an implementation problem of any size, you decide and keep
going. Choose, in this order of precedence:

1. the option most faithful to the design document's intent and its decision log;
2. then the one that follows the repository's existing conventions;
3. then the simplest option that satisfies both.

Implement it, then append one line to the decisions file you were given:

```
- [significant] <what you decided> — instead of <the alternative> — because <reason> (<your role>, task <K> if any)
- [routine] <what you decided> — instead of <the alternative> — because <reason> (<your role>)
```

A decision is **significant** when it changes a public API, a data model or
schema, a user-visible behaviour, or the phase's scope, or when it departs from an
item in the design document's decision log. Every other decision is **routine**.

Significant decisions are counted in your return and listed in the run's final
report, so the owner can audit them afterwards. Recording one is not an admission
of failure; an unrecorded one is.

Where the document contradicts itself, the decision log wins, then the more
specific statement over the more general one, then the later phase's statement
over an earlier one when the later phase is the one being built.

## When to return BLOCKED

`BLOCKED` exists for work that cannot proceed or must not. This is the complete
list. It is exhaustive; nothing outside it qualifies.

1. Missing credentials, access, or a required host approval.
2. A required tool, service or runtime is absent and cannot be installed with the
   repository's own tooling (its package manager, its scripts).
3. The host cannot nest agents, so the phase lead cannot dispatch workers.
4. The only way forward is destructive or outside the repository's scope:
   dropping or rewriting real data, rewriting shared git history, touching
   production or any external system, spending money.

A design problem is never on this list, however large. Neither is a missing
prerequisite (build it), a wrong assumption in the document (adapt and record),
a failing test (fix it), or an unclear requirement (decide and record).

| Thought | What to do instead |
|---|---|
| "The document assumes an API that doesn't exist" | Build the smallest version that serves the phase, or adapt to what exists. Record it as significant. |
| "Two sections of the document disagree" | Apply the precedence above. Record which one you followed. |
| "This is a big change; the owner should decide" | The owner delegated it. Decide, record it as significant, continue. |
| "I'm not sure which option is right" | Pick the one the precedence favours. Uncertainty is what the record is for. |
| "An earlier phase built this differently than the document says" | This phase builds on what exists. Adapt and record. |
