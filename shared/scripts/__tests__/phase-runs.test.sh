#!/usr/bin/env bash
# phase-runs: which other parallel runs are active in the repository, and the
# parallel skill's preflight, which prints them and records them in the ledger.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
RUNS="$here/../phase-runs"
ROOT=$(cd "$here/../../../skills/building-phased-specs-in-parallel" && pwd)
export PHASE_RUN_NAMESPACE=phase-parallel
export PHASE_RUN_ANCHOR=main
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
run_in() { # run_in DIR COMMAND…
  local dir=$1
  shift
  set +e
  OUT=$(cd "$dir" && "$@" 2>&1)
  RC=$?
  set -e
}
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
git -C "$repo" symbolic-ref HEAD refs/heads/main
git init -q --bare "$tmp/origin.git"
git -C "$repo" remote add origin "$tmp/origin.git"
for name in alpha beta done stale legacy; do
  printf '## Phase 1 — One\n**Depends on:** none\n## Phase 2 — Two\n**Depends on:** none\n' > "$repo/$name.md"
done
git -C "$repo" add -A
git -C "$repo" commit -qm initial
rundirs="$repo/.superpowers/phase-parallel"
old=$(date -v-3d +%Y%m%d%H%M 2>/dev/null || date -d '3 days ago' +%Y%m%d%H%M)

run_in "$repo" "$RUNS"
assert_rc 0 'no run directory: exits 0'
assert_eq '' "$OUT" 'no run directory: lists nothing'
assert_eq 'no' "$([ -e "$repo/.superpowers" ] && echo yes || echo no)" 'reads only: creates no run directory'
run_in "$tmp" "$RUNS"
assert_rc 2 'outside a repository: refused'

# --- two live runs see each other ---------------------------------------------------

run_in "$repo" "$ROOT/scripts/phase-preflight" "$repo/alpha.md" feat/a all
assert_rc 0 'the first run passes preflight'
assert_eq '' "$(printf '%s\n' "$OUT" | grep '^other-run')" 'the first run: no other run to print'
assert_eq '' "$(grep '^run: concurrent' "$rundirs/alpha/run.md")" 'the first run: no concurrent line in its ledger'

run_in "$repo" "$ROOT/scripts/phase-preflight" "$repo/beta.md" feat/b all
assert_rc 0 'a second run passes preflight beside the first: never refused'
assert_eq 'other-run alpha feat/a 0/2 merged' "$(printf '%s\n' "$OUT" | grep '^other-run')" \
  'the second run prints the first, after the rest of its output'
assert_contains 'design-doc ' "$(printf '%s\n' "$OUT" | grep -B1 '^other-run' | head -n 1)" \
  'the other-run lines follow the existing output'
assert_eq 'run: concurrent — alpha' "$(grep '^run: concurrent' "$rundirs/beta/run.md")" \
  'the second run records the first in its ledger'

printf 'phase 1: started — branch phase-1-one@beta, worktree .worktrees/beta/phase-1-one\nphase 1: lead dispatched\n' \
  >> "$rundirs/beta/run.md"
run_in "$repo/.worktrees/alpha/base" "$ROOT/scripts/phase-runs" "$repo/.worktrees/alpha/base/alpha.md"
assert_eq 'beta feat/b 0/2 merged · 1 building' "$OUT" 'the first run sees the second, with its state'
run_in "$repo" "$ROOT/scripts/phase-runs" "$repo/beta.md"
assert_eq 'alpha feat/a 0/2 merged' "$OUT" 'the second run sees the first, and not itself'
run_in "$repo" "$RUNS" --names
assert_eq "$(printf 'alpha\nbeta')" "$OUT" 'with no document, every active run; --names prints names only'

# Worktrees keep a run alive however long its ledger has been quiet.
touch -t "$old" "$rundirs/alpha/run.md"
run_in "$repo" "$RUNS" --names "$repo/beta.md"
assert_eq 'alpha' "$OUT" 'a quiet run with its worktrees left is active'
run_in "$repo" "$RUNS" "$repo/beta.md"
assert_eq 'alpha feat/a 0/2 merged · idle 3d' "$OUT" 'a quiet run shows how long it has been idle'

# --- finished runs --------------------------------------------------------------------

run_in "$repo" "$ROOT/scripts/phase-preflight" "$repo/done.md" feat/d all
printf 'run: PR https://example.com/pull/1\nrun: owner decision — rows align; fix dispatched\n' >> "$rundirs/done/run.md"
run_in "$repo" "$RUNS" --names
assert_eq "$(printf 'alpha\nbeta')" "$OUT" 'a run that opened its pull request is not listed, worktrees or not'
printf 'run: invoked — cap 2\n' >> "$rundirs/done/run.md"
run_in "$repo" "$RUNS" --names
assert_eq "$(printf 'alpha\nbeta\ndone')" "$OUT" 'a finished run resumed is active again'
printf 'RUN COMPLETE — phases 1–2 of done.md\n' >> "$rundirs/done/run.md"
run_in "$repo" "$RUNS" --names
assert_eq "$(printf 'alpha\nbeta')" "$OUT" 'a run that wrote its report is not listed'

# --- a stale run: not finished, no worktrees, ledger quiet -------------------------------

mkdir -p "$rundirs/stale"
printf '# Phase run — spec: %s\n# base: feat/s  requested: all\n# layout: run-scoped\n\nphase 1: lead dispatched\n' \
  "$repo/.worktrees/stale/base/stale.md" > "$rundirs/stale/run.md"
run_in "$repo" "$RUNS" --names
assert_contains 'stale' "$OUT" 'an unfinished ledger written recently is active, without worktrees'
touch -t "$old" "$rundirs/stale/run.md"
run_in "$repo" "$RUNS" --names
assert_eq "$(printf 'alpha\nbeta')" "$OUT" 'an unfinished ledger with no worktrees and quiet for days is not listed'

# --- a legacy run: shares .worktrees/ and names no run in its paths ---------------------

mkdir -p "$rundirs/legacy"
printf '# Phase run — spec: %s\n# base: feat/l  requested: all\n\n' "$repo/legacy.md" > "$rundirs/legacy/run.md"
printf 'phase 1: started — branch phase-1-one, worktree .worktrees/phase-1-one\nphase 1: lead dispatched\n' \
  >> "$rundirs/legacy/run.md"
git -C "$repo" worktree add -q "$repo/.worktrees/phase-1-one" -b phase-1-one main
touch -t "$old" "$rundirs/legacy/run.md"
run_in "$repo" "$RUNS" "$repo/beta.md"
assert_eq "$(printf 'alpha feat/a 0/2 merged · idle 3d\nlegacy feat/l 0/2 merged · 1 building · idle 3d')" "$OUT" \
  'a live legacy run is listed through the phase worktree its ledger started'
git -C "$repo" worktree remove "$repo/.worktrees/phase-1-one"
run_in "$repo" "$RUNS" --names
assert_eq "$(printf 'alpha\nbeta')" "$OUT" 'a legacy run whose worktrees are gone, quiet for days, is not listed'
git -C "$repo" worktree add -q "$repo/.worktrees/base" -b feat/l main
run_in "$repo" "$RUNS" --names
assert_eq "$(printf 'alpha\nbeta\nlegacy')" "$OUT" 'a legacy run is listed through .worktrees/base on its base'
git -C "$repo" worktree add -q "$repo/.worktrees/other" -b feat/other main
git -C "$repo" worktree remove "$repo/.worktrees/base"
run_in "$repo" "$RUNS" --names
assert_eq "$(printf 'alpha\nbeta')" "$OUT" "a legacy run is not kept alive by a worktree that is not its own"

finish
