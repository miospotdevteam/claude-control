#!/usr/bin/env bash
# Tests for guard-sensitive-state.sh PreToolUse hook
#
# Tests that direct access to the receipt state root is blocked
# while plugin-owned scripts are allowed through.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/guard-sensitive-state.sh"
STATE_ROOT="${HOME}/.claude/look-before-you-leap/state"

PASS=0
FAIL=0
HOOK_OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/guard-state-out.XXXXXX")
trap 'rm -f "$HOOK_OUT_FILE"' EXIT

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  PASS=$((PASS + 1))
}

assert_allowed() {
  local desc="$1"
  local output
  output=$(cat "$HOOK_OUT_FILE")
  if [[ "$output" == *'"permissionDecision"'*'"deny"'* ]]; then
    fail "$desc — expected allow, got deny"
  else
    pass
    echo "  PASS: $desc"
  fi
}

assert_denied() {
  local desc="$1"
  local output
  output=$(cat "$HOOK_OUT_FILE")
  if [[ "$output" == *'"permissionDecision"'*'"deny"'* ]]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc — expected deny, got allow"
  fi
}

run_hook() {
  local json_input="$1"
  : > "$HOOK_OUT_FILE"
  echo "$json_input" | bash "$HOOK" > "$HOOK_OUT_FILE" 2>/dev/null || true
}

# Ensure state root exists for tests
mkdir -p "$STATE_ROOT"

# ============================================================
echo "=== Test: Read of secret.key denied ==="
# ============================================================

run_hook '{"tool_name": "Read", "tool_input": {"file_path": "'"$STATE_ROOT"'/secret.key"}, "cwd": "/tmp"}'
assert_denied "Read secret.key"

# ============================================================
echo ""
echo "=== Test: Read of receipt file denied ==="
# ============================================================

run_hook '{"tool_name": "Read", "tool_input": {"file_path": "'"$STATE_ROOT"'/abc123/my-plan/bypass-default.json"}, "cwd": "/tmp"}'
assert_denied "Read receipt file"

# ============================================================
echo ""
echo "=== Test: Edit of receipt file denied ==="
# ============================================================

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$STATE_ROOT"'/abc123/my-plan/bypass-default.json"}, "cwd": "/tmp"}'
assert_denied "Edit receipt file"

# ============================================================
echo ""
echo "=== Test: Write to state root denied ==="
# ============================================================

run_hook '{"tool_name": "Write", "tool_input": {"file_path": "'"$STATE_ROOT"'/secret.key"}, "cwd": "/tmp"}'
assert_denied "Write to secret.key"

# ============================================================
echo ""
echo "=== Test: Bash cat of secret.key denied ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "cat '"$STATE_ROOT"'/secret.key"}, "cwd": "/tmp"}'
assert_denied "Bash cat secret.key"

# ============================================================
echo ""
echo "=== Test: Bash with state root path denied ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "ls '"$STATE_ROOT"'"}, "cwd": "/tmp"}'
assert_denied "Bash ls state root"

# ============================================================
echo ""
echo "=== Test: Bash with look-before-you-leap/state path denied ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "cat ~/.claude/look-before-you-leap/state/secret.key"}, "cwd": "/tmp"}'
assert_denied "Bash with relative state path"

# ============================================================
echo ""
echo "=== Test: Plugin scripts allowed ==="
# ============================================================

export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "python3 '"$PLUGIN_ROOT"'/scripts/receipt_utils.py bootstrap"}, "cwd": "/tmp"}'
assert_allowed "Plugin script via CLAUDE_PLUGIN_ROOT"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "bash '"$PLUGIN_ROOT"'/scripts/some-script.sh arg1"}, "cwd": "/tmp"}'
assert_allowed "Bash plugin script via CLAUDE_PLUGIN_ROOT"

# Arbitrary-path script accessing state root should be DENIED
run_hook '{"tool_name": "Bash", "tool_input": {"command": "python3 /tmp/receipt_utils.py && cat '"$STATE_ROOT"'/secret.key"}, "cwd": "/tmp"}'
assert_denied "Arbitrary script accessing state root denied"

# Compound command with plugin root should be DENIED
run_hook '{"tool_name": "Bash", "tool_input": {"command": "echo '"$PLUGIN_ROOT"' && cat '"$STATE_ROOT"'/secret.key"}, "cwd": "/tmp"}'
assert_denied "Compound command with plugin root denied"

# Plugin root substring spoof should be DENIED
run_hook '{"tool_name": "Bash", "tool_input": {"command": "python3 '"$PLUGIN_ROOT"'-evil/scripts/receipt_utils.py check && cat '"$STATE_ROOT"'/secret.key"}, "cwd": "/tmp"}'
assert_denied "Plugin root substring spoof denied"

# Plugin script with redirect into state root should be DENIED
run_hook '{"tool_name": "Bash", "tool_input": {"command": "python3 '"$PLUGIN_ROOT"'/scripts/receipt_utils.py bootstrap > '"$STATE_ROOT"'/secret.key"}, "cwd": "/tmp"}'
assert_denied "Plugin script redirecting to state root denied"

unset CLAUDE_PLUGIN_ROOT

# ============================================================
echo ""
echo "=== Test: Tilde paths also blocked ==="
# ============================================================

run_hook '{"tool_name": "Read", "tool_input": {"file_path": "~/.claude/look-before-you-leap/state/secret.key"}, "cwd": "/tmp"}'
assert_denied "Read secret.key via ~ path"

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "~/.claude/look-before-you-leap/state/proj/plan/bypass-default.json"}, "cwd": "/tmp"}'
assert_denied "Edit receipt via ~ path"

run_hook '{"tool_name": "Write", "tool_input": {"file_path": "~/.claude/look-before-you-leap/state/secret.key"}, "cwd": "/tmp"}'
assert_denied "Write secret.key via ~ path"

# ============================================================
echo ""
echo "=== Test: Read of non-state files allowed ==="
# ============================================================

run_hook '{"tool_name": "Read", "tool_input": {"file_path": "/tmp/somefile.txt"}, "cwd": "/tmp"}'
assert_allowed "Read normal file"

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "/tmp/somefile.txt"}, "cwd": "/tmp"}'
assert_allowed "Edit normal file"

# ============================================================
echo ""
echo "=== Test: Bash commands not referencing state allowed ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "echo hello"}, "cwd": "/tmp"}'
assert_allowed "Normal bash command"

# ============================================================
echo ""
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
fi
echo "ALL TESTS PASSED"
