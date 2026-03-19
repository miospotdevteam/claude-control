#!/usr/bin/env bash
# PostToolUse hook: Auto-clear .handoff-pending after Orbit approval or plan mode entry.
#
# Fires on:
#   - orbit_await_review (MCP tool) — clears marker only when status is "approved"
#   - EnterPlanMode (built-in tool) — always clears marker (fallback)
#
# This eliminates the need for Claude to manually `rm .handoff-pending`.
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

# EnterPlanMode — always clear (plan mode handoff is happening)
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
    rm -f "$MARKER"
  fi
fi
