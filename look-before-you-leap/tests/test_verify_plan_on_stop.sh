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
echo "=== Test: Allows stop when plan has only pending steps ==="
# ============================================================
# Hook only blocks on in_progress steps (lost-work risk).
# Pending steps haven't started — no progress to lose.

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
assert_allowed "only pending steps allows stop"
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
echo "=== Test: Allows stop when in-progress step has live Codex marker ==="
# ============================================================

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stop-test.XXXXXX")
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode/active/test-plan"
cat > "$ROOT/.temp/plan-mode/active/test-plan/plan.json" << 'JSON'
{
  "name": "test-plan", "title": "Test", "status": "active",
  "steps": [{"id": 1, "title": "t", "status": "in_progress", "result": null, "progress": []}],
  "blocked": [], "completedSummary": [], "deviations": []
}
JSON
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.session-lock"
# Write a live PID marker (use our own PID — guaranteed alive)
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.codex-inflight-step-1.pid"
cd "$ROOT"
run_hook '{"stop_hook_active": false, "cwd": "'"$ROOT"'"}'
assert_allowed "in-progress step with live Codex marker allows stop"
cd "$SCRIPT_DIR"
rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: Blocks stop when in-progress step has no Codex marker ==="
# ============================================================

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stop-test.XXXXXX")
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode/active/test-plan"
cat > "$ROOT/.temp/plan-mode/active/test-plan/plan.json" << 'JSON'
{
  "name": "test-plan", "title": "Test", "status": "active",
  "steps": [{"id": 1, "title": "t", "status": "in_progress", "result": null, "progress": []}],
  "blocked": [], "completedSummary": [], "deviations": []
}
JSON
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.session-lock"
cd "$ROOT"
run_hook '{"stop_hook_active": false, "cwd": "'"$ROOT"'"}'
assert_blocked "in-progress step without Codex marker blocks stop"
cd "$SCRIPT_DIR"
rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: Blocks stop when Codex marker has dead PID ==="
# ============================================================

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stop-test.XXXXXX")
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode/active/test-plan"
cat > "$ROOT/.temp/plan-mode/active/test-plan/plan.json" << 'JSON'
{
  "name": "test-plan", "title": "Test", "status": "active",
  "steps": [{"id": 1, "title": "t", "status": "in_progress", "result": null, "progress": []}],
  "blocked": [], "completedSummary": [], "deviations": []
}
JSON
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.session-lock"
# Write a marker with a dead PID
echo "999999" > "$ROOT/.temp/plan-mode/active/test-plan/.codex-inflight-step-1.pid"
cd "$ROOT"
run_hook '{"stop_hook_active": false, "cwd": "'"$ROOT"'"}'
assert_blocked "dead Codex PID marker blocks stop"
cd "$SCRIPT_DIR"
rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: Blocks stop when one of two in-progress steps has no marker ==="
# ============================================================

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stop-test.XXXXXX")
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode/active/test-plan"
cat > "$ROOT/.temp/plan-mode/active/test-plan/plan.json" << 'JSON'
{
  "name": "test-plan", "title": "Test", "status": "active",
  "steps": [
    {"id": 1, "title": "t1", "status": "in_progress", "result": null, "progress": []},
    {"id": 2, "title": "t2", "status": "in_progress", "result": null, "progress": []}
  ],
  "blocked": [], "completedSummary": [], "deviations": []
}
JSON
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.session-lock"
# Only step 1 has a live marker — step 2 has none
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.codex-inflight-step-1.pid"
cd "$ROOT"
run_hook '{"stop_hook_active": false, "cwd": "'"$ROOT"'"}'
assert_blocked "partial Codex markers blocks stop"
cd "$SCRIPT_DIR"
rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: Step ID prefix collision does not cause false allow ==="
# ============================================================
# Step 1 is in-progress with no marker. Step 10 has a live marker.
# The glob must NOT match step-10's marker for step 1.

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stop-test.XXXXXX")
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode/active/test-plan"
cat > "$ROOT/.temp/plan-mode/active/test-plan/plan.json" << 'JSON'
{
  "name": "test-plan", "title": "Test", "status": "active",
  "steps": [
    {"id": 1, "title": "t1", "status": "in_progress", "result": null, "progress": []},
    {"id": 10, "title": "t10", "status": "in_progress", "result": null, "progress": []}
  ],
  "blocked": [], "completedSummary": [], "deviations": []
}
JSON
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.session-lock"
# Only step 10 has a marker — step 1 does NOT
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.codex-inflight-step-10.pid"
cd "$ROOT"
run_hook '{"stop_hook_active": false, "cwd": "'"$ROOT"'"}'
assert_blocked "step-1 vs step-10 prefix collision blocks correctly"
cd "$SCRIPT_DIR"
rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: Syntax check ==="
# ============================================================

bash -n "$HOOK" 2>/dev/null && pass && echo "  PASS: syntax OK" || fail "syntax error"

# ============================================================
echo ""
echo "=== Test: Strict done step without receipt blocks stop ==="
# ============================================================

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stop-test.XXXXXX")
HOME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/stop-home.XXXXXX")
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode/active/test-plan"
cat > "$ROOT/.temp/plan-mode/active/test-plan/plan.json" << 'JSON'
{
  "name": "test-plan", "title": "Test", "status": "active", "_receiptMode": "strict",
  "steps": [
    {
      "id": 1,
      "title": "t",
      "status": "done",
      "owner": "claude",
      "mode": "claude-impl",
      "result": "Completed.",
      "progress": []
    }
  ],
  "blocked": [], "completedSummary": [], "deviations": []
}
JSON
echo "$$" > "$ROOT/.temp/plan-mode/active/test-plan/.session-lock"
cd "$ROOT"
HOME="$HOME_DIR" run_hook '{"stop_hook_active": false, "cwd": "'"$ROOT"'"}'
assert_blocked "strict done step without receipt blocks stop"
cd "$SCRIPT_DIR"
rm -rf "$ROOT" "$HOME_DIR"

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
