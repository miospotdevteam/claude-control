#!/usr/bin/env bash
# Tests for approval receipt infrastructure:
# - /bypass command (grant-bypass.sh)
# - capture-user-override.sh (UserPromptSubmit hook)
# - enforce-plan.sh receipt-based bypass check
# - clear-handoff-on-approval.sh receipt minting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RECEIPT_UTILS="${PLUGIN_ROOT}/scripts/receipt_utils.py"

PASS=0
FAIL=0

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  PASS=$((PASS + 1))
}

# Use a temp state root for isolation
ORIG_HOME="$HOME"
TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/approval-test-home.XXXXXX")
export HOME="$TEST_HOME"
trap 'export HOME="$ORIG_HOME"; rm -rf "$TEST_HOME"' EXIT

# Bootstrap state in test home
python3 "$RECEIPT_UTILS" bootstrap >/dev/null 2>&1

# ============================================================
echo "=== Test: grant-bypass.sh writes signed receipt ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode"

# Run grant-bypass.sh from within the test root so find_project_root works
GRANT_SCRIPT="${PLUGIN_ROOT}/scripts/grant-bypass.sh"
ORIG_DIR="$PWD"
cd "$TEST_ROOT"
OUTPUT=$(bash "$GRANT_SCRIPT" 5 2>&1) || true
cd "$ORIG_DIR"

if [[ "$OUTPUT" == *"Bypass granted"* ]]; then
  pass
  echo "  PASS: grant-bypass.sh writes receipt"
else
  fail "grant-bypass.sh did not produce expected output: $OUTPUT"
fi

# Verify receipt exists
PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null) || true
STATE_ROOT="$TEST_HOME/.claude/look-before-you-leap/state"

if [ -d "$STATE_ROOT/$PROJ_ID" ]; then
  RECEIPT_FILE=$(find "$STATE_ROOT/$PROJ_ID" -name "bypass-default.json" 2>/dev/null | head -1)
  if [ -n "$RECEIPT_FILE" ]; then
    VERIFY_RESULT=$(python3 "$RECEIPT_UTILS" verify "$RECEIPT_FILE" 2>/dev/null) || true
    if [[ "$VERIFY_RESULT" == "VALID"* ]]; then
      pass
      echo "  PASS: bypass receipt is valid"
    else
      fail "bypass receipt is invalid: $VERIFY_RESULT"
    fi
  else
    fail "no bypass receipt found in state"
  fi
else
  fail "no project dir in state root"
fi

# Verify legacy marker also written (PPID varies in subshell, check any .no-plan-*)
NO_PLAN_COUNT=$(find "$TEST_ROOT/.temp/plan-mode" -name ".no-plan-*" 2>/dev/null | wc -l | tr -d ' ')
if [ "$NO_PLAN_COUNT" -gt 0 ]; then
  pass
  echo "  PASS: legacy .no-plan marker also written"
else
  fail "legacy .no-plan marker not written"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: capture-user-override.sh mints receipt on override phrases ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode"
# Need to be in the test root for find_project_root
cd "$TEST_ROOT"

HOOK="${PLUGIN_ROOT}/hooks/capture-user-override.sh"

# Test "just do it" phrase
echo '{"prompt": "just do it, no plan needed"}' | bash "$HOOK" 2>/dev/null || true

if [ -f "$TEST_ROOT/.temp/plan-mode/.no-plan-$$" ]; then
  pass
  echo "  PASS: 'just do it' creates legacy marker"
else
  fail "'just do it' did not create legacy marker"
fi

rm -f "$TEST_ROOT/.temp/plan-mode/.no-plan-$$"

# Test "bypass" phrase
echo '{"prompt": "bypass"}' | bash "$HOOK" 2>/dev/null || true

if [ -f "$TEST_ROOT/.temp/plan-mode/.no-plan-$$" ]; then
  pass
  echo "  PASS: 'bypass' creates legacy marker"
else
  fail "'bypass' did not create legacy marker"
fi

rm -f "$TEST_ROOT/.temp/plan-mode/.no-plan-$$"

# Test non-override phrase — should NOT create marker
echo '{"prompt": "please write the code"}' | bash "$HOOK" 2>/dev/null || true

if [ ! -f "$TEST_ROOT/.temp/plan-mode/.no-plan-$$" ]; then
  pass
  echo "  PASS: non-override phrase does not create marker"
else
  fail "non-override phrase created marker"
fi

cd "$SCRIPT_DIR"
rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: Receipt tampering detected ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode"

PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null)
RECEIPT_PATH=$(python3 "$RECEIPT_UTILS" sign "bypass" "$PROJ_ID" "test-plan" 2>/dev/null)

# Tamper with the receipt
python3 -c "
import json
with open('$RECEIPT_PATH') as f:
    r = json.load(f)
