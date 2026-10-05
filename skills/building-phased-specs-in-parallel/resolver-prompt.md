# Resolver Dispatch Template

Dispatched at integration, only when merging the base branch into a built
phase branch stopped on a textual conflict. Other phases landed on base while
this one was being built; the resolver makes both sides live together. The merge
is already in progress in the phase's worktree when it starts. Substitute every
uppercase placeholder value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Resolve integration conflicts for phase PHASE_NUMBER"
  model: the most capable model available — this agent decides how two
         independently built phases fit together, unattended. Resolve the
         actual model through platform-guide.md; record inheritance if
         selection is unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of this phase's worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    A merge of the base branch into this phase's branch stopped on conflicts.
    You resolve them so that both this phase's behaviour and the behaviour of
    every phase merged into the base since this one began still hold.

    Phase number:    PHASE_NUMBER
    Phase branch:    PHASE_BRANCH          (checked out in WORKTREE, merge in progress)
    Base branch:     BASE                  (being merged in; "theirs" in this merge)
    Conflicts file:  CONFLICTS_PATH        (conflicted paths, and the phases merged since this one began)
    Brief:           BRIEF_PATH            (this phase)
    Decisions file:  DECISIONS_PATH        (this phase; you append to it)
    Merged phases:   MERGED_PHASE_BRIEFS   (brief and decisions paths of each phase merged since)
    Testing policy:  TESTING_POLICY_PATH
    Decision policy: DECISION_POLICY_PATH  (read it before you start)

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    1. Read CONFLICTS_PATH, then `git status` to confirm the merge is in
       progress and which paths are unmerged.
    2. Read this phase's brief header, Global constraints, and the tasks whose
       Files lines name a conflicted path. Read each merged phase's brief the
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
       command, and record which command:
       - Lockfiles are never hand-merged: take the base branch's version, then
         regenerate it with the repository's own package manager so it
         reflects both sides' manifests.
       - Generated files (agent-instruction files built from rules, codegen
         output, anything the repository's instructions say is generated):
         resolve the sources first, then rerun the generator and take its
         output.
       - ORM migration metadata (snapshots, journals, lock files): take the
         base branch's metadata and migrations as they are. If this phase
         added a migration, remove it and its metadata entries, then
         regenerate it with the repository's migration generator against the
         merged schema, so it follows the base branch's latest migration.
       - Translation catalogues: keep every key from both sides. Where both
         sides added the same key with different text, choose one and record
         it.
    5. A non-conflicted file may need a small change for the merged result to
       build — a call site the other phase renamed, an import the other phase
       moved. Make it; it is part of the resolution. Nothing beyond that.
    6. Run the brief's `Checks:` over every file you touched — the related
       tests and the typecheck — and lint where the repository has it. Do not
       run a command from the brief's `Full suites:` line; the integration
       verifier runs next. Judge every command by its exit code, never by its
       printed summary.
    7. Conclude the merge with `git commit --no-edit` and leave the working
       tree clean.
    8. Append your decisions to DECISIONS_PATH under the decision policy. A
       resolution that changes either phase's behaviour is significant.

    If the two sides cannot both hold without redesigning one of the phases,
    run `git merge --abort`, confirm with `git status` that the working tree is
    clean at the commit it was on before the merge, and return UNRESOLVED. A
    different agent with a wider mandate takes it from there.

    ## Constraints

    - Work only inside WORKTREE. Do NOT touch the main checkout, the base
      branch BASE, or any other phase's worktree or branch. Other phases are
      being built beside this one right now.
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
