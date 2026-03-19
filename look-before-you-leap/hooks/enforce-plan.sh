#!/usr/bin/env bash
# PreToolUse hook: Enforce that an active plan exists before Edit/Write.
#
# Allows:
#   - Edits to .temp/ (plan files themselves)
#   - Edits when .temp/plan-mode/.no-plan-$PPID exists (per-session counter-based bypass, max N edits)
#   - Edits when an active plan.json exists
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

# Check for per-session bypass (counter-based: contains PID:remaining_edits)
NO_PLAN_FILE="$PROJECT_ROOT/.temp/plan-mode/.no-plan-$PPID"
if [ -f "$NO_PLAN_FILE" ]; then
  bypass_content=$(cat "$NO_PLAN_FILE" 2>/dev/null) || true
  if [[ "$bypass_content" == *:* ]]; then
    bypass_pid="${bypass_content%%:*}"
    bypass_count="${bypass_content##*:}"
  else
    rm -f "$NO_PLAN_FILE"
    bypass_pid=""
    bypass_count=""
  fi
  if [ -n "$bypass_pid" ] && [ "$bypass_pid" = "$PPID" ] && [ -n "$bypass_count" ]; then
    # Decrement counter
    new_count=$((bypass_count - 1))
    if [ "$new_count" -le 0 ]; then
      rm -f "$NO_PLAN_FILE"
    else
      echo "${bypass_pid}:${new_count}" > "$NO_PLAN_FILE"
    fi
    exit 0
  else
    # Wrong session or invalid format — stale bypass, remove it
    rm -f "$NO_PLAN_FILE"
    # Fall through to deny
  fi
fi

# Check for per-plan handoff-pending marker (fresh plan needs plan mode handoff first)
# Find this session's plan via PPID routing, then check its directory for .handoff-pending
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/plan_utils.py"
SESSION_PLAN=$(python3 "$PLAN_UTILS" find-for-session "$PROJECT_ROOT" "$PPID" 2>/dev/null) || true

if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
  SESSION_PLAN_DIR="$(dirname "$SESSION_PLAN")"
  HANDOFF_MARKER="$SESSION_PLAN_DIR/.handoff-pending"

  if [ -f "$HANDOFF_MARKER" ]; then
    # Read the plan path stored in the marker
    PLAN_PATH=$(cat "$HANDOFF_MARKER" 2>/dev/null) || true

    # Auto-clear if plan has progressed
    if [ -n "$PLAN_PATH" ]; then
      plan_dir="$(dirname "$PLAN_PATH")"
      plan_json="$plan_dir/plan.json"
      if [ -f "$plan_json" ]; then
        is_fresh=$(python3 "$PLAN_UTILS" is-fresh "$plan_json" 2>/dev/null) || true
        if [ "$is_fresh" = "false" ]; then
          rm -f "$HANDOFF_MARKER"
          # Fall through — plan is active, allow edit
        fi
      elif [ -f "$PLAN_PATH" ]; then
        done_count=$(grep -cE '^\s*-\s*\[x\]' "$PLAN_PATH" 2>/dev/null) || true
        active_count=$(grep -cE '^\s*-\s*\[~\]' "$PLAN_PATH" 2>/dev/null) || true
        if [ "$done_count" -gt 0 ] || [ "$active_count" -gt 0 ]; then
          rm -f "$HANDOFF_MARKER"
        fi
      else
        rm -f "$HANDOFF_MARKER"
      fi
    else
      rm -f "$HANDOFF_MARKER"
    fi

    # Re-check: if marker still exists after auto-clear attempts, deny
    if [ -f "$HANDOFF_MARKER" ]; then
      export HOOK_MARKER_PATH="$HANDOFF_MARKER"
      export HOOK_PLAN_PATH="${PLAN_PATH:-unknown}"
      python3 << 'PYEOF'
import json, sys, os

marker = os.environ["HOOK_MARKER_PATH"]
plan_path = os.environ.get("HOOK_PLAN_PATH", "unknown")

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "BLOCKED: Fresh plan requires Orbit review before code edits.\n\n"
            "## Step 1: Discover Orbit tools\n\n"
            "Use ToolSearch to find orbit_await_review:\n"
            "  ToolSearch query: \"+orbit await_review\"\n\n"
            "## Step 2: Submit for review (blocking)\n\n"
            "1. Tell the user: \"The plan is open in VS Code for review. "
            "Add inline comments, then click Approve or Request Changes.\"\n"
            f"2. Call orbit_await_review with sourcePath: {plan_path}\n"
            "   This opens the plan in VS Code and BLOCKS until user responds.\n\n"
            "## Step 3: Handle the response\n\n"
            "- approved → proceed to Step 4\n"
            "- changes_requested → update plan, re-submit\n"
            "- timeout → ask user to review when ready\n\n"
            "## Step 4: Plan mode handoff\n\n"
            "The handoff marker is auto-cleared by a hook when you call "
            "EnterPlanMode (or when orbit_await_review returns approved).\n\n"
            "1. Call EnterPlanMode\n"
            "2. Write a summary to the scratch pad\n"
            "3. Call ExitPlanMode\n\n"
            f"To bypass (if Orbit unavailable): rm {marker}"
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
      exit 0
    fi
  fi
fi

# Check for per-plan step verification pending
if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
  VERIFY_MARKERS=("$SESSION_PLAN_DIR"/.verify-pending-*)
  if [ -e "${VERIFY_MARKERS[0]}" ]; then
    pending_steps=""
    for marker in "${VERIFY_MARKERS[@]}"; do
      step_num=$(head -1 "$marker" 2>/dev/null) || true
      if [ -n "$step_num" ]; then
        pending_steps="${pending_steps:+$pending_steps, }Step $step_num"
      fi
    done

    export HOOK_PENDING_STEPS="${pending_steps:-unknown}"
    export HOOK_PLAN_DIR="$SESSION_PLAN_DIR"
    python3 << 'PYEOF'
import json, os, sys

pending = os.environ["HOOK_PENDING_STEPS"]
plan_dir = os.environ["HOOK_PLAN_DIR"]

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"Step verification pending for {pending}. Code edits are blocked "
            "until a verification sub-agent confirms the completed step was "
            "implemented correctly and fully.\n\n"
            "Dispatch a verification agent now (see the directive injected when "
            "the step was marked [x]).\n\n"
            f"To bypass: rm {plan_dir}/.verify-pending-*"
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
    exit 0
  fi
fi

# PPID-scoped plan check: this session must have a claimed plan
# SESSION_PLAN was already computed above via find-for-session
if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
  exit 0
fi

# No plan for this session — deny the edit
python3 << 'PYEOF'
import json, sys

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "No active plan found for this session. The look-before-you-leap plugin "
            "requires a plan before editing code.\n\n"
            "To create a plan:\n"
            "1. Explore the codebase (read files, grep consumers)\n"
            "2. Write plan.json + masterPlan.md to .temp/plan-mode/active/<plan-name>/\n"
            "3. Then proceed with edits\n\n"
            "To bypass for trivial changes (max 3 edits): echo \"$PPID:3\" > .temp/plan-mode/.no-plan-$PPID"
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
