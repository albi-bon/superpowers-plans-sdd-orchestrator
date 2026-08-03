# Orchestrating Phased Specs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the whole `orchestrating-phased-specs` skill in one pass — three bash scripts, four subagent dispatch templates, `SKILL.md`, and an installer — so that invoking it against a phased design document plans, executes, verifies and merges each requested phase unattended.

**Architecture:** This repository **is** the skill: `SKILL.md`, `install.sh` and `scripts/` sit at its root, and `install.sh` symlinks `~/.claude/skills/orchestrating-phased-specs` at the checkout. Everything mechanical lives in a standalone bash script that can be unit-tested (`parse-phases`, `phase-run-dir`, `phase-preflight`); everything judgment-shaped lives in a prompt template the orchestrator hands to a subagent (`planner-prompt.md`, `executor-prompt.md`, `verifier-prompt.md`, `repair-prompt.md`); `SKILL.md` is the loop that ties the two together and holds nothing but paths. Tests are plain bash files run by a tiny harness — no `bats`, no package manager, nothing to install.

**Tech Stack:** bash (must run under 3.2), `awk` (must run under BSD one-true-awk), `git` (2.23+ for `git switch`), `shellcheck` for linting. No runtime dependencies of any kind.

**Spec:** `docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md`.

## Supersedes

This plan replaces `docs/superpowers/plans/2026-08-03-orchestrating-phased-specs-phase-1-parsing-and-run-state.md`, which covered only the spec's §7 Phase 1. Tasks 1–3 below carry that plan's content forward essentially verbatim; Task 8 deletes it so two competing plans never coexist in the repository. The spec's §7 phase split is superseded too — the project is small enough to build in one plan, and Task 8 records that in the spec.

## Two deliberate deviations from the spec

Both were agreed with the owner before this plan was written. Task 4 amends the spec to record the first; Task 8 records the second.

1. **A third script, `scripts/phase-preflight`, implements §4.3.** The spec places preflight in `SKILL.md` as prose, which makes the spec's own §7 Phase 3 requirement — "preflight refuses on each of the six §4.3 checks, one test per check" — verifiable only by invoking the skill six times. As a script it is unit-testable against throwaway repositories. Task 4 amends §5's file tree and adds decision **D14** to §6.
2. **The real two-phase end-to-end run is dropped.** The spec's §7 Phase 3 requires one; executing it inside this plan would nest orchestrator → executor → implementer *underneath* an already-nested subagent-driven-development implementer, at a depth the spec's §8.1 has not verified. A failure there would be ambiguous between the skill and the harness. The automated gate stops at the script tests plus structural tests over the templates and `SKILL.md`. **The skill is therefore unproven end to end when this plan completes** — the first real run is the proof, and it is the owner's to make.

## Global Constraints

Every task's requirements implicitly include all of these. They come from the spec's §6 decision log.

- **D9 — project-agnostic.** No build command, no repository name, no project path is hard-coded anywhere in the skill. The verifier subagent derives a repository's gates at runtime.
- **D10 — phase identity is the number captured from the heading, never an ordinal index into the list.** A document whose phases start at 0 makes the two differ. Selecting `2-6` must yield the phases *numbered* 2,3,4,5,6.
- **D11 — portability.** Written for `bash` 3.2 and BSD one-true-awk:
  - never `\s` — use `[[:space:]]`
  - never a bracket expression containing the em dash (`—`, U+2014) or en dash (`–`, U+2013) — match separators as whole strings via `index()`
  - never an interval expression (`{2,4}`) in any regex
  - never bash-4-only syntax: no `${var,,}`, no `${var^^}`, no associative arrays, no `mapfile`/`readarray`
- **D12 — all artifacts are files; dispatches carry paths; return values are capped.** No template may instruct a subagent to paste a plan, a diff, or test output into its return value. Script output is data on stdout, diagnostics on stderr; every error message names what was wrong and what the valid values were.
- **D13 — permission mode is documented, not detected.** No script may attempt to read it.
- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`, is `chmod +x`, and passes `shellcheck` with zero findings.
- Every script prints a usage line to stderr and exits `2` when called with the wrong number of arguments.

**Exit-code contract, shared by all three scripts:**

| Code | Meaning |
|---|---|
| `0` | Success |
| `2` | Usage error, unreadable input file, or malformed range syntax |
| `3` | The design document contains no phase headings at all |
| `4` | The requested range names a phase number the document does not contain |
| `10` | Not inside a git repository (`phase-preflight` only) |
| `11` | Working tree not clean (`phase-preflight` only) |
| `12` | The base branch is `main` or `master` (`phase-preflight` only) |
| `13` | The base branch could not be resolved or created (`phase-preflight` only) |
| `14` | A phase branch exists that the ledger does not account for (`phase-preflight` only) |

## File Structure

```
orchestrating-phased-specs/                 ← git repo, main branch
  README.md                                 install and status
  install.sh                                symlink ~/.claude/skills/… at this checkout
  SKILL.md                                  the orchestration loop
  planner-prompt.md                         ① dispatch template
  executor-prompt.md                        ② dispatch template
  verifier-prompt.md                        ③ dispatch template
  repair-prompt.md                          repair dispatch template
  docs/superpowers/
    specs/2026-08-03-…-design.md            the spec this plan implements
    plans/2026-08-03-orchestrating-phased-specs.md   this plan
  scripts/
    parse-phases                            design doc → phase records; range selection
    phase-run-dir                           resolve/create the run directory, ensure git-ignored
    phase-preflight                         the six §4.3 checks; base-branch resolution
    __tests__/
      assert.sh                             assertion helpers, sourced by every test file
      run-tests.sh                          runs every *.test.sh, aggregates, exits non-zero on failure
      parse-phases.test.sh                  extraction + range tests
      phase-run-dir.test.sh                 run-directory tests
      phase-preflight.test.sh               preflight refusal + resolution tests
      templates.test.sh                     structural tests over the four dispatch templates
      skill.test.sh                         structural tests over SKILL.md
      install.test.sh                       installer tests
      fixtures/
        session-tracker-headings.md         the nine real headings from a real phased spec
        edge-cases.md                       dash variants, heading levels, duplicates, malformed
        no-phases.md                        a document with no phase headings
```

Responsibilities: `parse-phases` owns turning a document into phase records and selecting among them. `phase-run-dir` owns where a run's scratch artifacts live. `phase-preflight` owns whether a run may start at all, and composes the other two rather than duplicating them. The four templates own what each subagent must and must not do. `SKILL.md` owns the loop, the ledger, and nothing else.

**Every command in this plan runs from the repository root.** All paths are relative to it, except the absolute path of the external corroboration document used in Task 1 Step 9 and Task 2 Step 6.

---

### Task 1: Test harness and phase extraction

Builds the harness, the fixtures, and `parse-phases`' listing mode (no range argument — emit every phase found).

**Files:**
- Create: `scripts/__tests__/assert.sh`
- Create: `scripts/__tests__/run-tests.sh`
- Create: `scripts/__tests__/fixtures/session-tracker-headings.md`
- Create: `scripts/__tests__/fixtures/edge-cases.md`
- Create: `scripts/__tests__/fixtures/no-phases.md`
- Create: `scripts/__tests__/parse-phases.test.sh`
- Create: `scripts/parse-phases`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `parse-phases DESIGN_DOC` → stdout, one line per phase, ascending by number, fields tab-separated: `number<TAB>title<TAB>slug`. Exit `0`.
  - `assert.sh` exports shell functions `run_cmd`, `assert_eq`, `assert_rc`, `assert_contains`, `finish` — used verbatim by Tasks 2–8's test files.
  - Fixture paths above — Tasks 2 and 4 reuse `session-tracker-headings.md` and `edge-cases.md`.

- [ ] **Step 1: Create the assertion helpers**

Create `scripts/__tests__/assert.sh`:

```bash
# Assertion helpers for the plain-bash test files in this directory.
# Sourced, never executed. No `set -e` here: a failing assertion must record
# the failure and let the file keep running, so one run reports every problem
# rather than only the first.

TESTS_RUN=0
TESTS_FAILED=0

# run_cmd COMMAND [ARGS...]
# Runs the command, capturing combined output in OUT and exit status in RC.
# Never aborts the caller, whatever the command returns.
run_cmd() {
  set +e
  OUT=$("$@" 2>&1)
  RC=$?
  set -e
}

# assert_eq EXPECTED ACTUAL MESSAGE
assert_eq() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$1" = "$2" ]; then
    printf '  ok   %s\n' "$3"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL %s\n' "$3"
    printf '    expected: [%s]\n' "$1"
    printf '    actual:   [%s]\n' "$2"
  fi
}

# assert_rc EXPECTED_CODE MESSAGE   (reads RC set by run_cmd)
assert_rc() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$1" = "$RC" ]; then
    printf '  ok   %s\n' "$2"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL %s\n' "$2"
    printf '    expected exit: %s\n' "$1"
    printf '    actual exit:   %s\n' "$RC"
    printf '    output:        %s\n' "$OUT"
  fi
}

# assert_contains NEEDLE HAYSTACK MESSAGE
# Matching is a shell `case` glob, so a NEEDLE containing '*', '?' or '['
# is a pattern, not a literal. Callers pass needles free of those characters.
assert_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$2" in
    *"$1"*)
      printf '  ok   %s\n' "$3"
      ;;
    *)
      TESTS_FAILED=$((TESTS_FAILED + 1))
      printf '  FAIL %s\n' "$3"
      printf '    expected to contain: [%s]\n' "$1"
      printf '    actual:              [%s]\n' "$2"
      ;;
  esac
}

# finish — print the per-file summary and exit non-zero if anything failed.
finish() {
  printf '  %s run, %s failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ] || exit 1
}
```

- [ ] **Step 2: Create the test runner**

Create `scripts/__tests__/run-tests.sh`:

```bash
#!/usr/bin/env bash
# Run every *.test.sh in this directory. Exit non-zero if any file fails.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
failed=0

