#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
LINE="$here/../phase-statusline"
WT="$here/../phase-worktree"
export PHASE_RUN_NAMESPACE=phase-parallel
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo/sub"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
git -C "$repo" symbolic-ref HEAD refs/heads/feat/x
printf '## Phase 1 — A\n## Phase 2 — B\n## Phase 3 — C\n## Phase 4 — D\n## Phase 5 — E\n## Phase 6 — F\n## Phase 7 — G\n' > "$repo/spec.md"
git -C "$repo" add spec.md
git -C "$repo" commit -qm initial
json() { printf '{"session_id":"s","workspace":{"current_dir":"%s"},"cwd":"%s"}' "$1" "$1"; }
line() { # line DIR — the status line for a session in DIR
  set +e
  OUT=$(json "$1" | "$LINE" 2>&1)
  RC=$?
  set -e
}

line "$repo"
assert_rc 0 'no run: exits 0'
assert_eq '' "$OUT" 'no run: prints nothing'
line "$tmp"
assert_eq '' "$OUT" 'outside a repository: prints nothing'

rundir="$repo/.superpowers/phase-parallel/spec"
mkdir -p "$rundir"
ledger="$rundir/run.md"
printf '# Phase run — spec: %s\n# base: feat/x  requested: 1-7\n\n' "$repo/spec.md" > "$ledger"
log() { printf '%s\n' "$@" >> "$ledger"; }
log 'run: invoked — cap 3'
for n in 1 2 3 4 5; do log "phase $n: started — branch phase-$n-x"; done
log 'phase 1: merged to base (aaa1)' \
  'phase 2: executed — a0a0a0a..bbb2, review 0/0/0 (0 fixed, 0 deferred), 0 significant' \
  'phase 3: executed — a0a0a0a..ccc3, review 0/0/0 (0 fixed, 0 deferred), 0 significant' \
  'batch 1: opened — phases 2@bbb2 3@ccc3' 'batch 1: built ddd1' \
  'phase 4: held — waits on phase 5 (domain: both reshape the store)' \
  'phase 5: lead dispatched'

line "$repo"
assert_eq 'feat/x · 1/7 merged · 1 building · batch 1 verifying 2 · 1 held · 2 left' "$OUT" \
  'a run in flight: merged of requested, building, the open batch, held, left'
line "$repo/sub"
assert_eq 'feat/x · 1/7 merged · 1 building · batch 1 verifying 2 · 1 held · 2 left' "$OUT" \
  'a session in a subdirectory finds the run'
set +e; OUT=$(cd "$repo" && "$LINE" </dev/null); set -e
assert_eq 'feat/x · 1/7 merged · 1 building · batch 1 verifying 2 · 1 held · 2 left' "$OUT" \
  'without session JSON it uses the working directory'

log 'batch 1: verified FAIL — pinned on phase 3 — tests' \
  'phase 6: started — branch phase-6-x' \
  'phase 6: executed — a0a0a0a..eee6, review 0/0/0 (0 fixed, 0 deferred), 0 significant'
line "$repo"
assert_eq 'feat/x · 1/7 merged · 1 building · 2 queued · 1 repairing · 1 held · 1 left' "$OUT" \
  'a pinned failure: the rest queue again, the culprit is repairing'

log 'phase 3: failed — ladder exhausted' 'run: draining — phase 3 ladder exhausted'
line "$repo"
assert_eq 'feat/x · 1/7 merged · draining · 1 building · 2 queued · 1 held · 1 failed · 1 left' "$OUT" \
  'draining and failed are shown'

touch -t 202001010000 "$ledger"
line "$repo"
assert_eq '' "$OUT" 'a ledger untouched for over a week is not shown'
touch "$ledger"

wt=$(cd "$repo" && "$WT" "$repo/spec.md" feat/x start 7)
line "$wt"
assert_contains 'feat/x · 1/7 merged' "$OUT" 'a session inside a phase worktree finds the run in the main checkout'

log 'RUN COMPLETE — phases 1–7 of spec.md'
line "$repo"
assert_eq '' "$OUT" 'a finished run is not shown'

finish
