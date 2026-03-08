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
  # Read the plan path stored in the marker
  PLAN_PATH=$(cat "$HANDOFF_MARKER" 2>/dev/null) || true

  # Auto-clear if the plan has progressed (any [x] or [~] means execution started)
  if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
    done_count=$(grep -cE '^\s*-\s*\[x\]' "$PLAN_PATH" 2>/dev/null) || true
    active_count=$(grep -cE '^\s*-\s*\[~\]' "$PLAN_PATH" 2>/dev/null) || true
    if [ "$done_count" -gt 0 ] || [ "$active_count" -gt 0 ]; then
      rm -f "$HANDOFF_MARKER"
      exit 0
    fi
  else
    # Plan file missing or marker empty — stale marker, clear it
    rm -f "$HANDOFF_MARKER"
    exit 0
  fi

  # Plan is still fresh — soft warning (not a hard deny, to prevent stuck loops)
  export HOOK_MARKER_PATH="$HANDOFF_MARKER"
  python3 << 'PYEOF'
import json, sys, os

marker = os.environ["HOOK_MARKER_PATH"]

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": (
            "Plan mode handoff recommended. A fresh plan exists but you haven't "
            "done the plan mode handoff yet.\n\n"
            "Recommended before editing code:\n"
            "1. Enter plan mode (EnterPlanMode)\n"
            "2. Write a plan summary to the scratch pad\n"
            "3. Exit plan mode (ExitPlanMode)\n\n"
            "This gives the user the 'clear context and accept all edits' prompt, "
            "ensuring execution starts with a fresh context.\n\n"
            f"To dismiss: rm {marker}"
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
  exit 0
fi

# Check for step verification pending (verification agent must run before next-step edits)
VERIFY_MARKERS=("$PROJECT_ROOT/.temp/plan-mode"/.verify-pending-*)
if [ -e "${VERIFY_MARKERS[0]}" ]; then
  # Read which steps are pending verification
  pending_steps=""
  for marker in "${VERIFY_MARKERS[@]}"; do
    step_num=$(head -1 "$marker" 2>/dev/null) || true
    if [ -n "$step_num" ]; then
      pending_steps="${pending_steps:+$pending_steps, }Step $step_num"
    fi
  done

  export HOOK_PENDING_STEPS="${pending_steps:-unknown}"
  export HOOK_PLAN_MODE_DIR="$PROJECT_ROOT/.temp/plan-mode"
  python3 << 'PYEOF'
import json, os, sys

pending = os.environ["HOOK_PENDING_STEPS"]
plan_mode_dir = os.environ["HOOK_PLAN_MODE_DIR"]

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
            f"To bypass: rm {plan_mode_dir}/.verify-pending-*"
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
