# Testing policy

Every task worker and fix worker follows this file, and the reviewer checks
against it. Tests exist to prove behaviour a user or caller relies on, and to
keep proving it as the code changes.

## What a task's tests cover

- One test per behaviour in the task's **Done when** and per acceptance criterion
  the phase names: a user flow, a command's effect, an endpoint's contract, a
  function's observable result.
- The edge and error cases the design document names explicitly.
- A regression test for every bug you hit while building the task.

## How many

Your ceiling is one test per **Done when** line, plus one per edge or error case
the design document names, plus one regression test per bug you hit. Work it
out yourself from your task; nobody hands you a list, and you choose what each
test is. Fewer is fine when one test proves several lines. Going over is
allowed when a behaviour truly needs it: say which tests and why in one line of
your report. Before adding a test file, extend the existing test of the same
unit. The reviewer does not count tests or raise findings over the ceiling;
keeping to it is yours.

## How to write them

- Drive the public surface: the route, the command, the component the way a user
  operates it, the exported function. Private helpers are covered through it.
- Mock only at system boundaries: network, clock, randomness, filesystem,
  third-party services. The module under test and its in-repository
  collaborators run for real.
- See each core behaviour test fail once: run it before the implementation
  exists, or break the implementation briefly and watch it go red. A test that
  has never failed has not been shown to test anything. One run of the new test
  file covers the red step; you do not need one per test. A task marked
  `Tier: mechanical` skips the red step.
- Use the repository's existing test framework, helpers, fixtures and naming.

## Running checks

Every test or typecheck run costs minutes, and in a parallel run it slows every
other phase on the machine. Run them sparingly.

- Use the brief's `Checks:` line: the repository's command for the tests
  related to the files you changed, and its typecheck. A brief without that
  line means the repository's own documented commands for the same two. Do
  not reach for a production build to typecheck when a typecheck exists.
- Never run the repository's full suites — the root test command, a whole
  package's suite, integration or end-to-end suites — listed on the brief's
  `Full suites:` line. The phase verifier runs them once, on the integrated
  tree. A repository may block them for you.
- Do not run the same command twice on an unchanged tree. Its result stands; a
  run that looks flaky is a finding for your report, not a reason to retry.
- Batch: finish an edit, then run the related tests once, rather than after
  every small change.
- Judge every run by the runner's exit code, not by its printed summary.

## What not to test

These tests break on every harmless change and prove nothing a user relies on.
Do not write them, and delete any you find yourself writing.

- Static copy, labels, headings, placeholder text, element order, layout, CSS
  classes, or styling. The exception is text that *is* the behaviour: a
  validation message the user must see, an error code a caller branches on.
- Markup or component snapshots.
- "Renders without crashing", "is defined", "exports a function".
- Tests that restate the implementation: that a function called its own
  internals, or that a mock returned what it was told to return.
