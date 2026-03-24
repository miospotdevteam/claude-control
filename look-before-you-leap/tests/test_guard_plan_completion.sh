#!/usr/bin/env bash
# Tests for guard-plan-completion.sh and verify-plan-on-stop.sh receipt checks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUARD_HOOK="${PLUGIN_ROOT}/hooks/guard-plan-completion.sh"
STOP_HOOK="${PLUGIN_ROOT}/hooks/verify-plan-on-stop.sh"

PASS=0
FAIL=0
HOOK_OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/guard-plan-out.XXXXXX")
trap 'rm -f "$HOOK_OUT_FILE"' EXIT

fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { PASS=$((PASS + 1)); }

assert_allowed() {
  local desc="$1"
  local output
  output=$(cat "$HOOK_OUT_FILE")
  if [[ "$output" == *'"deny"'* ]] || [[ "$output" == *'"block"'* ]]; then
    fail "$desc — expected allow, got deny/block: $output"
  else
    pass; echo "  PASS: $desc"
  fi
}

assert_denied() {
  local desc="$1"
  local output
  output=$(cat "$HOOK_OUT_FILE")
  if [[ "$output" == *'"deny"'* ]] || [[ "$output" == *'"block"'* ]]; then
    pass; echo "  PASS: $desc"
  else
    fail "$desc — expected deny/block, got allow"
  fi
}

# ============================================================
echo "=== Test: guard-plan-completion allows legacy plan with all done ==="
# ============================================================

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/guard-plan.XXXXXX")
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode/active/test-plan" "$ROOT/.temp/plan-mode/completed"

cat > "$ROOT/.temp/plan-mode/active/test-plan/plan.json" << 'JSON'
{
  "name": "test-plan",
  "title": "Test",
  "status": "active",
  "steps": [{"id": 1, "title": "t", "status": "done", "result": "Done.", "progress": [{"task": "t", "status": "done", "files": []}]}],
  "blocked": [],
  "completedSummary": [],
  "deviations": []
}
JSON
cat > "$ROOT/.temp/plan-mode/active/test-plan/masterPlan.md" << 'MD'
# Plan
- [x] Step 1
MD

CMD="mv $ROOT/.temp/plan-mode/active/test-plan $ROOT/.temp/plan-mode/completed/test-plan"
echo "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"$CMD\"}, \"cwd\": \"$ROOT\"}" | bash "$GUARD_HOOK" > "$HOOK_OUT_FILE" 2>/dev/null || true
assert_allowed "legacy plan with all done"

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: guard-plan-completion denies plan with pending steps ==="
# ============================================================

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/guard-plan.XXXXXX")
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode/active/test-plan" "$ROOT/.temp/plan-mode/completed"

cat > "$ROOT/.temp/plan-mode/active/test-plan/plan.json" << 'JSON'
{
  "name": "test-plan",
  "title": "Test",
  "status": "active",
  "steps": [
    {"id": 1, "title": "t", "status": "done", "result": "Done.", "progress": []},
    {"id": 2, "title": "t2", "status": "pending", "progress": []}
  ],
  "blocked": [],
  "completedSummary": [],
  "deviations": []
}
JSON
cat > "$ROOT/.temp/plan-mode/active/test-plan/masterPlan.md" << 'MD'
# Plan
- [x] Step 1
- [ ] Step 2
MD

CMD="mv $ROOT/.temp/plan-mode/active/test-plan $ROOT/.temp/plan-mode/completed/test-plan"
echo "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"$CMD\"}, \"cwd\": \"$ROOT\"}" | bash "$GUARD_HOOK" > "$HOOK_OUT_FILE" 2>/dev/null || true
assert_denied "plan with pending steps"

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: Syntax checks ==="
# ============================================================

bash -n "$GUARD_HOOK" 2>/dev/null && pass && echo "  PASS: guard-plan-completion.sh syntax" || fail "guard syntax"
bash -n "$STOP_HOOK" 2>/dev/null && pass && echo "  PASS: verify-plan-on-stop.sh syntax" || fail "stop syntax"

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
