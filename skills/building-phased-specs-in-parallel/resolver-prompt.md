# Resolver Dispatch Template

Dispatched while a batch is built, only when merging one phase onto the batch
branch stopped on a textual conflict. The batch branch holds the base branch
and the batch's phases merged before this one; the resolver makes this phase
live together with them. The merge is already in progress in the run's
integration worktree when it starts. Substitute every uppercase placeholder
value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Resolve batch BATCH_NUMBER conflicts for phase PHASE_NUMBER"
  model: the most capable model available — this agent decides how
         independently built phases fit together, unattended. Resolve the
         actual model through platform-guide.md; record inheritance if
         selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of the run's integration worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    A merge of one phase's branch into an integration batch stopped on
    conflicts. You resolve them so that this phase's behaviour and the
    behaviour of every phase on the other side still hold.

    Phase number:    PHASE_NUMBER
    Phase branch:    PHASE_BRANCH          (being merged in; "theirs" in this merge)
    Batch branch:    BATCH_BRANCH          (checked out in WORKTREE, merge in progress; "ours": BASE plus the batch's earlier phases)
    Base branch:     BASE
    Conflicts file:  CONFLICTS_PATH        (conflicted paths, and the phases on the other side)
    Brief:           BRIEF_PATH            (this phase)
    Decisions file:  DECISIONS_PATH        (this phase; you append to it)
    Other phases:    MERGED_PHASE_BRIEFS   (brief and decisions paths of each phase on the other side)
    Setup command:   SETUP_COMMAND
    Setup marker:    SETUP_MARKER          (the commit the worktree's dependencies were last installed for)
    Testing policy:  TESTING_POLICY_PATH
    Decision policy: DECISION_POLICY_PATH  (read it before you start)

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    1. Read CONFLICTS_PATH, then `git status` to confirm the merge is in
       progress and which paths are unmerged.
    2. Read this phase's brief header, Global constraints, and the tasks whose
       Files lines name a conflicted path. Read each other phase's brief the
       same way, and every decisions file you were given. You need to know
       what each side meant to do, not only what it typed.
    3. Resolve every conflicted path so that both sides' behaviour holds. A
       rename on one side and a new caller on the other means the caller uses
       the new name. Two additions to one list keep both entries. Where the
       sides genuinely contradict, apply the decision policy's precedence and
       record the choice. Never settle a source file by taking one side
       wholesale (`--ours`, `--theirs`, `-X`) unless the other side's change is
       fully contained in it, and record that you did.
    4. Conflicts are expected here: phases may share files, and only a clash
       of designs held one back. Files a tool produces are never hand-merged;
       regenerate them from the merged sources with the repository's own
       command, and record which command. The worktree is shared by every
       batch: if dependencies are missing or SETUP_MARKER is absent, run
       SETUP_COMMAND (or the brief's `Setup:` line when it is "none — discover
       it") first, and after it exits 0 write HEAD's full SHA to SETUP_MARKER.
       - Lockfiles are never hand-merged: take the batch side's version, then
         regenerate it with the repository's own package manager so it
         reflects both sides' manifests.
       - Generated files (agent-instruction files built from rules, codegen
         output, anything the repository's instructions say is generated):
         resolve the sources first, then rerun the generator and take its
         output.
       - ORM migration metadata (snapshots, journals, lock files): take the
         batch side's metadata and migrations as they are. If this phase
         added a migration, remove it and its metadata entries, then
         regenerate it with the repository's migration generator against the
         merged schema, so it follows the batch side's latest migration.
       - Translation catalogues: keep every key from both sides. Where both
         sides added the same key with different text, choose one and record
         it.
    5. A non-conflicted file may need a small change for the merged result to
       build — a call site the other side renamed, an import the other side
       moved. Make it; it is part of the resolution. Nothing beyond that.
    6. Run the brief's `Checks:` over every file you touched — the related
       tests and the typecheck — and lint where the repository has it. Do not
       run a command from the brief's `Full suites:` line; the integration
       verifier runs next. Judge every command by its exit code, never by its
       printed summary.
    7. Conclude the merge with `git commit --no-edit` and leave the working
       tree clean.
    8. Append your decisions to DECISIONS_PATH under the decision policy. A
       resolution that changes either side's behaviour is significant.

    If the sides cannot both hold without redesigning one of the phases, run
    `git merge --abort`, confirm with `git status` that the working tree is
    clean at the commit it was on before the merge, and return UNRESOLVED.
    The batch carries on without this phase, and an agent with a wider
    mandate takes it from there.

    ## Constraints

    - Work only inside WORKTREE. Do NOT touch the main checkout, the base
      branch BASE, or any phase's worktree or branch. Phases are being built
      beside this batch right now.
    - The merge already in progress is the only merge you make. Do NOT switch
      branches, create branches, rebase, reset, or push.
    - Do not weaken, skip or delete a test or check to make the merge build.

    ## Return contract

    At most four lines:
    - RESOLVED <short merge commit SHA>, or UNRESOLVED — <one-line reason>
    - conflicted files: <count>
    - decisions: <significant count> significant
    - DECISIONS_PATH

    Do not paste conflict hunks, diffs, file contents, or test output into
    your reply.
```
