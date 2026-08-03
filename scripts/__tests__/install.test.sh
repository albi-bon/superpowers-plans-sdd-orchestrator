#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

# `pwd -P` to match what install.sh resolves the checkout to, so the two agree
# even when the checkout sits behind a symlink.
ROOT=$(cd "$here/../.." && pwd -P)
INSTALL="$ROOT/install.sh"

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

# run_install SKILLS_DIR — run the installer against a throwaway skills dir.
run_install() {
  set +e
  OUT=$(CLAUDE_SKILLS_DIR="$1" "$INSTALL" 2>&1)
  RC=$?
  set -e
}

dest="$tmp/skills/orchestrating-phased-specs"

run_install "$tmp/skills"
assert_rc 0 'fresh install: exits 0'
assert_eq 'yes' "$([ -L "$dest" ] && echo yes || echo no)" 'creates a symlink'
assert_eq "$ROOT" "$(cd "$dest" && pwd -P)" 'the symlink resolves to this checkout'
assert_eq 'yes' "$([ -f "$dest/SKILL.md" ] && echo yes || echo no)" 'SKILL.md is reachable through it'

# Idempotent: re-running against an identical symlink is a no-op success.
run_install "$tmp/skills"
assert_rc 0 'second install: exits 0'
assert_contains 'already installed' "$OUT" 'second install: says it was already installed'

# A symlink pointing somewhere else is replaced.
rm "$dest"
ln -s "$tmp" "$dest"
run_install "$tmp/skills"
assert_rc 0 'stale symlink: exits 0'
assert_eq "$ROOT" "$(cd "$dest" && pwd -P)" 'stale symlink is repointed at this checkout'

# A real directory in the way is never deleted.
rm "$dest"
mkdir -p "$dest"
printf 'someone else\n' > "$dest/keep.txt"
run_install "$tmp/skills"
assert_rc 1 'real directory in the way: exits 1'
assert_contains 'not a symlink' "$OUT" 'real directory: message names the problem'
assert_eq 'yes' "$([ -f "$dest/keep.txt" ] && echo yes || echo no)" 'real directory: contents untouched'

finish