for f in "$here"/*.test.sh; do
  [ -e "$f" ] || continue
  printf '%s\n' "$(basename "$f")"
  if ! bash "$f"; then
    failed=$((failed + 1))
  fi
done

if [ "$failed" -ne 0 ]; then
  printf '\n%s test file(s) FAILED\n' "$failed"
  exit 1
fi

printf '\nall test files passed\n'
```

Then: `chmod +x scripts/__tests__/run-tests.sh`

- [ ] **Step 3: Create the three fixtures**

Create `scripts/__tests__/fixtures/session-tracker-headings.md`. These are nine phase headings copied verbatim from a real phased design document, so the parser is proven against the shape it will actually meet:

```markdown
# Session Tracker Redesign — Design Spec

## 7. Phases

### Phase 0 — Design-system foundations

Body text that must not be parsed as a heading.

### Phase 1 — Data model & pipeline

### Phase 2 — Shell & surface model (structure, no visual change)

### Phase 3 — Takeovers & interstitials

### Phase 4 — Standalone hero set

### Phase 5 — Multi-exercise groups

### Phase 6 — Sheets & end of session

### Phase 7 — History & session detail

### Phase 8 — Cleanup & verification
```

Create `scripts/__tests__/fixtures/edge-cases.md`:

```markdown
# Edge Cases

## Phase 1 – En dash separator

### Phase 2 - Plain hyphen separator

#### Phase 3 — Four hash levels are valid

##### Phase 4 — Five hashes must be ignored

# Phase 5 — One hash must be ignored

## Phase 6 — Ünïcode & symbols: 50% "quoted", (parens)

##   Phase 7   —   Extra whitespace everywhere

## Phase 8 — First occurrence wins

## Phase 8 — Duplicate that must be ignored

## Phase 9 No separator so this is not a phase

## Phase 10 —

## Phases 11 — Wrong keyword

Not a heading: ## Phase 12 — inline text in a paragraph
```

Create `scripts/__tests__/fixtures/no-phases.md`:

```markdown
# A Document With No Phases

## Summary

Some prose. The word Phase appears here but not as a heading.

## Decision log
```

- [ ] **Step 4: Write the failing extraction tests**

Create `scripts/__tests__/parse-phases.test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=assert.sh
. "$here/assert.sh"

PARSE="$here/../parse-phases"
FIX="$here/fixtures"

# rec LINE FIELD — field FIELD of line LINE of the last run_cmd's output.
# Fields are read with cut, never by writing a literal tab in this file:
# a literal tab is invisible and survives copy-paste badly.
rec() { printf '%s\n' "$OUT" | sed -n "${1}p" | cut -f"${2}"; }

# nums — the first field of every output line, comma-joined, in output order.
nums() { printf '%s\n' "$OUT" | cut -f1 | tr '\n' ','; }

# --- listing a real-shaped document ---------------------------------------

run_cmd "$PARSE" "$FIX/session-tracker-headings.md"
assert_rc 0 'real headings: exits 0'
assert_eq "0,1,2,3,4,5,6,7,8," "$(nums)" 'real headings: nine phases, ascending, starting at 0'

assert_eq 'Design-system foundations'  "$(rec 1 2)" 'phase 0 title'
assert_eq 'design-system-foundations'  "$(rec 1 3)" 'phase 0 slug'
assert_eq 'Data model & pipeline'      "$(rec 2 2)" 'phase 1 title'
assert_eq 'data-model-pipeline'        "$(rec 2 3)" 'phase 1 slug: ampersand collapses'
assert_eq 'Shell & surface model (structure, no visual change)' "$(rec 3 2)" 'phase 2 title'
assert_eq 'shell-surface-model-structure-no-visual-change'      "$(rec 3 3)" 'phase 2 slug: parens collapse, no trailing dash'
assert_eq 'Cleanup & verification'     "$(rec 9 2)" 'phase 8 title'
assert_eq 'cleanup-verification'       "$(rec 9 3)" 'phase 8 slug'

# --- separators, heading levels, duplicates, malformed ---------------------

run_cmd "$PARSE" "$FIX/edge-cases.md"
assert_rc 0 'edge cases: exits 0'

# One assertion covers every acceptance AND every rejection: the numbers that
# survive are exactly 1,2,3,6,7,8. Phase 4 (five hashes), 5 (one hash),
# 9 (no separator), 10 (empty title), 11 (wrong keyword) and 12 (inline
# paragraph text) are all absent, and the second 8 was deduplicated.
assert_eq "1,2,3,6,7,8," "$(nums)" 'edge cases: exactly the six valid phases, ascending'

assert_eq 'En dash separator'        "$(rec 1 2)" 'en dash separator parses'
assert_eq 'Plain hyphen separator'   "$(rec 2 2)" 'hyphen separator parses'
assert_eq 'Four hash levels are valid' "$(rec 3 2)" 'four hashes accepted'
assert_eq 'Extra whitespace everywhere' "$(rec 5 2)" 'extra whitespace tolerated'
assert_eq 'First occurrence wins'    "$(rec 6 2)" 'duplicate number: first occurrence wins'

# Slug rules on a hostile title. Every non-[a-z0-9] run becomes one dash and
# the leading and trailing dashes are trimmed, so:
#   "Ünïcode & symbols: 50% "quoted", (parens)"
#    ^      ^                                   non-ascii letters are not
#                                               [a-z0-9] whether or not this
#                                               awk's tolower() touches them,
#                                               so each becomes a dash
# yields n-code-symbols-50-quoted-parens.
assert_eq 'Ünïcode & symbols: 50% "quoted", (parens)' "$(rec 4 2)" 'title preserved verbatim, non-ascii included'
assert_eq 'n-code-symbols-50-quoted-parens'           "$(rec 4 3)" 'slug: non-ascii and symbols each collapse to one dash'

# --- documents and arguments that must be refused --------------------------

run_cmd "$PARSE" "$FIX/no-phases.md"
assert_rc 3 'no phases: exits 3'
assert_contains 'no phase headings' "$OUT" 'no phases: message names the problem'

run_cmd "$PARSE" "$FIX/does-not-exist.md"
assert_rc 2 'missing file: exits 2'
assert_contains 'no such design document' "$OUT" 'missing file: message names the problem'

run_cmd "$PARSE"
assert_rc 2 'no arguments: exits 2'
assert_contains 'usage:' "$OUT" 'no arguments: prints usage'

run_cmd "$PARSE" "$FIX/edge-cases.md" 1-2 extra
assert_rc 2 'too many arguments: exits 2'

finish
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: FAIL — every assertion errors because `scripts/parse-phases` does not exist yet, so `run_cmd` sets a non-zero `RC` and empty `OUT`.

- [ ] **Step 6: Implement extraction in parse-phases**

Create `scripts/parse-phases`. This step implements listing only; Task 2 adds the range argument.

```bash
#!/usr/bin/env bash
# Extract phase records from a phased design document.
#
# A heading qualifies when it has 2-4 leading '#', then the word Phase, then an
# integer, then a dash separator (em dash, en dash, or hyphen), then a non-empty
# title. Output is one tab-separated record per phase, ascending by number:
#
#   number<TAB>title<TAB>slug
#
# Portability rules this file obeys, because breaking them fails silently rather
# than loudly (see the spec's D11):
#   - no '\s' anywhere; BSD awk and sed do not support it
#   - no bracket expression containing the em/en dashes; a byte-oriented awk
#     matches their individual bytes, and '–-' can parse as a range. The three
#     separators are matched as whole strings with index(), and the earliest
#     position wins. index(), length() and substr() agree within any one awk,
#     so the offset arithmetic is correct whether it counts bytes or characters.
#   - no interval expressions like {2,4}; support is not universal
#   - no bash-4-only syntax; /bin/bash on stock macOS is 3.2
#
# The number is read from the heading. It is never an ordinal index into the
# list of phases — a document whose phases start at 0 makes the two differ, and
# an ordinal reading silently selects the wrong work (the spec's D10).
#
# Usage: parse-phases DESIGN_DOC [RANGE]
set -euo pipefail

usage() {
  echo "usage: parse-phases DESIGN_DOC [RANGE]" >&2
}

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  usage
  exit 2
fi

doc=$1

if [ ! -f "$doc" ]; then
  echo "no such design document: $doc" >&2
  exit 2
fi

extract() {
  awk '
    {
      line = $0

      # Count leading hashes without an interval expression.
      hashes = 0
      while (substr(line, hashes + 1, 1) == "#") hashes++
      if (hashes < 2 || hashes > 4) next

      rest = substr(line, hashes + 1)
      sub(/^[[:space:]]+/, "", rest)
      if (rest !~ /^Phase[[:space:]]+[0-9]/) next

      sub(/^Phase[[:space:]]+/, "", rest)

      num = rest
      sub(/[^0-9].*$/, "", num)
      if (num == "") next

      after = substr(rest, length(num) + 1)

      # Earliest of the three separators wins.
      sep = 0
      seplen = 0
      split("— – -", dashes, " ")
      for (i = 1; i <= 3; i++) {
        p = index(after, dashes[i])
        if (p > 0 && (sep == 0 || p < sep)) {
          sep = p
          seplen = length(dashes[i])
        }
      }
      if (sep == 0) next

      # Everything before the separator must be blank, or this is not a heading
      # of the expected shape.
      lead = substr(after, 1, sep - 1)
      if (lead !~ /^[[:space:]]*$/) next

      title = substr(after, sep + seplen)
      sub(/^[[:space:]]+/, "", title)
      sub(/[[:space:]]+$/, "", title)
      if (title == "") next

      # First occurrence of a number wins; a later duplicate is ignored.
      if (num in seen) next
      seen[num] = 1

      slug = tolower(title)
      gsub(/[^a-z0-9]+/, "-", slug)
      sub(/^-+/, "", slug)
      sub(/-+$/, "", slug)
      if (slug == "") next

      printf "%s\t%s\t%s\n", num, title, slug
    }
  ' "$1" | sort -n -k1,1
}

phases=$(extract "$doc")

if [ -z "$phases" ]; then
  echo "no phase headings found in: $doc" >&2
  exit 3
fi

printf '%s\n' "$phases"
```

Then: `chmod +x scripts/parse-phases`

Note on `split("— – -", dashes, " ")`: the dashes are held as data, not as a regex, which is what keeps them out of a bracket expression. `seen` is an awk associative array, which is portable — the D11 ban on associative arrays applies to **bash**, not to awk.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: PASS — `parse-phases.test.sh` reports `0 failed`, runner prints `all test files passed`.

- [ ] **Step 8: Lint**

Run: `shellcheck scripts/parse-phases scripts/__tests__/run-tests.sh scripts/__tests__/assert.sh scripts/__tests__/parse-phases.test.sh`

Expected: no output, exit 0. Fix any finding rather than suppressing it with a `# shellcheck disable` directive, unless the finding is the `source=assert.sh` case already annotated in the test file.

- [ ] **Step 9: Verify against a real design document**

This is the check that matters most: the fixture is a copy, and a copy can drift from the thing it copies.

Run:
```bash
scripts/parse-phases \
  /Users/albertobonino/projects/fitsheet/docs/superpowers/specs/2026-08-03-session-tracker-redesign-design.md
```

Expected: exactly 9 lines, first field `0` through `8` in ascending order, third line's slug `shell-surface-model-structure-no-visual-change`.

If that file no longer exists, say so in the task report and move on — the fixture assertions in Step 4 are the binding requirement; this step is corroboration.

- [ ] **Step 10: Commit**

```bash
git add scripts/parse-phases scripts/__tests__
git commit -m "feat: phase extraction and test harness"
```

---

### Task 2: Range selection and validation

Adds the optional second argument to `parse-phases`.

**Files:**
- Modify: `scripts/parse-phases`
- Modify: `scripts/__tests__/parse-phases.test.sh`

**Interfaces:**
- Consumes: `parse-phases DESIGN_DOC` and the `extract` function from Task 1; `assert.sh`'s `run_cmd`, `assert_eq`, `assert_rc`, `assert_contains`, `finish`; the fixtures `session-tracker-headings.md` and `edge-cases.md`.
- Produces: `parse-phases DESIGN_DOC RANGE` → the same tab-separated record format, filtered to the selected phase numbers, ascending. Exit `4` when a requested number is absent from the document; exit `2` on malformed range syntax. Task 4's `phase-preflight` shells out to exactly this interface and passes its exit codes through unchanged.

**Range grammar.** After normalising, a range is a comma-separated list of items; each item is either a single non-negative integer or `A-B` with `A <= B`, inclusive at both ends. `all` selects everything. Normalisation before parsing: lowercase the whole string, replace every run of `[[:space:]]*to[[:space:]]*` with `-`, then delete all remaining whitespace. So `2 to 6`, `2-6`, `2 - 6` and `2To6` all mean the same thing, and `2,4,5` selects three phases.

- [ ] **Step 1: Write the failing range tests**

Append to `scripts/__tests__/parse-phases.test.sh`, **immediately before** the final `finish` line:

```bash
# --- range selection -------------------------------------------------------

# Reuses the nums() helper defined at the top of this file by Task 1.

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" 2-6
assert_rc 0 'range 2-6: exits 0'
assert_eq "2,3,4,5,6," "$(nums)" 'range 2-6 selects phases numbered 2..6, not the 2nd..6th'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" '2 to 6'
assert_rc 0 'range "2 to 6": exits 0'
assert_eq "2,3,4,5,6," "$(nums)" 'range "2 to 6" equals 2-6'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" '2,4,5'
assert_rc 0 'comma list: exits 0'
assert_eq "2,4,5," "$(nums)" 'comma list selects exactly those numbers'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" 3
assert_rc 0 'single phase: exits 0'
assert_eq "3," "$(nums)" 'single phase selects one'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" all
assert_rc 0 'all: exits 0'
assert_eq "0,1,2,3,4,5,6,7,8," "$(nums)" 'all selects every phase including 0'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" 0
assert_rc 0 'phase zero: exits 0'
assert_eq "0," "$(nums)" 'phase zero is selectable'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" '5-3'
assert_rc 2 'descending range: exits 2'
assert_contains 'descending' "$OUT" 'descending range: message names the problem'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" '6,2,4'
assert_rc 0 'unsorted comma list: exits 0'
assert_eq "2,4,6," "$(nums)" 'output is always ascending regardless of input order'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" '2,2,3'
assert_rc 0 'repeated number: exits 0'
assert_eq "2,3," "$(nums)" 'a repeated number yields one record'

# --- ranges that must be refused -------------------------------------------

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" '2-99'
assert_rc 4 'absent number: exits 4'
assert_contains '99' "$OUT" 'absent number: message names the missing number'
assert_contains '0 1 2 3 4 5 6 7 8' "$OUT" 'absent number: message lists available numbers'

run_cmd "$PARSE" "$FIX/edge-cases.md" '4'
assert_rc 4 'number present but not a valid phase: exits 4'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" 'two'
assert_rc 2 'non-numeric range: exits 2'
assert_contains 'malformed range' "$OUT" 'non-numeric range: message names the problem'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" '2--6'
assert_rc 2 'double dash: exits 2'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" ''
assert_rc 2 'empty range: exits 2'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" '2,'
assert_rc 2 'trailing comma: exits 2'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" '-2'
assert_rc 2 'leading dash: exits 2'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: FAIL — the Task 1 assertions still pass, but every range assertion fails because `parse-phases` currently ignores its second argument, so `2-6` selects nothing and all nine phases are printed.

- [ ] **Step 3: Implement range selection**

In `scripts/parse-phases`, replace the final block — everything from `phases=$(extract "$doc")` to the end of the file — with:

```bash
phases=$(extract "$doc")

if [ -z "$phases" ]; then
  echo "no phase headings found in: $doc" >&2
  exit 3
fi

available=$(printf '%s\n' "$phases" | cut -f1)

if [ $# -eq 1 ]; then
  printf '%s\n' "$phases"
  exit 0
fi

raw=$2

# Normalise: lowercase, 'to' becomes '-', drop all whitespace.
range=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
range=$(printf '%s' "$range" | sed -E 's/[[:space:]]*to[[:space:]]*/-/g')
range=$(printf '%s' "$range" | tr -d '[:space:]')

