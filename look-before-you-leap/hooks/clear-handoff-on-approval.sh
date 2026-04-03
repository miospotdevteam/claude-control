#!/usr/bin/env bash
# PostToolUse hook: Auto-clear .handoff-pending after Orbit approval.
#
# Fires on:
#   - orbit_await_review (MCP tool) — clears marker only when status is "approved"
#
# This auto-clears the handoff marker only when approval is real. EnterPlanMode
# must not erase the pending-review marker by itself.
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

# Extract tool name
TOOL_NAME=$(hook_get_tool_name)

if [[ "$TOOL_NAME" != *"orbit_await_review"* ]]; then
  exit 0
fi

# Mint a handoff_approved receipt alongside marker removal
source "${BASH_SOURCE[0]%/*}/lib/receipt-state.sh"
mint_handoff_receipt() {
  local target_plan="$1"
  receipt_bootstrap 2>/dev/null || true
  local proj_id
  proj_id=$(receipt_project_id "$PROJECT_ROOT" 2>/dev/null) || true
  local plan_name
  plan_name=$(receipt_plan_id "$target_plan" 2>/dev/null) || true
  if [ -n "$proj_id" ] && [ -n "$plan_name" ]; then
    receipt_sign "handoff_approved" "$proj_id" "$plan_name" >/dev/null 2>&1 || true
  fi
}

# Parse tool_result for approval status.
# tool_result can arrive as: str, list (MCP content array), or dict.
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

# Approval did not happen — nothing to do.
if [ "$approved" != "yes" ]; then
  exit 0
fi

# Prefer the session plan, but fall back to the reviewed sourcePath so an
# approval is still honored if PPID routing missed for this one hook call.
SESSION_PLAN=$(plan_resolve_session "$PROJECT_ROOT")
SOURCE_PLAN=$(python3 -c "
import json, os, sys

data = json.loads(sys.stdin.read())
source = data.get('tool_input', {}).get('sourcePath', '')
cwd = data.get('cwd') or os.getcwd()

if not source:
    print('')
    raise SystemExit(0)

if not os.path.isabs(source):
    source = os.path.join(cwd, source)

source = os.path.normpath(os.path.abspath(os.path.expanduser(source)))
base = os.path.basename(source)

if base == 'plan.json':
    candidate = source
elif base == 'masterPlan.md':
    candidate = os.path.join(os.path.dirname(source), 'plan.json')
else:
    candidate = ''

print(candidate if candidate and os.path.isfile(candidate) else '')
" <<< "$INPUT" 2>/dev/null) || true

TARGET_PLAN="$SESSION_PLAN"
if [ -z "$TARGET_PLAN" ] || [ ! -f "$TARGET_PLAN" ]; then
  TARGET_PLAN="$SOURCE_PLAN"
fi

if [ -z "$TARGET_PLAN" ] || [ ! -f "$TARGET_PLAN" ]; then
  exit 0
fi

MARKER="$(dirname "$TARGET_PLAN")/.handoff-pending"
mint_handoff_receipt "$TARGET_PLAN"
[ -f "$MARKER" ] && rm -f "$MARKER"
