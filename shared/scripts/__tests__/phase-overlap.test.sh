#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
OVERLAP="$here/../phase-overlap"
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
printf '## Phase 1 — A\n## Phase 2 — B\n## Phase 3 — C\n## Phase 4 — D\n' > "$tmp/spec.md"
git -C "$tmp" add spec.md
git -C "$tmp" commit -qm initial
rundir="$tmp/.superpowers/phase-parallel/spec"
mkdir -p "$rundir"
ledger="$rundir/run.md"
printf '# Phase run — spec: x\n# base: feat/x  requested: all\n\n' > "$ledger"
brief() { # brief N FILES-LINE...
  local n=$1; shift
  { printf '# Phase %s\n\n## Tasks\n\n### - [ ] Task 1 — t\n' "$n"; for l in "$@"; do printf -- '- **Files:** %s\n' "$l"; done; } > "$rundir/phase-$n-brief.md"
}

# Phase 1 is in flight, planning src/a.ts and src/lib/, with a commit touching src/c.ts.
printf 'phase 1: started — branch phase-1-a\n' >> "$ledger"
brief 1 '`src/a.ts` (create), `package-lock.json` (modify)' '`src/lib/` (create)'
git -C "$tmp" branch phase-1-a
git -C "$tmp" switch -q phase-1-a
mkdir -p "$tmp/src"; printf 'c\n' > "$tmp/src/c.ts"
git -C "$tmp" add src/c.ts; git -C "$tmp" commit -qm c
git -C "$tmp" switch -q feat/x

run_in "$OVERLAP" "$tmp/spec.md" feat/x 2
assert_rc 2 'no brief: refused'

printf 'phase 2: started — branch phase-2-b\n' >> "$ledger"
brief 2 '`src/b.ts` (create)' '`package-lock.json` (modify), `./README.md` (modify)'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 2
assert_rc 0 'disjoint: exits 0'
assert_eq 'clear' "$OUT" 'disjoint files and a shared lockfile: clear'
assert_eq '0' "$(grep -c 'held' "$ledger")" 'clear: appends nothing'

run_in "$OVERLAP" "$tmp/spec.md" feat/x 2 'prereq-inflight: phase 1'
assert_eq 'held 1 prereq-inflight' "$OUT" 'scout reports an in-flight prerequisite: held'
assert_contains 'phase 2: held — waits on phase 1 (prereq-inflight)' "$(cat "$ledger")" 'prereq hold recorded'

printf 'phase 3: started — branch phase-3-c\n' >> "$ledger"
brief 3 'src/x.ts, src/a.ts'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 3
assert_eq 'held 1 overlap src/a.ts' "$OUT" 'brief vs brief, unquoted paths: held'
assert_contains 'phase 3: held — waits on phase 1 (overlap src/a.ts)' "$(cat "$ledger")" 'overlap hold recorded'

printf 'phase 4: started — branch phase-4-d\n' >> "$ledger"
brief 4 '`src/c.ts` (modify)'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'held 1 overlap src/c.ts' "$OUT" 'brief vs the in-flight branch diff: held'

brief 4 '`src/lib/util.ts` (create)'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'held 1 overlap src/lib/util.ts' "$OUT" 'a path under an in-flight directory: held'

# Held phases are never compared against: phase 3 also plans src/x.ts.
printf 'phase 1: merged to base (abc)\n' >> "$ledger"
brief 4 '`src/x.ts` (create)'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'clear' "$OUT" 'held and merged phases are not compared against'

run_in "$OVERLAP" "$tmp/spec.md" feat/x 4 'phase 1'
assert_eq 'clear' "$OUT" 'prerequisite already merged: clear'

finish
