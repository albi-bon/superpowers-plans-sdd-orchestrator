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

# Host selection is independent; no installation touches real user directories.
run_target() {
  set +e
  OUT=$(CLAUDE_SKILLS_DIR="$tmp/claude skills" CODEX_SKILLS_DIR="$tmp/codex skills" "$INSTALL" "$@" 2>&1)
  RC=$?
  set -e
}
run_target codex
assert_rc 0 'Codex install: succeeds'
assert_eq "$ROOT" "$(cd "$tmp/codex skills/orchestrating-phased-specs" && pwd -P)" 'Codex link resolves to checkout'
assert_eq 'no' "$([ -e "$tmp/claude skills" ] && echo yes || echo no)" 'Codex install does not install Claude'
run_target all
assert_rc 0 'both hosts: succeeds'
assert_eq "$ROOT" "$(cd "$tmp/claude skills/orchestrating-phased-specs" && pwd -P)" 'combined install creates Claude link'
run_target all
assert_rc 0 'both hosts: idempotent'

# Broken links should be replaceable too (cd into one fails).
rm "$tmp/codex skills/orchestrating-phased-specs"
ln -s "$tmp/does-not-exist" "$tmp/codex skills/orchestrating-phased-specs"
run_target codex
assert_rc 0 'dangling link: repaired'
assert_eq "$ROOT" "$(cd "$tmp/codex skills/orchestrating-phased-specs" && pwd -P)" 'dangling link now reaches checkout'
rm "$tmp/codex skills/orchestrating-phased-specs"
mkdir "$tmp/codex skills/orchestrating-phased-specs"
printf 'keep\n' > "$tmp/codex skills/orchestrating-phased-specs/keep.txt"
run_target codex
assert_rc 1 'Codex real directory: refused'
assert_eq 'keep' "$(cat "$tmp/codex skills/orchestrating-phased-specs/keep.txt")" 'Codex directory preserved'
run_target unknown
assert_rc 2 'unknown target: usage error'
run_target codex extra
assert_rc 2 'extra argument: usage error'

finish
