#!/usr/bin/env bash
# Symlink this checkout into the skills directory, so edits here are live and
# the skill stays git-tracked in one place.
#
# CLAUDE_SKILLS_DIR overrides the destination. That override exists so the test
# suite can install into a throwaway directory instead of a real one.
#
# `pwd -P` throughout, never a bare `pwd`: bash's `cd` keeps the logical path it
# was given, so `cd "$dest" && pwd` on an existing symlink prints the symlink's
# own path rather than what it points at — and the already-installed check would
# then never match.
#
# Usage: ./install.sh
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd -P)

if [ ! -f "$src/SKILL.md" ]; then
  echo "no SKILL.md in $src — refusing to install an incomplete skill" >&2
  exit 1
fi

skills_dir=${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}
dest="$skills_dir/orchestrating-phased-specs"

mkdir -p "$skills_dir"

if [ -L "$dest" ]; then
  current=$(cd "$dest" && pwd -P)
  if [ "$current" = "$src" ]; then
    echo "already installed: $dest -> $src"
    exit 0
  fi
  rm "$dest"
elif [ -e "$dest" ]; then
  echo "$dest exists and is not a symlink — refusing to replace it" >&2
  echo "move it aside yourself, then re-run this installer" >&2
  exit 1
fi

ln -s "$src" "$dest"
echo "installed: $dest -> $src"
