#!/usr/bin/env bash
# Symlink this checkout's skills into the skills directory, so edits here are
# live and the skills stay git-tracked in one place.
#
# Each skill lives in skills/<name>/ and is linked as <skills-dir>/<name>. An
# older installation that linked the repository root as
# orchestrating-phased-specs is a symlink pointing elsewhere, so it is
# repointed like any other stale link.
#
# CLAUDE_SKILLS_DIR and CODEX_SKILLS_DIR override their respective destinations.
# With no arguments, install both skills for Claude Code.
#
# `pwd -P` throughout, never a bare `pwd`: bash's `cd` keeps the logical path it
# was given, so `cd "$dest" && pwd` on an existing symlink prints the symlink's
# own path rather than what it points at — and the already-installed check would
# then never match.
#
# Usage: ./install.sh [claude|codex|all] [orchestrating|building|all]
set -euo pipefail

usage() {
  echo "usage: $0 [claude|codex|all] [orchestrating|building|all]" >&2
  exit 2
}

if [ "$#" -gt 2 ]; then
  usage
fi
host=${1:-claude}
which=${2:-all}
case "$host" in
  claude | codex | all) ;;
  *) usage ;;
esac
case "$which" in
  orchestrating) skills="orchestrating-phased-specs" ;;
  building) skills="building-phased-specs" ;;
  all) skills="orchestrating-phased-specs building-phased-specs" ;;
  *) usage ;;
esac

root=$(cd "$(dirname "$0")" && pwd -P)

for name in $skills; do
  if [ ! -f "$root/skills/$name/SKILL.md" ]; then
    echo "no SKILL.md in $root/skills/$name — refusing to install an incomplete skill" >&2
    exit 1
  fi
done

install_to() {
  local skills_dir=$1 name=$2 src dest current
  src="$root/skills/$name"
  dest="$skills_dir/$name"
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

install_host() {
  local skills_dir=$1 name
  for name in $skills; do
    install_to "$skills_dir" "$name"
  done
}

case "$host" in
  claude) install_host "${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}" ;;
  codex) install_host "${CODEX_SKILLS_DIR:-$HOME/.agents/skills}" ;;
  all)
    install_host "${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
    install_host "${CODEX_SKILLS_DIR:-$HOME/.agents/skills}"
    ;;
esac
