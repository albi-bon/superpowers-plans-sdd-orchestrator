#!/usr/bin/env bash
# phase-integrate and phase-land together: two phases built side by side, one
# landing cleanly, one integrating cleanly, one through a conflict.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
WT="$here/../phase-worktree"
INTEGRATE="$here/../phase-integrate"
LAND="$here/../phase-land"
export PHASE_RUN_NAMESPACE=phase-parallel
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
git -C "$tmp" symbolic-ref HEAD refs/heads/feat/x
printf '## Phase 1 — One\n## Phase 2 — Two\n## Phase 3 — Three\n' > "$tmp/spec.md"
printf 'shared\n' > "$tmp/shared.txt"
git -C "$tmp" add spec.md shared.txt
git -C "$tmp" commit -qm initial
rundir="$tmp/.superpowers/phase-parallel/spec"
mkdir -p "$rundir"
ledger="$rundir/run.md"
printf '# Phase run — spec: x\n# base: feat/x  requested: all\n\n' > "$ledger"
commit_in() { # commit_in DIR FILE CONTENT
  printf '%s\n' "$3" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -qm "$2"
}

run_in "$WT" "$tmp/spec.md" feat/x start 1; wt1=$OUT
run_in "$WT" "$tmp/spec.md" feat/x start 2; wt2=$OUT
run_in "$WT" "$tmp/spec.md" feat/x start 3; wt3=$OUT
commit_in "$wt1" one.txt one
commit_in "$wt2" two.txt two
commit_in "$wt3" shared.txt 'phase three'
v1=$(git -C "$wt1" rev-parse --short HEAD)
v2=$(git -C "$wt2" rev-parse --short HEAD)
v3=$(git -C "$wt3" rev-parse --short HEAD)

# --- refusals ------------------------------------------------------------------

printf 'dirty\n' > "$wt1/dirty.txt"
run_in "$INTEGRATE" "$tmp/spec.md" feat/x 1 "$v1"
assert_rc 11 'integrate: dirty worktree refused'
rm "$wt1/dirty.txt"
run_in "$INTEGRATE" "$tmp/spec.md" feat/x 1 deadbeef
assert_rc 19 'integrate: unknown verified SHA refused'
run_in "$LAND" "$tmp/spec.md" feat/x 1 "$v2"
assert_rc 19 'land: branch not at the verified SHA refused'

# --- phase 1: base never moved, ready, lands ------------------------------------

run_in "$INTEGRATE" "$tmp/spec.md" feat/x 1 "$v1"
assert_rc 0 'integrate 1: exits 0'
assert_eq "ready $v1" "$OUT" 'integrate 1: base unchanged, ready'
assert_contains "phase 1: integrating — base unchanged, ready $v1" "$(cat "$ledger")" 'integrate 1: recorded'
run_in "$INTEGRATE" "$tmp/spec.md" feat/x 1 "$v1"
assert_eq '1' "$(grep -c '^phase 1: integrating' "$ledger")" 'integrate 1 again: idempotent, one ledger line'

printf 'dirty\n' > "$tmp/dirty.txt"
run_in "$LAND" "$tmp/spec.md" feat/x 1 "$v1"
assert_rc 11 'land: dirty main checkout refused'
rm "$tmp/dirty.txt"
run_in "$LAND" "$tmp/spec.md" feat/x 1 "$v1"
assert_rc 0 'land 1: exits 0'
assert_eq 'merge: phase 1 — One' "$(git -C "$tmp" log -1 --format=%s)" 'land 1: --no-ff merge commit named for the phase'
assert_eq "$(git -C "$tmp" rev-parse "$v1^{tree}")" "$(git -C "$tmp" rev-parse 'HEAD^{tree}')" 'land 1: base tree equals the verified tree'
assert_eq 'no' "$([ -d "$wt1" ] && echo yes || echo no)" 'land 1: worktree removed'
assert_contains "phase 1: merged to base (" "$(cat "$ledger")" 'land 1: recorded'
run_in "$LAND" "$tmp/spec.md" feat/x 1 "$v1"
assert_rc 17 'land 1 again: refused'

# --- phase 2: base moved, clean merge, then lands -------------------------------

run_in "$LAND" "$tmp/spec.md" feat/x 2 "$v2"
assert_rc 21 'land before integrating a moved base: refused'
run_in "$INTEGRATE" "$tmp/spec.md" feat/x 2 "$v2"
assert_rc 0 'integrate 2: exits 0'
i2=$(git -C "$wt2" rev-parse --short HEAD)
assert_eq "merged $i2" "$OUT" 'integrate 2: clean merge of the moved base'
assert_contains "phase 2: integrating — base moved (phase 1), clean merge $i2" "$(cat "$ledger")" 'integrate 2: names the phase that moved base'
assert_eq 'integrate: base into phase 2' "$(git -C "$wt2" log -1 --format=%s)" 'integrate 2: merge commit subject'
run_in "$INTEGRATE" "$tmp/spec.md" feat/x 2 "$v2"
assert_eq "merged $i2" "$OUT" 'integrate 2 again: idempotent'
assert_eq '1' "$(grep -c '^phase 2: integrating' "$ledger")" 'integrate 2 again: one ledger line'
printf 'phase 2: integration verified PASS %s\n' "$i2" >> "$ledger"
run_in "$LAND" "$tmp/spec.md" feat/x 2 "$i2"
assert_rc 0 'land 2: exits 0'
assert_eq "$(git -C "$tmp" rev-parse "$i2^{tree}")" "$(git -C "$tmp" rev-parse 'HEAD^{tree}')" 'land 2: base tree equals the integrated tree'

# --- phase 3: conflict, resolved by hand, lands ----------------------------------

git -C "$tmp" switch -q -c side
commit_in "$tmp" shared.txt 'base side'
git -C "$tmp" switch -q feat/x
git -C "$tmp" merge -q --no-ff side -m 'merge: phase 9 — Elsewhere'
run_in "$INTEGRATE" "$tmp/spec.md" feat/x 3 "$v3"
assert_rc 0 'integrate 3: exits 0 on conflict'
assert_eq 'conflict' "$OUT" 'integrate 3: reports the conflict'
assert_eq 'yes' "$(git -C "$wt3" rev-parse -q --verify MERGE_HEAD >/dev/null && echo yes || echo no)" 'integrate 3: merge left in progress'
assert_contains 'shared.txt' "$(cat "$rundir/phase-3-conflicts.md")" 'conflicts file lists the path'
assert_contains '- phase 1' "$(cat "$rundir/phase-3-conflicts.md")" 'conflicts file lists phases merged since the fork'
assert_contains '- phase 9' "$(cat "$rundir/phase-3-conflicts.md")" 'conflicts file lists every landed phase'
assert_contains 'conflict in 1 files' "$(cat "$ledger")" 'integrate 3: conflict recorded'
run_in "$INTEGRATE" "$tmp/spec.md" feat/x 3 "$v3"
assert_eq 'conflict' "$OUT" 'integrate 3 again: still conflict, idempotent'
run_in "$WT" "$tmp/spec.md" feat/x check
assert_rc 0 'check: a worktree mid-integration is not refused'

printf 'phase three\nbase side\n' > "$wt3/shared.txt"
git -C "$wt3" add shared.txt
git -C "$wt3" commit -q --no-edit
i3=$(git -C "$wt3" rev-parse --short HEAD)
run_in "$LAND" "$tmp/spec.md" feat/x 3 "$i3"
assert_rc 0 'land 3 after resolution: exits 0'
assert_eq "$(printf 'phase three\nbase side')" "$(cat "$tmp/shared.txt")" 'land 3: base holds the resolution'

finish
