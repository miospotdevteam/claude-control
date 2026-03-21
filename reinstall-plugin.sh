#!/usr/bin/env bash
# Cleanly reinstall the look-before-you-leap plugin from remote.
# Clears both marketplace and plugin caches to force a fresh clone.
#
# Usage: bash reinstall-plugin.sh

set -euo pipefail

PLUGIN="look-before-you-leap@claude-code-setup"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/claude-code-setup"
CACHE_DIR="$HOME/.claude/plugins/cache/claude-code-setup"

echo "Uninstalling $PLUGIN..."
claude plugin uninstall "$PLUGIN" --scope user 2>/dev/null || true

echo "Clearing marketplace cache..."
rm -rf "$MARKETPLACE_DIR"

echo "Clearing plugin cache..."
rm -rf "$CACHE_DIR"

echo "Installing fresh from remote..."
claude plugin install "$PLUGIN" --scope user

echo ""
echo "Installed version:"
claude plugin list 2>&1 | grep -A 2 "$PLUGIN"
