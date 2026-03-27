#!/usr/bin/env bash
# PreToolUse hook: Block EnterPlanMode when background Codex tasks are running.
#
# Checks for .codex-inflight-step-N.pid files in the active plan directory.
# If any exist with a live PID, blocks the handoff with a clear message.
#
# Input: JSON on stdin with tool_name (EnterPlanMode)

set -euo pipefail

# Find active plan directory for this session
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

INPUT=$(cat)
CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
PLAN_DIR="$PROJECT_ROOT/.temp/plan-mode"
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"

# Find the active plan for this session
SESSION_PLAN=$(python3 "$PLAN_UTILS" find-for-session "$PROJECT_ROOT" "$PPID" 2>/dev/null) || true
if [ -z "$SESSION_PLAN" ] || [ ! -f "$SESSION_PLAN" ]; then
  # No active plan — nothing to guard
  exit 0
fi

SESSION_PLAN_DIR="$(dirname "$SESSION_PLAN")"

# Check for active .codex-inflight-*.pid files
live_tasks=""
for pid_file in "$SESSION_PLAN_DIR"/.codex-inflight-*.pid; do
  [ -f "$pid_file" ] || continue
  inflight_pid=$(cat "$pid_file" 2>/dev/null) || continue
  if [ -n "$inflight_pid" ] && kill -0 "$inflight_pid" 2>/dev/null; then
    marker_name="$(basename "$pid_file")"
    # Extract step info from filename: .codex-inflight-step-N.pid
    step_info="${marker_name#.codex-inflight-}"
    step_info="${step_info%.pid}"
    live_tasks="${live_tasks}  - ${step_info} (PID: ${inflight_pid})\n"
  else
    # PID is dead — clean up stale marker
    rm -f "$pid_file"
  fi
done

if [ -n "$live_tasks" ]; then
  export HOOK_LIVE_TASKS="$live_tasks"
  python3 << 'PYEOF'
import json, os, sys

live_tasks = os.environ.get("HOOK_LIVE_TASKS", "")

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "BLOCKED: Cannot enter plan mode — background Codex tasks are still running.\n\n"
            "Active tasks:\n"
            f"{live_tasks}\n"
            "Kill ALL background tasks before handoff. Stale Codex results "
            "leak into the post-handoff session and corrupt execution.\n\n"
            "After killing background tasks, retry EnterPlanMode."
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
  exit 0
fi

# No live inflight tasks — allow handoff
exit 0
