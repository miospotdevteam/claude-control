#!/usr/bin/env bash
# PostToolUse hook: Enforce plan review handoff for fresh plans.
#
# After every Edit/Write to a masterPlan.md, checks if the plan is fresh
# (all steps are [ ], none are [x] or [~]). If so:
# 1. Creates .handoff-pending marker inside the plan directory
# 2. Injects directive to present the plan via Orbit MCP for user review
#
# The Orbit flow: generate resolved artifact (opens in VS Code) → user
# reviews with inline comments → user approves or requests changes →
# Claude reads feedback, iterates if needed, then proceeds to execution
# via plan mode handoff (EnterPlanMode → summarize → ExitPlanMode).
#
# The marker is cleared by clear-handoff-on-approval.sh (on Orbit approval
# or EnterPlanMode). It is NOT auto-cleared on session start.
# Bypass: ask the user to run /bypass
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
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"
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

# Write marker to per-plan directory (not global)
MARKER_FILE="$PLAN_DIR/.handoff-pending"

# Don't re-fire if handoff is already pending (prevents re-injection after Orbit approval)
if [ -f "$MARKER_FILE" ]; then
  exit 0
fi

# Create the marker in the plan directory
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
            "The handoff marker is auto-cleared by a hook when you call "
            "EnterPlanMode (or when orbit_await_review returns approved).\n\n"
            "**BEFORE calling EnterPlanMode**: Kill ALL running background "
            "tasks (background Bash commands, background Agents, pending "
            "Codex exec). They are no longer needed after plan approval. If "
            "any survive, their results leak into the new session after "
            "context clears and corrupt the fresh start. Use TaskStop for "
            "agents and kill for Bash processes.\n\n"
            "3. Call `EnterPlanMode` — do NOT output any text in the same "
            "response. Call the tool and NOTHING ELSE.\n"
            "4. After EnterPlanMode succeeds, a system message tells you the "
            "**scratch pad file path** (it will be under `~/.claude/plans/`). "
            "Write to THAT file — NOT to masterPlan.md or plan.json. Use "
            "this exact format:\n\n"
            "   # Plan: <title>\n"
            "   Path: <absolute path to plan.json>\n"
            "   Steps: <N> total\n"
            "   Context: <one-liner from plan.json.context>\n\n"
            "   Read plan.json at the path above to begin execution.\n\n"
            "   Do NOT include step descriptions, acceptance criteria, file "
            "lists, Codex consensus results, exploration findings, or "
            "transcript references. All of that lives on disk. The scratch "
            "pad is a pointer, not a copy.\n"
            "5. Call `ExitPlanMode` — again, do NOT output text in the same "
            "response. Just call the tool.\n\n"
            "This gives the user the 'autoaccept edits and clear context?' "
            "prompt. If they accept, context clears and execution starts "
            "fresh.\n\n"
            "IMPORTANT: Do not output explanatory text alongside EnterPlanMode "
            "or ExitPlanMode calls. Extra text can interfere with the plan "
            "mode transition and cause the scratch pad to appear as a stashed "
            "message instead of the plan mode UI.\n\n"
            "Code edits are BLOCKED until this handoff is complete (or "
            "bypassed).\n"
            "To bypass, ask the user to run /bypass."
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
