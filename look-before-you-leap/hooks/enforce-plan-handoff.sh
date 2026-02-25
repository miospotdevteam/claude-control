#!/usr/bin/env bash
# PostToolUse hook: Enforce plan mode handoff for fresh plans.
#
# After every Edit/Write to a masterPlan.md, checks if the plan is fresh
# (all steps are [ ], none are [x] or [~]). If so:
# 1. Creates .temp/plan-mode/.handoff-pending marker
# 2. Injects a strong directive to enter plan mode, summarize, and exit
#
# This ensures Claude always does the plan mode handoff (enter plan mode →
# summarize → exit plan mode → user gets "clear context and accept all edits"
# prompt) before starting execution. Fresh context = more reliable execution.
#
# The marker is cleared by session-start.sh (new session = context cleared).
# Bypass: rm .temp/plan-mode/.handoff-pending
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

# Check if this is a fresh plan: all steps are [ ], none are [x] or [~]
# Only match checklist lines (not prose that mentions these markers)
done_count=$(grep -cE '^\s*-\s*\[x\]' "$FILE_PATH" 2>/dev/null) || true
active_count=$(grep -cE '^\s*-\s*\[~\]' "$FILE_PATH" 2>/dev/null) || true
pending_count=$(grep -cE '^\s*-\s*\[ \]' "$FILE_PATH" 2>/dev/null) || true

# Not a fresh plan if any step is done or in progress
if [ "$done_count" -gt 0 ] || [ "$active_count" -gt 0 ]; then
  exit 0
fi

# No pending steps = not a real plan (maybe just the header)
if [ "$pending_count" -eq 0 ]; then
  exit 0
fi

# --- Fresh plan detected: all steps are [ ] ---

# Find project root
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

HOOK_CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${HOOK_CWD:-$PWD}")"
PLAN_MODE_DIR="$PROJECT_ROOT/.temp/plan-mode"
MARKER_FILE="$PLAN_MODE_DIR/.handoff-pending"

# Create the marker (idempotent — re-creating on repeated edits is fine)
echo "$FILE_PATH" > "$MARKER_FILE"

# Inject directive
plan_dir="$(dirname "$FILE_PATH")"
plan_name="$(basename "$plan_dir")"

export HOOK_PLAN_NAME="$plan_name"
export HOOK_PLAN_PATH="$FILE_PATH"
export HOOK_PENDING_COUNT="$pending_count"
export HOOK_MARKER_FILE="$MARKER_FILE"

python3 << 'PYEOF'
import json, os, sys

plan_name = os.environ["HOOK_PLAN_NAME"]
plan_path = os.environ["HOOK_PLAN_PATH"]
pending = os.environ["HOOK_PENDING_COUNT"]
marker = os.environ["HOOK_MARKER_FILE"]

output = {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            f"PLAN MODE HANDOFF REQUIRED — Fresh plan '{plan_name}' detected "
            f"({pending} steps, all pending).\n\n"
            "STOP. Do NOT start editing code files. You MUST do the plan mode "
            "handoff first:\n\n"
            "1. Call `EnterPlanMode` to enter plan mode\n"
            "2. Read the masterPlan you just wrote from disk\n"
            "3. Write a summary to the plan mode scratch pad — include: key steps, "
            "files involved, acceptance criteria (enough for the user to approve "
            "or reject)\n"
            "4. Call `ExitPlanMode` to present the plan to the user\n\n"
            "This gives the user the built-in 'autoaccept edits and clear context?' "
            "prompt. If they accept, context clears and execution starts fresh — "
            "far more reliable than executing in a bloated context full of "
            "exploration data.\n\n"
            "Code edits are BLOCKED until this handoff is complete (or bypassed).\n"
            f"To bypass: rm {marker}"
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