r['type'] = 'codex_verify'
with open('$RECEIPT_PATH', 'w') as f:
    json.dump(r, f)
" 2>/dev/null

VERIFY=$(python3 "$RECEIPT_UTILS" verify "$RECEIPT_PATH" 2>/dev/null) || VERIFY="INVALID"

if [[ "$VERIFY" == "INVALID"* ]]; then
  pass
  echo "  PASS: tampered receipt detected as invalid"
else
  fail "tampered receipt was not detected"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: hooks.json is valid JSON ==="
# ============================================================

python3 -m json.tool "${PLUGIN_ROOT}/hooks/hooks.json" >/dev/null 2>&1
if [ $? -eq 0 ]; then
  pass
  echo "  PASS: hooks.json is valid JSON"
else
  fail "hooks.json is not valid JSON"
fi

# ============================================================
echo ""
echo "=== Test: capture-user-override.sh registered in hooks.json ==="
# ============================================================

if grep -q "capture-user-override.sh" "${PLUGIN_ROOT}/hooks/hooks.json"; then
  pass
  echo "  PASS: capture-user-override.sh in hooks.json"
else
  fail "capture-user-override.sh not in hooks.json"
fi

# ============================================================
echo ""
echo "=== Test: Session start does NOT auto-clear handoff ==="
# ============================================================

# Check that session-start.sh no longer has rm -f handoff-pending
if grep -q 'rm -f.*\.handoff-pending' "${PLUGIN_ROOT}/hooks/session-start.sh"; then
  fail "session-start.sh still auto-clears handoff"
else
  pass
  echo "  PASS: session-start.sh does not auto-clear handoff"
fi

# Check post-compact.sh
if grep -q 'rm -f.*\.handoff-pending' "${PLUGIN_ROOT}/hooks/post-compact.sh"; then
  fail "post-compact.sh still auto-clears handoff"
else
  pass
  echo "  PASS: post-compact.sh does not auto-clear handoff"
fi

# ============================================================
echo ""
echo "=== Test: verify-bypass CLI — live session valid ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode"
PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null)
# Sign a bypass with our PID as session
RECEIPT_PATH=$(python3 "$RECEIPT_UTILS" sign "bypass" "$PROJ_ID" "test-plan" "session=$$" 2>/dev/null)

VERIFY_OUT=$(python3 "$RECEIPT_UTILS" verify-bypass "$RECEIPT_PATH" "$$" 2>/dev/null) || true
if [[ "$VERIFY_OUT" == "VALID" ]]; then
  pass
  echo "  PASS: verify-bypass returns VALID for live matching session"
else
  fail "verify-bypass returned '$VERIFY_OUT' instead of VALID"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: verify-bypass CLI — dead PID returns STALE ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode"
PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null)
RECEIPT_PATH=$(python3 "$RECEIPT_UTILS" sign "bypass" "$PROJ_ID" "test-plan" "session=99999" 2>/dev/null)

VERIFY_OUT=$(python3 "$RECEIPT_UTILS" verify-bypass "$RECEIPT_PATH" "99999" 2>/dev/null) || true
if [[ "$VERIFY_OUT" == "STALE" ]]; then
  pass
  echo "  PASS: verify-bypass returns STALE for dead PID"
else
  fail "verify-bypass returned '$VERIFY_OUT' instead of STALE"
fi

# Verify receipt was auto-deleted
if [ ! -f "$RECEIPT_PATH" ]; then
  pass
  echo "  PASS: stale receipt auto-deleted"
else
  fail "stale receipt was NOT auto-deleted"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: verify-bypass CLI — wrong session returns STALE ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode"
PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null)
# Sign with PID 1 (always alive) but verify with our PID
RECEIPT_PATH=$(python3 "$RECEIPT_UTILS" sign "bypass" "$PROJ_ID" "test-plan" "session=1" 2>/dev/null)

VERIFY_OUT=$(python3 "$RECEIPT_UTILS" verify-bypass "$RECEIPT_PATH" "$$" 2>/dev/null) || true
if [[ "$VERIFY_OUT" == "STALE" ]]; then
  pass
  echo "  PASS: verify-bypass returns STALE for wrong session"
else
  fail "verify-bypass returned '$VERIFY_OUT' instead of STALE"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: verify-bypass CLI — maxEdits consumed ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode"
PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null)
RECEIPT_PATH=$(python3 "$RECEIPT_UTILS" sign "bypass" "$PROJ_ID" "test-plan" "session=$$" "maxEdits=1" 2>/dev/null)

# First call: VALID (last allowed edit)
VERIFY_OUT=$(python3 "$RECEIPT_UTILS" verify-bypass "$RECEIPT_PATH" "$$" 2>/dev/null) || true
if [[ "$VERIFY_OUT" == "VALID" ]]; then
  pass
  echo "  PASS: maxEdits=1 first call returns VALID"
