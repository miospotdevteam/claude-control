#!/usr/bin/env bash
# Shared helper: find the project root for plan-mode operations.
#
# Walks up from the given directory (or $PWD) looking for .git or CLAUDE.md.
# If .temp/plan-mode/ exists at that root, returns it immediately.
# If not, keeps walking up to find a parent that HAS .temp/plan-mode/.
# This handles monorepos where Claude Code runs in a subdirectory
# but the plan lives at a parent level.
#
# Usage: source this file, then call find_project_root [start_dir]

find_project_root() {
  local dir="${1:-$PWD}"
  local first_root=""

  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
      # Found a project root candidate
      if [ -d "$dir/.temp/plan-mode" ]; then
        # This root has plan-mode — use it
        echo "$dir"
        return 0
      fi
      # Remember the first root we found (fallback if no plan-mode anywhere)
      if [ -z "$first_root" ]; then
        first_root="$dir"
      fi
    fi
    dir="$(dirname "$dir")"
  done

  # Return the first root found (even without plan-mode), or the start dir
  echo "${first_root:-${1:-$PWD}}"
}