if [ -z "$range" ]; then
  echo "malformed range: (empty). Expected e.g. 2, 2-6, '2 to 6', 2,4,5, or all" >&2
  exit 2
fi

wanted=""

if [ "$range" = "all" ]; then
  wanted=$available
else
  # Expand each comma-separated item into the numbers it names.
  saved_ifs=$IFS
  IFS=','
  # shellcheck disable=SC2086
  set -- $range
  IFS=$saved_ifs

  if [ $# -eq 0 ]; then
    echo "malformed range: $raw. Expected e.g. 2, 2-6, '2 to 6', 2,4,5, or all" >&2
    exit 2
  fi

  for item in "$@"; do
    case "$item" in
      *[!0-9-]* | '' | -* | *- | *-*-*)
        echo "malformed range item: $item. Expected e.g. 2, 2-6, '2 to 6', 2,4,5, or all" >&2
        exit 2
        ;;
    esac

    case "$item" in
      *-*)
        low=${item%%-*}
        high=${item##*-}
        if [ -z "$low" ] || [ -z "$high" ]; then
          echo "malformed range item: $item. Expected e.g. 2, 2-6, '2 to 6', 2,4,5, or all" >&2
          exit 2
        fi
        if [ "$low" -gt "$high" ]; then
          echo "descending range not allowed: $item. Write ${high}-${low} instead" >&2
          exit 2
        fi
        n=$low
        while [ "$n" -le "$high" ]; do
          wanted="$wanted$n
"
          n=$((n + 1))
        done
        ;;
      *)
        wanted="$wanted$item
"
        ;;
    esac
  done
fi

# Deduplicate and sort ascending.
wanted=$(printf '%s' "$wanted" | grep -v '^$' | sort -n -u)

# Every requested number must exist in the document.
missing=""
for n in $wanted; do
  if ! printf '%s\n' "$available" | grep -qx "$n"; then
    missing="$missing $n"
  fi
done

if [ -n "$missing" ]; then
  echo "phase(s) not found in $doc:$missing" >&2
  echo "available phase numbers: $(printf '%s' "$available" | tr '\n' ' ' | sed 's/ $//')" >&2
  exit 4
fi

for n in $wanted; do
  printf '%s\n' "$phases" | awk -F'\t' -v want="$n" '$1 == want { print; exit }'
done
```

Note on the guard `*[!0-9-]* | '' | -* | *- | *-*-*`: it rejects, in order, any character that is not a digit or a hyphen (catches `two`), an empty item (catches `2,` and the empty range), a leading hyphen (catches `-2`), a trailing hyphen (catches `2-`), and more than one hyphen (catches `2--6`, whose middle field is empty).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: PASS — `0 failed`, and `all test files passed`.

- [ ] **Step 5: Lint**

Run: `shellcheck scripts/parse-phases scripts/__tests__/parse-phases.test.sh`

Expected: no output, exit 0. The one permitted suppression is the `SC2086` directive already present above the `set -- $range` line, which is deliberate word-splitting on a validated string.

- [ ] **Step 6: Verify range selection against a real design document**

Run:
```bash
scripts/parse-phases \
  /Users/albertobonino/projects/fitsheet/docs/superpowers/specs/2026-08-03-session-tracker-redesign-design.md \
  '2 to 6' | cut -f1 | tr '\n' ' '
```

Expected output: `2 3 4 5 6 `

This is the D10 check against the real artefact — the document's phases start at 0, so an ordinal reading would print `1 2 3 4 5`. If it does, the implementation is wrong.

If that file no longer exists, say so in the task report and move on.

- [ ] **Step 7: Commit**

```bash
git add scripts/parse-phases scripts/__tests__/parse-phases.test.sh
git commit -m "feat: range selection and validation"
```

---

### Task 3: The run directory

**Files:**
- Create: `scripts/phase-run-dir`
- Create: `scripts/__tests__/phase-run-dir.test.sh`

**Interfaces:**
- Consumes: `assert.sh`'s `run_cmd`, `assert_eq`, `assert_rc`, `assert_contains`, `finish`.
- Produces: `phase-run-dir DESIGN_DOC` → prints the absolute path of `<repo-root>/.superpowers/phase-orchestrator/<design-doc-basename-without-.md>/`, creating it and ensuring `<repo-root>/.superpowers/phase-orchestrator/.gitignore` contains `*`. Exit `0`. Task 4's `phase-preflight` and Task 7's `SKILL.md` both resolve the run directory through this script and never construct the path themselves.

This mirrors `subagent-driven-development`'s `scripts/sdd-workspace`, deliberately: same directory shape, same self-ignoring `.gitignore`, same reason for living in the working tree rather than under `.git/` (Claude Code treats `.git/` as protected and denies agent writes there, which would block a subagent from writing its report file).

- [ ] **Step 1: Write the failing tests**

Create `scripts/__tests__/phase-run-dir.test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=assert.sh
. "$here/assert.sh"

RUNDIR="$here/../phase-run-dir"

# run_in DIR COMMAND [ARGS...] — like run_cmd, but with DIR as the working
# directory. A subshell rather than `env -C`, which BSD env on macOS does not
# support; the subshell form works everywhere.
run_in() {
  dir=$1
  shift
  set +e
  OUT=$(cd "$dir" && "$@" 2>&1)
  RC=$?
  set -e
}

# A throwaway git repository, so the test never touches a real one.
# The `cd … && pwd` resolves symlinks up front: on macOS `mktemp -d` returns a
# path under /var/folders/… which is a symlink to /private/var/folders/…, and
# phase-run-dir ends with `cd "$dir" && pwd`, which resolves it. Without this,
# the path assertions below compare a symlinked path against a resolved one and
# fail for a reason that has nothing to do with the behaviour under test.
tmp=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q
printf '# spec\n' > "$tmp/my-feature-design.md"

run_in "$tmp" "$RUNDIR" "$tmp/my-feature-design.md"
assert_rc 0 'creates the run directory: exits 0'
assert_eq "$tmp/.superpowers/phase-orchestrator/my-feature-design" "$OUT" \
  'prints the run directory path, basename without .md'
assert_eq 'yes' "$([ -d "$tmp/.superpowers/phase-orchestrator/my-feature-design" ] && echo yes || echo no)" \
  'the directory exists on disk'
assert_eq '*' "$(cat "$tmp/.superpowers/phase-orchestrator/.gitignore")" \
  'the parent carries a self-ignoring .gitignore'
assert_eq '' "$(git -C "$tmp" status --porcelain | grep superpowers || true)" \
  'nothing under .superpowers shows in git status'

# Idempotent: a second call must succeed and print the same path.
first=$OUT
run_in "$tmp" "$RUNDIR" "$tmp/my-feature-design.md"
assert_rc 0 'second call: exits 0'
assert_eq "$first" "$OUT" 'second call prints the same path'

# Two different specs get two different directories.
printf '# other\n' > "$tmp/other-design.md"
run_in "$tmp" "$RUNDIR" "$tmp/other-design.md"
assert_rc 0 'second spec: exits 0'
assert_eq "$tmp/.superpowers/phase-orchestrator/other-design" "$OUT" \
  'a different spec gets its own directory'

# Refusals.
run_in "$tmp" "$RUNDIR" "$tmp/nope.md"
assert_rc 2 'missing design document: exits 2'
assert_contains 'no such design document' "$OUT" 'missing document: message names the problem'

run_in "$tmp" "$RUNDIR"
assert_rc 2 'no arguments: exits 2'
assert_contains 'usage:' "$OUT" 'no arguments: prints usage'

outside=$(mktemp -d)
printf '# spec\n' > "$outside/loose-design.md"
run_in "$outside" "$RUNDIR" "$outside/loose-design.md"
assert_rc 2 'outside a git repository: exits 2'
assert_contains 'not inside a git repository' "$OUT" 'outside a repo: message names the problem'
rm -rf "$outside"

