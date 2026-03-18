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

# Act on plan.json OR masterPlan.md inside .temp/plan-mode/active/
if [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/plan.json" ]]; then
  PLAN_DIR="$(dirname "$FILE_PATH")"
elif [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/masterPlan.md" ]]; then
  PLAN_DIR="$(dirname "$FILE_PATH")"
else
  exit 0
fi

# Determine freshness — prefer plan.json
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/plan_utils.py"
PLAN_JSON="$PLAN_DIR/plan.json"
MASTER_PLAN="$PLAN_DIR/masterPlan.md"

if [ -f "$PLAN_JSON" ]; then
  is_fresh=$(python3 "$PLAN_UTILS" is-fresh "$PLAN_JSON" 2>/dev/null) || true
  if [ "$is_fresh" != "true" ]; then
    exit 0
  fi
  pending_count=$(python3 -c "
import json
plan = json.load(open('$PLAN_JSON'))
print(sum(1 for s in plan.get('steps', []) if s.get('status') == 'pending'))
" 2>/dev/null) || true
  # For the FILE_PATH used in the directive, prefer masterPlan.md (user-facing)
  if [ -f "$MASTER_PLAN" ]; then
    FILE_PATH="$MASTER_PLAN"
  fi
elif [ -f "$MASTER_PLAN" ]; then
  # Legacy: grep masterPlan.md
  done_count=$(grep -cE '^\s*-\s*\[x\]' "$MASTER_PLAN" 2>/dev/null) || true
  active_count=$(grep -cE '^\s*-\s*\[~\]' "$MASTER_PLAN" 2>/dev/null) || true
  pending_count=$(grep -cE '^\s*-\s*\[ \]' "$MASTER_PLAN" 2>/dev/null) || true
  if [ "$done_count" -gt 0 ] || [ "$active_count" -gt 0 ]; then
    exit 0
  fi
  if [ "$pending_count" -eq 0 ]; then
    exit 0
  fi
  FILE_PATH="$MASTER_PLAN"
else
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
            "## Step A: Discover Orbit tools\n\n"
            "Use ToolSearch to load the orbit_await_review tool:\n"
            "  ToolSearch query: \"+orbit await_review\"\n\n"
            "## Step B: Submit for review (blocking)\n\n"
            "1. Tell the user: \"The plan is open in VS Code for review. "
            "Add inline comments on any section, then click Approve or "
            "Request Changes.\"\n"
            f"2. Call `orbit_await_review` with sourcePath: `{plan_path}`\n"
            "   This generates the artifact, opens it in VS Code, and BLOCKS "
            "until the user clicks Approve or Request Changes. Do NOT call "
            "orbit_generate_resolved separately — orbit_await_review does it.\n\n"
            "## Step C: Handle the response\n\n"
            "orbit_await_review returns a JSON with `status` and `threads`.\n\n"
            "- **If status is `approved` with no threads**: Proceed to Step D.\n"
            "- **If status is `approved` with threads**: Read each thread, "
            "reply as agent acknowledging the feedback, resolve threads, "
            "then proceed to Step D.\n"
            "- **If status is `changes_requested`**: Read all threads. Update "
            "masterPlan.md to address the feedback. Reply to each thread "
            "explaining what you changed. Resolve threads. Then call "
            f"`orbit_await_review` again on `{plan_path}` for re-review. "
            "Loop back to handle the new response.\n"
            "- **If status is `timeout`**: Tell the user the review timed out "
            "and ask them to review when ready.\n\n"
            "## Step D: Plan mode handoff (post-approval)\n\n"
            f"3. **Remove the handoff marker**: `rm {marker}`\n"
            "   This MUST happen before EnterPlanMode — the marker blocks "
            "writes needed for the plan mode scratch pad.\n"
            "4. Call `EnterPlanMode` to enter plan mode\n"
            "5. Read the masterPlan from disk\n"
            "6. Write a summary to the plan mode scratch pad — include: key "
            "steps, files involved, acceptance criteria\n"
            "7. Call `ExitPlanMode` to present to the user\n\n"
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
