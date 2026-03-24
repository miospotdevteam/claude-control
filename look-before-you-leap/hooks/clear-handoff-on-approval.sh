#!/usr/bin/env bash
# PostToolUse hook: Auto-clear .handoff-pending after Orbit approval or plan mode entry.
#
# Fires on:
#   - orbit_await_review (MCP tool) — clears marker only when status is "approved"
#   - EnterPlanMode (built-in tool) — always clears marker (fallback)
#
# This auto-clears the handoff marker so Claude does not need to bypass it.
# The marker's purpose (force Orbit review) is fulfilled once approval comes back.
#
# Input: JSON on stdin with tool_name, tool_input, tool_result, cwd

set -euo pipefail

INPUT=$(cat)

# Find project root and derive plan dir via PPID routing
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"

# Find the plan for this session
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/plan_utils.py"
SESSION_PLAN=$(python3 "$PLAN_UTILS" find-for-session "$PROJECT_ROOT" "$PPID" 2>/dev/null) || true

if [ -z "$SESSION_PLAN" ] || [ ! -f "$SESSION_PLAN" ]; then
  exit 0
fi

MARKER="$(dirname "$SESSION_PLAN")/.handoff-pending"

# No marker — nothing to do
if [ ! -f "$MARKER" ]; then
  exit 0
fi

# Extract tool name
TOOL_NAME=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_name', ''))
" <<< "$INPUT" 2>/dev/null) || true

# Mint a handoff_approved receipt alongside marker removal
source "${BASH_SOURCE[0]%/*}/lib/receipt-state.sh"
mint_handoff_receipt() {
  receipt_bootstrap 2>/dev/null || true
  local proj_id
  proj_id=$(receipt_project_id "$PROJECT_ROOT" 2>/dev/null) || true
  local plan_name
  plan_name=$(receipt_plan_id "$SESSION_PLAN" 2>/dev/null) || true
  if [ -n "$proj_id" ] && [ -n "$plan_name" ]; then
    receipt_sign "handoff_approved" "$proj_id" "$plan_name" >/dev/null 2>&1 || true
  fi
}

# EnterPlanMode — clear marker only (handoff is happening), but do NOT mint
# a handoff_approved receipt. Only Orbit approval can mint that receipt.
if [[ "$TOOL_NAME" == "EnterPlanMode" ]]; then
  rm -f "$MARKER"
  exit 0
fi

# orbit_await_review — clear only on approval
if [[ "$TOOL_NAME" == *"orbit_await_review"* ]]; then
  # Parse tool_result for approval status
  approved=$(python3 -c "
import json, sys

data = json.loads(sys.stdin.read())
result = data.get('tool_result', '')

# tool_result may be a string (MCP response text) or structured
if isinstance(result, str) and 'approved' in result:
    # Try to parse as JSON to confirm it's the status field
    try:
        parsed = json.loads(result)
        if parsed.get('status') == 'approved':
            print('yes')
            sys.exit(0)
    except (json.JSONDecodeError, AttributeError):
        pass
    # Fallback: check for the pattern in the raw string
    if '\"status\": \"approved\"' in result or '\"status\":\"approved\"' in result:
        print('yes')
        sys.exit(0)

print('no')
" <<< "$INPUT" 2>/dev/null) || true

  if [ "$approved" = "yes" ]; then
    mint_handoff_receipt
    rm -f "$MARKER"
  fi
fi
