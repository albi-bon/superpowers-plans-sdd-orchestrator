#!/usr/bin/env bash
# phase-batch, phase-land, phase-push and phase-pr together: phases built side
# by side are merged onto a batch branch, one conflict is resolved, the batch
# lands only once the ledger shows it verified, base is pushed, and a pull
# request is opened through a stand-in gh.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"
WT="$here/../phase-worktree"
BATCH="$here/../phase-batch"
LAND="$here/../phase-land"
PUSH="$here/../phase-push"
PR="$here/../phase-pr"
STATE="$here/../phase-state"
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
printf '# Example — Design Spec\n## Phase 1 — One\n## Phase 2 — Two\n## Phase 3 — Three\n## Phase 4 — Four\n## Phase 5 — Five\n' > "$repo/spec.md"
printf 'shared\n' > "$repo/shared.txt"
git -C "$repo" add spec.md shared.txt
git -C "$repo" commit -qm initial
rundir="$repo/.superpowers/phase-parallel/spec"
mkdir -p "$rundir"
ledger="$rundir/run.md"
printf '# Phase run — spec: x\n# base: feat/x  requested: 1-5\n\n' > "$ledger"
log() { printf '%s\n' "$@" >> "$ledger"; }
commit_in() { # commit_in DIR FILE CONTENT
  printf '%s\n' "$3" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -qm "$2"
}
iwt="$repo/.worktrees/integration"

for n in 1 2 3 4; do run_in "$WT" "$repo/spec.md" feat/x start "$n"; eval "wt$n=\$OUT"; done
# shellcheck disable=SC2154 # wt1..wt4 are set by the eval above
{
  commit_in "$wt1" one.txt one
  commit_in "$wt2" shared.txt 'phase two'
  commit_in "$wt3" shared.txt 'phase three'
  commit_in "$wt4" shared.txt 'phase four'
}
v1=$(git -C "$wt1" rev-parse --short HEAD)
v2=$(git -C "$wt2" rev-parse --short HEAD)
v3=$(git -C "$wt3" rev-parse --short HEAD)
v4=$(git -C "$wt4" rev-parse --short HEAD)

# --- phase-push ---------------------------------------------------------------------

run_in "$PUSH" "$repo/spec.md" feat/x 1
assert_rc 0 'push 1: exits 0'
assert_eq "push: phase-1-one at $v1" "$OUT" 'push 1: prints what it pushed'
assert_eq "$(git -C "$repo" rev-parse "$v1")" "$(git -C "$origin" rev-parse refs/heads/phase-1-one)" 'push 1: origin holds the phase branch'
assert_contains "push: phase-1-one at $v1" "$(cat "$ledger")" 'push 1: recorded'
git -C "$repo" remote rename origin away
run_in "$PUSH" "$repo/spec.md" feat/x 2
assert_rc 0 'push without origin: still exits 0, a push is a backup'
assert_contains 'push: phase-2-two failed — ' "$OUT" 'push without origin: the failure is printed'
assert_contains 'push: phase-2-two failed — ' "$(cat "$ledger")" 'push without origin: the failure is recorded'
git -C "$repo" remote rename away origin
run_in "$PUSH" "$repo/spec.md" feat/x 5
assert_rc 18 'push of a phase with no branch: refused'

# --- refusals before a batch opens ----------------------------------------------------

run_in "$BATCH" "$repo/spec.md" feat/x open
assert_rc 2 'open with no phases: usage error'
run_in "$BATCH" "$repo/spec.md" feat/x open 1
assert_rc 2 'open with no sha: usage error'
run_in "$BATCH" "$repo/spec.md" feat/x open "1@$v2"
assert_rc 19 'open: a phase branch not at its queued sha is refused'
assert_contains 'phase 1' "$OUT" 'open: names the phase'
run_in "$BATCH" "$repo/spec.md" feat/x build 1
assert_rc 18 'build of a batch that is not open: refused'
assert_eq '' "$(grep '^batch' "$ledger")" 'refusals: nothing recorded'

# --- batch 1: three phases, one conflict -----------------------------------------------

