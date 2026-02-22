#!/usr/bin/env bash
# PostToolUse hook: Enforce plan checkpointing during execution.
#
# Tracks edits to non-plan files. After 3 code edits without a
# masterPlan.md update, injects a strong reminder into context.
#
# Counter file: .temp/plan-mode/.edit-count
#   - Incremented on each Edit/Write to a non-.temp file
#   - Reset to 0 when masterPlan.md (or sub-plan) is edited
#
# Input: JSON on stdin with tool_name, tool_input.file_path, cwd

set -euo pipefail

INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null) || true

[ -z "$FILE_PATH" ] && exit 0

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
PLAN_MODE_DIR="$PROJECT_ROOT/.temp/plan-mode"
ACTIVE_DIR="$PLAN_MODE_DIR/active"
COUNTER_FILE="$PLAN_MODE_DIR/.edit-count"

# No active plan directory — nothing to enforce
[ ! -d "$ACTIVE_DIR" ] && exit 0

# Check if any active plan exists
plan_found=false
for plan in "$ACTIVE_DIR"/*/masterPlan.md; do
  if [ -f "$plan" ]; then
    plan_found=true
    break
  fi
done
[ "$plan_found" = false ] && exit 0

# --- Determine if this edit was to a plan file or a code file ---

# Plan file edit: anything inside .temp/plan-mode/ (masterPlan, sub-plans, discovery)
if [[ "$FILE_PATH" == *"/.temp/plan-mode/"* ]]; then
  # Reset counter — plan was just updated
  echo "0" > "$COUNTER_FILE"
  exit 0
fi

# Edits to other .temp/ files (not plan-mode) — ignore, don't count
if [[ "$FILE_PATH" == *"/.temp/"* ]]; then
  exit 0
fi

# --- Code file edit: increment counter ---

current=0
if [ -f "$COUNTER_FILE" ]; then
  current=$(cat "$COUNTER_FILE" 2>/dev/null) || true
  # Validate it's a number
  if ! [[ "$current" =~ ^[0-9]+$ ]]; then
    current=0
  fi
fi

current=$((current + 1))
echo "$current" > "$COUNTER_FILE"

# Threshold: remind after 3 edits without a plan update
if [ "$current" -lt 3 ]; then
  exit 0
fi

# --- Inject reminder ---

# Find the active plan path for the message
latest_plan=""
if command -v stat >/dev/null 2>&1; then
  # macOS stat
  latest_plan=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
  # Linux fallback
  if [ -z "$latest_plan" ]; then
    latest_plan=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  fi
fi
# Final fallback
if [ -z "$latest_plan" ]; then
  latest_plan=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f 2>/dev/null | head -1)
fi

# Reset counter after firing the reminder
echo "0" > "$COUNTER_FILE"

export HOOK_EDIT_COUNT="$current"
export HOOK_PLAN_PATH="${latest_plan:-unknown}"

python3 << 'PYEOF'
import json, os, sys

edit_count = os.environ["HOOK_EDIT_COUNT"]
plan_path = os.environ["HOOK_PLAN_PATH"]

output = {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            f"⚠️ CHECKPOINT NOW — You have made {edit_count} code edits without "
            "updating your masterPlan.md.\n\n"
            "The persistent-plans skill REQUIRES checkpointing every 2-3 file edits. "
            "**Stop coding and update your plan NOW:**\n\n"
            "1. Open your masterPlan.md and update the current step's Progress checklist\n"
            "2. Mark completed sub-tasks: `[ ]` → `[x]`\n"
            "3. Add notes to the Result field for the current step\n"
            "4. Save the file (Edit tool on disk)\n\n"
            "If auto-compaction fired RIGHT NOW, could you resume from the plan file alone? "
            "If not, the plan is stale.\n\n"
            f"Plan file: {plan_path}"
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
