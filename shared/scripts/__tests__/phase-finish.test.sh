#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
START="$here/../phase-start"
PRE="$here/../phase-preflight"
FINISH="$here/../phase-finish"
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
ledger="$tmp/.superpowers/phase-orchestrator/spec/run.md"

run_in "$PRE" "$tmp/spec.md" feat/demo 1-2
run_in "$START" "$tmp/spec.md" feat/demo 1
printf 'one\n' > "$tmp/one.txt"
git -C "$tmp" add one.txt
git -C "$tmp" commit -qm one
verified=$(git -C "$tmp" rev-parse --short HEAD)

# Refusals before anything moves.
run_in "$FINISH" "$tmp/spec.md" feat/demo 1
assert_rc 2 'missing verified SHA: usage error'
run_in "$FINISH" "$tmp/spec.md" feat/demo x "$verified"
assert_rc 2 'non-integer phase: usage error'

printf 'dirty\n' > "$tmp/dirty.txt"
run_in "$FINISH" "$tmp/spec.md" feat/demo 1 "$verified"
assert_rc 11 'dirty tree: refused'
assert_eq 'phase-1-first' "$(git -C "$tmp" branch --show-current)" 'dirty tree: stays on the phase branch'
rm "$tmp/dirty.txt"

printf 'later\n' > "$tmp/later.txt"
git -C "$tmp" add later.txt
git -C "$tmp" commit -qm 'unverified later commit'
run_in "$FINISH" "$tmp/spec.md" feat/demo 1 "$verified"
assert_rc 19 'HEAD moved past the verified SHA: refused'
assert_contains 'verify again' "$OUT" 'HEAD mismatch: message says to verify again'
assert_eq 'phase-1-first' "$(git -C "$tmp" branch --show-current)" 'HEAD mismatch: stays on the phase branch'
run_in "$FINISH" "$tmp/spec.md" feat/demo 1 deadbeefdeadbeef
assert_rc 19 'unknown verified SHA: refused'

run_in "$FINISH" "$tmp/spec.md" feat/demo 2 "$verified"
assert_rc 18 'missing phase branch: refused'

# The happy path.
verified=$(git -C "$tmp" rev-parse --short HEAD)
run_in "$FINISH" "$tmp/spec.md" feat/demo 1 "$verified"
assert_rc 0 'verified phase merges'
assert_eq 'feat/demo' "$(git -C "$tmp" branch --show-current)" 'ends on base'
# A merge commit's rev-list line is its own SHA plus two parents.
assert_eq '3' "$(git -C "$tmp" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" \
  'the merge is a real merge commit (--no-ff)'
assert_eq 'merge: phase 1 — First' "$(git -C "$tmp" log -1 --format=%s)" 'merge message names the phase'
merged=$(git -C "$tmp" rev-parse --short HEAD)
assert_contains "phase 1 merged to feat/demo ($merged)" "$OUT" 'prints one summary line'
assert_eq '1' "$(grep -c "^phase 1: merged to base ($merged)$" "$ledger")" 'appends exactly one ledger line'

run_in "$FINISH" "$tmp/spec.md" feat/demo 1 "$verified"
assert_rc 17 'second finish of the same phase: refused'
assert_eq '1' "$(grep -c '^phase 1: merged to base' "$ledger")" 'refusal adds no ledger line'

# A forced merge failure: base gains a conflicting commit behind the phase's back.
run_in "$START" "$tmp/spec.md" feat/demo 2
printf 'phase\n' > "$tmp/clash.txt"
git -C "$tmp" add clash.txt
git -C "$tmp" commit -qm 'phase side'
verified=$(git -C "$tmp" rev-parse HEAD)
git -C "$tmp" switch -q feat/demo
printf 'base\n' > "$tmp/clash.txt"
git -C "$tmp" add clash.txt
git -C "$tmp" commit -qm 'base side'
base_before=$(git -C "$tmp" rev-parse HEAD)
git -C "$tmp" switch -q phase-2-second
run_in "$FINISH" "$tmp/spec.md" feat/demo 2 "$verified"
assert_rc 20 'conflicting merge: exits 20'
assert_eq "$base_before" "$(git -C "$tmp" rev-parse feat/demo)" 'conflicting merge: base unchanged'
assert_eq 'phase-2-second' "$(git -C "$tmp" branch --show-current)" 'conflicting merge: back on the phase branch'
assert_eq '' "$(git -C "$tmp" status --porcelain)" 'conflicting merge: tree left clean'
assert_eq '0' "$(grep -c '^phase 2: merged' "$ledger")" 'conflicting merge: no ledger line'

finish