run_in "$BATCH" "$repo/spec.md" feat/x open "1@$v1" "2@$v2" "3@$v3"
assert_rc 0 'open: exits 0 on a conflict'
assert_eq 'conflict 1 3 1,2' "$OUT" 'open: phase 3 conflicts with the phases merged before it'
assert_contains "batch 1: opened — phases 1@$v1 2@$v2 3@$v3" "$(cat "$ledger")" 'open: recorded with each phase sha'
assert_eq 'phase-batch-1' "$(git -C "$iwt" branch --show-current)" 'open: the integration worktree is on the batch branch'
assert_eq 'feat/x' "$(git -C "$repo" branch --show-current)" 'open: the main checkout stays on base'
assert_contains 'phase 1: batched — batch 1, clean merge' "$(cat "$ledger")" 'phase 1 merged cleanly'
assert_contains 'phase 3: batched — batch 1, conflict in 1 files' "$(cat "$ledger")" 'phase 3 conflict recorded'
assert_eq 'merge: phase 2 — Two' "$(git -C "$iwt" log -1 --format=%s HEAD)" 'each phase is merged with the subject base uses'
assert_contains 'shared.txt' "$(cat "$rundir/phase-3-conflicts.md")" 'conflicts file lists the path'
assert_contains '- phase 2' "$(cat "$rundir/phase-3-conflicts.md")" 'conflicts file lists the phases already in the batch'

run_in "$BATCH" "$repo/spec.md" feat/x open "4@$v4"
assert_rc 17 'a second batch while one is open: refused'
run_in "$BATCH" "$repo/spec.md" feat/x build 1
assert_eq 'conflict 1 3 1,2' "$OUT" 'build mid-merge: the same conflict again, idempotent'
assert_eq '1' "$(grep -c '^phase 3: batched' "$ledger")" 'build mid-merge: no second ledger line'
run_in "$WT" "$repo/spec.md" feat/x check
assert_rc 0 'check: the integration worktree mid-merge for an open batch is not refused'
run_in "$BATCH" "$repo/spec.md" feat/x final
assert_rc 17 'final while a batch is open: refused'

printf 'phase two\nphase three\n' > "$iwt/shared.txt"
git -C "$iwt" add shared.txt
git -C "$iwt" commit -q --no-edit
log "phase 3: resolved $(git -C "$iwt" rev-parse --short HEAD)"
run_in "$BATCH" "$repo/spec.md" feat/x build 1
b1=$(git -C "$iwt" rev-parse --short HEAD)
assert_rc 0 'build after the resolution: exits 0'
assert_eq "built 1 $b1" "$OUT" 'build: every phase in, built at the batch tip'
run_in "$BATCH" "$repo/spec.md" feat/x build 1
assert_eq "built 1 $b1" "$OUT" 'build again: idempotent'
assert_eq '1' "$(grep -c '^batch 1: built' "$ledger")" 'build again: one ledger line'

# --- landing batch 1 ---------------------------------------------------------------------

run_in "$LAND" "$repo/spec.md" feat/x 1 "$b1"
assert_rc 22 'land: built alone is not landable'
log 'batch 1: verified PASS — full suites all — deadbee'
run_in "$LAND" "$repo/spec.md" feat/x 1 "$b1"
assert_rc 22 'land: a pass recorded for another commit is refused'
log "batch 1: verified FAIL — not pinned — flaky"
run_in "$LAND" "$repo/spec.md" feat/x 1 "$b1"
assert_rc 22 'land: a failed batch is refused'
grep -v '^batch 1: verified' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"
log "batch 1: verified PASS — full suites all — $b1"
printf 'dirty\n' > "$repo/dirty.txt"
run_in "$LAND" "$repo/spec.md" feat/x 1 "$b1"
assert_rc 11 'land: dirty main checkout refused'
rm "$repo/dirty.txt"
run_in "$LAND" "$repo/spec.md" feat/x 1 "$v1"
assert_rc 19 'land: the batch branch not at the given sha is refused'

run_in "$LAND" "$repo/spec.md" feat/x 1 "$b1"
assert_rc 0 'land 1: exits 0'
assert_contains 'batch 1 landed on feat/x' "$OUT" 'land 1: says what landed'
assert_eq "$(git -C "$repo" rev-parse "$b1")" "$(git -C "$repo" rev-parse HEAD)" 'land 1: base is exactly the verified commit'
assert_eq "$(printf 'merge: phase 3 — Three\nmerge: phase 2 — Two\nmerge: phase 1 — One\ninitial')" \
  "$(git -C "$repo" log --first-parent --format=%s)" 'land 1: base history reads one merge per phase'
for n in 1 2 3; do
  assert_contains "phase $n: merged to base (" "$(cat "$ledger")" "land 1: phase $n recorded as merged"
  assert_contains "phase $n: metrics — source +" "$(cat "$ledger")" "land 1: phase $n metrics recorded"
