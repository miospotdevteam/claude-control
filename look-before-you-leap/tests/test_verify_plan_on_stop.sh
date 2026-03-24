#!/usr/bin/env bash
# Tests for verify-plan-on-stop.sh Stop hook

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/verify-plan-on-stop.sh"

PASS=0
FAIL=0
HOOK_OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/stop-hook-out.XXXXXX")
trap 'rm -f "$HOOK_OUT_FILE"' EXIT

fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { PASS=$((PASS + 1)); }

run_hook() {
  local json_input="$1"
  : > "$HOOK_OUT_FILE"
  echo "$json_input" | bash "$HOOK" > "$HOOK_OUT_FILE" 2>/dev/null || true
}

assert_allowed() {
  local desc="$1"
  local output
  output=$(cat "$HOOK_OUT_FILE")
  if [[ "$output" == *'"block"'* ]]; then
    fail "$desc — expected allow, got block"
  else
    pass; echo "  PASS: $desc"
  fi
}

assert_blocked() {
  local desc="$1"
  local output
  output=$(cat "$HOOK_OUT_FILE")
  if [[ "$output" == *'"block"'* ]]; then
    pass; echo "  PASS: $desc"
  else
    fail "$desc — expected block, got allow"
  fi
}

# ============================================================
echo "=== Test: Allows stop when no active plan ==="
# ============================================================

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stop-test.XXXXXX")
mkdir -p "$ROOT/.git"
cd "$ROOT"
run_hook '{"stop_hook_active": false, "cwd": "'"$ROOT"'"}'
assert_allowed "no active plan allows stop"
cd "$SCRIPT_DIR"
rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: Blocks stop when plan has pending steps ==="
# ============================================================

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stop-test.XXXXXX")
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode/active/test-plan"
cat > "$ROOT/.temp/plan-mode/active/test-plan/plan.json" << 'JSON'
{
  "name": "test-plan", "title": "Test", "status": "active",
  "steps": [
    {"id": 1, "title": "t", "status": "done", "result": "Done.", "progress": []},
    {"id": 2, "title": "t2", "status": "pending", "progress": []}
  ],
  "blocked": [], "completedSummary": [], "deviations": []
}
JSON
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.session-lock"
cd "$ROOT"
run_hook '{"stop_hook_active": false, "cwd": "'"$ROOT"'"}'
assert_blocked "pending steps blocks stop"
cd "$SCRIPT_DIR"
rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: Allows stop when all done with results ==="
# ============================================================

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stop-test.XXXXXX")
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode/active/test-plan"
cat > "$ROOT/.temp/plan-mode/active/test-plan/plan.json" << 'JSON'
{
  "name": "test-plan", "title": "Test", "status": "active",
  "steps": [{"id": 1, "title": "t", "status": "done", "result": "Completed.", "progress": []}],
  "blocked": [], "completedSummary": [], "deviations": []
}
JSON
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.session-lock"
cd "$ROOT"
run_hook '{"stop_hook_active": false, "cwd": "'"$ROOT"'"}'
assert_allowed "all done with results allows stop"
cd "$SCRIPT_DIR"
rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: Blocks stop when done step has no result ==="
# ============================================================

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stop-test.XXXXXX")
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode/active/test-plan"
cat > "$ROOT/.temp/plan-mode/active/test-plan/plan.json" << 'JSON'
{
  "name": "test-plan", "title": "Test", "status": "active",
  "steps": [{"id": 1, "title": "t", "status": "done", "result": null, "progress": []}],
  "blocked": [], "completedSummary": [], "deviations": []
}
JSON
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.session-lock"
cd "$ROOT"
run_hook '{"stop_hook_active": false, "cwd": "'"$ROOT"'"}'
assert_blocked "done step with no result blocks stop"
cd "$SCRIPT_DIR"
rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: Allows stop when stop_hook_active is true ==="
# ============================================================

run_hook '{"stop_hook_active": true, "cwd": "/tmp"}'
assert_allowed "stop_hook_active prevents loop"

# ============================================================
echo ""
echo "=== Test: Syntax check ==="
# ============================================================

bash -n "$HOOK" 2>/dev/null && pass && echo "  PASS: syntax OK" || fail "syntax error"

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
