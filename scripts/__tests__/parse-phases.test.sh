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

finish
