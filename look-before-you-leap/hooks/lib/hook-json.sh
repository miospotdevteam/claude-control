#!/usr/bin/env bash
# Shared library for hook JSON input parsing and output emission.
#
# Usage: source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
#
# After sourcing, call hook_read_input to capture stdin, then use
# the getter functions to extract fields. Use the emit functions
# to produce JSON output for Claude Code.

# Read stdin into HOOK_INPUT. Must be called before any getter.
hook_read_input() {
  HOOK_INPUT=$(cat)
  INPUT="$HOOK_INPUT"  # backward compat: many hooks reference $INPUT in heredocs
}

# --- Field extraction (requires HOOK_INPUT to be set) ---

hook_get_cwd() {
  python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$HOOK_INPUT" 2>/dev/null || true
}

hook_get_tool_name() {
  python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_name', ''))
" <<< "$HOOK_INPUT" 2>/dev/null || true
}

hook_get_file_path() {
  python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$HOOK_INPUT" 2>/dev/null || true
}

hook_get_command() {
  python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('command', ''))
" <<< "$HOOK_INPUT" 2>/dev/null || true
}

hook_get_pattern() {
  python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('pattern', ''))
" <<< "$HOOK_INPUT" 2>/dev/null || true
}

hook_get_prompt() {
  python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
prompt = data.get('user_prompt')
if prompt is None:
    prompt = data.get('prompt', '')
print(prompt)
" <<< "$HOOK_INPUT" 2>/dev/null || true
}

hook_get_tool_result() {
  python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
result = data.get('tool_result', '')
if isinstance(result, str):
    print(result)
elif isinstance(result, (dict, list)):
    print(json.dumps(result))
else:
    print(str(result))
" <<< "$HOOK_INPUT" 2>/dev/null || true
}

# --- JSON output emission ---

hook_deny() {
  local reason="$1"
  python3 -c "
import json, sys
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': sys.stdin.read()
    }
}
json.dump(output, sys.stdout)
" <<< "$reason"
}

hook_allow_with_context() {
  local context="$1"
  local event="${2:-PostToolUse}"
  _HOOK_EVENT="$event" python3 -c "
import json, sys, os
output = {
    'hookSpecificOutput': {
        'hookEventName': os.environ['_HOOK_EVENT'],
        'additionalContext': sys.stdin.read()
    }
}
json.dump(output, sys.stdout)
" <<< "$context"
}
