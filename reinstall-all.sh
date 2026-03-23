#!/usr/bin/env bash
# Reinstall the Claude Code plugin AND sync Codex skills in one shot.
#
# Usage: bash reinstall-all.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

echo "=== Reinstalling Claude Code plugin ==="
bash "$REPO_ROOT/scripts/reinstall-plugin.sh"

echo ""
echo "=== Installing Codex skills ==="
bash "$REPO_ROOT/scripts/install-codex-skills.sh"

echo ""
echo "Done. Both plugin and Codex skills are up to date."
