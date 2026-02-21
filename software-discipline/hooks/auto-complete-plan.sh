#!/usr/bin/env bash
# PostToolUse hook: Detect when all plan steps are complete.
#
# After every Edit/Write to a masterPlan.md, checks if all steps are [x].
# If so, emits an advisory message telling Claude to finalize the plan
# (update Completed Summary, verify, then move to completed/).
#
# Does NOT auto-move — Claude needs to make final edits first.
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
pending=$(grep -cE '\[ \]' "$FILE_PATH" 2>/dev/null) || true
active=$(grep -cE '\[~\]' "$FILE_PATH" 2>/dev/null) || true
blocked=$(grep -cE '\[!\]' "$FILE_PATH" 2>/dev/null) || true
done_count=$(grep -cE '\[x\]' "$FILE_PATH" 2>/dev/null) || true

remaining=$((pending + active + blocked))

# Not all done yet — nothing to do
if [ "$remaining" -gt 0 ] || [ "$done_count" -eq 0 ]; then
  exit 0
fi

# All steps complete — tell Claude to finalize
plan_dir="$(dirname "$FILE_PATH")"
plan_name="$(basename "$plan_dir")"
active_parent="$(dirname "$plan_dir")"
completed_dir="$(dirname "$active_parent")/completed"

export HOOK_PLAN_NAME="$plan_name"
export HOOK_DONE_COUNT="$done_count"
export HOOK_PLAN_DIR="$plan_dir"
export HOOK_COMPLETED_DIR="$completed_dir"

python3 << 'PYEOF'
import json, sys, os

plan_name = os.environ["HOOK_PLAN_NAME"]
done_count = os.environ["HOOK_DONE_COUNT"]
plan_dir = os.environ["HOOK_PLAN_DIR"]
completed_dir = os.environ["HOOK_COMPLETED_DIR"]

output = {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            f"ALL STEPS COMPLETE in plan '{plan_name}' ({done_count} steps done).\n\n"
            "Before closing this plan:\n"
            "1. Update the Completed Summary section with final results\n"
            "2. Verify all work (run type checker, linter, tests if applicable)\n"
            "3. Report completion to the user\n"
            f"4. Move the plan folder to completed/:\n"
            f"   mv '{plan_dir}' '{completed_dir}/{plan_name}'\n"
            "5. Remove .no-plan bypass if it exists:\n"
            f"   rm -f '{os.path.dirname(completed_dir)}/.no-plan'"
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
