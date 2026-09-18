#!/usr/bin/env bash
# Symlink this checkout into the skills directory, so edits here are live and
# the skill stays git-tracked in one place.
#
# CLAUDE_SKILLS_DIR and CODEX_SKILLS_DIR override their respective destinations.
# With no argument, preserve the original Claude Code installation behavior.
#
# `pwd -P` throughout, never a bare `pwd`: bash's `cd` keeps the logical path it
# was given, so `cd "$dest" && pwd` on an existing symlink prints the symlink's
# own path rather than what it points at — and the already-installed check would
# then never match.
#
# Usage: ./install.sh [claude|codex|all]
set -euo pipefail

target=${1:-claude}
if [ "$#" -gt 1 ]; then
  echo "usage: $0 [claude|codex|all]" >&2
  exit 2
fi
case "$target" in
  claude | codex | all) ;;
  *) echo "usage: $0 [claude|codex|all]" >&2; exit 2 ;;
esac

src=$(cd "$(dirname "$0")" && pwd -P)

if [ ! -f "$src/SKILL.md" ]; then
  echo "no SKILL.md in $src — refusing to install an incomplete skill" >&2
  exit 1
fi

install_to() {
  local skills_dir=$1 dest current
  dest="$skills_dir/orchestrating-phased-specs"
  mkdir -p "$skills_dir"

  if [ -L "$dest" ]; then
    current=$(cd "$dest" 2>/dev/null && pwd -P) || current=""
    if [ "$current" = "$src" ]; then
      echo "already installed: $dest -> $src"
      return 0
    fi
    rm "$dest"
  elif [ -e "$dest" ]; then
    echo "$dest exists and is not a symlink — refusing to replace it" >&2
    echo "move it aside yourself, then re-run this installer" >&2
    return 1
  fi

  ln -s "$src" "$dest"
  echo "installed: $dest -> $src"
}

case "$target" in
  claude) install_to "${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}" ;;
  codex) install_to "${CODEX_SKILLS_DIR:-$HOME/.agents/skills}" ;;
  all)
    install_to "${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
    install_to "${CODEX_SKILLS_DIR:-$HOME/.agents/skills}"
    ;;
esac
