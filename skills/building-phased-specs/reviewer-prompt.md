# Reviewer Dispatch Template

Dispatched by the phase lead exactly once per phase, after the last task. It is
the only review the phase gets. Substitute every uppercase placeholder value
before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Review phase PHASE_NUMBER"
  model: the most capable model available — this is the phase's only review,
         and a defect in an early task has had every later task built on top
         of it. Resolve the actual model through platform-guide.md; record
         inheritance if selection is unavailable.
  prompt: |
    Repository: REPO_ROOT (absolute path; use it for every shell working directory)
    Read applicable repository instructions. All artifact paths below are absolute.

    Review one phase of a phased design document. You did not write this
    code.

    Design document: DESIGN_DOC      (read phase PHASE_NUMBER's section)
    Brief:           BRIEF_PATH      (what the phase was split into, and its drift table)
    Decisions file:  DECISIONS_PATH  (choices the agents made on their own)
    Testing policy:  TESTING_POLICY_PATH
    Review range:    PHASE_BASE_SHA..HEAD on PHASE_BRANCH
    Findings file:   FINDINGS_PATH

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    Review exactly the range `git diff PHASE_BASE_SHA..HEAD`. Earlier phases
    are already integrated and are not under review. Read the surrounding code
    wherever you need it to judge a change.

    Look for these, in this order of importance:

    1. Correctness: logic errors, unhandled cases, broken error paths, race
       conditions, resource leaks, anything that breaks existing behaviour.
    2. Coverage of the phase: a deliverable in the phase section or a brief
       task's Done when that was not built, or was built differently with no
       recorded decision explaining why.
    3. Decisions: a recorded significant decision that contradicts the design
       document's decision log, or that the phase's own requirements rule out.
    4. Security and data integrity.
    5. Tests, judged against the testing policy: a Done-when behaviour with no
       test; tests of copy, layout, snapshots or implementation details that
       should not exist; tests that could not fail.
    6. Leftovers: dead code, debug output, commented-out code, TODOs standing
       in for required behaviour.

    Spend your effort in proportion to the phase's size. Skip style
    preferences the repository's linters do not enforce.

    Write FINDINGS_PATH in this shape, one block per finding, most severe
    first:

    ~~~markdown
    ## F1 — critical — <one-line title>
    - **Where:** <repository-relative path:line>
    - **Problem:** <what is wrong and how it fails, concretely>
    - **Fix:** <the change you recommend>
    ~~~

    Severity:
    - **critical** — wrong behaviour, data loss, a security hole, or a missing
      deliverable.
    - **important** — a real defect or gap that will bite later: an unhandled
      edge case, a missing behaviour test, a decision that strains the
      document's intent.
    - **minor** — worth doing, safe to defer.

    If you find nothing, write "No findings." to FINDINGS_PATH.

    ## Constraints

    - Do NOT edit, fix, or commit anything. You write only FINDINGS_PATH.
    - Do NOT switch branches.

    ## Return contract

    At most three lines:
    - findings: <critical> critical, <important> important, <minor> minor
    - FINDINGS_PATH

    Do not paste findings, code, or diffs into your reply.
```
