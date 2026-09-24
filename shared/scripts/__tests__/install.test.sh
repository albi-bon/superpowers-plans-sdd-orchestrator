#!/usr/bin/env bash
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=assert.sh
. "$here/assert.sh"

# `pwd -P` to match what install.sh resolves the checkout to, so the two agree
# even when the checkout sits behind a symlink.
ROOT=$(cd "$here/../../.." && pwd -P)
INSTALL="$ROOT/install.sh"
ORCH="$ROOT/skills/orchestrating-phased-specs"
BUILD="$ROOT/skills/building-phased-specs"
EXEC="$ROOT/skills/executing-phased-specs"

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
bdest="$tmp/skills/building-phased-specs"
edest="$tmp/skills/executing-phased-specs"

run_install "$tmp/skills"
assert_rc 0 'fresh install: exits 0'
assert_eq 'yes' "$([ -L "$dest" ] && echo yes || echo no)" 'creates a symlink'
assert_eq "$ORCH" "$(cd "$dest" && pwd -P)" 'the symlink resolves to the skill directory'
assert_eq 'yes' "$([ -f "$dest/SKILL.md" ] && echo yes || echo no)" 'SKILL.md is reachable through it'
assert_eq "$BUILD" "$(cd "$bdest" && pwd -P)" 'the default installs building-phased-specs too'
assert_eq 'yes' "$([ -f "$bdest/SKILL.md" ] && echo yes || echo no)" 'its SKILL.md is reachable'
assert_eq "$EXEC" "$(cd "$edest" && pwd -P)" 'the default installs executing-phased-specs too'
assert_eq 'yes' "$([ -f "$edest/SKILL.md" ] && echo yes || echo no)" 'its SKILL.md is reachable'

# The wrappers reach the shared scripts through the installed symlink.
spec_repo=$(cd "$(mktemp -d)" && pwd -P)
git -C "$spec_repo" init -q
printf '## Phase 1 — One\n' > "$spec_repo/spec.md"
assert_eq "$spec_repo/.superpowers/phase-builder/spec" \
  "$(cd "$spec_repo" && "$bdest/scripts/phase-run-dir" "$spec_repo/spec.md")" \
  'building wrapper, through the install link, uses the phase-builder namespace'
assert_eq "$spec_repo/.superpowers/phase-orchestrator/spec" \
  "$(cd "$spec_repo" && "$dest/scripts/phase-run-dir" "$spec_repo/spec.md")" \
  'orchestrating wrapper, through the install link, keeps the phase-orchestrator path'
assert_eq "$spec_repo/.superpowers/phase-executor/spec" \
  "$(cd "$spec_repo" && "$edest/scripts/phase-run-dir" "$spec_repo/spec.md")" \
  'executing wrapper, through the install link, uses the phase-executor namespace'
assert_eq "$(printf '1\tOne\tone')" \
  "$(cd "$spec_repo" && "$bdest/scripts/parse-phases" "$spec_repo/spec.md" all)" \
  'parse-phases wrapper passes arguments through'
rm -rf "$spec_repo"

# Idempotent: re-running against an identical symlink is a no-op success.
run_install "$tmp/skills"
assert_rc 0 'second install: exits 0'
assert_contains 'already installed' "$OUT" 'second install: says it was already installed'

# A symlink pointing somewhere else is replaced.
rm "$dest"
ln -s "$tmp" "$dest"
run_install "$tmp/skills"
assert_rc 0 'stale symlink: exits 0'
assert_eq "$ORCH" "$(cd "$dest" && pwd -P)" 'stale symlink is repointed at the skill directory'

# The pre-restructure install linked the repository root under this name.
rm "$dest"
ln -s "$ROOT" "$dest"
run_install "$tmp/skills"
assert_rc 0 'root-level install: exits 0'
assert_eq "$ORCH" "$(cd "$dest" && pwd -P)" 'root-level install is repointed at skills/orchestrating-phased-specs'

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
assert_eq "$ORCH" "$(cd "$tmp/codex skills/orchestrating-phased-specs" && pwd -P)" 'Codex link resolves to the skill'
assert_eq 'no' "$([ -e "$tmp/claude skills" ] && echo yes || echo no)" 'Codex install does not install Claude'
run_target all
assert_rc 0 'both hosts: succeeds'
assert_eq "$ORCH" "$(cd "$tmp/claude skills/orchestrating-phased-specs" && pwd -P)" 'combined install creates Claude link'
run_target all
assert_rc 0 'both hosts: idempotent'

# Broken links should be replaceable too (cd into one fails).
rm "$tmp/codex skills/orchestrating-phased-specs"
ln -s "$tmp/does-not-exist" "$tmp/codex skills/orchestrating-phased-specs"
run_target codex
assert_rc 0 'dangling link: repaired'
assert_eq "$ORCH" "$(cd "$tmp/codex skills/orchestrating-phased-specs" && pwd -P)" 'dangling link now reaches the skill'
rm "$tmp/codex skills/orchestrating-phased-specs"
mkdir "$tmp/codex skills/orchestrating-phased-specs"
printf 'keep\n' > "$tmp/codex skills/orchestrating-phased-specs/keep.txt"
run_target codex
assert_rc 1 'Codex real directory: refused'
assert_eq 'keep' "$(cat "$tmp/codex skills/orchestrating-phased-specs/keep.txt")" 'Codex directory preserved'
run_target unknown
assert_rc 2 'unknown target: usage error'
run_target codex extra
assert_rc 2 'unknown skill selector: usage error'
run_target codex building extra
assert_rc 2 'extra argument: usage error'

# Skill selection installs only the named skill.
sel="$tmp/selected skills"
set +e
OUT=$(CLAUDE_SKILLS_DIR="$sel" "$INSTALL" claude building 2>&1)
RC=$?
set -e
assert_rc 0 'single-skill install: succeeds'
assert_eq "$BUILD" "$(cd "$sel/building-phased-specs" && pwd -P)" 'single-skill install links the named skill'
assert_eq 'no' "$([ -e "$sel/orchestrating-phased-specs" ] && echo yes || echo no)" 'single-skill install leaves the other alone'

sel2="$tmp/executing only"
set +e
OUT=$(CLAUDE_SKILLS_DIR="$sel2" "$INSTALL" claude executing 2>&1)
RC=$?
set -e
assert_rc 0 'executing-only install: succeeds'
assert_eq "$EXEC" "$(cd "$sel2/executing-phased-specs" && pwd -P)" 'executing-only install links the named skill'
assert_eq 'no' "$([ -e "$sel2/orchestrating-phased-specs" ] && echo yes || echo no)" 'executing-only install leaves the others alone'

finish
