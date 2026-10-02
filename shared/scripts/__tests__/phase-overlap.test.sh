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
pairs4="$rundir/phase-4-overlap.tsv"
printf '# Phase run — spec: x\n# base: feat/x  requested: all\n\n' > "$ledger"
brief() { # brief N FILES-LINE...
  local n=$1; shift
  { printf '# Phase %s\n\n## Tasks\n\n### - [ ] Task 1 — t\n' "$n"; for l in "$@"; do printf -- '- **Files:** %s\n' "$l"; done; } > "$rundir/phase-$n-brief.md"
}
holds() { grep -c 'held' "$ledger"; }

# Paths integration settles by regenerating or merging; phase 1 plans every one.
IGNORED='package-lock.json
packages/client/src/i18n/en.json
locales/it.json
ios/App/en.lproj/Localizable.strings
po/it.po
AGENTS.md
packages/server/CLAUDE.md
rules/packages/client/session.md
docs/architecture/server.mdx
src/__generated__/graphql.ts
src/api/client.generated.ts
packages/server/drizzle/meta/_journal.json
packages/server/src/db/migrations/meta/0012_snapshot.json
prisma/migrations/migration_lock.toml
db/schema.rb
packages/client/src/__tests__/store.test.ts
packages/server/src/trpc/procedure-inventory.guard.test.ts
src/session.spec.ts
pkg/store_test.go
tests/test_api.py
src/__snapshots__/card.snap'

# Phase 1 is in flight, planning src/a.ts, src/lib/, a schema catalogue and
# every ignored path, with a commit touching src/c.ts.
printf 'phase 1: started — branch phase-1-a\n' >> "$ledger"
ignored_line=$(printf '%s\n' "$IGNORED" | awk '{ printf "%s`%s` (modify)", (NR > 1 ? ", " : ""), $0 }')
brief 1 '`src/a.ts` (create), `package-lock.json` (modify)' '`src/lib/` (create)' \
  '`src/schema/catalogue.ts` (modify)' "$ignored_line"
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
assert_eq '0' "$(holds)" 'clear: appends nothing'

run_in "$OVERLAP" "$tmp/spec.md" feat/x 2 'prereq-inflight: phase 1'
assert_eq 'held 1 prereq-inflight' "$OUT" 'scout reports an in-flight prerequisite: held'
assert_contains 'phase 2: held — waits on phase 1 (prereq-inflight)' "$(cat "$ledger")" 'prereq hold recorded'

# --- a file overlap is a signal for the judge, never a hold ------------------

printf 'phase 3: started — branch phase-3-c\n' >> "$ledger"
brief 3 'src/x.ts, src/a.ts'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 3
assert_rc 0 'overlap: exits 0'
assert_eq 'overlap 1 src/a.ts' "$OUT" 'brief vs brief, unquoted paths: overlap'
assert_eq '1' "$(holds)" 'overlap: appends nothing, the judge decides'
assert_eq "$(printf '1\tsrc/a.ts')" "$(cat "$rundir/phase-3-overlap.tsv" 2>/dev/null)" \
  'overlap: the pairs file lists phase and path for the judge'

printf 'phase 4: started — branch phase-4-d\n' >> "$ledger"
brief 4 '`src/c.ts` (modify)'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'overlap 1 src/c.ts' "$OUT" 'brief vs the in-flight branch diff: overlap'

brief 4 '`src/lib/util.ts` (create)'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'overlap 1 src/lib/util.ts' "$OUT" 'a path under an in-flight directory: overlap'

# Phase 3 is still active (an overlap holds nothing), so both phases count.
brief 4 '`src/a.ts` (modify), `src/x.ts` (modify), `src/c.ts` (modify)'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'overlap 1,3 src/a.ts,src/c.ts,src/x.ts' "$OUT" 'several in-flight phases: one line, every phase and path'
assert_eq "$(printf '1\tsrc/a.ts\n1\tsrc/c.ts\n3\tsrc/a.ts\n3\tsrc/x.ts')" "$(cat "$pairs4" 2>/dev/null)" \
  'several in-flight phases: every pair in the pairs file'

brief 4 '`src/lib/1.ts`, `src/lib/2.ts`, `src/lib/3.ts`, `src/lib/4.ts`, `src/lib/5.ts`, `src/lib/6.ts`, `src/lib/7.ts`'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'overlap 1 src/lib/1.ts,src/lib/2.ts,src/lib/3.ts,src/lib/4.ts,src/lib/5.ts,+2 more' "$OUT" \
  'the printed path list is capped at five'
assert_eq '7' "$(wc -l < "$pairs4" | tr -d ' ')" 'the pairs file is not capped'

# --- ignore patterns -----------------------------------------------------------

while IFS= read -r p; do
  brief 4 "\`$p\` (modify)"
  run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
  assert_eq 'clear' "$OUT" "built-in ignore: $p never counts"
done <<EOF
$IGNORED
EOF
assert_eq 'no' "$([ -e "$pairs4" ] && echo yes || echo no)" 'clear removes a stale pairs file'

brief 4 '`src/schema/catalogue.ts` (modify)'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'overlap 1 src/schema/catalogue.ts' "$OUT" 'a code file outside every pattern counts'
printf '# shared schema catalogue\nsrc/schema/catalogue.ts\n' > "$tmp/.phase-overlap-ignore"
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'clear' "$OUT" 'the repository ignore file adds a path pattern'
rm "$tmp/.phase-overlap-ignore"

printf 'catalogue.ts\n' > "$rundir/overlap-ignore"
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'clear' "$OUT" 'the run-directory ignore file adds a file-name pattern'

printf 'catalogue.ts\n!src/schema/\n' > "$rundir/overlap-ignore"
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'overlap 1 src/schema/catalogue.ts' "$OUT" 'a later ! pattern makes a path count again'

printf '!AGENTS.md\n' > "$rundir/overlap-ignore"
brief 4 '`AGENTS.md` (modify)'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'overlap 1 AGENTS.md' "$OUT" 'an owner pattern overrides a built-in one'
rm "$rundir/overlap-ignore"

# --- what is compared against ---------------------------------------------------

# The judge held phase 3 on phase 1. Held phases are never compared against:
# phase 3 also plans src/x.ts.
printf 'phase 3: held — waits on phase 1 (domain: both reshape the store)\n' >> "$ledger"
printf 'phase 1: merged to base (abc)\n' >> "$ledger"
brief 4 '`src/x.ts` (create)'
run_in "$OVERLAP" "$tmp/spec.md" feat/x 4
assert_eq 'clear' "$OUT" 'held and merged phases are not compared against'

run_in "$OVERLAP" "$tmp/spec.md" feat/x 4 'phase 1'
assert_eq 'clear' "$OUT" 'prerequisite already merged: clear'

finish
