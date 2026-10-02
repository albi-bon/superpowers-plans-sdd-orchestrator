# Overlap Judge Dispatch Template

Dispatched after a scout, only when `phase-overlap` printed `overlap …`: the new
phase's brief names files that phases already in flight also touch. A shared
file alone is no reason to wait: integration resolves merge conflicts. The judge
reads both sides' briefs and decides whether the two phases would make major
changes to the same domain, in which case each would build a design the other
contradicts. It reads and writes nothing else. Substitute every uppercase
placeholder value before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Judge the overlap of phase PHASE_NUMBER"
  model: the most capable model available — a wrong "run" costs a rescue at
         integration, a wrong "hold" serialises the run. Resolve the actual
         model through platform-guide.md; record inheritance if selection is
         unavailable.
  prompt: |
    Repository: WORKTREE (absolute path of this phase's worktree; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    Phase PHASE_NUMBER has been grounded and is about to be built. Phases
    already in flight touch some of the same files. Decide whether phase
    PHASE_NUMBER builds now, beside them, or waits until one of them merges.

    Phase number:    PHASE_NUMBER
    Brief:           BRIEF_PATH            (this phase)
    Overlap file:    OVERLAP_PATH          (one line per shared file: <phase><TAB><path>)
    In-flight phases: IN_FLIGHT_BRIEFS     (for each phase in OVERLAP_PATH: number, branch, brief path, decisions path)
    Base branch:     BASE
    Verdict file:    VERDICT_PATH          (you write it)

    Do not spawn subagents; complete this bounded role yourself.

    ## The rule

    Hold only when both phases make a **major change to the same domain**:
    both reshape the same data model or schema, the same state machine, the
    same store shape, or the contract (signature, semantics, return shape)
    of the same core function or module. Then each phase builds on a design
    the other is replacing, and no merge can reconcile them.

    Everything else runs, however many files are shared:
    - Additive edits to a shared file: new entries in a list, registry,
      router, schema catalogue, barrel or config; new keys in a catalogue.
    - One side reshapes something and the other only uses or touches it (a
      new caller, an extra field read, a renamed import). The resolver moves
      the small side onto the new shape.
    - Shared tests, guards, fixtures, docs, generated files, migration
      metadata. Integration regenerates or merges these.
    - Edits to different parts of the same file.

    When you are unsure, run. A wrong run costs a conflict that the resolver,
    and if need be a rescue, works through; a wrong hold serialises phases the
    owner wanted built in parallel.

    ## Your job

    1. Read OVERLAP_PATH, then this phase's brief: header, Global constraints,
       and every task whose Files lines name a shared path.
    2. For each in-flight phase in OVERLAP_PATH, read its brief the same way,
       and its decisions file. Where its branch already has commits on a
       shared path, `git diff $(git merge-base BASE <branch>) <branch> --
       <path>` shows what it actually did; read nothing beyond the shared
       paths.
    3. Per in-flight phase: name the domain each side changes on the shared
       paths, and whether each change is major (reshapes it) or minor (adds
       to it, uses it). Hold only when both are major on the same domain.
    4. If several in-flight phases call for a hold, hold on the lowest
       numbered one; the overlap check runs again when it merges.
    5. Write VERDICT_PATH:

       ~~~markdown
       # Phase PHASE_NUMBER — overlap verdict

       verdict: run | hold on <M>
       reason: <one line>

       ## Phase <M>
       - shared: <paths>
       - phase PHASE_NUMBER: <domain> — major | minor — <what it changes>
       - phase <M>: <domain> — major | minor — <what it changes>
       - same domain, both major: yes | no
       ~~~

    ## Constraints

    - Read only. You write VERDICT_PATH and nothing else: no source file, no
      brief, no decisions file, no ledger, no commit.
    - Run no Git command that changes anything.
    - Do NOT touch the main checkout, the base branch BASE, or any phase's
      worktree or branch beyond reading them.

    ## Return contract

    At most three lines:
    - RUN — <one-line reason>, or HOLD <M> — <one-line reason naming the domain>
    - phases judged: <comma-separated numbers>
    - VERDICT_PATH

    Do not paste brief text, diffs, or your per-phase analysis into your
    reply. The verdict file is where it goes.
```
