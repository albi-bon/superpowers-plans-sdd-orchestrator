#!/usr/bin/env bash
# phase-qa: the QA pass's branch, its one next action, landing, closing, the
# status line's stage and the report block.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
QA="$here/../phase-qa"
export PHASE_RUN_NAMESPACE=phase-parallel
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
origin="$tmp/origin.git"
run_in() {
  set +e
  OUT=$(cd "$repo" && "$@" 2>&1)
  RC=$?
  set -e
}
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
git -C "$repo" symbolic-ref HEAD refs/heads/feat/x
git init -q --bare "$origin"
git -C "$repo" remote add origin "$origin"
printf '# Example — Design Spec\n## Phase 1 — One\n## Phase 2 — Two\n' > "$repo/spec.md"
printf 'shared\n' > "$repo/shared.txt"
git -C "$repo" add spec.md shared.txt
git -C "$repo" commit -qm initial
rundir="$repo/.superpowers/phase-parallel/spec"
ledger="$rundir/run.md"
iwt="$repo/.worktrees/integration"
log() { printf '%s\n' "$@" >> "$ledger"; }
reset_ledger() { # start the ledger again, then append the lines given
  mkdir -p "$rundir"
  printf '# Phase run — spec: %s\n# base: feat/x  requested: 1-2\n\n' "$repo/spec.md" > "$ledger"
  [ "$#" -eq 0 ] || log "$@"
}
qa() { run_in "$QA" "$repo/spec.md" feat/x "$@"; }
tip() { git -C "$repo" rev-parse --short "$1"; }
commit_in() { # commit_in DIR FILE CONTENT
  printf '%s\n' "$3" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -qm "$2"
}

# --- open ---------------------------------------------------------------------------

reset_ledger 'run: invoked — cap 3'
b=$(tip feat/x)
qa open
assert_rc 0 'open: exits 0'
assert_eq "opened $b" "$OUT" 'open: prints the base tip'
assert_eq 'phase-qa-spec' "$(git -C "$iwt" branch --show-current)" 'open: the integration worktree is on the QA branch, named after the run'
assert_contains "qa: opened — phase-qa-spec at $b" "$(cat "$ledger")" 'open: recorded'

printf 'left by a walker\n' >> "$iwt/shared.txt"
qa open
assert_rc 0 'open again: exits 0'
assert_eq '' "$(git -C "$iwt" status --porcelain --untracked-files=no)" 'open again: tracked changes are discarded'
assert_eq '1' "$(grep -c '^qa: opened' "$ledger")" 'open again: the same tip is not recorded twice'
log 'qa: skipped — the product could not be started'
qa open
assert_eq '2' "$(grep -c '^qa: opened' "$ledger")" 'open after a skip: recorded again'

commit_in "$repo" two.txt two
b2=$(tip feat/x)
qa open
assert_eq "$(git -C "$repo" rev-parse feat/x)" "$(git -C "$repo" rev-parse phase-qa-spec)" 'open: an unused QA branch follows base'
assert_contains "qa: opened — phase-qa-spec at $b2" "$(cat "$ledger")" 'open: the new tip is recorded'

log 'qa: flows defined — 1 found, selected 1, not walkable -, parallel yes'
commit_in "$iwt" fix.txt fix
f=$(tip phase-qa-spec)
qa open
assert_eq "$f" "$(tip phase-qa-spec)" 'open: once flows are defined the branch is never moved'

reset_ledger 'run: invoked — cap 3'
qa open
assert_rc 14 'open: refuses a QA branch the ledger does not account for'
git -C "$iwt" switch -q --detach feat/x
git -C "$repo" branch -q -D phase-qa-spec
log 'batch 1: opened — phases 1@abc1234'
qa open
assert_rc 17 'open: refuses while a batch is open'
qa nonsense
assert_rc 2 'an unknown subcommand is a usage error'

finish