done
assert_eq 'no' "$([ -d "$wt1" ] && echo yes || echo no)" 'land 1: phase worktrees removed'
assert_eq 'yes' "$([ -d "$iwt" ] && echo yes || echo no)" 'land 1: the integration worktree stays for the next batch'
assert_contains "batch 1: landed (" "$(cat "$ledger")" 'land 1: batch recorded as landed'
assert_contains 'push: feat/x at ' "$(cat "$ledger")" 'land 1: base pushed'
assert_eq "$(git -C "$repo" rev-parse HEAD)" "$(git -C "$origin" rev-parse refs/heads/feat/x)" 'land 1: origin holds the landed base'
run_in "$STATE" "$repo/spec.md"
assert_contains "$(printf 'batch\t1\tlanded')" "$OUT" 'phase-state: batch 1 landed'
run_in "$LAND" "$repo/spec.md" feat/x 1 "$b1"
assert_rc 17 'land 1 again: refused'

# --- batch 2: the resolver gives up on one phase -----------------------------------------

run_in "$WT" "$repo/spec.md" feat/x start 5; wt5=$OUT
commit_in "$wt5" five.txt five
v5=$(git -C "$wt5" rev-parse --short HEAD)
run_in "$BATCH" "$repo/spec.md" feat/x open "4@$v4" "5@$v5"
assert_eq 'conflict 2 4 1,2,3' "$OUT" 'open 2: phase 4 forked before batch 1 landed, so the landed phases are the other side'
assert_eq 'no' "$(git -C "$repo" show-ref --verify --quiet refs/heads/phase-batch-1 && echo yes || echo no)" \
  'open 2: the landed batch branch is deleted'
git -C "$iwt" merge --abort
log 'phase 4: unresolved — both sides rewrite shared.txt'
run_in "$BATCH" "$repo/spec.md" feat/x build 2
b2=$(git -C "$iwt" rev-parse --short HEAD)
assert_eq "built 2 $b2" "$OUT" 'build 2: carries on without the unresolved phase'
assert_eq 'merge: phase 5 — Five' "$(git -C "$iwt" log -1 --format=%s)" 'build 2: only phase 5 merged'
run_in "$STATE" "$repo/spec.md"
assert_contains "$(printf '4\tfailing\t%s' "$v4")" "$OUT" 'phase-state: the unresolved phase is failing'

git -C "$repo" commit -q --allow-empty -m 'stray commit on base'
log "batch 2: verified PASS — full suites partial — $b2"
run_in "$LAND" "$repo/spec.md" feat/x 2 "$b2"
assert_rc 21 'land: base moved under the batch is refused'
git -C "$repo" reset -q --hard HEAD~1
run_in "$LAND" "$repo/spec.md" feat/x 2 "$b2"
assert_rc 0 'land 2: exits 0'
assert_eq '1' "$(grep -c '^phase 5: merged to base' "$ledger")" 'land 2: phase 5 merged'
assert_eq '' "$(grep '^phase 4: merged' "$ledger")" 'land 2: the unresolved phase is not'

# --- an empty batch, and the final check ----------------------------------------------------

run_in "$BATCH" "$repo/spec.md" feat/x open "4@$v4"
assert_eq 'conflict 3 4 1,2,3,5' "$OUT" 'open 3: phase 4 conflicts again'
git -C "$iwt" merge --abort
log 'phase 4: unresolved — still clashes'
run_in "$BATCH" "$repo/spec.md" feat/x build 3
assert_eq 'empty 3' "$OUT" 'every phase left the batch: empty'
assert_contains 'batch 3: empty' "$(cat "$ledger")" 'empty recorded'
run_in "$BATCH" "$repo/spec.md" feat/x final
assert_rc 0 'final: exits 0 once no batch is open'
assert_eq "final $(git -C "$repo" rev-parse --short HEAD)" "$OUT" 'final: the integration worktree is at the base tip'
assert_eq '' "$(git -C "$iwt" branch --show-current)" 'final: detached, not on a branch'

# --- a landing interrupted after the fast-forward ---------------------------------------------

