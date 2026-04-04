#!/usr/bin/env bash
# Behavioral tests for post-compact.sh resumption hook.
#
# End-to-end tests that invoke the actual hook with temp project fixtures.
# Tests:
# 1. plan.json-backed resumption emits correct JSON context
# 2. Legacy masterPlan.md next-step reports the correct step
# 3. Legacy live foreign lock is preserved (hook emits nothing)
# 4. Legacy stale lock is claimed (hook emits resumption context)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/post-compact.sh"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"

PASS=0
FAIL=0

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  PASS=$((PASS + 1))
}

# Create isolated temp project root
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/post-compact-test.XXXXXX")
OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/post-compact-output.XXXXXX")
trap 'rm -rf "$TEST_ROOT" "$OUTPUT_FILE"' EXIT

# Helper: run hook from temp project root, capture output.
# Uses pushd/popd (not a subshell) so the hook's PPID = $$ of this script.
run_hook() {
  pushd "$TEST_ROOT" >/dev/null
  bash "$HOOK" > "$OUTPUT_FILE" 2>/dev/null || true
  popd >/dev/null
}

# ============================================================
echo "=== Test: plan.json resumption emits context ==="
# ============================================================

mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/.temp/plan-mode/active/e2e-plan"
PLAN_DIR="$TEST_ROOT/.temp/plan-mode/active/e2e-plan"

cat > "$PLAN_DIR/plan.json" << 'JSONEOF'
{
  "name": "e2e-plan",
  "title": "E2E Test Plan",
  "context": "Test context",
  "status": "active",
  "requiredSkills": [],
  "disciplines": [],
  "discovery": {"scope":"test","entryPoints":"","consumers":"","existingPatterns":"","testInfrastructure":"","conventions":"","blastRadius":"","confidence":"high"},
  "steps": [
    {"id":1,"title":"Step one","status":"done","skill":"none","simplify":false,"codexVerify":true,"files":[],"description":"Done step","acceptanceCriteria":"Done","progress":[{"task":"t","status":"done","files":[]}],"subPlan":null,"result":"done"},
    {"id":2,"title":"Step two","status":"pending","skill":"none","simplify":false,"codexVerify":true,"files":[],"description":"Pending step","acceptanceCriteria":"Pending","progress":[{"task":"t","status":"pending","files":[]}],"subPlan":null,"result":null}
  ],
  "blocked": []
}
JSONEOF

python3 "$PLAN_UTILS" init-progress "$PLAN_DIR/plan.json" >/dev/null 2>&1
python3 "$PLAN_UTILS" update-step "$PLAN_DIR/plan.json" 1 done >/dev/null 2>&1

# Claim for our PID (the subshell in run_hook sees $$ as PPID)
echo "$$" > "$PLAN_DIR/.session-lock"

run_hook

if python3 -c "
import json, sys
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
ctx = data.get('hookSpecificOutput', {}).get('additionalContext', '')
assert 'CONTEXT WAS COMPACTED' in ctx, 'Missing compaction header'
assert 'e2e-plan' in ctx, 'Missing plan name'
assert 'Step two' in ctx, 'Missing next step'
assert 'Respect step ownership exactly.' in ctx, 'Missing ownership reminder'
assert 'Independent verification is a gate.' in ctx, 'Missing verification reminder'
print('OK')
" 2>/dev/null | grep -q "OK"; then
  pass
  echo "  PASS: plan.json resumption emits correct context"
else
  fail "plan.json resumption output incorrect. Got: $(cat "$OUTPUT_FILE" | head -3)"
fi

# ============================================================
echo ""
echo "=== Test: Legacy next-step reports correct step ==="
# ============================================================

rm -rf "$TEST_ROOT/.temp/plan-mode/active/e2e-plan"
mkdir -p "$TEST_ROOT/.temp/plan-mode/active/legacy-test"
LEGACY_DIR="$TEST_ROOT/.temp/plan-mode/active/legacy-test"

