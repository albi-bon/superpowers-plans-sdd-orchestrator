#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
METRICS="$here/../phase-metrics"
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
printf 'seed\n' > "$tmp/README.md"
git -C "$tmp" add README.md
git -C "$tmp" commit -qm initial

git -C "$tmp" switch -q -c phase-1-first
mkdir -p "$tmp/src/__tests__" "$tmp/docs"
printf 'a\nb\nc\nd\n' > "$tmp/src/a.ts"
printf 'x\ny\n' > "$tmp/src/__tests__/a.test.ts"
printf 'z\n' > "$tmp/src/b.spec.tsx"
printf 'doc\ndoc\ndoc\n' > "$tmp/docs/notes.md"
printf '{"k": 1}\n' > "$tmp/data.json"
git -C "$tmp" add -A
git -C "$tmp" commit -qm work
git -C "$tmp" switch -q main
git -C "$tmp" merge -q --no-ff phase-1-first -m 'merge: phase 1 — First'
merge=$(git -C "$tmp" rev-parse --short HEAD)

run_in "$METRICS" "$merge"
assert_rc 2 'one argument: usage error'
run_in "$METRICS" "$(git -C "$tmp" rev-parse --short HEAD^1)" phase-1-first
assert_rc 2 'a non-merge commit: refused'
assert_contains 'not a merge commit' "$OUT" 'non-merge: says why'

run_in "$METRICS" "$merge" phase-1-first
assert_rc 0 'a merge commit: printed'
assert_contains 'source +4, tests +3 (0.75 per source line)' "$OUT" 'source and test lines; docs and data count as neither'
assert_contains '2 new test files' "$OUT" 'both test files counted as new'
assert_contains 'checks: no agent-checks log' "$OUT" 'no log: says so'

log="$tmp/.git/agent-checks.log"
tab=$'\t'
{
  printf '1%sphase-1-first%sworker%srelated%srun%svitest related src/a.ts --run\n' "$tab" "$tab" "$tab" "$tab" "$tab"
  printf '2%sphase-1-first%sworker%srelated%srun%svitest related src/a.ts --run\n' "$tab" "$tab" "$tab" "$tab" "$tab"
  printf '3%sphase-1-first%sworker%stypecheck%srun%stsc -b\n' "$tab" "$tab" "$tab" "$tab" "$tab"
  printf '4%sphase-1-first%sworker%sfull%sblocked-full%spnpm test\n' "$tab" "$tab" "$tab" "$tab" "$tab"
  printf '5%sphase-1-first%sworker%srelated%sblocked-repeat%svitest related src/a.ts --run\n' "$tab" "$tab" "$tab" "$tab" "$tab"
  printf '6%sphase-1-first%sverifier%sfull%srun%sFULL_CHECKS=1 pnpm test\n' "$tab" "$tab" "$tab" "$tab" "$tab"
  printf '7%sphase-2-other%sworker%sfull%srun%spnpm test\n' "$tab" "$tab" "$tab" "$tab" "$tab"
} > "$log"
run_in "$METRICS" "$merge" phase-1-first
assert_contains 'checks: related 2, typecheck 1, build 0, full 1; blocked: full 1, repeat 1' "$OUT" \
  'log rows counted for this branch only'

PHASE_TEST_PATHS='\.spec\.' run_in "$METRICS" "$merge" phase-1-first
assert_contains 'source +6, tests +1' "$OUT" 'PHASE_TEST_PATHS overrides what counts as a test'

finish
