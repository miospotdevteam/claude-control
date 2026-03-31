#!/usr/bin/env bash
# PreToolUse hook: Block EnterPlanMode when background tasks are still running.
#
# Four detection layers (any one blocks the handoff):
# 1. PID markers — .codex-inflight-step-N.pid with a live process
# 2. Incomplete streams — .codex-stream-step-N.jsonl without a matching
#    .codex-result-step-N.txt (Codex started but hasn't finished)
# 3. pgrep scan — catches direct codex exec calls (co-exploration,
#    consensus, design review) that have no PID markers
# 4. Background agent receipt gate — requires Claude to confirm via
#    TaskList that no background agents are running before handoff
#
# Layers 1-2 are session-scoped (plan directory). Layer 3 is project-scoped.
# Layer 4 uses a receipt file that Claude creates after clearing agents.
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

cleaned=""

# --- Layer 1: PID markers (direction-locked scripts) — auto-kill live processes ---
for pid_file in "$SESSION_PLAN_DIR"/.codex-inflight-*.pid; do
  [ -f "$pid_file" ] || continue
  inflight_pid=$(cat "$pid_file" 2>/dev/null) || continue
  if [ -n "$inflight_pid" ] && kill -0 "$inflight_pid" 2>/dev/null; then
    # Kill the live codex process — it's stale during handoff
    kill "$inflight_pid" 2>/dev/null || true
    marker_name="$(basename "$pid_file")"
    step_info="${marker_name#.codex-inflight-}"
    step_info="${step_info%.pid}"
    cleaned="${cleaned}  - [killed] ${step_info} (PID: ${inflight_pid})\n"
  fi
  # Clean up marker regardless (dead or just killed)
  rm -f "$pid_file"
done

# --- Layer 2: Incomplete streams (stream exists, result does not) — clean up ---
for stream_file in "$SESSION_PLAN_DIR"/.codex-stream-*.jsonl; do
  [ -f "$stream_file" ] || continue
  stream_name="$(basename "$stream_file")"
  result_name="${stream_name/.codex-stream-/.codex-result-}"
  result_name="${result_name%.jsonl}.txt"
  result_file="$SESSION_PLAN_DIR/$result_name"
  if [ ! -f "$result_file" ]; then
    suffix="${stream_name#.codex-stream-}"
    suffix="${suffix%.jsonl}"
    cleaned="${cleaned}  - [cleaned] ${suffix} (stale stream, no result)\n"
    rm -f "$stream_file"
  fi
done

# --- Layer 3: pgrep scan for direct codex exec calls (co-exploration, consensus, etc.) ---
# Scope to this project's root so we don't kill codex in other sessions
CODEX_PATTERN="codex exec -C ${PROJECT_ROOT}"
if pgrep -f "$CODEX_PATTERN" >/dev/null 2>&1; then
  pkill -f "$CODEX_PATTERN" 2>/dev/null || true
  cleaned="${cleaned}  - [killed] orphaned codex exec process(es) for ${PROJECT_ROOT} (via pgrep)\n"
  echo "guard-handoff: killed orphaned codex exec process(es) for ${PROJECT_ROOT}" >&2
fi

# --- P2: Block if processes survive kill — wait and re-check ---
if [ -n "$cleaned" ]; then
  sleep 1
  if pgrep -f "$CODEX_PATTERN" >/dev/null 2>&1; then
    # Processes still alive — block the handoff
    echo "BLOCKED: codex process still running after kill. Wait a few seconds and retry EnterPlanMode."
    exit 0
  fi

  # All dead — report cleanup and allow handoff
  export HOOK_CLEANED="$cleaned"
  python3 << 'PYEOF'
import json, os, sys

cleaned = os.environ.get("HOOK_CLEANED", "")

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": (
            "Auto-cleaned stale background tasks before handoff:\n"
            f"{cleaned}\n"
            "Handoff proceeding."
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
  exit 0
fi

# --- Layer 4: Background agent receipt gate ---
# Claude Code's background agents aren't OS processes — we can't detect them
# from a shell hook. Instead, require Claude to confirm they're stopped by
# writing a receipt file. Block until the receipt exists.
RECEIPT="$SESSION_PLAN_DIR/.background-cleared"
if [ ! -f "$RECEIPT" ]; then
  echo "BLOCKED: Before EnterPlanMode, you must clear background agents. Run TaskList to check for in_progress tasks, run TaskStop on each, then write the receipt: touch $RECEIPT — then retry EnterPlanMode."
  exit 0
fi
# Clean up the receipt so it doesn't persist into the next handoff cycle
rm -f "$RECEIPT"

# Nothing to clean — allow handoff
exit 0
