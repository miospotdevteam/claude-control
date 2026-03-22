#!/usr/bin/env bash
# Install look-before-you-leap Codex skills to ~/.codex/skills/.
#
# Copies lbyl-verify and lbyl-implement skills so Codex knows the
# verification and implementation protocols. Called from session-start.sh
# to keep skills up to date automatically.
#
# Usage: install-codex-skills.sh [plugin-root]
#   plugin-root: path to the look-before-you-leap plugin root
#                (defaults to parent of this script's directory)

set -euo pipefail

# Determine plugin root
if [ $# -ge 1 ]; then
  PLUGIN_ROOT="$1"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

CODEX_SKILLS_SRC="$PLUGIN_ROOT/codex-skills"
CODEX_SKILLS_DST="$HOME/.codex/skills"

# Check codex is installed
if ! command -v codex >/dev/null 2>&1; then
  # Codex not installed — skip silently (not an error)
  exit 0
fi

# Check source skills exist
if [ ! -d "$CODEX_SKILLS_SRC" ]; then
  echo "Warning: codex-skills directory not found at $CODEX_SKILLS_SRC" >&2
  exit 0
fi

installed=0

for skill_dir in "$CODEX_SKILLS_SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  src_file="$skill_dir/SKILL.md"
  dst_dir="$CODEX_SKILLS_DST/$skill_name"
  dst_file="$dst_dir/SKILL.md"

  [ -f "$src_file" ] || continue

  # Only copy if destination is missing or source is newer
  if [ ! -f "$dst_file" ] || [ "$src_file" -nt "$dst_file" ]; then
    mkdir -p "$dst_dir"
    cp "$src_file" "$dst_file"
    installed=$((installed + 1))
  fi
done

if [ "$installed" -gt 0 ]; then
  echo "Installed $installed Codex skill(s) to $CODEX_SKILLS_DST"
fi
