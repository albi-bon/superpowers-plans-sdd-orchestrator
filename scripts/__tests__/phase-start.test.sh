#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
START="$here/../phase-start"
PRE="$here/../phase-preflight"
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
run_in() {
  set +e
  OUT=$(cd "$tmp" && "$@" 2>&1)
  RC=$?
  set -e
}
git -C "$tmp" init -q
git -C "$tmp" config user.email test@example.com
git -C "$tmp" config user.name Test
git -C "$tmp" symbolic-ref HEAD refs/heads/main
printf '## Phase 1 — First\n## Phase 2 — Second\n' > "$tmp/spec.md"
git -C "$tmp" add spec.md
git -C "$tmp" commit -qm initial
run_in "$PRE" "$tmp/spec.md" feat/demo 1-2
assert_rc 0 'preflight initializes two-phase run'
run_in "$START" "$tmp/spec.md" feat/demo 1
assert_rc 0 'new phase starts'
assert_eq 'phase-1-first' "$(git -C "$tmp" branch --show-current)" 'new phase checked out'
ledger="$tmp/.superpowers/phase-orchestrator/spec/run.md"
assert_contains 'phase 1: started — branch phase-1-first' "$(cat "$ledger")" 'start checkpoint exists before planner'

# Interrupt after a committed plan. Resume must keep the branch and its commits.
printf 'plan\n' > "$tmp/plan.md"
git -C "$tmp" add plan.md
git -C "$tmp" commit -qm plan
printf 'phase 1 (First): plan plan.md\n' >> "$ledger"
head_before=$(git -C "$tmp" rev-parse HEAD)
run_in "$START" "$tmp/spec.md" feat/demo 1
assert_rc 0 'existing phase resumes'
assert_eq 'phase-1-first' "$(git -C "$tmp" branch --show-current)" 'resume returns to phase branch'
assert_eq "$head_before" "$(git -C "$tmp" rev-parse HEAD)" 'resume preserves commits'
assert_eq '1' "$(grep -c '^phase 1: started' "$ledger")" 'resume does not duplicate start record'

# Complete a two-phase Git flow with the same helpers used in the skill.
git -C "$tmp" switch -q feat/demo
git -C "$tmp" merge --no-ff -qm 'merge phase 1' phase-1-first
printf 'phase 1: merged to base (%s)\n' "$(git -C "$tmp" rev-parse HEAD)" >> "$ledger"
run_in "$START" "$tmp/spec.md" feat/demo 1
assert_rc 17 'already merged phase is not re-executed'
run_in "$START" "$tmp/spec.md" feat/demo 2
assert_rc 0 'second phase starts'
assert_eq 'plan' "$(cat "$tmp/plan.md")" 'second phase includes first phase changes'
printf 'implementation\n' > "$tmp/code.txt"
git -C "$tmp" add code.txt
git -C "$tmp" commit -qm implementation
git -C "$tmp" switch -q feat/demo
git -C "$tmp" merge --no-ff -qm 'merge phase 2' phase-2-second
assert_eq 'implementation' "$(git -C "$tmp" show feat/demo:code.txt)" 'second phase reaches base'

# Base advanced separately: do not resume a stale branch or reset it.
run_in "$START" "$tmp/spec.md" feat/demo 2
assert_rc 16 'advanced base refuses stale phase branch'
assert_eq 'feat/demo' "$(git -C "$tmp" branch --show-current)" 'stale branch refusal stays on base'
printf 'dirty\n' > "$tmp/untracked.txt"
run_in "$START" "$tmp/spec.md" feat/demo 2
assert_rc 11 'dirty interrupted work is preserved and refused'
assert_eq 'dirty' "$(cat "$tmp/untracked.txt")" 'dirty file preserved'
run_in "$START" "$tmp/spec.md" feat/demo '1-2'
assert_rc 2 'phase-start accepts only one phase number'
rm "$tmp/untracked.txt"
git -C "$tmp" branch -D phase-2-second >/dev/null
run_in "$START" "$tmp/spec.md" feat/demo 2
assert_rc 18 'missing recorded phase branch: refused instead of recreated'
assert_eq 'feat/demo' "$(git -C "$tmp" branch --show-current)" 'missing branch refusal stays on base'
finish