finish
```

One assumption to preserve: the throwaway repository must not sit inside another git repository, or `git rev-parse --show-toplevel` finds the outer one and every path assertion goes wrong. `mktemp -d` satisfies this; changing where the throwaway repository lives puts it at risk.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: FAIL on `phase-run-dir.test.sh` — the script does not exist. `parse-phases.test.sh` must still pass.

- [ ] **Step 3: Implement phase-run-dir**

Create `scripts/phase-run-dir`:

```bash
#!/usr/bin/env bash
# Resolve and ensure the working-tree directory one orchestration run uses for
# its scratch artifacts: the run ledger, per-phase decision summaries, and
# per-phase verification evidence. Print the run directory's absolute path.
#
# One directory per design document
# (.superpowers/phase-orchestrator/<doc-basename>/) so a second run against a
# different spec in the same working tree can never read or overwrite this
# run's ledger. A stale ledger misread as current progress makes an
# orchestrator re-dispatch or skip whole phases — scoping removes that
# structurally.
#
# The directory lives in the working tree rather than under .git/ because
# Claude Code treats .git/ as a protected path and denies agent writes there,
# which would block a subagent from writing its evidence file. A self-ignoring
# .gitignore at .superpowers/phase-orchestrator/ keeps every run's scratch out
# of `git status` and out of accidental commits, without modifying any tracked
# file.
#
# Usage: phase-run-dir DESIGN_DOC
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: phase-run-dir DESIGN_DOC" >&2
  exit 2
fi

doc=$1

if [ ! -f "$doc" ]; then
  echo "no such design document: $doc" >&2
  exit 2
fi

slug=$(basename "$doc" .md)
if [ -z "$slug" ] || [ "$slug" = "." ] || [ "$slug" = ".." ]; then
  echo "cannot derive a run directory name from: $doc" >&2
  exit 2
fi

if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "not inside a git repository: run this from the repository the phases will land in" >&2
  exit 2
fi

base="$root/.superpowers/phase-orchestrator"
dir="$base/$slug"
mkdir -p "$dir"
printf '*\n' > "$base/.gitignore"
cd "$dir" && pwd
```

Then: `chmod +x scripts/phase-run-dir`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: PASS — both test files report `0 failed`, runner prints `all test files passed`.

- [ ] **Step 5: Lint**

Run: `shellcheck scripts/phase-run-dir scripts/__tests__/phase-run-dir.test.sh`

Expected: no output, exit 0.

- [ ] **Step 6: Confirm the suite leaves nothing behind**

The test creates a git repository and a `.superpowers/` tree. Prove it cleaned up after itself rather than writing into a real checkout.

```bash
bash scripts/__tests__/run-tests.sh
ls -d .superpowers 2>/dev/null || echo "no stray run directory in this repo"
git status --porcelain
```

Expected: the suite passes, the second command prints `no stray run directory in this repo`, and `git status --porcelain` shows only the files this task created. Together these confirm the test's `trap … EXIT` removed its throwaway repository and that `phase-run-dir` was never invoked against this checkout.

- [ ] **Step 7: Commit**

```bash
git add scripts/phase-run-dir scripts/__tests__/phase-run-dir.test.sh
git commit -m "feat: run directory resolution"
```

---

### Task 4: Preflight

Implements the spec's §4.3 as a script rather than as prose, and amends the spec to record that.

**Files:**
- Create: `scripts/phase-preflight`
- Create: `scripts/__tests__/phase-preflight.test.sh`
- Modify: `docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md`

**Interfaces:**
- Consumes: `parse-phases DESIGN_DOC RANGE` (Task 2) and `phase-run-dir DESIGN_DOC` (Task 3), both invoked as sibling scripts resolved from `$(dirname "$0")`; `assert.sh`'s helpers.
- Produces: `phase-preflight DESIGN_DOC BASE RANGE` → exit `0` and one stdout line beginning `preflight ok:` when the run may start, having switched the working tree to `BASE` (creating it off trunk if absent). Non-zero exit with an actionable stderr message otherwise, per the exit-code contract in Global Constraints. Task 7's `SKILL.md` calls this as its first action and refuses the run on any non-zero exit.

**Check order.** Not the spec's table order. The trunk check runs before anything mutates git state, because switching to `main` in order to then refuse it is exactly the accident the check exists to prevent. The working-tree-clean check runs before the run directory is created, so the check cannot observe its own side effects.

1. argument count, then design document readable → `2`
2. inside a git repository → `10`
3. base is not `main`/`master` → `12`
4. working tree clean → `11`
5. design document parses and every requested number is present → `2` / `3` / `4`, passed through from `parse-phases`
6. base branch resolved: switch to it, or create it off `main` (else `master`) → `13`
7. no phase branch for a requested phase that the ledger does not account for → `14`

**Check 7 and resume.** A branch named `phase-<N>-<slug>` for a requested phase is a refusal *unless* this spec's ledger accounts for it. It is accounted for when `<run-dir>/run.md` exists, its first line names this design document's basename, and it contains a line beginning `phase <N>` followed by a non-digit. That is the spec's §4.4 rule stated mechanically: in-flight work from an earlier invocation is reused; a branch with no ledger entry at all has unknown provenance and is always refused.

- [ ] **Step 1: Write the failing preflight tests**

Create `scripts/__tests__/phase-preflight.test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=assert.sh
. "$here/assert.sh"

PRE="$here/../phase-preflight"
FIX="$here/fixtures"

# The slug of phase 2 in the session-tracker fixture. Written out once here so
# every branch-collision test names the same branch the script will compute.
P2_BRANCH='phase-2-shell-surface-model-structure-no-visual-change'

run_in() {
  dir=$1
  shift
  set +e
  OUT=$(cd "$dir" && "$@" 2>&1)
  RC=$?
  set -e
}

# new_repo — a throwaway repository on branch main with the fixture spec
# committed as spec-design.md. Prints its resolved absolute path.
# `symbolic-ref` before the first commit forces the branch name regardless of
# the machine's init.defaultBranch, so the trunk-detection tests are stable.
new_repo() {
  d=$(cd "$(mktemp -d)" && pwd)
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name Test
  git -C "$d" symbolic-ref HEAD refs/heads/main
  cp "$FIX/session-tracker-headings.md" "$d/spec-design.md"
  git -C "$d" add -A
  git -C "$d" commit -qm init
  printf '%s\n' "$d"
}

repos=""
cleanup() { for r in $repos; do rm -rf "$r"; done; }
trap cleanup EXIT
track() { repos="$repos $1"; }

# --- the happy path --------------------------------------------------------

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/spec-design.md" feat/tracker '2 to 6'
assert_rc 0 'happy path: exits 0'
assert_contains 'preflight ok' "$OUT" 'happy path: reports ok'
assert_eq 'feat/tracker' "$(git -C "$r" rev-parse --abbrev-ref HEAD)" \
  'happy path: created the base branch and switched to it'
assert_eq 'yes' "$([ -d "$r/.superpowers/phase-orchestrator/spec-design" ] && echo yes || echo no)" \
  'happy path: created the run directory'

# Idempotent: running it again on the now-existing base branch must succeed.
run_in "$r" "$PRE" "$r/spec-design.md" feat/tracker '2 to 6'
assert_rc 0 'second run on an existing base: exits 0'
assert_eq 'feat/tracker' "$(git -C "$r" rev-parse --abbrev-ref HEAD)" \
  'second run: still on the base branch'

# --- refusals, one per check ----------------------------------------------

run_in "$(dirname "$r")" "$PRE"
assert_rc 2 'no arguments: exits 2'
assert_contains 'usage:' "$OUT" 'no arguments: prints usage'

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/absent-design.md" feat/x all
assert_rc 2 'missing design document: exits 2'
assert_contains 'no such design document' "$OUT" 'missing document: message names the problem'

outside=$(cd "$(mktemp -d)" && pwd); track "$outside"
cp "$FIX/session-tracker-headings.md" "$outside/spec-design.md"
run_in "$outside" "$PRE" "$outside/spec-design.md" feat/x all
assert_rc 10 'outside a git repository: exits 10'
assert_contains 'not inside a git repository' "$OUT" 'outside a repo: message names the problem'

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/spec-design.md" main all
assert_rc 12 'base is main: exits 12'
assert_contains 'refusing to run against trunk' "$OUT" 'base main: message names the problem'
assert_eq 'main' "$(git -C "$r" rev-parse --abbrev-ref HEAD)" \
  'base main: refused before touching git state'

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/spec-design.md" master all
assert_rc 12 'base is master: exits 12'

r=$(new_repo); track "$r"
printf 'uncommitted\n' > "$r/stray.txt"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x all
assert_rc 11 'dirty working tree: exits 11'
assert_contains 'working tree not clean' "$OUT" 'dirty tree: message names the problem'

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x '2-99'
assert_rc 4 'absent phase number: exits 4'
assert_contains '99' "$OUT" 'absent phase: message names the missing number'
assert_eq 'main' "$(git -C "$r" rev-parse --abbrev-ref HEAD)" \
  'absent phase: refused before creating the base branch'

r=$(new_repo); track "$r"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x 'two'
assert_rc 2 'malformed range: exits 2'

r=$(new_repo); track "$r"
cp "$FIX/no-phases.md" "$r/spec-design.md"
git -C "$r" commit -qam 'no phases'
run_in "$r" "$PRE" "$r/spec-design.md" feat/x all
assert_rc 3 'document with no phase headings: exits 3'

# No main and no master to branch from.
r=$(new_repo); track "$r"
git -C "$r" branch -m main trunkless
run_in "$r" "$PRE" "$r/spec-design.md" feat/x all
assert_rc 13 'no main or master to create the base from: exits 13'
assert_contains 'does not exist' "$OUT" 'no trunk: message names the problem'

# --- check 7: phase branch with no ledger entry ---------------------------

r=$(new_repo); track "$r"
git -C "$r" branch "$P2_BRANCH"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x '2-3'
assert_rc 14 'unexplained phase branch: exits 14'
assert_contains "$P2_BRANCH" "$OUT" 'unexplained branch: message names the branch'
assert_contains 'ledger' "$OUT" 'unexplained branch: message explains why it was refused'

# Same branch, but this spec's ledger accounts for phase 2: reuse, do not refuse.
# The .gitignore is written alongside the ledger because the clean-tree check
# runs before phase-run-dir does: a hand-made .superpowers/ with nothing ignoring
# it is untracked content, and preflight would refuse with 11 for that reason
# instead of reaching the check under test. A real resume always has it already.
r=$(new_repo); track "$r"
git -C "$r" branch "$P2_BRANCH"
led="$r/.superpowers/phase-orchestrator/spec-design"
mkdir -p "$led"
printf '*\n' > "$r/.superpowers/phase-orchestrator/.gitignore"
{
  printf '# Phase run — spec: %s/spec-design.md\n' "$r"
  printf '# base: feat/x  requested: 2-3\n\n'
  printf 'phase 2 (Shell & surface model): plan docs/plans/p2.md\n'
} > "$led/run.md"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x '2-3'
assert_rc 0 'phase branch with a matching ledger entry: exits 0'

# A branch for a phase the ledger does not mention is still refused, even when
# a ledger exists for other phases.
r=$(new_repo); track "$r"
git -C "$r" branch "$P2_BRANCH"
led="$r/.superpowers/phase-orchestrator/spec-design"
mkdir -p "$led"
printf '*\n' > "$r/.superpowers/phase-orchestrator/.gitignore"
{
  printf '# Phase run — spec: %s/spec-design.md\n' "$r"
  printf '# base: feat/x  requested: 3\n\n'
  printf 'phase 3 (Takeovers): plan docs/plans/p3.md\n'
} > "$led/run.md"
run_in "$r" "$PRE" "$r/spec-design.md" feat/x '2-3'
assert_rc 14 'ledger mentions another phase only: still exits 14'

