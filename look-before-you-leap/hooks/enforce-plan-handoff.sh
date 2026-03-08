#!/usr/bin/env bash
# PostToolUse hook: Enforce plan review handoff for fresh plans.
#
# After every Edit/Write to a masterPlan.md, checks if the plan is fresh
# (all steps are [ ], none are [x] or [~]). If so:
# 1. Creates .temp/plan-mode/.handoff-pending marker
# 2. Injects directive to present the plan via Orbit MCP for user review
#
# The Orbit flow: generate resolved artifact (opens in VS Code) → user
# reviews with inline comments → user approves or requests changes →
# Claude reads feedback, iterates if needed, then proceeds to execution
# via plan mode handoff (EnterPlanMode → summarize → ExitPlanMode).
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

# Don't re-fire if handoff is already pending (prevents re-injection after Orbit approval)
if [ -f "$MARKER_FILE" ]; then
  exit 0
fi

# Create the marker
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
            f"PLAN REVIEW REQUIRED — Fresh plan '{plan_name}' detected "
            f"({pending} steps, all pending).\n\n"
            "STOP. Do NOT start editing code files. Present the plan to the "
            "user for review via Orbit MCP, then do the plan mode handoff.\n\n"
            "## Step A: Present via Orbit\n\n"
            f"1. Call `orbit_generate_resolved` with sourcePath: `{plan_path}`\n"
            "   This opens the plan in VS Code as a reviewable artifact.\n"
            "2. Tell the user: \"The plan is open in VS Code for review. "
            "You can add inline comments on any section, then approve or "
            "request changes.\"\n"
            "3. Wait for the user to respond (they will say they approved, "
            "request changes, or ask you to check).\n\n"
            "## Step B: Check review state\n\n"
            f"4. Call `orbit_get_review_state` with sourcePath: `{plan_path}`\n"
            f"5. Call `orbit_list_threads` with sourcePath: `{plan_path}` "
            "and status: `open`\n\n"
            "## Step C: Handle feedback\n\n"
            "- **If approved with no open threads**: Proceed to Step D.\n"
            "- **If approved with open threads**: Read each thread, reply as "
            "agent acknowledging the feedback, resolve threads, then proceed "
            "to Step D.\n"
            "- **If changes_requested**: Read all open threads. Update the "
            "masterPlan.md to address the feedback. Reply to each thread "
            "explaining what you changed. Resolve threads. Call "
            f"`orbit_generate_resolved` again on `{plan_path}` to refresh "
            "the artifact. Tell the user to re-review. Loop back to Step B.\n\n"
            "## Step D: Plan mode handoff (post-approval)\n\n"
            "6. Call `EnterPlanMode` to enter plan mode\n"
            "7. Read the masterPlan from disk\n"
            "8. Write a summary to the plan mode scratch pad — include: key "
            "steps, files involved, acceptance criteria\n"
            "9. Call `ExitPlanMode` to present to the user\n\n"
            "This gives the user the 'autoaccept edits and clear context?' "
            "prompt. If they accept, context clears and execution starts "
            "fresh.\n\n"
            "Code edits are BLOCKED until this handoff is complete (or "
            "bypassed).\n"
            f"To bypass: rm {marker}"
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
