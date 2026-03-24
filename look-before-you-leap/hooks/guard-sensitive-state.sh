#!/usr/bin/env bash
# PreToolUse hook: Block direct access to the receipt state root.
#
# Prevents Claude from reading or modifying the HMAC secret key and
# receipt files directly. Only plugin-owned scripts (under
# $CLAUDE_PLUGIN_ROOT) are allowed to access state via receipt_utils.py.
#
# Blocks:
#   - Read of any file under ~/.claude/look-before-you-leap/state/
#   - Edit/Write to any file under the state root
#   - Bash commands that read (cat, head, less) or modify files in the state root
#
# Allows:
#   - Bash commands that invoke plugin-owned scripts (they access state
#     internally via receipt_utils.py)
#
# Input: JSON on stdin with tool_name, tool_input, cwd

set -euo pipefail

STATE_ROOT="${HOME}/.claude/look-before-you-leap/state"

# Quick exit if state root doesn't exist yet
[ -d "$STATE_ROOT" ] || exit 0

INPUT=$(cat)

# Extract tool name
TOOL_NAME=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_name', ''))
" <<< "$INPUT" 2>/dev/null) || true

[ -z "$TOOL_NAME" ] && exit 0

normalize_path() {
  # Expand ~ to $HOME and resolve common path forms
  local p="$1"
  # Replace leading ~ with $HOME
  if [[ "$p" == "~/"* ]]; then
    p="${HOME}${p#\~}"
  elif [[ "$p" == "~" ]]; then
    p="$HOME"
  fi
  echo "$p"
}

is_state_path() {
  local p
  p=$(normalize_path "$1")
  [[ -n "$p" && "$p" == "$STATE_ROOT"* ]]
}

deny() {
  local reason="$1"
  python3 -c "
import json, sys
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': sys.argv[1]
    }
}
json.dump(output, sys.stdout)
" "$reason"
  exit 0
}

# --- Check Read tool ---
if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null) || true

  if is_state_path "$FILE_PATH"; then
    deny "BLOCKED: Direct read of receipt state files is not allowed. The state root at ${STATE_ROOT} contains the HMAC secret and signed receipts. Only plugin-owned scripts may access these files."
  fi
fi

# --- Check Edit/Write tools ---
if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
  FILE_PATH=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null) || true

  if is_state_path "$FILE_PATH"; then
    deny "BLOCKED: Direct modification of receipt state files is not allowed. The state root at ${STATE_ROOT} is managed by plugin scripts only. Do not attempt to edit, write, or create files here."
  fi
fi

# --- Check Bash tool ---
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('command', ''))
" <<< "$INPUT" 2>/dev/null) || true

  [ -z "$COMMAND" ] && exit 0

  # FIRST: Block any command that references the state root path,
  # regardless of whether it also invokes plugin scripts. This prevents
  # "plugin-script > state-root/secret.key" redirect bypasses.
  # Block commands that reference the state root path
  if [[ "$COMMAND" == *"$STATE_ROOT"* ]] || \
     [[ "$COMMAND" == *"look-before-you-leap/state"* ]]; then
    deny "BLOCKED: Bash command references the receipt state root. Direct access to ${STATE_ROOT} is not allowed. Use plugin-provided scripts (receipt_utils.py) to interact with receipts."
  fi
fi

# All other tools — allow
exit 0