finish
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: FAIL on `phase-preflight.test.sh` — the script does not exist. The other two test files must still pass.

- [ ] **Step 3: Implement phase-preflight**

Create `scripts/phase-preflight`:

```bash
#!/usr/bin/env bash
# Decide whether one orchestration run may start, and put the working tree on
# the base branch it will merge into. Every check must pass or the run refuses;
# a refusal names the failed check and the command that fixes it.
#
# Check order is not the design document's table order. The trunk check runs
# before anything mutates git state — switching to main in order to then refuse
# it is exactly the accident the check exists to prevent. The clean-tree check
# runs before the run directory is created, so it cannot observe its own side
# effects.
#
# Exit codes:
#   0   ok
#   2   usage error, unreadable design document, or malformed range
#   3   the design document contains no phase headings
#   4   a requested phase number is absent from the document
#   10  not inside a git repository
#   11  working tree not clean
#   12  the base branch is main or master
#   13  the base branch could not be resolved or created
#   14  a phase branch exists that this run's ledger does not account for
#
# Permission mode is NOT checked here: it cannot be read from inside a skill
# (the spec's D13). SKILL.md states the requirement instead.
#
# Usage: phase-preflight DESIGN_DOC BASE RANGE
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: phase-preflight DESIGN_DOC BASE RANGE" >&2
  exit 2
fi

doc=$1
base=$2
range=$3

here=$(cd "$(dirname "$0")" && pwd)

if [ ! -f "$doc" ]; then
  echo "no such design document: $doc" >&2
  exit 2
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "not inside a git repository: cd to the repository the phases will land in" >&2
  exit 10
fi

case "$base" in
  main | master)
    echo "refusing to run against trunk: base is '$base'." >&2
    echo "pass a feature branch instead, e.g. feat/<name>" >&2
    exit 12
    ;;
esac

if [ -n "$(git status --porcelain)" ]; then
  echo "working tree not clean: commit or stash before starting a run (git status)" >&2
  exit 11
fi

# Delegates the whole of the document/range contract to parse-phases and passes
# its exit code straight through, so the two scripts can never disagree about
# which phases a range names.
set +e
selected=$("$here/parse-phases" "$doc" "$range" 2>&1)
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$selected" >&2
  exit "$rc"
fi

if git show-ref --verify --quiet "refs/heads/$base"; then
  if ! git switch "$base" >/dev/null 2>&1; then
    echo "could not switch to base branch '$base' (git switch $base)" >&2
    exit 13
  fi
else
  trunk=""
  for candidate in main master; do
    if git show-ref --verify --quiet "refs/heads/$candidate"; then
      trunk=$candidate
      break
    fi
  done
  if [ -z "$trunk" ]; then
    echo "base branch '$base' does not exist, and neither 'main' nor 'master' exists to create it from" >&2
    echo "create it yourself: git switch -c $base <start-point>" >&2
    exit 13
  fi
  if ! git switch -c "$base" "$trunk" >/dev/null 2>&1; then
    echo "could not create base branch '$base' off '$trunk'" >&2
    exit 13
  fi
fi

rundir=$("$here/phase-run-dir" "$doc")
ledger="$rundir/run.md"
docname=$(basename "$doc")

# A phase branch for a requested phase is in-flight work only if this spec's
# ledger accounts for it. Anything else has unknown provenance and is refused.
tmpsel=$(mktemp)
trap 'rm -f "$tmpsel"' EXIT
printf '%s\n' "$selected" > "$tmpsel"

while IFS="$(printf '\t')" read -r num _ slug; do
  [ -n "$num" ] || continue
  branch="phase-$num-$slug"
  git show-ref --verify --quiet "refs/heads/$branch" || continue

  if [ -f "$ledger" ] \
    && head -n 1 "$ledger" | grep -Fq "$docname" \
    && grep -q "^phase $num[^0-9]" "$ledger"; then
    continue
  fi

  echo "branch '$branch' already exists, and this run's ledger does not account for it." >&2
  echo "ledger: $ledger" >&2
  echo "a leftover branch means a resume, not a fresh start: either resume the run that" >&2
  echo "created it, or delete it (git branch -D $branch) and start again" >&2
  exit 14
done < "$tmpsel"

numbers=$(printf '%s\n' "$selected" | cut -f1 | tr '\n' ',' | sed 's/,$//')
echo "preflight ok: base $base, phases $numbers, run-dir $rundir"
```

Then: `chmod +x scripts/phase-preflight`

Two notes on portability. `IFS="$(printf '\t')"` rather than `IFS=$'\t'` keeps the file free of bashisms that a `sh`-invoked copy would mis-tokenise, and reading from `< "$tmpsel"` rather than from a pipe keeps the loop in the current shell, so its `exit 14` actually exits the script — a piped `while` runs in a subshell and its exit status is discarded. The temporary file also avoids `mapfile` and indexed-array expansion, both of which are either bash-4-only or unsafe under `set -u` on bash 3.2 when empty.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: PASS — all three test files report `0 failed`, runner prints `all test files passed`.

- [ ] **Step 5: Lint**

Run: `shellcheck scripts/phase-preflight scripts/__tests__/phase-preflight.test.sh`

Expected: no output, exit 0.

- [ ] **Step 6: Amend the spec to record the third script**

The design document's §5 lists two scripts and §4.3 describes preflight as prose in `SKILL.md`. The document's own rule is that an implementation which deviates from a decision amends §6 first and says why. Make both edits.

In `docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md`, in the §5 file-structure block, replace this line:

```
    phase-run-dir         resolve/create run directory, ensure it is git-ignored
```

with:

```
    phase-run-dir         resolve/create run directory, ensure it is git-ignored
    phase-preflight       the §4.3 checks; resolves and switches to the base branch
```

Then append this row to the §6 decision-log table, immediately after the **D13** row:

```
| **D14** | **Preflight is a script (`scripts/phase-preflight`), not prose in `SKILL.md`.** §4.3's checks and the base-branch resolution move into it; `SKILL.md` calls it and refuses the run on a non-zero exit. | Added 2026-08-03 while planning the build. §7 Phase 3 requires one test per §4.3 check; as prose that means invoking the whole skill six times, and the checks would be verified only by the thing they gate. As a script they are unit-tested against throwaway repositories in seconds. Does not weaken D13 — permission mode is still neither checked nor checkable. |
```

- [ ] **Step 7: Commit**

```bash
git add scripts/phase-preflight scripts/__tests__/phase-preflight.test.sh \
  docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md
git commit -m "feat: preflight checks and base branch resolution"
```

---

### Task 5: The planner and repair dispatch templates

The two simpler templates, plus the structural test harness that Task 6 extends.

**Files:**
- Create: `planner-prompt.md`
- Create: `repair-prompt.md`
- Create: `scripts/__tests__/templates.test.sh`

**Interfaces:**
- Consumes: `assert.sh`'s helpers.
- Produces: two template files at the repository root, and `templates.test.sh`, which Task 6 appends to. Task 7's `SKILL.md` references all four templates by these exact filenames.

**Template conventions, binding on Tasks 5 and 6.** Each template is a markdown file whose body is one fenced block in `subagent-driven-development`'s dispatch shape: a `Subagent (general-purpose):` line, a `description:`, a `model:`, and a `prompt: |`. Values the orchestrator substitutes are written in `ANGLE_BRACKET_CAPS` — never in square brackets, because the test file's `assert_contains` matches with a shell `case` glob in which `[…]` is a character class. Every template ends with an explicit, capped return contract.

- [ ] **Step 1: Write the failing template tests**

