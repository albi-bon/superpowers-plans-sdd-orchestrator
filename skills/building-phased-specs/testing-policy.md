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

A handful of tests per task is normal. If you are writing dozens, you are
testing something other than behaviour.

## How to write them

- Drive the public surface: the route, the command, the component the way a user
  operates it, the exported function. Private helpers are covered through it.
- Mock only at system boundaries: network, clock, randomness, filesystem,
  third-party services. The module under test and its in-repository
  collaborators run for real.
- See each core behaviour test fail once: run it before the implementation
  exists, or break the implementation briefly and watch it go red. A test that
  has never failed has not been shown to test anything.
- Use the repository's existing test framework, helpers, fixtures and naming.
- Run the tests you wrote and judge them by the runner's exit code, not by its
  printed summary.

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
