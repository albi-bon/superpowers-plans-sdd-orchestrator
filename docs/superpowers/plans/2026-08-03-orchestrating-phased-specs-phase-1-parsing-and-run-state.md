# Orchestrating Phased Specs — Phase 1: Parsing and Run State — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the two bash scripts the orchestrator skill depends on — `parse-phases` (design document → phase records, with range selection) and `phase-run-dir` (resolve and git-ignore a run's scratch directory) — plus a dependency-free test harness that proves them against real and hostile inputs.

**Architecture:** Two standalone POSIX-ish bash scripts under `scripts/`, each doing one thing and printing to stdout. `parse-phases` extracts phase records with a single `awk` program, then selects a requested range in bash. `phase-run-dir` mirrors `subagent-driven-development`'s `sdd-workspace` exactly. Tests are plain bash files run by a tiny harness — no `bats`, no package manager, nothing to install.

**Tech Stack:** bash (must run under 3.2), `awk` (must run under BSD one-true-awk), `git`, `shellcheck` for linting.

**Spec:** `docs/superpowers/specs/2026-08-03-orchestrating-phased-specs-design.md` — this plan implements §7 Phase 1, against §4.1 (parsing), §4.2 (paths) and §4.3 (preflight's phase-presence check).

## Global Constraints

Every task's requirements implicitly include all of these. They come from the spec's §6 decision log.

- **D9 — project-agnostic.** No build command, no repository name, no project path is hard-coded anywhere in these scripts.
- **D10 — phase identity is the number captured from the heading, never an ordinal index into the list.** A document whose phases start at 0 makes the two differ. Selecting `2-6` must yield the phases *numbered* 2,3,4,5,6.
- **D11 — portability.** Written for `bash` 3.2 and BSD one-true-awk:
  - never `\s` — use `[[:space:]]`
  - never a bracket expression containing the em dash (`—`, U+2014) or en dash (`–`, U+2013) — match separators as whole strings via `index()`
  - never an interval expression (`{2,4}`) in any regex
  - never bash-4-only syntax: no `${var,,}`, no `${var^^}`, no associative arrays, no `mapfile`/`readarray`
- **D12 — output is data on stdout, diagnostics on stderr.** Every error message goes to stderr and is actionable: it names what was wrong and what the valid values were.
- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`, is `chmod +x`, and passes `shellcheck` with zero findings.
- Every script prints a usage line to stderr and exits `2` when called with the wrong number of arguments.

**Exit-code contract, shared by both scripts:**

| Code | Meaning |
|---|---|
| `0` | Success |
| `2` | Usage error, unreadable input file, or malformed range syntax |
| `3` | The design document contains no phase headings at all |
| `4` | The requested range names a phase number the document does not contain |

## File Structure

The repository at `/Users/albertobonino/projects/orchestrating-phased-specs` **is** the skill: `SKILL.md` and `scripts/` sit at its root, and `install.sh` will later symlink `~/.claude/skills/orchestrating-phased-specs` at it. Only `scripts/` exists after this phase — `SKILL.md` and the dispatch templates are Phases 2 and 3, and no task here may create them.

**Every command in this plan runs from the repository root.** All paths are relative to it, except the absolute path of the external fitsheet document used for corroboration in Task 1 Step 9 and Task 2 Step 6.

```
orchestrating-phased-specs/                 ← git repo, main branch
  docs/superpowers/
    specs/2026-08-03-…-design.md            the spec this plan implements
    plans/2026-08-03-…-phase-1-….md         this plan
  scripts/
    parse-phases                          design doc → phase records; range selection
    phase-run-dir                         resolve/create the run directory, ensure git-ignored
    __tests__/
      assert.sh                           assertion helpers, sourced by every test file
      run-tests.sh                        runs every *.test.sh, aggregates, exits non-zero on failure
      parse-phases.test.sh                extraction + range tests
      phase-run-dir.test.sh               run-directory tests
      fixtures/
        session-tracker-headings.md       the nine real headings from the fitsheet spec
        edge-cases.md                     dash variants, heading levels, duplicates, malformed
        no-phases.md                      a document with no phase headings
```

Responsibilities: `parse-phases` owns everything about turning a document into phase records and selecting among them. `phase-run-dir` owns everything about where a run's scratch artifacts live. They share no code — each is small enough that a shared library would cost more than it saves.

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
  - `assert.sh` exports shell functions `run_cmd`, `assert_eq`, `assert_rc`, `assert_contains`, `finish` — used verbatim by Task 3's test file.
  - Fixture paths above — Task 2 reuses `session-tracker-headings.md` and `edge-cases.md`.

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

Create `scripts/__tests__/fixtures/session-tracker-headings.md`. These are the nine phase headings copied verbatim from the real fitsheet design document, so the parser is proven against the shape it will actually meet:

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

Note on the `grep -c … | sed 's/^0$//'` idiom: it turns a count of `0` into the empty string, so `assert_eq ""` reads as "this phase number is absent". Any non-zero count fails the assertion and prints the count.

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
# Usage: parse-phases DESIGN_DOC
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

- [ ] **Step 9: Verify against the real design document**

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
- Produces: `parse-phases DESIGN_DOC RANGE` → the same tab-separated record format, filtered to the selected phase numbers, ascending. Exit `4` when a requested number is absent from the document; exit `2` on malformed range syntax.

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

Expected: FAIL — the Task 1 assertions still pass, but every range assertion fails because `parse-phases` currently exits `2` on a second argument (the arg-count guard accepts it, but nothing consumes it, so `2-6` is ignored and all nine phases are printed).

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

- [ ] **Step 6: Verify range selection against the real design document**

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
- Produces: `phase-run-dir DESIGN_DOC` → prints the absolute path of `<repo-root>/.superpowers/phase-orchestrator/<design-doc-basename-without-.md>/`, creating it and ensuring `<repo-root>/.superpowers/phase-orchestrator/.gitignore` contains `*`. Exit `0`.

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

## Phase 1 Done When

- `bash scripts/__tests__/run-tests.sh` prints `all test files passed`
- `shellcheck` is clean across all five shell files
- `parse-phases <real fitsheet spec> '2 to 6' | cut -f1` prints `2 3 4 5 6`, not `1 2 3 4 5`
- `phase-run-dir` is idempotent and leaves its output git-ignored
- No task in this plan has written any part of `SKILL.md` or any dispatch template — those are Phases 2 and 3