Create `scripts/__tests__/templates.test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../.." && pwd)

# has FILE NEEDLE MESSAGE — the template file must contain NEEDLE verbatim.
# NEEDLE must be free of '*', '?' and '[' — assert_contains globs.
has() { assert_contains "$2" "$(cat "$ROOT/$1")" "$1: $3"; }

exists() {
  assert_eq 'yes' "$([ -f "$ROOT/$1" ] && echo yes || echo no)" "$1 exists"
}

# --- planner-prompt.md -----------------------------------------------------

exists planner-prompt.md
has planner-prompt.md 'superpowers:writing-plans' 'names the skill the planner must invoke'
has planner-prompt.md 'phase PHASE_NUMBER only' 'scopes the plan to one phase'
has planner-prompt.md 'Read the whole design document' 'planner reads the whole document for context'
has planner-prompt.md 'Do NOT present the execution-choice menu' 'override 1: no execution menu'
has planner-prompt.md 'Do NOT execute the plan' 'override 2: no execution'
has planner-prompt.md 'Global Constraints' 'copies cross-cutting constraints into the plan'
has planner-prompt.md 'Commit the plan file' 'planner commits the plan'
has planner-prompt.md 'PLAN_PATH' 'writes to the exact path it was given'
has planner-prompt.md 'Return ONLY the plan file path' 'return contract is the path alone'

# --- repair-prompt.md ------------------------------------------------------

exists repair-prompt.md
has repair-prompt.md 'EVIDENCE_PATH' 'receives the evidence file path'
has repair-prompt.md 'PLAN_PATH' 'receives the plan path'
has repair-prompt.md 'PHASE_BRANCH' 'receives the phase branch'
has repair-prompt.md 'Do NOT switch branches' 'stays on the phase branch'
has repair-prompt.md 'exit code' 'repairs against exit codes, not printed totals'
has repair-prompt.md 'six lines' 'return contract is capped'

# --- rules binding on every template --------------------------------------

for t in planner-prompt.md repair-prompt.md; do
  has "$t" 'general-purpose' 'dispatches a general-purpose subagent'
  has "$t" 'model:' 'names a model explicitly'
  assert_eq '' "$(grep -n 'paste' "$ROOT/$t" | grep -iv 'do not paste' || true)" \
    "$t: never asks an agent to paste an artifact into its return value"
done

finish
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: FAIL on `templates.test.sh` — neither template exists, so `cat` prints nothing and every `has` assertion reports a miss. The three script test files must still pass.

- [ ] **Step 3: Write planner-prompt.md**

Create `planner-prompt.md`:

````markdown
# ① Planner Dispatch Template

Dispatched once per phase, before anything is executed. Substitute every
`ANGLE_BRACKET_CAPS` value before dispatching.

```
Subagent (general-purpose):
  description: "Plan phase PHASE_NUMBER of DESIGN_DOC_BASENAME"
  model: the most capable model available — writing a plan from a spec is design
         judgment, and every downstream cost compounds from its quality. An
         omitted model silently inherits the session's.
  prompt: |
    You are writing the implementation plan for ONE phase of a phased design
    document.

    Design document: DESIGN_DOC
    Phase number:    PHASE_NUMBER
    Phase title:     PHASE_TITLE
    Write the plan to: PLAN_PATH

    ## Your job

    1. Read the whole design document, so you understand the phases either side
       of yours and the decisions that constrain them.
    2. Write a plan for phase PHASE_NUMBER only. Nothing from any other phase
       belongs in it. If phase PHASE_NUMBER depends on work an earlier phase
       delivered, treat that work as already present — it is.
    3. Invoke superpowers:writing-plans and follow it.
    4. Save the plan to exactly PLAN_PATH. Do not choose your own filename and
       do not save it anywhere else — the orchestrator hands this exact path to
       the agent that executes it.
    5. Copy the design document's cross-cutting constraints — the decision log,
       the platform and portability rules, anything the document states as
       binding on every phase — into the plan's `## Global Constraints` block,
       with their exact values. The agent executing your plan will never read
       the design document.
    6. Commit the plan file.

    ## Two overrides of superpowers:writing-plans

    These supersede that skill's own ending. It is not a preference.

    - Do NOT present the execution-choice menu at the end ("Subagent-Driven /
      Inline Execution"). Nobody is there to answer it. The orchestrator has
      already chosen.
    - Do NOT execute the plan, or any part of it. A separate agent does that.

    ## Return contract

    Return ONLY the plan file path, on one line, and nothing else. No summary,
    no plan text, no commit log. The orchestrator that reads your reply must
    survive several more phases, and everything you print stays in its context
    for the rest of the run.
```
````

- [ ] **Step 4: Write repair-prompt.md**

Create `repair-prompt.md`:

````markdown
# Repair Dispatch Template

Dispatched at most once per phase, only after a verifier FAIL. There is never a
second repair attempt: a second is how an unattended run burns an afternoon
converging on nothing. Substitute every `ANGLE_BRACKET_CAPS` value before
dispatching.

```
Subagent (general-purpose):
  description: "Repair phase PHASE_NUMBER after a failed verification"
  model: the most capable model available — this is fresh eyes on something a
         full subagent-driven-development run did not get right. An omitted
         model silently inherits the session's.
  prompt: |
    A phase of a phased design document was implemented and then failed
    verification. You are fixing it. You get one attempt.

    Phase branch:  PHASE_BRANCH   (you are already on it)
    Plan:          PLAN_PATH      (what the phase was supposed to build)
    Evidence:      EVIDENCE_PATH  (what failed, and how)

    ## Your job

    1. Read the evidence file first. It names the commands that were run, their
       exit codes, and the failing output.
    2. Read the plan to understand what the phase was meant to deliver.
    3. Diagnose and fix the root cause. Do not paper over a failure by
       weakening, skipping, or deleting the check that caught it.
    4. Re-run the failing commands yourself and confirm each one now exits 0.
       A command that prints an all-green summary and exits non-zero has NOT
       passed — judge by the exit code, never by the printed totals.
    5. Commit your fix on PHASE_BRANCH.

    ## Constraints

    - Do NOT switch branches, create branches, merge, or rebase. The
      orchestrator owns integration; you own this branch's contents.
    - Do NOT invoke superpowers:finishing-a-development-branch.
    - Stay inside the phase's scope. Fixing the failure is the job; improving
      neighbouring code is not.
    - Nobody is available to answer questions. If you would normally stop and
      ask for direction, take the option you would tag as recommended and say
      which, in your return value.

    ## Return contract

    At most six lines:
    - status: FIXED or STILL_BROKEN
    - the one-line root cause
    - the commands you re-ran and their exit codes
    - your commit SHAs
    - any decision you took on your own

    Do not paste diffs, file contents, or test output into your reply.
```
````

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: PASS — all four test files report `0 failed`.

- [ ] **Step 6: Lint**

Run: `shellcheck scripts/__tests__/templates.test.sh`

Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add planner-prompt.md repair-prompt.md scripts/__tests__/templates.test.sh
git commit -m "feat: planner and repair dispatch templates"
```

---

### Task 6: The executor and verifier dispatch templates

The two load-bearing templates. The executor carries three overrides of `subagent-driven-development` and two user directives that must appear verbatim; the verifier carries the exit-code rule that is the whole reason it exists.

**Files:**
- Create: `executor-prompt.md`
- Create: `verifier-prompt.md`
- Modify: `scripts/__tests__/templates.test.sh`

**Interfaces:**
- Consumes: `templates.test.sh` and the `has`/`exists` helpers defined in it by Task 5; `assert.sh`'s helpers.
- Produces: two template files at the repository root, referenced by those filenames from Task 7's `SKILL.md`.

**The two directives are verbatim text.** They are reproduced below exactly as the design document's §3.4 states them, em dash included. They are quoted user speech passed through to the executor, not paraphrase for the orchestrator to reword — an override phrased as a preference gets ignored, and a directive reworded loses the authority of having been said by the person the executor is working for.

- [ ] **Step 1: Write the failing tests**

Append to `scripts/__tests__/templates.test.sh`, **immediately before** the `# --- rules binding on every template` comment block:

```bash
# --- executor-prompt.md ----------------------------------------------------

exists executor-prompt.md
has executor-prompt.md 'superpowers:subagent-driven-development' 'names the skill the executor must invoke'
has executor-prompt.md 'PLAN_PATH' 'receives the plan path'
has executor-prompt.md 'PHASE_BRANCH' 'receives the phase branch'
has executor-prompt.md 'DECISIONS_PATH' 'receives the decisions file path'

# The three overrides of subagent-driven-development.
has executor-prompt.md 'Do NOT create or verify a worktree' 'override 1: no worktree'
has executor-prompt.md 'superpowers:using-git-worktrees' 'override 1 names the routing it disables'
has executor-prompt.md 'Do NOT invoke superpowers:finishing-a-development-branch' 'override 2: no branch finishing'
has executor-prompt.md 'Do NOT switch branches' 'override 3: no branch switching'
has executor-prompt.md 'supersede' 'overrides are stated as superseding the skill'

# The two user directives, verbatim.
has executor-prompt.md \
  'Only perform one round of review. After applying any patches/fixes from the first' \
  'directive 1 present verbatim, line 1'
has executor-prompt.md \
  'review, do not run a second pass — mark the task done.' \
  'directive 1 present verbatim, line 2'
has executor-prompt.md \
  "I'm going to be afk. If you hit a situation where you would normally stop and ask for" \
  'directive 2 present verbatim, line 1'
has executor-prompt.md \
  'direction, pick the option you' \
  'directive 2 present verbatim, line 2'
has executor-prompt.md 'summarise the decisions taken at the end' 'directive 2 present verbatim, line 3'
has executor-prompt.md 'write that summary to DECISIONS_PATH' 'the decisions summary goes to a file, not the reply'

has executor-prompt.md 'ten lines' 'return contract is capped'
has executor-prompt.md 'BLOCKED' 'return contract carries a status'

# --- verifier-prompt.md ----------------------------------------------------

exists verifier-prompt.md
has verifier-prompt.md 'EVIDENCE_PATH' 'receives the evidence file path'
has verifier-prompt.md 'PHASE_BRANCH' 'receives the phase branch'
has verifier-prompt.md 'DESIGN_DOC' 'receives the design document'
has verifier-prompt.md 'did not write this code' 'states that the verifier is independent'
has verifier-prompt.md 'Verification' 'reads the phase Verification section'
has verifier-prompt.md 'no verification of its own' 'handles a phase with no Verification section'
has verifier-prompt.md 'Report the exit code of every command' 'the exit-code rule'
has verifier-prompt.md 'exits non-zero is a FAIL' 'an all-green print with a non-zero exit is a FAIL'
has verifier-prompt.md 'Do NOT fix anything' 'the verifier does not repair'
has verifier-prompt.md 'three lines' 'return contract is capped'
```

Then extend the loop at the bottom of the file to cover all four templates. Replace this line:

```bash
for t in planner-prompt.md repair-prompt.md; do
```

with:

```bash
for t in planner-prompt.md repair-prompt.md executor-prompt.md verifier-prompt.md; do
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: FAIL on `templates.test.sh` — the planner and repair assertions still pass, every executor and verifier assertion misses.

- [ ] **Step 3: Write executor-prompt.md**

Create `executor-prompt.md`:

````markdown
# ② Executor Dispatch Template

Dispatched once per phase, after the planner. This agent runs a full
`subagent-driven-development` loop of its own, so it will spawn subagents.
Substitute every `ANGLE_BRACKET_CAPS` value before dispatching.

```
Subagent (general-purpose):
  description: "Execute the plan for phase PHASE_NUMBER"
  model: the most capable model available — this agent is itself a controller,
         running a review loop and adjudicating findings unattended. An omitted
         model silently inherits the session's.
  prompt: |
    Execute an implementation plan with superpowers:subagent-driven-development.

    Plan:            PLAN_PATH
    Phase branch:    PHASE_BRANCH   (you are already on it, in a normal checkout)
    Run directory:   RUN_DIR
    Decisions file:  DECISIONS_PATH

    Invoke superpowers:subagent-driven-development and execute PLAN_PATH with it.

    ## Three overrides of superpowers:subagent-driven-development

    These supersede that skill's own instructions wherever they conflict. They
    are requirements, not preferences.

    1. Do NOT create or verify a worktree, and do NOT route through
       superpowers:using-git-worktrees, whatever that skill's Setup step says.
       You are already on an isolated phase branch in a single checkout, and
       that is the isolation. A worktree you fork here is invisible to the
       orchestrator, which will merge PHASE_BRANCH and silently get nothing.
    2. Do NOT invoke superpowers:finishing-a-development-branch, and do not push,
       open a pull request, or merge. That skill is subagent-driven-development's
       terminal state; here, integration belongs to the orchestrator that
       dispatched you.
    3. Do NOT switch branches, create branches, or rebase. Every commit lands on
       PHASE_BRANCH.

    ## Two directives from the person this run is for

    These come from them directly, and they supersede subagent-driven-development's
    own rules where the two disagree:

    > 1. Only perform one round of review. After applying any patches/fixes from the first
    >    review, do not run a second pass — mark the task done.
    > 2. I'm going to be afk. If you hit a situation where you would normally stop and ask for
    >    direction, pick the option you'd normally tag as recommended, and summarise the
    >    decisions taken at the end.

    For directive 2's summary: write that summary to DECISIONS_PATH — one line
    per decision, naming the choice you took and the alternative you passed
    over. It does not go in your reply.

    Keep every artifact of your own loop — briefs, reports, review packages,
    your ledger — under RUN_DIR or wherever subagent-driven-development puts
    them. Not in your reply.

    ## Return contract

    At most ten lines:
    - status: DONE or BLOCKED
    - the commit range on PHASE_BRANCH, as SHORT_SHA..SHORT_SHA
    - the review outcome in one line
    - how many findings you parked, and how many minor findings you deferred
    - DECISIONS_PATH

    If BLOCKED, put what blocked you in those ten lines — the orchestrator acts
    on it directly and will not read your files.

    Do not paste plan text, diffs, file contents, or test output into your
    reply. The orchestrator reading it must survive several more phases, and
    everything you print stays in its context for the rest of the run.
```
````

- [ ] **Step 4: Write verifier-prompt.md**

Create `verifier-prompt.md`:

````markdown
# ③ Verifier Dispatch Template

Dispatched once per phase after the executor, and once more after a repair. A
fresh agent that did not write the code: the executor reviews its own work under
a one-round cap, and an agent invested in code it just wrote rationalises a
non-zero exit code away. Substitute every `ANGLE_BRACKET_CAPS` value before
dispatching.

```
Subagent (general-purpose):
  description: "Verify phase PHASE_NUMBER on PHASE_BRANCH"
  model: a mid-tier model — this is running commands and reading exit codes,
         but it must still reason about which gates a repository has. An
         omitted model silently inherits the session's.
  prompt: |
    Verify one phase of a phased design document. You did not write this code
    and you have no stake in it passing.

    Design document: DESIGN_DOC
    Phase number:    PHASE_NUMBER
    Phase branch:    PHASE_BRANCH   (you are already on it)
    Evidence file:   EVIDENCE_PATH

    ## Your job

    1. Read phase PHASE_NUMBER's own Verification section in the design
       document, and check what it asks for. If that phase has no Verification
       section, run the repository's standard gates and state in the evidence
       file that the phase specified no verification of its own.
    2. Work out which gates this repository actually has — typecheck, lint,
       test, build, whatever is really there — from its manifests, scripts and
       configuration. Nothing is hard-coded; different repositories have
       different gates.
    3. Run them.
    4. Report the exit code of every command you run. A suite that prints
       "all passed" and exits non-zero is a FAIL. A suite whose summary line
       looks green and whose exit code is 1 is a FAIL. Judge by the exit code,
       never by the printed totals — this failure mode is real and reproduces.
    5. Write the full evidence to EVIDENCE_PATH: every command, its exit code,
       and the output that matters. Nobody will re-run these commands to find
       out what you saw.

    ## Constraints

    - Do NOT fix anything, do not edit any file, do not commit. If something is
      broken, that is the finding. A different agent repairs it.
    - Do NOT switch branches, merge, or rebase.
    - Nobody is available to answer questions. If a gate is ambiguous, run it,
      report what happened, and say in the evidence file what you were unsure of.

    ## Return contract

    At most three lines:
    - PASS or FAIL
    - a one-line reason
    - EVIDENCE_PATH

    Do not paste command output, diffs, or file contents into your reply — the
    evidence file is where those go.
```
````

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: PASS — all four test files report `0 failed`.

- [ ] **Step 6: Confirm the two directives are byte-identical to the spec**

The tests assert substrings; this confirms the whole quoted block matches the design document's §3.4, em dash and all.

```bash
diff \
  <(sed -n '/^> 1\. Only perform one round/,/decisions taken at the end\./p' \
      docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md \
    | sed 's/^[[:space:]]*//') \
  <(sed -n '/^    > 1\. Only perform one round/,/decisions taken at the end\./p' \
      executor-prompt.md \
    | sed 's/^[[:space:]]*//')
```

Expected: no output, exit 0. If it differs, the template is wrong — copy the spec's text, do not adjust the spec.

The range's end pattern is `decisions taken at the end\.` and not the whole sentence: that sentence is wrapped across two lines in both files, so a pattern spanning the wrap matches no single line and `sed` would run to end of file in both, comparing the rest of two unrelated documents.

- [ ] **Step 7: Lint and commit**

```bash
shellcheck scripts/__tests__/templates.test.sh
git add executor-prompt.md verifier-prompt.md scripts/__tests__/templates.test.sh
git commit -m "feat: executor and verifier dispatch templates"
```

Expected: `shellcheck` silent, exit 0.

---

### Task 7: SKILL.md — the orchestration loop

**Files:**
- Create: `SKILL.md`
- Create: `scripts/__tests__/skill.test.sh`

**Interfaces:**
- Consumes: all three scripts (Tasks 1–4) and all four templates (Tasks 5–6), by the exact filenames those tasks created; `assert.sh`'s helpers.
- Produces: `SKILL.md` at the repository root — the file `install.sh` (Task 8) exposes as the skill.

- [ ] **Step 1: Write the failing tests**

Create `scripts/__tests__/skill.test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../.." && pwd)
SKILL="$ROOT/SKILL.md"
BODY=$(cat "$SKILL" 2>/dev/null || true)

has() { assert_contains "$1" "$BODY" "SKILL.md: $2"; }

assert_eq 'yes' "$([ -f "$SKILL" ] && echo yes || echo no)" 'SKILL.md exists'

# --- frontmatter -----------------------------------------------------------

assert_eq '---' "$(head -n 1 "$SKILL" 2>/dev/null || true)" 'starts with YAML frontmatter'
has 'name: orchestrating-phased-specs' 'frontmatter names the skill'
has 'description: Use when' 'description states triggering conditions'
has 'phases 2 to 6' 'description carries the natural trigger phrasing'

# --- the permission-mode requirement, stated where it cannot be missed -----

assert_contains 'bypass-permissions' "$(sed -n '1,25p' "$SKILL")" \
  'SKILL.md: permission-mode requirement appears in the opening lines'
has 'cannot be read from inside a skill' 'says why permission mode is not checked'

# --- every script and template it depends on -------------------------------

for f in scripts/phase-preflight scripts/parse-phases scripts/phase-run-dir \
         planner-prompt.md executor-prompt.md verifier-prompt.md repair-prompt.md; do
  has "$f" "references $f"
  assert_eq 'yes' "$([ -e "$ROOT/$f" ] && echo yes || echo no)" \
    "SKILL.md: the referenced path $f exists on disk"
done

# --- the loop, the ledger, halting, the report -----------------------------

has 'git merge --no-ff' 'merges each phase branch with --no-ff'
has 'ascending numeric order' 'phases run in ascending numeric order'
has 'run.md' 'names the ledger file'
has 'merged' 'the ledger records a merged state per phase'
has 'Resume' 'documents resume'
has 'repair attempt per phase' 'exactly one repair attempt'
has 'halt' 'documents halting'
has 'nothing pushed, no PR opened' 'the run ends at a report'

# --- the model table -------------------------------------------------------

has 'name a model explicitly' 'requires an explicit model on every dispatch'
has 'mid-tier' 'the verifier takes a mid-tier model'

# --- the four known limits -------------------------------------------------

has 'Known limits' 'has a known-limits section'
has 'parks on a prompt' 'limit 1: wrong permission mode stalls rather than fails'
has 'compounds across phases' 'limit 2: capped review compounds'
has 'working tree is busy' 'limit 3: the working tree is busy for the whole run'
has 'depth' 'limit 4: nesting depth is a platform assumption'

finish
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: FAIL on `skill.test.sh` — `SKILL.md` does not exist, so `BODY` is empty and every assertion misses. The four other test files must still pass.

- [ ] **Step 3: Write SKILL.md**

Create `SKILL.md`:

````markdown
---
name: orchestrating-phased-specs
description: Use when the user asks to run multiple phases of a phased design document or spec — e.g. "let's work on phases 2 to 6 of <spec>" — orchestrating plan-writing and subagent-driven execution per phase across a base branch.
---

# Orchestrating Phased Specs

Run the requested phases of a phased design document end to end, unattended: per
phase, write a plan, execute it, verify it, merge it, record it.

**Run this in a bypass-permissions session**, or in one whose allow-rules cover
git, the repository's test runner, and this skill's scripts. Permission mode
cannot be read from inside a skill, so nothing checks this. In the wrong mode the
run does not fail — it parks on a permission prompt mid-phase and is
indistinguishable from a slow phase until someone looks.

**You are a thin controller.** You never read a plan, a diff, or a test log.
Artifacts live in files, dispatches carry paths, return values are capped. This is
not tidiness: everything you paste into a dispatch and everything a subagent
prints back stays resident in your context for the rest of the run and is re-read
every turn — and this session outlives one full `subagent-driven-development` run
per phase.

**Narration:** at most one short line between tool calls. The ledger is the record.

## Invocation

> Let's work on phases 2 to 6 of docs/superpowers/specs/…-design.md on branch feat/thing

From that you need three values, and nothing else:

| Value | Where it comes from |
|---|---|
| `DESIGN_DOC` | the path in the request |
| `BASE` | the branch named in the request. If none was named, ask — do not guess, and never default to trunk |
| `RANGE` | the phases named in the request: `2 to 6`, `2-6`, `2,4,5`, `3`, or `all` |

## Preflight

```bash
scripts/phase-preflight <DESIGN_DOC> <BASE> <RANGE>
```

Every check must pass or the run does not start. On a non-zero exit, stop and
show the script's stderr verbatim — it names the failed check and the command
that fixes it. Do not work around a refusal.

On success it has switched the working tree to `BASE`, creating it off trunk if
it did not exist, and printed the run directory. Then get the phase records:

```bash
scripts/parse-phases <DESIGN_DOC> <RANGE>   # number<TAB>title<TAB>slug, ascending
scripts/phase-run-dir <DESIGN_DOC>          # <run-dir>, git-ignored
```

Hold exactly this much state for the whole run: `DESIGN_DOC`, `BASE`, the phase
records, and `<run-dir>`. Nothing else accumulates across phases.

## The loop

For each requested phase in **ascending numeric order** — the number from the
heading, never a position in the list:

```bash
git switch <BASE> && git switch -c phase-<N>-<slug>
```

Then four dispatches. Every one of them **must name a model explicitly**; an
omitted model inherits this session's, which is the most expensive one.

| # | Dispatch | Template | Model | Why |
|---|---|---|---|---|
| ① | planner | `planner-prompt.md` | most capable | Writing a plan from a spec is design judgment, and every downstream cost compounds from its quality |
| ② | executor | `executor-prompt.md` | most capable | It is itself a controller, running a review loop and adjudicating findings unattended |
| ③ | verifier | `verifier-prompt.md` | mid-tier | Runs commands and reads exit codes — mechanical, but it must still reason about which gates a repository has |
| — | repair | `repair-prompt.md` | most capable | Fresh eyes on something a full execution run did not get right |

The executor's *own* dispatches are governed by `subagent-driven-development`'s
Model Selection. Do not reach into them.

Paths to substitute into the templates:

| Artifact | Path |
|---|---|
| Plan | `docs/superpowers/plans/<date>-<spec-slug>-phase-<N>-<slug>.md` |
| Executor decisions | `<run-dir>/phase-<N>-decisions.md` |
| Verifier evidence | `<run-dir>/phase-<N>-evidence.md` |
| Ledger | `<run-dir>/run.md` |

Order within a phase:

1. **①  planner** → returns the plan path. Append `phase <N> (<title>): plan <path>` to the ledger.
2. **②  executor** → returns `DONE` or `BLOCKED` in ten lines. Append the executed line.
3. **③  verifier** → returns `PASS` or `FAIL` plus the evidence path. Append the verified line.
4. On `FAIL`: dispatch **repair** once, then re-run the verifier. Green → continue. Red → halt.
   **Exactly one repair attempt per phase.** A second is how an unattended run burns an
   afternoon converging on nothing.
5. Merge:

```bash
git switch <BASE>
git merge --no-ff phase-<N>-<slug> -m "merge: phase <N> — <title>"
```

Conflicts cannot arise structurally — each phase branch forks from the current
base tip and base advances only through these merges, so the fork point is always
the merge base. Check the exit code anyway and halt on non-zero: a structural
impossibility that happens anyway is exactly what an unattended run must not
plough through. Keep phase branches after merging — free rollback points at zero
cost.

6. Append `phase <N>: merged to base (<sha>)` to the ledger.

## The ledger

`<run-dir>/run.md`. Write it as you go, not at the end. Its first two lines carry
its identity:

```markdown
# Phase run — spec: docs/superpowers/specs/…-design.md
# base: feat/thing  requested: 2-6

phase 2 (Shell & surface model): plan docs/superpowers/plans/…-phase-2-shell.md
phase 2: executed — 11 commits, review clean, 2 minor deferred, decisions phase-2-decisions.md
phase 2: verified PASS
phase 2: merged to base (a1b2c3d)
phase 3 (Takeovers & interstitials): plan docs/superpowers/plans/…-phase-3-takeovers.md
phase 3: executed — 9 commits, 1 parked
phase 3: verified FAIL — rest-arbitration.characterization.test.ts, exit 1
phase 3: repair round 1 — verified PASS
phase 3: merged to base (d4e5f6a)
```

A long run compacts this session's context, and a controller that loses its place
re-dispatches completed work — the most expensive failure mode there is. The
ledger is the recovery map, and the commits it names exist in git even when your
memory of them does not. After compaction, trust the ledger and `git log` over
your own recollection.

## Resume

Re-invoking this skill with the same spec and base **is** the resume. Read the
ledger and restart at the first requested phase with no `merged` line:

- A phase with a `plan` line but no `executed` line resumes at the executor,
  reusing the plan that is already on disk. Do not re-plan it.
- A phase with an `executed` line but no `verified PASS` resumes at the verifier.
- Nothing already merged is re-planned or re-executed.
- A ledger whose first line names a different spec is another run's. Leave it
  alone and start fresh.

## Halting

Halt on: an executor `BLOCKED` that repair does not clear, a second verifier
`FAIL`, a non-zero merge exit code, or a preflight refusal.

On halt: leave the failing phase's branch in place and unmerged, leave base at the
end of the last successful phase, start no later phase, and report the failed
check, the evidence file path, and the branch to inspect.

## The report

Write it to the ledger and print it:

```
RUN COMPLETE — phases 2–6 of …-design.md

phase 2  merged  a1b2c3d..d4e5f6a  11 commits   1 auto-decision   2 minor deferred
phase 3  merged  d4e5f6a..8f9a0b1   9 commits   0 auto-decisions  1 parked  (1 repair round)
…
base feat/thing ready — nothing pushed, no PR opened

auto-decisions:  <run-dir>/phase-N-decisions.md
parked findings: see ledger
```

Integration into trunk is a decision worth a human. The run ends here.

## Known limits

State these to your human partner when they matter; do not paper over them.

1. **The wrong permission mode stalls rather than fails.** The run parks on a
   prompt mid-phase and looks like a slow phase until inspected.
2. **Capped review compounds across phases.** The executor runs one review round
   per task, so phase N+1 builds on phase N's residual findings. The ledger and
   the report surface them; nothing prevents them.
3. **The working tree is busy for the whole run.** No worktrees, so the
   repository cannot be used for anything else while phases execute.
4. **Nesting depth is a platform assumption, not a guarantee.** This design needs
   a subagent to spawn subagents, to depth 3. If the executor cannot dispatch its
   own implementers, halt and say so — the design does not degrade gracefully.

## Common rationalizations

| Excuse | Reality |
|--------|---------|
| "I'll read the plan to check the planner did it right" | That is what the verifier and the executor's own review are for. A plan in your context is there for every remaining phase. |
| "The verifier's FAIL looks like a flake, I'll just merge" | The verifier reads exit codes; you did not run the command. One repair attempt, then halt. |
| "Repair almost worked, one more round" | Exactly one. Past it, the failure is structural and another round burns the afternoon. |
| "I'll fix this small thing myself" | Controller fixes skip verification and pollute your context. Dispatch it. |
| "I'll write the whole ledger at the end" | The end is exactly when your context may no longer exist. Append as you go. |
| "Phase 4 failed, but 5 and 6 are independent" | Phases share a base branch and are usually sequentially dependent. Halt. |
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: PASS — all five test files report `0 failed`, runner prints `all test files passed`.

- [ ] **Step 5: Check the frontmatter against the skill spec**

Frontmatter must be under 1024 characters total, and `name` must contain only letters, numbers and hyphens.

```bash
awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside {n+=length($0)+1} END {print n " frontmatter bytes"}' SKILL.md
grep -c '^name: [a-z0-9-]*$' SKILL.md
```

Expected: the byte count is well under 1024, and the second command prints `1`.

- [ ] **Step 6: Lint and commit**

```bash
shellcheck scripts/__tests__/skill.test.sh
git add SKILL.md scripts/__tests__/skill.test.sh
git commit -m "feat: the orchestration loop"
```

Expected: `shellcheck` silent, exit 0.

---

### Task 8: Installer, README, and spec bookkeeping

**Files:**
- Create: `install.sh`
- Create: `scripts/__tests__/install.test.sh`
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md`
- Delete: `docs/superpowers/plans/2026-08-03-orchestrating-phased-specs-phase-1-parsing-and-run-state.md`

**Interfaces:**
- Consumes: `assert.sh`'s helpers; `SKILL.md` from Task 7 (the installer refuses to run without it).
- Produces: `install.sh SKILLS_DIR_OVERRIDE_VIA_ENV` → symlinks `<skills-dir>/orchestrating-phased-specs` at this checkout. The skills directory is `$CLAUDE_SKILLS_DIR` when set, else `$HOME/.claude/skills` — the override exists so the test never writes into a real skills directory.

- [ ] **Step 1: Write the failing installer tests**

Create `scripts/__tests__/install.test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=assert.sh
. "$here/assert.sh"

ROOT=$(cd "$here/../.." && pwd)
INSTALL="$ROOT/install.sh"

tmp=$(cd "$(mktemp -d)" && pwd)
trap 'rm -rf "$tmp"' EXIT

# run_install SKILLS_DIR — run the installer against a throwaway skills dir.
run_install() {
  set +e
  OUT=$(CLAUDE_SKILLS_DIR="$1" "$INSTALL" 2>&1)
  RC=$?
  set -e
}

dest="$tmp/skills/orchestrating-phased-specs"

run_install "$tmp/skills"
assert_rc 0 'fresh install: exits 0'
assert_eq 'yes' "$([ -L "$dest" ] && echo yes || echo no)" 'creates a symlink'
assert_eq "$ROOT" "$(cd "$dest" && pwd)" 'the symlink resolves to this checkout'
assert_eq 'yes' "$([ -f "$dest/SKILL.md" ] && echo yes || echo no)" 'SKILL.md is reachable through it'

# Idempotent: re-running against an identical symlink is a no-op success.
run_install "$tmp/skills"
assert_rc 0 'second install: exits 0'
assert_contains 'already installed' "$OUT" 'second install: says it was already installed'

# A symlink pointing somewhere else is replaced.
rm "$dest"
ln -s "$tmp" "$dest"
run_install "$tmp/skills"
assert_rc 0 'stale symlink: exits 0'
assert_eq "$ROOT" "$(cd "$dest" && pwd)" 'stale symlink is repointed at this checkout'

# A real directory in the way is never deleted.
rm "$dest"
mkdir -p "$dest"
printf 'someone else\n' > "$dest/keep.txt"
run_install "$tmp/skills"
assert_rc 1 'real directory in the way: exits 1'
assert_contains 'not a symlink' "$OUT" 'real directory: message names the problem'
assert_eq 'yes' "$([ -f "$dest/keep.txt" ] && echo yes || echo no)" 'real directory: contents untouched'

finish
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: FAIL on `install.test.sh` — `install.sh` does not exist. The five other test files must still pass.

- [ ] **Step 3: Write install.sh**

Create `install.sh`:

```bash
#!/usr/bin/env bash
# Symlink this checkout into the skills directory, so edits here are live and
# the skill stays git-tracked in one place.
#
# CLAUDE_SKILLS_DIR overrides the destination. That override exists so the test
# suite can install into a throwaway directory instead of a real one.
#
# Usage: ./install.sh
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)

if [ ! -f "$src/SKILL.md" ]; then
  echo "no SKILL.md in $src — refusing to install an incomplete skill" >&2
  exit 1
fi

skills_dir=${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}
dest="$skills_dir/orchestrating-phased-specs"

mkdir -p "$skills_dir"

if [ -L "$dest" ]; then
  current=$(cd "$dest" && pwd)
  if [ "$current" = "$src" ]; then
    echo "already installed: $dest -> $src"
    exit 0
  fi
  rm "$dest"
elif [ -e "$dest" ]; then
  echo "$dest exists and is not a symlink — refusing to replace it" >&2
  echo "move it aside yourself, then re-run this installer" >&2
  exit 1
fi

ln -s "$src" "$dest"
echo "installed: $dest -> $src"
```

Then: `chmod +x install.sh`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/__tests__/run-tests.sh`

Expected: PASS — all six test files report `0 failed`, runner prints `all test files passed`.

- [ ] **Step 5: Update the README**

In `README.md`, replace the whole `## Status` section — the heading, the sentence beneath it, and the three-row phase table — with:

```markdown
## Status

Built in one pass against `docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md`.

| Piece | State |
|---|---|
| `scripts/parse-phases`, `scripts/phase-run-dir`, `scripts/phase-preflight` | done, unit-tested |
| `planner-prompt.md`, `executor-prompt.md`, `verifier-prompt.md`, `repair-prompt.md` | done, structurally tested |
| `SKILL.md` — the orchestration loop | done, structurally tested |

**Not yet proven end to end.** No real multi-phase run has been executed against
this skill; the first one is the proof. See the spec's §9 for the limits it ships with.
```

- [ ] **Step 6: Record the abandoned phase split in the spec**

The spec's §7 splits the build into three phases, each its own plan and session. That is no longer how it was built. In `docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md`, replace this line under `## 7. Implementation phases`:

```
Each phase is one session: its own plan, its own verification, its own commit.
```

with:

```
**Superseded 2026-08-03.** The project proved small enough to build in a single
plan — `docs/superpowers/plans/2026-08-03-orchestrating-phased-specs.md` — whose
tasks cover all three phases below. This section is kept as the record of what
each phase was meant to deliver and how it was to be verified. The one
verification it does not cover is §7 Phase 3's real two-phase end-to-end run:
executing it inside the build plan would have nested this skill's own agents
beneath the plan's, at a depth §8.1 has not verified. The first real run is that
verification.

Each phase below was to be one session: its own plan, its own verification, its own commit.
```

- [ ] **Step 7: Delete the superseded phase-1 plan**

```bash
git rm docs/superpowers/plans/2026-08-03-orchestrating-phased-specs-phase-1-parsing-and-run-state.md
```

Its content survives as Tasks 1–3 of this plan; two plans covering the same scripts is how a future session executes the wrong one.

- [ ] **Step 8: Full verification**

```bash
bash scripts/__tests__/run-tests.sh
shellcheck install.sh scripts/parse-phases scripts/phase-run-dir scripts/phase-preflight \
  scripts/__tests__/*.sh
ls -d .superpowers 2>/dev/null || echo "no stray run directory in this repo"
git status --porcelain
```

Expected: `all test files passed`; `shellcheck` silent and exit 0; `no stray run directory in this repo`; `git status --porcelain` showing only this task's files.

- [ ] **Step 9: Commit**

```bash
git add install.sh scripts/__tests__/install.test.sh README.md \
  docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md
git commit -m "feat: installer, and record the single-plan build in the spec"
```

---

## Done When

- `bash scripts/__tests__/run-tests.sh` prints `all test files passed` across all six test files
- `shellcheck` is clean across `install.sh`, the three scripts, and every file in `scripts/__tests__/`
- `scripts/parse-phases <a real phased spec> '2 to 6' | cut -f1` prints `2 3 4 5 6`, not `1 2 3 4 5`
- `scripts/phase-preflight` refuses on each of the six §4.3 checks, with a distinct exit code and an actionable message per check
- `./install.sh` symlinks the checkout into the skills directory, is idempotent, and refuses to clobber a real directory
- The spec carries D14 and the §7 supersession note; `README.md` states that the skill is not yet proven end to end
- Only one plan file remains under `docs/superpowers/plans/`

**What this plan does not deliver:** a real multi-phase run. See "Two deliberate deviations" at the top. The skill is complete and internally tested; it is unproven against a live spec until someone runs it.
