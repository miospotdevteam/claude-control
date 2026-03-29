#!/usr/bin/env bash
# PreToolUse hook: Block EnterPlanMode when background tasks are still running.
#
# Two detection layers (any one blocks the handoff):
# 1. PID markers — .codex-inflight-step-N.pid with a live process
# 2. Incomplete streams — .codex-stream-step-N.jsonl without a matching
#    .codex-result-step-N.txt (Codex started but hasn't finished)
#
# Both layers are session-scoped (plan directory), safe for parallel sessions.
#
# Input: JSON on stdin with tool_name (EnterPlanMode)

set -euo pipefail

# Find active plan directory for this session
source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"
source "${BASH_SOURCE[0]%/*}/lib/plan-state.sh"
hook_read_input

CWD=$(hook_get_cwd)

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"

# Find the active plan for this session
SESSION_PLAN=$(plan_resolve_session "$PROJECT_ROOT")
if [ -z "$SESSION_PLAN" ] || [ ! -f "$SESSION_PLAN" ]; then
  # No active plan — nothing to guard
  exit 0
fi

SESSION_PLAN_DIR="$(dirname "$SESSION_PLAN")"

blockers=""

# --- Layer 1: PID markers ---
for pid_file in "$SESSION_PLAN_DIR"/.codex-inflight-*.pid; do
  [ -f "$pid_file" ] || continue
  inflight_pid=$(cat "$pid_file" 2>/dev/null) || continue
  if [ -n "$inflight_pid" ] && kill -0 "$inflight_pid" 2>/dev/null; then
    marker_name="$(basename "$pid_file")"
    step_info="${marker_name#.codex-inflight-}"
    step_info="${step_info%.pid}"
    blockers="${blockers}  - [pid] ${step_info} (PID: ${inflight_pid})\n"
  else
    # PID is dead — clean up stale marker
    rm -f "$pid_file"
  fi
done

# --- Layer 2: Incomplete streams (stream exists, result does not) ---
for stream_file in "$SESSION_PLAN_DIR"/.codex-stream-*.jsonl; do
  [ -f "$stream_file" ] || continue
  stream_name="$(basename "$stream_file")"
  # .codex-stream-step-N.jsonl -> .codex-result-step-N.txt
  result_name="${stream_name/.codex-stream-/.codex-result-}"
  result_name="${result_name%.jsonl}.txt"
  result_file="$SESSION_PLAN_DIR/$result_name"
  if [ ! -f "$result_file" ]; then
    suffix="${stream_name#.codex-stream-}"
    suffix="${suffix%.jsonl}"
    blockers="${blockers}  - [stream] ${suffix} (stream exists, no result yet)\n"
  fi
done

if [ -n "$blockers" ]; then
  export HOOK_BLOCKERS="$blockers"
  python3 << 'PYEOF'
import json, os, sys

blockers = os.environ.get("HOOK_BLOCKERS", "")

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "BLOCKED: Cannot enter plan mode — background tasks are still running.\n\n"
            "Active tasks:\n"
            f"{blockers}\n"
            "Kill ALL background tasks before handoff. Stale results "
            "leak into the post-handoff session and corrupt execution.\n\n"
            "After killing background tasks, retry EnterPlanMode."
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
  exit 0
fi

# No blockers — allow handoff
exit 0