cat > "$LEGACY_DIR/masterPlan.md" << 'MDEOF'
# Test Plan

### Step 1: First step
- [x] Item A done
- [x] Item B done

### Step 2: Second step
- [ ] Item C pending
- [ ] Item D pending
MDEOF

# No session lock — hook will claim it
run_hook

if python3 -c "
import json, sys
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
ctx = data.get('hookSpecificOutput', {}).get('additionalContext', '')
assert 'NEXT: Step 2: Second step' in ctx, f'Wrong next step in: {ctx}'
print('OK')
" 2>/dev/null | grep -q "OK"; then
  pass
  echo "  PASS: legacy next-step correctly reports Step 2 (not Step 1)"
else
  fail "legacy next-step output incorrect. Got: $(cat "$OUTPUT_FILE" | head -5)"
fi

# ============================================================
echo ""
echo "=== Test: Legacy active-step reports correct step ==="
# ============================================================

cat > "$LEGACY_DIR/masterPlan.md" << 'MDEOF'
# Test Plan

### Step 1: First step
- [x] Item A done

### Step 2: Second step
- [~] Item B active

### Step 3: Third step
- [ ] Item C pending
MDEOF

# Remove lock so hook re-claims
rm -f "$LEGACY_DIR/.session-lock"
run_hook

if python3 -c "
import json, sys
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
ctx = data.get('hookSpecificOutput', {}).get('additionalContext', '')
assert 'IN PROGRESS: Step 2: Second step' in ctx, f'Wrong active step in: {ctx}'
print('OK')
" 2>/dev/null | grep -q "OK"; then
  pass
  echo "  PASS: legacy active-step correctly reports Step 2"
else
  fail "legacy active-step output incorrect. Got: $(cat "$OUTPUT_FILE" | head -5)"
fi

# ============================================================
echo ""
echo "=== Test: Legacy live foreign lock preserved ==="
# ============================================================

rm -rf "$LEGACY_DIR"
mkdir -p "$LEGACY_DIR"
cat > "$LEGACY_DIR/masterPlan.md" << 'MDEOF'
# Lock Test

### Step 1: Only step
- [ ] Pending item
MDEOF

# Write lock with PPID (our parent — alive, accessible via kill -0, differs from $$)
echo "$PPID" > "$LEGACY_DIR/.session-lock"

run_hook

# Hook should produce empty output (foreign live lock blocks claiming)
if [ ! -s "$OUTPUT_FILE" ]; then
  pass
  echo "  PASS: hook emits nothing for foreign live lock"
else
  fail "hook should emit nothing for foreign live lock. Got: $(cat "$OUTPUT_FILE" | head -3)"
fi

# Verify lock was NOT overwritten
lock_content=$(cat "$LEGACY_DIR/.session-lock")
if [ "$lock_content" = "$PPID" ]; then
  pass
  echo "  PASS: lock file content unchanged"
else
  fail "lock file was overwritten: expected '$PPID' got '$lock_content'"
fi

# ============================================================
echo ""
echo "=== Test: Legacy stale lock IS claimed ==="
# ============================================================

# Use PID 99999 which is almost certainly dead
echo "99999" > "$LEGACY_DIR/.session-lock"

run_hook

if python3 -c "
import json, sys
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
ctx = data.get('hookSpecificOutput', {}).get('additionalContext', '')
assert 'CONTEXT WAS COMPACTED' in ctx, 'Missing compaction header'
print('OK')
" 2>/dev/null | grep -q "OK"; then
  pass
  echo "  PASS: stale lock claimed, resumption context emitted"
else
  fail "stale lock should allow claiming. Got: $(cat "$OUTPUT_FILE" | head -3)"
fi

# Verify lock was updated to the hook's PPID (= our $$)
lock_content=$(cat "$LEGACY_DIR/.session-lock")
if [ "$lock_content" = "$$" ]; then
  pass
  echo "  PASS: lock updated to current session PID"
else
  fail "lock should be updated to '$$' but got '$lock_content'"
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
