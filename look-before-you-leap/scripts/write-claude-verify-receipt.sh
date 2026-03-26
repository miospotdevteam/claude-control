#!/usr/bin/env bash
# Write a signed claude_verify receipt for codex-impl step verification.
#
# Called by Claude after independently verifying a Codex-implemented step
# (reading files, running tsc/lint/tests, checking consumers).
#
# Usage: bash write-claude-verify-receipt.sh <project_root> <plan.json> <step_number>

set -euo pipefail

PROJECT_ROOT="${1:?Usage: write-claude-verify-receipt.sh <project_root> <plan.json> <step>}"
PLAN_JSON="${2:?Usage: write-claude-verify-receipt.sh <project_root> <plan.json> <step>}"
STEP_NUM="${3:?Usage: write-claude-verify-receipt.sh <project_root> <plan.json> <step>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${PLUGIN_ROOT}/hooks/lib/receipt-state.sh"

receipt_bootstrap

PROJ_ID=$(receipt_project_id "$PROJECT_ROOT")
P_ID=$(receipt_plan_id "$PLAN_JSON")

RECEIPT_PATH=$(receipt_sign "claude_verify" "$PROJ_ID" "$P_ID" "step=$STEP_NUM")

echo "Claude verify receipt written: $RECEIPT_PATH"
