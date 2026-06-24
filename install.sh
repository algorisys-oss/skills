#!/usr/bin/env bash
#
# install.sh - symlink skills from this repo into ~/.claude/skills so Claude Code discovers them.
#
# Usage:
#   ./install.sh              Symlink every skill (any dir containing SKILL.md) in this repo
#   ./install.sh owasp ...    Symlink only the named skill(s)
#
# Re-running is safe: existing symlinks pointing here are refreshed. A real (non-symlink)
# directory of the same name is left untouched and reported, so nothing is clobbered.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
mkdir -p "$DEST"

# Determine the list of skill directories to install.
skills=()
if [ $# -gt 0 ]; then
  skills=("$@")
else
  for d in "$REPO_DIR"/*/; do
    [ -f "${d}SKILL.md" ] && skills+=("$(basename "$d")")
  done
fi

if [ ${#skills[@]} -eq 0 ]; then
  echo "No skills found (looked for directories containing SKILL.md)." >&2
  exit 1
fi

for name in "${skills[@]}"; do
  src="$REPO_DIR/$name"
  link="$DEST/$name"

  if [ ! -f "$src/SKILL.md" ]; then
    echo "skip   $name  (no $src/SKILL.md)" >&2
    continue
  fi

  if [ -L "$link" ]; then
    ln -sfn "$src" "$link"
    echo "relink $name -> $link"
  elif [ -e "$link" ]; then
    echo "EXISTS $name  ($link is a real path, not a symlink — left untouched)" >&2
  else
    ln -s "$src" "$link"
    echo "link   $name -> $link"
  fi
done

echo "Done. Installed into: $DEST"
