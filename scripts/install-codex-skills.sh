#!/usr/bin/env bash
# Install Codex skills from the plugin's codex-skills/ directory.
# Thin wrapper around the plugin's own install script.
#
# Usage: bash scripts/install-codex-skills.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

bash "$REPO_ROOT/look-before-you-leap/scripts/install-codex-skills.sh" "$REPO_ROOT/look-before-you-leap"