git -C "$wt4" merge -q feat/x >/dev/null 2>&1 || true
printf 'phase four\n' > "$wt4/shared.txt"
git -C "$wt4" add shared.txt
git -C "$wt4" commit -q --no-edit
r4=$(git -C "$wt4" rev-parse --short HEAD)
log 'phase 4: rescue — started (attempt 2/2)' "phase 4: executed — repaired, HEAD $r4"
printf 'left by a verifier\n' > "$iwt/spec.md"
run_in "$BATCH" "$repo/spec.md" feat/x open "4@$r4"
b4=$(git -C "$iwt" rev-parse --short HEAD)
assert_eq "built 4 $b4" "$OUT" 'open: tracked changes a verifier left in the integration worktree are discarded'
log "batch 4: verified PASS — full suites all — $b4"
git -C "$repo" merge -q --ff-only phase-batch-4
run_in "$LAND" "$repo/spec.md" feat/x 4 "$b4"
assert_rc 0 'land after an interrupted fast-forward: exits 0'
assert_eq '1' "$(grep -c '^phase 4: merged to base' "$ledger")" 'land re-run: the phase is recorded as merged'
assert_contains 'batch 4: landed (' "$(cat "$ledger")" 'land re-run: the batch is recorded as landed'
assert_eq "$(git -C "$repo" rev-parse HEAD)" "$(git -C "$origin" rev-parse refs/heads/feat/x)" 'land re-run: base pushed'
run_in "$STATE" "$repo/spec.md"
assert_contains "$(printf '4\tmerged')" "$OUT" 'land re-run: phase 4 is merged, not stuck'

# --- a conflict with nothing but base on the other side ---------------------------------------

printf '## Phase 6 — Six\n' >> "$repo/spec.md"
git -C "$repo" commit -qam 'owner: add phase 6'
run_in "$WT" "$repo/spec.md" feat/x start 6; wt6=$OUT
commit_in "$wt6" six.txt six
v6=$(git -C "$wt6" rev-parse --short HEAD)
commit_in "$repo" six.txt 'owner six'
run_in "$BATCH" "$repo/spec.md" feat/x open "6@$v6"
assert_rc 0 'open: a conflict with an owner commit on base exits 0'
assert_eq 'conflict 5 6 -' "$OUT" 'open: no phase on the other side prints -'
grep -v '^phase 6: batched' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"
run_in "$BATCH" "$repo/spec.md" feat/x build 5
assert_eq 'conflict 5 6 -' "$OUT" 'build: a merge in progress the ledger never recorded is aborted and redone'
assert_eq '1' "$(grep -c '^phase 6: batched — batch 5, conflict' "$ledger")" 'build: the redone conflict is recorded once'

# --- phase-pr, with a stand-in gh -------------------------------------------------------------

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/gh.log"
case "\$1 \$2" in
  'pr list') [ -f "$tmp/pr-url" ] && cat "$tmp/pr-url"; exit 0 ;;
  'pr create') echo 'https://example.test/pr/7' > "$tmp/pr-url"; echo 'https://example.test/pr/7' ;;
  'repo view') echo main ;;
esac
EOF
chmod +x "$tmp/bin/gh"
printf 'RUN COMPLETE\n' > "$rundir/report.md"
run_in env PATH="$tmp/bin:$PATH" "$PR" "$repo/spec.md" feat/x - "$rundir/missing.md"
assert_rc 18 'pr: a missing body file is refused'
run_in env PATH="$tmp/bin:$PATH" "$PR" "$repo/spec.md" feat/x feat/x "$rundir/report.md"
assert_rc 2 'pr: a target equal to base is refused'
run_in env PATH="$tmp/bin:$PATH" "$PR" "$repo/spec.md" feat/x - "$rundir/report.md" draft
assert_rc 0 'pr: exits 0'
assert_eq 'pr https://example.test/pr/7' "$(printf '%s\n' "$OUT" | tail -n 1)" 'pr: prints the url'
assert_contains '--base main --head feat/x --title Example — Design Spec — phases 1-5' "$(cat "$tmp/gh.log")" \
  "pr: targets origin's default branch, titled from the document and range"
assert_contains '--draft' "$(cat "$tmp/gh.log")" 'pr: draft when asked'
assert_contains 'run: PR https://example.test/pr/7' "$(cat "$ledger")" 'pr: recorded'
run_in env PATH="$tmp/bin:$PATH" "$PR" "$repo/spec.md" feat/x - "$rundir/report.md"
assert_eq 'pr https://example.test/pr/7' "$(printf '%s\n' "$OUT" | tail -n 1)" 'pr again: the open one is reused'
assert_eq '1' "$(grep -c '^pr create' "$tmp/gh.log")" 'pr again: no second pull request'
git -C "$repo" remote rename origin away
run_in env PATH="$tmp/bin:$PATH" "$PR" "$repo/spec.md" feat/x main "$rundir/report.md"
assert_rc 23 'pr: refused when base cannot be pushed'

finish
