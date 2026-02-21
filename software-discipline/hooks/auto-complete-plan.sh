#!/usr/bin/env bash
# PostToolUse hook: Automatically move completed plans to completed/.
#
# After every Edit/Write, checks if the edited file is a masterPlan.md.
# If all steps are [x] complete (and none are pending/in-progress/blocked),
# moves the plan folder from active/ to completed/.
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

# Only act on masterPlan.md files inside .temp/plan-mode/active/
if [[ "$FILE_PATH" != *"/.temp/plan-mode/active/"*"/masterPlan.md" ]]; then
  exit 0
fi

# Verify the file exists
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Check if all steps are complete
# Match both "[ ] pending" (template format) and bare "[ ]" (common usage)
pending=$(grep -cE '\[ \]' "$FILE_PATH" 2>/dev/null) || true
active=$(grep -cE '\[~\]' "$FILE_PATH" 2>/dev/null) || true
blocked=$(grep -cE '\[!\]' "$FILE_PATH" 2>/dev/null) || true
done_count=$(grep -cE '\[x\]' "$FILE_PATH" 2>/dev/null) || true

remaining=$((pending + active + blocked))

# Not all done yet — nothing to do
if [ "$remaining" -gt 0 ] || [ "$done_count" -eq 0 ]; then
  exit 0
fi

# All steps complete — move plan folder to completed/
plan_dir="$(dirname "$FILE_PATH")"
plan_name="$(basename "$plan_dir")"
active_parent="$(dirname "$plan_dir")"
completed_dir="$(dirname "$active_parent")/completed"

# Create completed directory if needed
mkdir -p "$completed_dir"

# Move the plan folder
if [ -d "$plan_dir" ]; then
  # If a plan with the same name already exists in completed, add timestamp
  target="$completed_dir/$plan_name"
  if [ -d "$target" ]; then
    target="${target}-$(date +%Y%m%d-%H%M%S)"
  fi

  mv "$plan_dir" "$target"

  # Also remove .no-plan bypass if it exists
  no_plan_file="$(dirname "$active_parent")/.no-plan"
  [ -f "$no_plan_file" ] && rm -f "$no_plan_file"

  export HOOK_PLAN_NAME="$plan_name"
  export HOOK_DONE_COUNT="$done_count"
  export HOOK_TARGET="$target"

  python3 << 'PYEOF'
import json, sys, os

plan_name = os.environ["HOOK_PLAN_NAME"]
done_count = os.environ["HOOK_DONE_COUNT"]
target = os.environ["HOOK_TARGET"]

output = {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            f"Plan '{plan_name}' completed ({done_count} steps done). "
            f"Automatically moved to: {target}\n"
            "Report completion to the user."
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
else
  exit 0
fi
