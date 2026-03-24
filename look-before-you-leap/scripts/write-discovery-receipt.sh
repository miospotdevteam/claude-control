#!/usr/bin/env bash
# Write a signed discovery receipt after co-exploration completes.
#
# Called after discovery.md is written with findings from both Claude
# and Codex (or with documented fallback when Codex is unavailable).
#
# Usage: bash write-discovery-receipt.sh <project_root> <plan_name> <codex_status>
#   codex_status: "complete" | "unavailable" | "skipped-user-override"
#
# The receipt records the exploration state so writing-plans can gate
# on verified discovery before producing a plan.

set -euo pipefail

PROJECT_ROOT="${1:?Usage: write-discovery-receipt.sh <project_root> <plan_name> <codex_status>}"
PLAN_NAME="${2:?Usage: write-discovery-receipt.sh <project_root> <plan_name> <codex_status>}"
CODEX_STATUS="${3:?Usage: write-discovery-receipt.sh <project_root> <plan_name> <codex_status>}"

# Validate codex_status against allowed values
case "$CODEX_STATUS" in
  complete|unavailable|skipped-user-override)
    ;;
  *)
    echo "ERROR: Invalid codex_status '$CODEX_STATUS'. Must be one of: complete, unavailable, skipped-user-override" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${PLUGIN_ROOT}/hooks/lib/receipt-state.sh"

receipt_bootstrap

PROJ_ID=$(receipt_project_id "$PROJECT_ROOT")

RECEIPT_PATH=$(receipt_sign "discovery" "$PROJ_ID" "$PLAN_NAME" "codexStatus=$CODEX_STATUS")

echo "Discovery receipt written: $RECEIPT_PATH"
echo "  Codex status: $CODEX_STATUS"
