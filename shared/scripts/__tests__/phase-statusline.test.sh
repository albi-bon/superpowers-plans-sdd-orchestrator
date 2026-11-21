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
printf '# Phase run — spec: %s\n# base: feat/x  requested: 1-7\n# layout: run-scoped\n\n' "$repo/spec.md" > "$ledger"
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

# A run's ledger names base's copy, in the run's base worktree; the owner can
# move the main checkout to a branch without the spec.
git -C "$repo" worktree add -q "$repo/.worktrees/spec/base" -b feat/base-copy feat/x
sed -i.bak "1s|.*|# Phase run — spec: $repo/.worktrees/spec/base/spec.md|" "$ledger" && rm "$ledger.bak"
git -C "$repo" rm -q spec.md
git -C "$repo" commit -qm 'the main checkout moves on'
line "$repo"
assert_contains 'feat/x · 1/7 merged' "$OUT" 'the main checkout lost the spec: the run is found through the base worktree'
line "$repo/.worktrees/spec/base"
assert_contains 'feat/x · 1/7 merged' "$OUT" 'a session inside the base worktree finds the run'

# A second run in the same repository, written to more recently. A session in
# the main checkout shows the latest; one inside a run's worktrees shows that
# run.
git -C "$repo" show feat/base-copy:spec.md > "$tmp/other.md"
other="$repo/.superpowers/phase-parallel/other"
mkdir -p "$other"
printf '# Phase run — spec: %s\n# base: feat/y  requested: 1-2\n# layout: run-scoped\n\n' "$tmp/other.md" > "$other/run.md"
printf 'phase 1: started — branch phase-1-a@other\n' >> "$other/run.md"
touch -t "$(date -v-2M +%Y%m%d%H%M 2>/dev/null || date -d '2 minutes ago' +%Y%m%d%H%M)" "$ledger"
line "$repo"
assert_eq 'feat/y · 0/2 merged · 1 building · 1 left · +1 runs' "$OUT" 'two runs: the main checkout shows the latest'
line "$repo/.worktrees/spec/base"
assert_contains 'feat/x · 1/7 merged' "$OUT" "two runs: a session in one run's base worktree shows that run"
assert_contains '+1 runs' "$OUT" 'two runs: and counts the other'
line "$wt"
assert_contains 'feat/x · 1/7 merged' "$OUT" "two runs: a session in one run's phase worktree shows that run"
rm -rf "$other"

log 'RUN COMPLETE — phases 1–7 of spec.md'
line "$repo"
assert_eq '' "$OUT" 'a finished run is not shown'

# --- a legacy ledger ----------------------------------------------------------------
# A ledger from before runs were named, written when base lived in the main
# checkout, names the main checkout's copy: once that is gone, the run is read
# from the legacy base worktree, .worktrees/base.

git -C "$repo" worktree add -q "$repo/.worktrees/base" -b feat/legacy-copy feat/base-copy
printf '# Phase run — spec: %s\n# base: feat/x  requested: 1-2\n\nphase 1: started — branch phase-1-a\n' "$repo/spec.md" > "$ledger"
line "$repo"
assert_eq 'feat/x · 0/2 merged · 1 building · 1 left' "$OUT" 'legacy ledger: read through .worktrees/base'

# --- the QA pass --------------------------------------------------------------------

printf '# Phase run — spec: %s\n# base: feat/x  requested: 1-2\n# layout: run-scoped\n\n' "$repo/.worktrees/spec/base/spec.md" > "$ledger"
log 'run: qa scope — all' 'phase 1: merged to base (aaa1)' 'phase 2: merged to base (aaa1)' 'batch 1: landed (aaa1)'
line "$repo"
assert_eq 'feat/x · 2/2 merged' "$OUT" 'no QA segment before the pass opens'
log 'qa: opened — phase-qa@spec at aaa1'
line "$repo"
assert_eq 'feat/x · 2/2 merged · qa planning' "$OUT" 'a QA stage without counts'
log 'qa: flows defined — 3 found, selected 1,2,3, not walkable -, parallel yes' 'qa flow 1: walked — 0 findings'
line "$repo"
assert_eq 'feat/x · 2/2 merged · qa walking 1/3' "$OUT" 'a QA stage with progress'

# A phase-qa that fails must never take the status line down with it. The
# status line finds its siblings beside itself, so a copy gets a stand-in.
fake="$tmp/fake-scripts"
mkdir -p "$fake"
cp "$here"/../parse-phases "$here"/../phase-state "$here"/../phase-run-dir "$here"/../phase-statusline "$fake"/
printf '#!/usr/bin/env bash\necho boom\necho boom >&2\nexit 3\n' > "$fake/phase-qa"
chmod +x "$fake/phase-qa"
set +e
OUT=$(json "$repo" | "$fake/phase-statusline" 2>&1)
RC=$?
set -e
assert_rc 0 'a failing phase-qa never fails the status line'
assert_eq 'feat/x · 2/2 merged' "$OUT" 'a failing phase-qa leaves the QA segment out'

log 'qa: done — abandoned, base moved under the pass'
line "$repo"
assert_eq 'feat/x · 2/2 merged' "$OUT" 'no QA segment once the pass is done'

finish
