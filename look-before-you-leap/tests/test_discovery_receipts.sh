#!/usr/bin/env bash
# Tests for discovery receipt infrastructure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RECEIPT_UTILS="${PLUGIN_ROOT}/scripts/receipt_utils.py"
DISCOVERY_SCRIPT="${PLUGIN_ROOT}/scripts/write-discovery-receipt.sh"

PASS=0
FAIL=0

fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { PASS=$((PASS + 1)); }

# Isolate state
ORIG_HOME="$HOME"
TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/discovery-test.XXXXXX")
export HOME="$TEST_HOME"
trap 'export HOME="$ORIG_HOME"; rm -rf "$TEST_HOME"' EXIT

python3 "$RECEIPT_UTILS" bootstrap >/dev/null 2>&1

# ============================================================
echo "=== Test: write-discovery-receipt.sh creates signed receipt ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/disc-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git"

OUTPUT=$(bash "$DISCOVERY_SCRIPT" "$TEST_ROOT" "my-plan" "complete" 2>&1) || true

if [[ "$OUTPUT" == *"Discovery receipt written"* ]]; then
  pass; echo "  PASS: script reports receipt written"
else
  fail "script did not report receipt written: $OUTPUT"
fi

# Verify receipt exists and is valid
PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null)
CHECK_RESULT=$(python3 "$RECEIPT_UTILS" check "discovery" "$PROJ_ID" "my-plan" 2>/dev/null) || CHECK_RESULT="MISSING"

if [[ "$CHECK_RESULT" == "EXISTS"* ]]; then
  pass; echo "  PASS: discovery receipt exists and is valid"
else
  fail "discovery receipt missing or invalid: $CHECK_RESULT"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: codex_status recorded in receipt ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/disc-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git"

bash "$DISCOVERY_SCRIPT" "$TEST_ROOT" "test-plan" "unavailable" >/dev/null 2>&1 || true

PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null)
STATE_ROOT="$TEST_HOME/.claude/look-before-you-leap/state"
RECEIPT_FILE=$(find "$STATE_ROOT/$PROJ_ID/test-plan" -name "discovery-default.json" 2>/dev/null | head -1)

if [ -n "$RECEIPT_FILE" ]; then
  STATUS=$(python3 -c "
import json
with open('$RECEIPT_FILE') as f:
    r = json.load(f)
print(r.get('data', {}).get('codexStatus', ''))
" 2>/dev/null)
  if [ "$STATUS" = "unavailable" ]; then
    pass; echo "  PASS: codexStatus=unavailable recorded"
  else
    fail "codexStatus not recorded correctly: $STATUS"
  fi
else
  fail "receipt file not found"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: Different codex statuses all produce valid receipts ==="
# ============================================================

for status in "complete" "unavailable" "skipped-user-override"; do
  TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/disc-test.XXXXXX")
  mkdir -p "$TEST_ROOT/.git"
  bash "$DISCOVERY_SCRIPT" "$TEST_ROOT" "plan-$status" "$status" >/dev/null 2>&1 || true
  PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null)
  CHECK=$(python3 "$RECEIPT_UTILS" check "discovery" "$PROJ_ID" "plan-$status" 2>/dev/null) || CHECK="MISSING"
  if [[ "$CHECK" == "EXISTS"* ]]; then
    pass; echo "  PASS: codexStatus=$status produces valid receipt"
  else
    fail "codexStatus=$status receipt failed: $CHECK"
  fi
  rm -rf "$TEST_ROOT"
done

# ============================================================
echo ""
echo "=== Test: Invalid codex_status rejected ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/disc-test.XXXXXX")
mkdir -p "$TEST_ROOT/.git"
OUTPUT=$(bash "$DISCOVERY_SCRIPT" "$TEST_ROOT" "bad-plan" "bogus-status" 2>&1) || true
if [[ "$OUTPUT" == *"ERROR"* ]] || [[ "$OUTPUT" == *"Invalid"* ]]; then
  pass; echo "  PASS: bogus codex_status rejected"
else
  fail "bogus codex_status was accepted: $OUTPUT"
fi
rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: Syntax check ==="
# ============================================================

bash -n "$DISCOVERY_SCRIPT" 2>/dev/null
if [ $? -eq 0 ]; then
  pass; echo "  PASS: write-discovery-receipt.sh syntax OK"
else
  fail "write-discovery-receipt.sh syntax error"
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
