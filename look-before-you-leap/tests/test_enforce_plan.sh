#!/usr/bin/env bash
# Tests for enforce-plan.sh plan.json immutability bypass handling.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/enforce-plan.sh"
RECEIPT_UTILS="${PLUGIN_ROOT}/scripts/receipt_utils.py"

PASS=0
FAIL=0
HOOK_OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/enforce-plan-out.XXXXXX")
ORIG_HOME="$HOME"
TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/enforce-plan-home.XXXXXX")
export HOME="$TEST_HOME"
trap 'export HOME="$ORIG_HOME"; rm -f "$HOOK_OUT_FILE"; rm -rf "$TEST_HOME"' EXIT

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
    fail "$desc — expected allow, got deny: $output"
  else
    pass
    echo "  PASS: $desc"
  fi
}

assert_denied_with_immutable_message() {
  local desc="$1"
  local output
  output=$(cat "$HOOK_OUT_FILE")
  if [[ "$output" == *'"permissionDecision"'*'"deny"'* &&
        "$output" == *"BLOCKED: plan.json is immutable after approval"* ]]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc — expected immutable-plan deny, got: $output"
  fi
}

make_root() {
  mktemp -d "${TMPDIR:-/tmp}/enforce-plan.XXXXXX"
}

write_started_plan() {
  local root="$1"
  mkdir -p "$root/.git" "$root/.temp/plan-mode/active/demo"
  cat > "$root/.temp/plan-mode/active/demo/plan.json" << 'JSON'
{
  "name": "demo",
  "title": "Demo",
  "context": "test",
  "status": "active",
  "steps": [
    {"id": 1, "title": "Started", "status": "in_progress", "progress": []}
  ],
  "blocked": [],
  "completedSummary": [],
  "deviations": []
}
JSON
}

make_input() {
  local tool_name="$1"
  local file_path="$2"
  local cwd="$3"
  python3 -c "
import json, sys
print(json.dumps({
    'tool_name': sys.argv[1],
    'tool_input': {'file_path': sys.argv[2]},
    'cwd': sys.argv[3],
}))
" "$tool_name" "$file_path" "$cwd"
}

run_hook() {
  local tool_name="$1"
  local file_path="$2"
  local cwd="$3"
  : > "$HOOK_OUT_FILE"
  make_input "$tool_name" "$file_path" "$cwd" | bash "$HOOK" > "$HOOK_OUT_FILE" 2>/dev/null || true
}

# ============================================================
echo "=== Test: plan.json edit denied without bypass ==="
# ============================================================

ROOT=$(make_root)
write_started_plan "$ROOT"
PLAN_JSON="$ROOT/.temp/plan-mode/active/demo/plan.json"

run_hook "Edit" "$PLAN_JSON" "$ROOT"
assert_denied_with_immutable_message "Edit plan.json without bypass denied"

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: signed bypass receipt allows plan.json edit and decrements budget ==="
# ============================================================

ROOT=$(make_root)
write_started_plan "$ROOT"
PLAN_JSON="$ROOT/.temp/plan-mode/active/demo/plan.json"
python3 "$RECEIPT_UTILS" bootstrap >/dev/null 2>&1
PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$ROOT" 2>/dev/null)
RECEIPT_PATH=$(python3 "$RECEIPT_UTILS" sign "bypass" "$PROJ_ID" "receipt-plan" "session=$$" "maxEdits=2" 2>/dev/null)

run_hook "Edit" "$PLAN_JSON" "$ROOT"
assert_allowed "Edit plan.json with signed bypass receipt allowed"

REMAINING_EDITS=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f)['data']['maxEdits'])
" "$RECEIPT_PATH")
if [ "$REMAINING_EDITS" = "1" ]; then
  pass
  echo "  PASS: signed bypass receipt budget decremented"
else
  fail "signed bypass receipt budget did not decrement (got '$REMAINING_EDITS')"
fi

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: legacy bypass allows one plan.json edit and decrements budget ==="
# ============================================================

ROOT=$(make_root)
write_started_plan "$ROOT"
PLAN_JSON="$ROOT/.temp/plan-mode/active/demo/plan.json"
NO_PLAN_FILE="$ROOT/.temp/plan-mode/.no-plan-$$"
echo "$$:2" > "$NO_PLAN_FILE"

run_hook "Edit" "$PLAN_JSON" "$ROOT"
assert_allowed "Edit plan.json with legacy bypass allowed"

MARKER_CONTENT=$(cat "$NO_PLAN_FILE" 2>/dev/null || true)
if [ "$MARKER_CONTENT" = "$$:1" ]; then
  pass
  echo "  PASS: legacy bypass budget decremented"
else
  fail "legacy bypass budget did not decrement (got '$MARKER_CONTENT')"
fi

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: final legacy bypass edit consumes marker ==="
# ============================================================

ROOT=$(make_root)
write_started_plan "$ROOT"
PLAN_JSON="$ROOT/.temp/plan-mode/active/demo/plan.json"
NO_PLAN_FILE="$ROOT/.temp/plan-mode/.no-plan-$$"
echo "$$:1" > "$NO_PLAN_FILE"

run_hook "Write" "$PLAN_JSON" "$ROOT"
assert_allowed "Write plan.json with final legacy bypass edit allowed"

if [ ! -f "$NO_PLAN_FILE" ]; then
  pass
  echo "  PASS: legacy bypass marker removed after final edit"
else
  fail "legacy bypass marker still exists after final edit"
fi

rm -rf "$ROOT"

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
