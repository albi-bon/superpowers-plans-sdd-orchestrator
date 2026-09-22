#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
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

# The same defect class as the trailing comma: word splitting on IFS drops
# leading and trailing empty fields, so these cannot be caught per-item.
run_cmd "$PARSE" "$FIX/session-tracker-headings.md" ',2'
assert_rc 2 'leading comma: exits 2'

run_cmd "$PARSE" "$FIX/session-tracker-headings.md" '2,,3'
assert_rc 2 'empty item between commas: exits 2'

finish
