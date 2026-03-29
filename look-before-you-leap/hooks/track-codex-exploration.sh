#!/usr/bin/env bash
# PostToolUse hook: Track Codex exploration activity during discovery.
#
# On Bash PostToolUse:
# - `command -v codex` writes .codex-preflight-$PPID with available/unavailable
# - `codex exec` writes .codex-co-exploration-$PPID
#
# Markers are only written during the exploration phase:
# - plan dir exists but plan.json does not yet exist, or
# - plan.json exists and all steps are still pending
#
# Input: JSON on stdin with tool_input.command, tool_response, cwd

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
hook_read_input

COMMAND=$(hook_get_command)

[ -z "$COMMAND" ] && exit 0

CMD_TRIMMED="${COMMAND#"${COMMAND%%[![:space:]]*}"}"

MARKER_NAME=""
PRECHECK_RESULT=""

if [[ "$CMD_TRIMMED" =~ (^|[[:space:];|&])command[[:space:]]+-v[[:space:]]+codex([[:space:]]|$) ]]; then
  MARKER_NAME=".codex-preflight-$PPID"
  TOOL_RESPONSE=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_response', ''))
" <<< "$INPUT" 2>/dev/null) || true
  if [[ "$TOOL_RESPONSE" == *"Exit code"* ]] || [[ "$TOOL_RESPONSE" == *"not found"* ]]; then
    PRECHECK_RESULT="unavailable"
  else
    PRECHECK_RESULT="available"
  fi
elif [[ "$CMD_TRIMMED" =~ (^|[[:space:];|&])codex[[:space:]]+exec([[:space:]]|$) ]]; then
  MARKER_NAME=".codex-co-exploration-$PPID"
else
  exit 0
fi

source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"
source "${BASH_SOURCE[0]%/*}/lib/plan-state.sh"

CWD=$(hook_get_cwd)

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
ACTIVE_DIR="$PROJECT_ROOT/.temp/plan-mode/active"
[ -d "$ACTIVE_DIR" ] || exit 0

PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"
[ -f "$PLAN_UTILS" ] || exit 0

resolve_plan_dir() {
  local session_plan=""
  local dir_count=0
  local only_dir=""
  local dir=""
  local lock_pid=""

  session_plan=$(plan_resolve_session "$PROJECT_ROOT")
  if [ -n "$session_plan" ] && [ -f "$session_plan" ]; then
    dirname "$session_plan"
    return 0
  fi

  for dir in "$ACTIVE_DIR"/*; do
    [ -d "$dir" ] || continue
    dir_count=$((dir_count + 1))
    only_dir="$dir"
    if [ -f "$dir/.session-lock" ]; then
      lock_pid=$(cat "$dir/.session-lock" 2>/dev/null) || true
      if [ "$lock_pid" = "$PPID" ]; then
        echo "$dir"
        return 0
      fi
    fi
  done

  if [ "$dir_count" -eq 1 ] && [ -n "$only_dir" ]; then
    echo "$only_dir"
  fi
}

PLAN_DIR="$(resolve_plan_dir)"
[ -n "$PLAN_DIR" ] || exit 0
[ -d "$PLAN_DIR" ] || exit 0

PLAN_JSON="$PLAN_DIR/plan.json"

if [ -f "$PLAN_JSON" ]; then
  is_fresh=$(python3 "$PLAN_UTILS" is-fresh "$PLAN_JSON" 2>/dev/null) || true
  [ "$is_fresh" = "true" ] || exit 0
fi

MARKER_PATH="$PLAN_DIR/$MARKER_NAME"

if [ -n "$PRECHECK_RESULT" ]; then
  printf '%s\n' "$PRECHECK_RESULT" > "$MARKER_PATH" 2>/dev/null || true
else
  : > "$MARKER_PATH" 2>/dev/null || true
fi

exit 0
