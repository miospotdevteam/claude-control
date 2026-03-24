#!/usr/bin/env bash
# Grant a temporary bypass receipt for plan enforcement.
#
# Called by the /bypass command (user-invocable only).
# Writes a signed receipt to the external state root AND the legacy
# .no-plan-$PPID marker for backwards compatibility with legacy plans.
#
# Usage: bash grant-bypass.sh [max_edits]
#   max_edits: optional, defaults to 10

set -euo pipefail

MAX_EDITS="${1:-10}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${PLUGIN_ROOT}/hooks/lib/find-root.sh"
source "${PLUGIN_ROOT}/hooks/lib/receipt-state.sh"

PROJECT_ROOT="$(find_project_root)"

# Bootstrap state if needed
receipt_bootstrap

# Compute project and plan IDs
PROJ_ID=$(receipt_project_id "$PROJECT_ROOT")

# Find active plan name (if any)
PLAN_UTILS="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/plan_utils.py"
SESSION_PLAN=$(python3 "$PLAN_UTILS" find-for-session "$PROJECT_ROOT" "$PPID" 2>/dev/null) || true

if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
  PLAN_NAME=$(receipt_plan_id "$SESSION_PLAN")
else
  # No active plan — use a session-scoped default
  PLAN_NAME="no-plan-session-$$"
fi

# Write signed bypass receipt
RECEIPT_PATH=$(receipt_sign "bypass" "$PROJ_ID" "$PLAN_NAME" "session=$PPID" "maxEdits=$MAX_EDITS")

# Also write legacy .no-plan marker for backwards compatibility
mkdir -p "$PROJECT_ROOT/.temp/plan-mode"
echo "${PPID}:${MAX_EDITS}" > "$PROJECT_ROOT/.temp/plan-mode/.no-plan-$PPID"

echo "Bypass granted."
echo "  Receipt: $RECEIPT_PATH"
echo "  Legacy marker: .temp/plan-mode/.no-plan-$PPID"
echo "  Max edits: $MAX_EDITS"
echo "  Session: $PPID"
