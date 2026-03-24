#!/usr/bin/env bash
# Cleanly reinstall the look-before-you-leap plugin from remote.
# Clears both marketplace and plugin caches to force a fresh clone.
#
# Usage: bash reinstall-plugin.sh

set -euo pipefail

PLUGIN="look-before-you-leap@claude-code-setup"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/claude-code-setup"
CACHE_DIR="$HOME/.claude/plugins/cache/claude-code-setup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_SRC_PATH="look-before-you-leap"

repair_cached_exec_bits() {
  local cache_root="$1"
  local repaired=0

  [ -d "$cache_root" ] || return 0

  while IFS= read -r rel_path; do
    [ -n "$rel_path" ] || continue
    rel_path="${rel_path#${PLUGIN_SRC_PATH}/}"
    local cached_path="$cache_root/$rel_path"
    [ -e "$cached_path" ] || continue
    chmod +x "$cached_path"
    repaired=$((repaired + 1))
  done < <(
    git -C "$REPO_ROOT" ls-files --stage "$PLUGIN_SRC_PATH" \
      | awk '$1 == "100755" { print $4 }'
  )

  echo "Repaired executable permissions on $repaired cached file(s) in $cache_root"
}

repair_installed_plugin_cache() {
  local plugin_cache_parent="$CACHE_DIR/look-before-you-leap"

  [ -d "$plugin_cache_parent" ] || return 0

  local cache_root
  for cache_root in "$plugin_cache_parent"/*; do
    [ -d "$cache_root" ] || continue
    repair_cached_exec_bits "$cache_root"
  done
}

get_installed_plugin_hash() {
  claude plugin list 2>&1 \
    | awk -v plugin="$PLUGIN" '
        $0 ~ plugin { in_block=1; next }
        in_block && $1 == "Version:" { print $2; exit }
        in_block && NF == 0 { exit }
      '
}

echo "Uninstalling $PLUGIN..."
claude plugin uninstall "$PLUGIN" --scope user 2>/dev/null || true

echo "Clearing marketplace cache..."
rm -rf "$MARKETPLACE_DIR"

echo "Clearing plugin cache..."
rm -rf "$CACHE_DIR"

echo "Installing fresh from remote..."
claude plugin install "$PLUGIN" --scope user

echo "Repairing executable permissions in installed cache..."
repair_installed_plugin_cache

installed_hash="$(get_installed_plugin_hash)"

echo ""
echo "Installed version:"
claude plugin list 2>&1 | grep -A 2 "$PLUGIN"

if [ -n "$installed_hash" ]; then
  echo ""
  echo "Installed hash: $installed_hash"
  echo "Cache path: $CACHE_DIR/look-before-you-leap/$installed_hash"
fi