else
  fail "maxEdits=1 first call returned '$VERIFY_OUT' instead of VALID"
fi

# Second call: CONSUMED
VERIFY_OUT=$(python3 "$RECEIPT_UTILS" verify-bypass "$RECEIPT_PATH" "$$" 2>/dev/null) || true
if [[ "$VERIFY_OUT" == "CONSUMED" ]]; then
  pass
  echo "  PASS: maxEdits=1 second call returns CONSUMED"
else
  fail "maxEdits=1 second call returned '$VERIFY_OUT' instead of CONSUMED"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: enforce-plan.sh denies with stale bypass receipt ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode"
PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null)
# Create bypass receipt with dead PID session
RECEIPT_PATH=$(python3 "$RECEIPT_UTILS" sign "bypass" "$PROJ_ID" "stale-plan" "session=99999" 2>/dev/null)

HOOK_INPUT=$(python3 -c "
import json
print(json.dumps({
    'tool_name': 'Edit',
    'tool_input': {'file_path': '$TEST_ROOT/src/foo.ts'},
    'cwd': '$TEST_ROOT'
}))
")

HOOK_RESULT=$(echo "$HOOK_INPUT" | bash "${PLUGIN_ROOT}/hooks/enforce-plan.sh" 2>/dev/null) || true

if echo "$HOOK_RESULT" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
decision = data.get('hookSpecificOutput', {}).get('permissionDecision', '')
sys.exit(0 if decision == 'deny' else 1)
" 2>/dev/null; then
  pass
  echo "  PASS: enforce-plan.sh denies with stale bypass receipt"
else
  fail "enforce-plan.sh did not deny with stale bypass"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: enforce-plan.sh allows with live matching bypass receipt ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode"
PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null)
# Create bypass receipt with our PID as session
RECEIPT_PATH=$(python3 "$RECEIPT_UTILS" sign "bypass" "$PROJ_ID" "live-plan" "session=$$" 2>/dev/null)

HOOK_INPUT=$(python3 -c "
import json
print(json.dumps({
    'tool_name': 'Edit',
    'tool_input': {'file_path': '$TEST_ROOT/src/foo.ts'},
    'cwd': '$TEST_ROOT'
}))
")

HOOK_EXIT=0
echo "$HOOK_INPUT" | bash "${PLUGIN_ROOT}/hooks/enforce-plan.sh" >/dev/null 2>&1 || HOOK_EXIT=$?

if [ "$HOOK_EXIT" -eq 0 ]; then
  pass
  echo "  PASS: enforce-plan.sh allows with live matching bypass receipt"
else
  fail "enforce-plan.sh denied with live bypass (exit=$HOOK_EXIT)"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: guard-filesystem-mutation.sh denies file_write with stale bypass ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode"
PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null)
# Create bypass receipt with dead PID session
RECEIPT_PATH=$(python3 "$RECEIPT_UTILS" sign "bypass" "$PROJ_ID" "stale-plan" "session=99999" 2>/dev/null)

HOOK_INPUT=$(python3 -c "
import json
print(json.dumps({
    'tool_name': 'Bash',
    'tool_input': {'command': 'echo hello > $TEST_ROOT/output.txt'},
    'cwd': '$TEST_ROOT'
}))
")

HOOK_RESULT=$(echo "$HOOK_INPUT" | bash "${PLUGIN_ROOT}/hooks/guard-filesystem-mutation.sh" 2>/dev/null) || true

if echo "$HOOK_RESULT" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
decision = data.get('hookSpecificOutput', {}).get('permissionDecision', '')
sys.exit(0 if decision == 'deny' else 1)
" 2>/dev/null; then
  pass
  echo "  PASS: guard-filesystem-mutation.sh denies file_write with stale bypass"
else
  fail "guard-filesystem-mutation.sh did not deny file_write with stale bypass"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: guard-handoff-background.sh registered in hooks.json ==="
# ============================================================

if grep -q "guard-handoff-background.sh" "${PLUGIN_ROOT}/hooks/hooks.json"; then
  pass
  echo "  PASS: guard-handoff-background.sh in hooks.json"
else
  fail "guard-handoff-background.sh not in hooks.json"
fi

# Verify it's a PreToolUse hook on EnterPlanMode
if python3 -c "
import json
with open('${PLUGIN_ROOT}/hooks/hooks.json') as f:
    h = json.load(f)
for entry in h['hooks'].get('PreToolUse', []):
    if entry.get('matcher') == 'EnterPlanMode':
        for hook in entry.get('hooks', []):
            if 'guard-handoff-background' in hook.get('command', ''):
                exit(0)
exit(1)
" 2>/dev/null; then
  pass
  echo "  PASS: guard-handoff-background.sh registered as PreToolUse on EnterPlanMode"
else
  fail "guard-handoff-background.sh not correctly registered"
fi

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
