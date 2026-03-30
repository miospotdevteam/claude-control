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

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"
source "${BASH_SOURCE[0]%/*}/lib/plan-state.sh"
hook_read_input

# Find project root and derive plan dir via PPID routing
CWD=$(hook_get_cwd)

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"

# Find the plan for this session
SESSION_PLAN=$(plan_resolve_session "$PROJECT_ROOT")

if [ -z "$SESSION_PLAN" ] || [ ! -f "$SESSION_PLAN" ]; then
  exit 0
fi

MARKER="$(dirname "$SESSION_PLAN")/.handoff-pending"

# No marker — nothing to do
if [ ! -f "$MARKER" ]; then
  exit 0
fi

# Extract tool name
TOOL_NAME=$(hook_get_tool_name)

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
  # tool_result can arrive as: str, list (MCP content array), or dict
  approved=$(python3 -c "
import json, sys

data = json.loads(sys.stdin.read())
result = data.get('tool_result', '')

def check_approved(text):
    if not isinstance(text, str) or 'approved' not in text:
        return False
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict) and parsed.get('status') == 'approved':
            return True
    except (json.JSONDecodeError, ValueError):
        pass
    if '\"status\": \"approved\"' in text or '\"status\":\"approved\"' in text:
        return True
    return False

if isinstance(result, str):
    if check_approved(result):
        print('yes')
        sys.exit(0)
elif isinstance(result, list):
    # MCP content array: [{\"type\": \"text\", \"text\": \"...\"}]
    for item in result:
        if isinstance(item, dict) and check_approved(item.get('text', '')):
            print('yes')
            sys.exit(0)
elif isinstance(result, dict):
    if result.get('status') == 'approved':
        print('yes')
        sys.exit(0)
    if check_approved(result.get('text', '')):
        print('yes')
        sys.exit(0)

print('no')
" <<< "$INPUT" 2>/dev/null) || true

  if [ "$approved" = "yes" ]; then
    mint_handoff_receipt
    rm -f "$MARKER"
  fi
fi
