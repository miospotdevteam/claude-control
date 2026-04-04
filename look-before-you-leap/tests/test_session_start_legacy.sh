#!/usr/bin/env bash
# Targeted behavioral tests for session-start.sh legacy plan detection.
#
# Tests the modified paths:
# 1. Variable initialization (set -u safety when plan_get_status returns empty)
# 2. Legacy next-step awk extraction (correct step reported)
# 3. Legacy active-step awk extraction

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"

PASS=0
FAIL=0

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  PASS=$((PASS + 1))
}

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/session-start-test.XXXXXX")
OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/session-start-output.XXXXXX")
trap 'rm -rf "$TEST_ROOT" "$OUTPUT_FILE"' EXIT

run_hook() {
  pushd "$TEST_ROOT" >/dev/null
  bash "$HOOK" > "$OUTPUT_FILE" 2>/dev/null || true
  popd >/dev/null
}

# ============================================================
echo "=== Test: plan.json plan detected and claimed ==="
# ============================================================

mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode/active/ss-test"
PLAN_DIR="$TEST_ROOT/.temp/plan-mode/active/ss-test"

cat > "$PLAN_DIR/plan.json" << 'JSONEOF'
{
  "name": "ss-test",
  "title": "Session Start Test",
  "context": "Test",
  "status": "active",
  "requiredSkills": [],
  "disciplines": [],
  "discovery": {"scope":"","entryPoints":"","consumers":"","existingPatterns":"","testInfrastructure":"","conventions":"","blastRadius":"","confidence":"high"},
  "steps": [
    {"id":1,"title":"Pending step","status":"pending","skill":"none","simplify":false,"codexVerify":true,"files":[],"description":"","acceptanceCriteria":"","progress":[{"task":"t","status":"pending","files":[]}],"subPlan":null,"result":null}
  ],
  "blocked": []
}
JSONEOF

python3 "$PLUGIN_ROOT/scripts/plan_utils.py" init-progress "$PLAN_DIR/plan.json" >/dev/null 2>&1

# No session lock — hook should auto-claim as orphan
run_hook

if python3 -c "
import json, sys
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
ctx = data.get('hookSpecificOutput', {}).get('additionalContext', '')
assert 'ACTIVE PLAN DETECTED' in ctx, 'Missing plan header'
assert 'ss-test' in ctx, 'Missing plan name'
assert 'Pending step' in ctx, 'Missing next step'
assert 'Respect step ownership exactly.' in ctx, 'Missing ownership reminder'
assert 'Independent verification is a gate.' in ctx, 'Missing verification reminder'
print('OK')
" 2>/dev/null | grep -q "OK"; then
  pass
  echo "  PASS: plan.json plan detected and auto-claimed"
else
  fail "plan.json detection failed. Tail: $(tail -5 "$OUTPUT_FILE")"
fi

# Verify session lock was written
if [ -f "$PLAN_DIR/.session-lock" ]; then
  pass
  echo "  PASS: session lock file created"
else
  fail "session lock file not created"
fi

# ============================================================
echo ""
echo "=== Test: Legacy next-step reports correct step ==="
# ============================================================

rm -rf "$TEST_ROOT/.temp/plan-mode/active/ss-test"
mkdir -p "$TEST_ROOT/.temp/plan-mode/active/legacy-ss"
LEGACY_DIR="$TEST_ROOT/.temp/plan-mode/active/legacy-ss"

cat > "$LEGACY_DIR/masterPlan.md" << 'MDEOF'
# Test Plan

### Step 1: Done step
- [x] Completed

### Step 2: Next step
- [ ] Pending
MDEOF

run_hook

if python3 -c "
import json, sys
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
ctx = data.get('hookSpecificOutput', {}).get('additionalContext', '')
assert 'NEXT: Step 2: Next step' in ctx, f'Wrong next step in context'
print('OK')
" 2>/dev/null | grep -q "OK"; then
  pass
  echo "  PASS: legacy next-step correctly reports Step 2"
else
  fail "legacy next-step incorrect. Tail: $(tail -5 "$OUTPUT_FILE")"
fi

# ============================================================
echo ""
echo "=== Test: Legacy active-step reports correct step ==="
# ============================================================

cat > "$LEGACY_DIR/masterPlan.md" << 'MDEOF'
# Test Plan

### Step 1: Done step
- [x] Completed

### Step 2: Active step
- [~] In progress

### Step 3: Pending step
- [ ] Waiting
MDEOF

rm -f "$LEGACY_DIR/.session-lock"
run_hook

if python3 -c "
import json, sys
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
ctx = data.get('hookSpecificOutput', {}).get('additionalContext', '')
assert 'IN PROGRESS: Step 2: Active step' in ctx, f'Wrong active step'
print('OK')
" 2>/dev/null | grep -q "OK"; then
  pass
  echo "  PASS: legacy active-step correctly reports Step 2"
else
  fail "legacy active-step incorrect. Tail: $(tail -5 "$OUTPUT_FILE")"
fi

# ============================================================
echo ""
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
fi
