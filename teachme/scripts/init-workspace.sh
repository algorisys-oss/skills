#!/usr/bin/env bash
#
# init-workspace.sh - scaffold a teachme workspace for a topic.
#
# Usage:
#   init-workspace.sh "<topic>" [parent-dir]
#
# Creates <parent-dir>/.teachme/<topic-slug>/ with MISSION.md, LOG.md, RESOURCES.md
# and an examples/ dir. parent-dir defaults to the current directory.
# Safe to re-run: existing files are left untouched (never clobbered).

set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 \"<topic>\" [parent-dir]" >&2; exit 1; }

TOPIC="$1"
PARENT="${2:-.}"

# slug: lowercase, spaces/punct -> single hyphen, trim hyphens
SLUG="$(printf '%s' "$TOPIC" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
[ -n "$SLUG" ] || SLUG="topic"

DIR="$PARENT/.teachme/$SLUG"
mkdir -p "$DIR/examples"

write_if_absent() {
  local path="$1"
  if [ -e "$path" ]; then
    echo "keep   $path (exists)"
  else
    cat > "$path"
    echo "create $path"
  fi
}

write_if_absent "$DIR/MISSION.md" <<EOF
# Mission — $TOPIC

**Goal (what they want to *do*):**
**Why it matters to them:**
**Success looks like:**
**Current level:** novice | developing | proficient
**Constraints / preferences:**
EOF

write_if_absent "$DIR/LOG.md" <<EOF
# Learning log — $TOPIC

<!-- Append one block per session. Open each session by retrieving the queued items from memory. -->
EOF

write_if_absent "$DIR/RESOURCES.md" <<EOF
# Resources — $TOPIC

<!-- High-trust sources only, each with a one-line why. -->
EOF

echo "Workspace ready: $DIR"
