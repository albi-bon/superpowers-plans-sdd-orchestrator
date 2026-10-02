#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
DEPS="$here/../parse-deps"
export PHASE_RUN_NAMESPACE=phase-parallel
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
run_in() {
  set +e
  OUT=$(cd "$tmp" && "$@" 2>&1)
  RC=$?
  set -e
}
# Graph output with tabs shown as spaces, lines joined by '|'.
flat() { printf '%s\n' "$OUT" | tr '\t' ' ' | tr '\n' '|'; }
git -C "$tmp" init -q

# --- every accepted line shape, and the missing-line default ----------------

cat > "$tmp/shapes.md" <<'EOF'
# Spec
## Phase 1 — Base
**Depends on:** none
Body text.
## Phase 2 — Bold
**Depends on:** Phase 1
## Phase 3 — Plain bullet
- Depends on: 1
## Phase 4 — Undeclared
## Phase 5 — Several
**Depends on:** Phase 3 and Phase 4.
## Phase 6 — Bare list
depends on: 2, 5, 2
Depends on: 1
EOF
run_in "$DEPS" "$tmp/shapes.md"
assert_rc 0 'shapes: exits 0'
assert_eq '1 - line|2 1 line|3 1 line|4 3 default|5 3,4 line|6 2,5 line|' "$(flat)" \
  'shapes: bold, plain, bullet, none, and-list, duplicates, first line wins, next-lower default'

# --- no Depends on lines at all: the graph agent is needed ------------------

printf '## Phase 1 — A\n## Phase 2 — B\n' > "$tmp/none.md"
run_in "$DEPS" "$tmp/none.md"
assert_rc 5 'no lines: exits 5'
assert_contains 'dispatch the graph agent' "$OUT" 'no lines: says to dispatch the graph agent'

printf '## Phase 1 — A\nDepends on: none\n## Phase 2 — B\nDepends on: phases 1–3 (roughly)\n## Phase 3 — C\n' > "$tmp/odd.md"
run_in "$DEPS" "$tmp/odd.md"
assert_rc 5 'unparseable line: exits 5, never half-read'
assert_contains 'phase(s): 2' "$OUT" 'unparseable line: names the phase'

# --- invalid graphs ----------------------------------------------------------

printf '## Phase 1 — A\nDepends on: 2\n## Phase 2 — B\nDepends on: 1\n' > "$tmp/cycle.md"
run_in "$DEPS" "$tmp/cycle.md"
assert_rc 6 'cycle: exits 6'
assert_contains 'dependency cycle among phases: 1 2' "$OUT" 'cycle: names the phases'

printf '## Phase 1 — A\nDepends on: 1\n' > "$tmp/self.md"
run_in "$DEPS" "$tmp/self.md"
assert_rc 6 'self-dependency: exits 6'

printf '## Phase 1 — A\nDepends on: 9\n' > "$tmp/unknown.md"
run_in "$DEPS" "$tmp/unknown.md"
assert_rc 6 'unknown phase: exits 6'
assert_contains 'depends on phase 9' "$OUT" 'unknown phase: names it'

# --- --write: graph.tsv, the ledger line, reuse ------------------------------

rundir="$tmp/.superpowers/phase-parallel/shapes"
mkdir -p "$rundir"
printf '# Phase run — spec: x\n# base: feat/x  requested: all\n\n' > "$rundir/run.md"
run_in "$DEPS" --write "$tmp/shapes.md"
assert_rc 0 '--write: exits 0'
assert_eq 'graph: 1→{} 2→{1} 3→{1} 4→{3} 5→{3,4} 6→{2,5} (source: line)' "$OUT" '--write: prints the summary'
assert_eq '6' "$(wc -l < "$rundir/graph.tsv" | tr -d ' ')" '--write: graph.tsv has one line per phase'
assert_eq '1' "$(grep -c '^graph: ' "$rundir/run.md")" '--write: one ledger line'
run_in "$DEPS" --write "$tmp/shapes.md"
assert_eq '1' "$(grep -c '^graph: ' "$rundir/run.md")" '--write again: no second ledger line'

# An agent-written graph is validated and reused, never regenerated.
rundir="$tmp/.superpowers/phase-parallel/none"
mkdir -p "$rundir"
printf '1\t-\tagent\n2\t1\tagent\n' > "$rundir/graph.tsv"
run_in "$DEPS" --write "$tmp/none.md"
assert_rc 0 'agent graph: accepted'
assert_eq 'graph: 1→{} 2→{1} (source: agent)' "$OUT" 'agent graph: summary names the agent'
printf '1\t2\tagent\n2\t1\tagent\n' > "$rundir/graph.tsv"
run_in "$DEPS" --write "$tmp/none.md"
assert_rc 6 'agent graph with a cycle: refused'
printf '1\t-\tagent\n' > "$rundir/graph.tsv"
run_in "$DEPS" --write "$tmp/none.md"
assert_rc 6 'agent graph missing a phase: refused'
assert_contains 'does not list phase 2' "$OUT" 'missing phase: named'

finish
