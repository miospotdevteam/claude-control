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

# Find project root
find_project_root() {
  local dir="${1:-$PWD}"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "${1:-$PWD}"
}

CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"

# Check for explicit bypass
if [ -f "$PROJECT_ROOT/.temp/plan-mode/.no-plan" ]; then
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
            "No active plan found. The software-discipline plugin requires a plan "
            "before editing code.\n\n"
            "To create a plan:\n"
            "1. Explore the codebase (read files, grep consumers)\n"
            "2. Write a masterPlan.md to .temp/plan-mode/active/<plan-name>/masterPlan.md\n"
            "3. Then proceed with edits\n\n"
            "To bypass for trivial changes: create .temp/plan-mode/.no-plan"
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
