#!/usr/bin/env bash
# Shared helpers for resolving root directories.
#
# find_project_root [start_dir]
#   Walks up from the given directory (or $PWD) looking for .git or CLAUDE.md.
#   If .temp/plan-mode/ exists at that root, returns it immediately.
#   If not, keeps walking up to find a parent that HAS .temp/plan-mode/.
#   This handles monorepos where Claude Code runs in a subdirectory
#   but the plan lives at a parent level.
#
# find_plugin_repo
#   Derives the plugin SOURCE repo root from CLAUDE_PLUGIN_ROOT.
#   Handles both layouts:
#     ~/.claude/plugins/cache/<repo-name>/<plugin>/<hash>
#     ~/.claude/plugins/marketplaces/<repo-name>/<plugin>
#   Checks ~/Projects/<repo-name> (and other common dirs) for a git repo.
#   Returns empty string and exit 1 if not found.

find_plugin_repo() {
  local cache_path="${CLAUDE_PLUGIN_ROOT:-}"
  if [ -z "$cache_path" ]; then
    return 1
  fi

  # Extract repo name from plugin path.
  # Handles both cache and marketplace layouts:
  #   ~/.claude/plugins/cache/<repo-name>/<plugin>/<hash>
  #   ~/.claude/plugins/marketplaces/<repo-name>/<plugin>
  local after_plugins="${cache_path#*plugins/}"
  # Strip the first path component (cache/ or marketplaces/)
  local after_type="${after_plugins#*/}"
  local repo_name="${after_type%%/*}"

  if [ -z "$repo_name" ]; then
    return 1
  fi

  # Check common development directories
  for base in "$HOME/Projects" "$HOME/Code" "$HOME/Dev" "$HOME/src" "$HOME"; do
    if [ -d "$base/$repo_name/.git" ]; then
      echo "$base/$repo_name"
      return 0
    fi
  done

  return 1
}

# find_plan_dir [script_dir]
#   Locates .temp/plan-mode/ from the script's own location or by walking up
#   from $PWD. Used by plan-status.sh and resume.sh.
find_plan_dir() {
  local script_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"

  # If we're inside .temp/plan-mode/scripts/, use the parent
  if [[ "$script_dir" == *".temp/plan-mode/scripts" ]]; then
    echo "$(dirname "$script_dir")"
    return 0
  fi

  # Otherwise, look for .temp/plan-mode/ from the project root
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.temp/plan-mode" ]; then
      echo "$dir/.temp/plan-mode"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  echo ""
}

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
