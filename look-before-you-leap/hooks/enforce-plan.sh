#!/usr/bin/env bash
# PreToolUse hook: Enforce that an active plan exists before Edit/Write.
#
# Allows:
#   - Edits to .temp/ (plan files themselves)
#   - Edits when .temp/plan-mode/.no-plan exists (explicit bypass)
#   - Edits when an active masterPlan.md exists
#
# Denies:
#   - All other Edit/Write calls — forces plan creation first.
#
# Input: JSON on stdin with tool_name, tool_input.file_path, cwd

set -euo pipefail

INPUT=$(cat)

# Extract file path from tool input (works for both Edit and Write)
FILE_PATH=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null) || true

# Always allow edits to plan files and .temp/ directory
if [[ "$FILE_PATH" == *"/.temp/"* ]] || [[ "$FILE_PATH" == *"/.temp" ]]; then
  exit 0
fi

# Find project root (prefers root with .temp/plan-mode/ for monorepo support)
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"

# Check for explicit bypass (session-scoped: contains PID of creating session)
NO_PLAN_FILE="$PROJECT_ROOT/.temp/plan-mode/.no-plan"
if [ -f "$NO_PLAN_FILE" ]; then
  bypass_pid=$(cat "$NO_PLAN_FILE" 2>/dev/null) || true
  if [ -n "$bypass_pid" ] && kill -0 "$bypass_pid" 2>/dev/null; then
    # Creating session is still alive — allow
    exit 0
  else
    # Session ended or file has no PID — stale bypass, remove it
    rm -f "$NO_PLAN_FILE"
    # Fall through to deny
  fi
fi

# Check for handoff-pending marker (fresh plan needs plan mode handoff first)
HANDOFF_MARKER="$PROJECT_ROOT/.temp/plan-mode/.handoff-pending"
if [ -f "$HANDOFF_MARKER" ]; then
  export HOOK_MARKER_PATH="$HANDOFF_MARKER"
  python3 << 'PYEOF'
import json, sys, os

marker = os.environ["HOOK_MARKER_PATH"]

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "Plan mode handoff required. A fresh plan exists but you haven't "
            "done the plan mode handoff yet.\n\n"
            "Before editing code, you MUST:\n"
            "1. Enter plan mode (EnterPlanMode)\n"
            "2. Write a plan summary to the scratch pad\n"
            "3. Exit plan mode (ExitPlanMode)\n\n"
            "This gives the user the 'clear context and accept all edits' prompt, "
            "ensuring execution starts with a fresh context.\n\n"
            f"To bypass: rm {marker}"
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
  exit 0
fi

# Check for active plan
ACTIVE_DIR="$PROJECT_ROOT/.temp/plan-mode/active"
plan_found=false

if [ -d "$ACTIVE_DIR" ]; then
  for plan in "$ACTIVE_DIR"/*/masterPlan.md; do
    if [ -f "$plan" ]; then
      plan_found=true
      break
    fi
  done
fi

if [ "$plan_found" = true ]; then
  exit 0
fi

# No plan found — deny the edit
python3 << 'PYEOF'
import json, sys

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "No active plan found. The look-before-you-leap plugin requires a plan "
            "before editing code.\n\n"
            "To create a plan:\n"
            "1. Explore the codebase (read files, grep consumers)\n"
            "2. Write a masterPlan.md to .temp/plan-mode/active/<plan-name>/masterPlan.md\n"
            "3. Then proceed with edits\n\n"
            "To bypass for trivial changes: echo $PPID > .temp/plan-mode/.no-plan"
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
