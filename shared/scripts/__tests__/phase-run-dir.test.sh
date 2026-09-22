#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

RUNDIR="$here/../phase-run-dir"

# run_in DIR COMMAND [ARGS...] — like run_cmd, but with DIR as the working
# directory. A subshell rather than `env -C`, which BSD env on macOS does not
# support; the subshell form works everywhere.
run_in() {
  dir=$1
  shift
  set +e
  OUT=$(cd "$dir" && "$@" 2>&1)
  RC=$?
  set -e
}

# A throwaway git repository, so the test never touches a real one.
# The `cd … && pwd -P` resolves symlinks up front: on macOS `mktemp -d` returns
# a path under /var/folders/… which is a symlink to /private/var/folders/…, and
# phase-run-dir builds its output from `git rev-parse --show-toplevel`, which is
# already resolved. Without this the path assertions below compare a symlinked
# path against a resolved one and fail for a reason that has nothing to do with
# the behaviour under test. `pwd` alone is not enough: bash's `cd` keeps the
# logical path it was given, so only the -P flag resolves it.
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q
printf '# spec\n' > "$tmp/my-feature-design.md"

run_in "$tmp" "$RUNDIR" "$tmp/my-feature-design.md"
assert_rc 0 'creates the run directory: exits 0'
assert_eq "$tmp/.superpowers/phase-orchestrator/my-feature-design" "$OUT" \
  'prints the run directory path, basename without .md'
assert_eq 'yes' "$([ -d "$tmp/.superpowers/phase-orchestrator/my-feature-design" ] && echo yes || echo no)" \
  'the directory exists on disk'
assert_eq '*' "$(cat "$tmp/.superpowers/phase-orchestrator/.gitignore")" \
  'the parent carries a self-ignoring .gitignore'
assert_eq '' "$(git -C "$tmp" status --porcelain | grep superpowers || true)" \
  'nothing under .superpowers shows in git status'

# Idempotent: a second call must succeed and print the same path.
first=$OUT
run_in "$tmp" "$RUNDIR" "$tmp/my-feature-design.md"
assert_rc 0 'second call: exits 0'
assert_eq "$first" "$OUT" 'second call prints the same path'

# Two different specs get two different directories.
printf '# other\n' > "$tmp/other-design.md"
run_in "$tmp" "$RUNDIR" "$tmp/other-design.md"
assert_rc 0 'second spec: exits 0'
assert_eq "$tmp/.superpowers/phase-orchestrator/other-design" "$OUT" \
  'a different spec gets its own directory'

# Refusals.
run_in "$tmp" "$RUNDIR" "$tmp/nope.md"
assert_rc 2 'missing design document: exits 2'
assert_contains 'no such design document' "$OUT" 'missing document: message names the problem'

run_in "$tmp" "$RUNDIR"
assert_rc 2 'no arguments: exits 2'
assert_contains 'usage:' "$OUT" 'no arguments: prints usage'

outside=$(mktemp -d)
printf '# spec\n' > "$outside/loose-design.md"
run_in "$outside" "$RUNDIR" "$outside/loose-design.md"
assert_rc 2 'outside a git repository: exits 2'
assert_contains 'not inside a git repository' "$OUT" 'outside a repo: message names the problem'
rm -rf "$outside"

finish
