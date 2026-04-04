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

if find "$TEST_ROOT/.temp/plan-mode" -maxdepth 1 -name ".no-plan-*" | grep -q .; then
  pass
  echo "  PASS: 'just do it' creates legacy marker"
else
  fail "'just do it' did not create legacy marker"
fi

find "$TEST_ROOT/.temp/plan-mode" -maxdepth 1 -name ".no-plan-*" -delete

# Test explicit slash command
echo '{"prompt": "/bypass"}' | bash "$HOOK" 2>/dev/null || true

if find "$TEST_ROOT/.temp/plan-mode" -maxdepth 1 -name ".no-plan-*" | grep -q .; then
  pass
  echo "  PASS: '/bypass' creates legacy marker"
else
  fail "'/bypass' did not create legacy marker"
fi

find "$TEST_ROOT/.temp/plan-mode" -maxdepth 1 -name ".no-plan-*" -delete

# Test filename / docs mention — should NOT create marker
echo '{"prompt": "please review commands/bypass.md before we change it"}' | bash "$HOOK" 2>/dev/null || true

if ! find "$TEST_ROOT/.temp/plan-mode" -maxdepth 1 -name ".no-plan-*" | grep -q .; then
  pass
  echo "  PASS: mentioning commands/bypass.md does not create marker"
else
  fail "mentioning commands/bypass.md created marker"
fi

# Test non-override phrase — should NOT create marker
echo '{"prompt": "please write the code"}' | bash "$HOOK" 2>/dev/null || true

if ! find "$TEST_ROOT/.temp/plan-mode" -maxdepth 1 -name ".no-plan-*" | grep -q .; then
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

# ============================================================
echo ""
echo "=== Test: clear-handoff-on-approval runs as catch-all PostToolUse hook ==="
# ============================================================

if python3 -c "
import json
with open('${PLUGIN_ROOT}/hooks/hooks.json') as f:
    hooks = json.load(f)['hooks'].get('PostToolUse', [])
for entry in hooks:
    if 'clear-handoff-on-approval.sh' not in str(entry):
        continue
    if 'matcher' not in entry:
        raise SystemExit(1)
raise SystemExit(0)
" 2>/dev/null; then
  fail "clear-handoff-on-approval is still matcher-gated"
else
  pass
  echo "  PASS: clear-handoff-on-approval runs for all PostToolUse events and filters in-script"
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
echo "=== Test: clear-handoff-on-approval.sh clears marker from reviewed sourcePath ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
PLAN_DIR="$TEST_ROOT/.temp/plan-mode/active/review-plan"
mkdir -p "$TEST_ROOT/.git" "$PLAN_DIR"

cat > "$PLAN_DIR/plan.json" <<'EOF'
{
  "name": "review-plan",
  "steps": [
    {"id": 1, "title": "Step 1", "status": "pending"}
  ]
}
EOF

cat > "$PLAN_DIR/masterPlan.md" <<'EOF'
# Review plan
- [ ] Step 1
EOF

echo "$PLAN_DIR/masterPlan.md" > "$PLAN_DIR/.handoff-pending"

HOOK_INPUT=$(python3 -c "
import json
print(json.dumps({
    'tool_name': 'orbit_await_review',
    'tool_input': {'sourcePath': '$PLAN_DIR/masterPlan.md'},
    'tool_result': {'status': 'approved', 'threads': []},
    'cwd': '$TEST_ROOT'
}))
")

echo "$HOOK_INPUT" | bash "${PLUGIN_ROOT}/hooks/clear-handoff-on-approval.sh" >/dev/null 2>&1 || true

if [ ! -f "$PLAN_DIR/.handoff-pending" ]; then
  pass
  echo "  PASS: clear-handoff-on-approval clears marker from sourcePath fallback"
else
  fail "clear-handoff-on-approval did not clear marker via sourcePath fallback"
fi

PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null) || true
HANDOFF_RECEIPT="$STATE_ROOT/$PROJ_ID/review-plan/handoff_approved-default.json"
if [ -f "$HANDOFF_RECEIPT" ]; then
  pass
  echo "  PASS: sourcePath fallback also minted handoff receipt"
else
  fail "sourcePath fallback did not mint handoff receipt"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: clear-handoff-on-approval.sh accepts live MCP Orbit payload shape ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
PLAN_DIR="$TEST_ROOT/.temp/plan-mode/active/review-plan"
mkdir -p "$TEST_ROOT/.git" "$PLAN_DIR"

cat > "$PLAN_DIR/plan.json" <<'EOF'
{
  "name": "review-plan",
  "steps": [
    {"id": 1, "title": "Step 1", "status": "pending"}
  ]
}
EOF

cat > "$PLAN_DIR/masterPlan.md" <<'EOF'
# Review plan
- [ ] Step 1
EOF

echo "$PLAN_DIR/masterPlan.md" > "$PLAN_DIR/.handoff-pending"

HOOK_INPUT=$(python3 -c "
import json
print(json.dumps({
    'tool_name': 'mcp__orbit__orbit_await_review',
    'tool_input': {'sourcePath': '$PLAN_DIR/masterPlan.md'},
    'tool_result': [{'type': 'text', 'text': '{\\n  \"status\": \"approved\",\\n  \"threads\": []\\n}'}],
    'cwd': '$TEST_ROOT'
}))
")

echo "$HOOK_INPUT" | bash "${PLUGIN_ROOT}/hooks/clear-handoff-on-approval.sh" >/dev/null 2>&1 || true

if [ ! -f "$PLAN_DIR/.handoff-pending" ]; then
  pass
  echo "  PASS: live MCP Orbit payload clears handoff marker"
else
  fail "live MCP Orbit payload did not clear handoff marker"
fi

PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null) || true
HANDOFF_RECEIPT="$STATE_ROOT/$PROJ_ID/review-plan/handoff_approved-default.json"
if [ -f "$HANDOFF_RECEIPT" ]; then
  pass
  echo "  PASS: live MCP Orbit payload minted handoff receipt"
else
  fail "live MCP Orbit payload did not mint handoff receipt"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: enforce-plan.sh clears stale handoff marker after approval receipt ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
PLAN_DIR="$TEST_ROOT/.temp/plan-mode/active/review-plan"
mkdir -p "$TEST_ROOT/.git" "$PLAN_DIR"

cat > "$PLAN_DIR/plan.json" <<'EOF'
{
  "name": "review-plan",
  "_receiptMode": "strict",
  "steps": [
    {"id": 1, "title": "Step 1", "status": "pending"}
  ]
}
EOF

cat > "$PLAN_DIR/masterPlan.md" <<'EOF'
# Review plan
- [ ] Step 1
EOF

echo "$$" > "$PLAN_DIR/.session-lock"
echo "$PLAN_DIR/plan.json" > "$PLAN_DIR/.handoff-pending"

PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null) || true
python3 "$RECEIPT_UTILS" sign "handoff_approved" "$PROJ_ID" "review-plan" >/dev/null 2>&1

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

if [ "$HOOK_EXIT" -eq 0 ] && [ ! -f "$PLAN_DIR/.handoff-pending" ]; then
  pass
  echo "  PASS: enforce-plan.sh trusts handoff receipt and clears stale marker"
else
  fail "enforce-plan.sh did not recover from stale handoff marker after approval"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: session-start.sh recovers approved handoff across live foreign lock ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
APPROVED_DIR="$TEST_ROOT/.temp/plan-mode/active/approved-plan"
OTHER_DIR="$TEST_ROOT/.temp/plan-mode/active/other-plan"
OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/approval-session-start.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$APPROVED_DIR" "$OTHER_DIR"

cat > "$APPROVED_DIR/plan.json" <<'EOF'
{
  "name": "approved-plan",
  "_receiptMode": "strict",
  "steps": [
    {"id": 1, "title": "Approved step", "status": "pending"}
  ]
}
EOF

cat > "$APPROVED_DIR/masterPlan.md" <<'EOF'
# Approved plan
- [ ] Approved step
EOF

cat > "$OTHER_DIR/plan.json" <<'EOF'
{
  "name": "other-plan",
  "_receiptMode": "strict",
  "steps": [
    {"id": 1, "title": "Other step", "status": "pending"}
  ]
}
EOF

echo "$PPID" > "$APPROVED_DIR/.session-lock"
echo "$PPID" > "$OTHER_DIR/.session-lock"
echo "$APPROVED_DIR/masterPlan.md" > "$APPROVED_DIR/.handoff-pending"

PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null) || true
python3 "$RECEIPT_UTILS" sign "handoff_approved" "$PROJ_ID" "approved-plan" >/dev/null 2>&1

pushd "$TEST_ROOT" >/dev/null
bash "${PLUGIN_ROOT}/hooks/session-start.sh" > "$OUTPUT_FILE" 2>/dev/null || true
popd >/dev/null

if python3 -c "
import json
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
ctx = data.get('hookSpecificOutput', {}).get('additionalContext', '')
assert 'ACTIVE PLAN DETECTED' in ctx
assert 'approved-plan' in ctx
print('OK')
" 2>/dev/null | grep -q "OK"; then
  pass
  echo "  PASS: session-start.sh recovered approved handoff plan"
else
  fail "session-start.sh did not recover approved handoff. Tail: $(tail -5 "$OUTPUT_FILE")"
fi

lock_content=$(cat "$APPROVED_DIR/.session-lock" 2>/dev/null || true)
if [ "$lock_content" = "$$" ] && [ ! -f "$APPROVED_DIR/.handoff-pending" ]; then
  pass
  echo "  PASS: approved plan was re-claimed and stale handoff marker cleared"
else
  fail "session-start.sh did not claim approved plan correctly (lock='$lock_content')"
fi

rm -f "$OUTPUT_FILE"
rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: session-start.sh recovers Orbit-approved handoff from review metadata ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
APPROVED_DIR="$TEST_ROOT/.temp/plan-mode/active/approved-plan"
OTHER_DIR="$TEST_ROOT/.temp/plan-mode/active/other-plan"
OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/approval-session-start-review.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$APPROVED_DIR" "$OTHER_DIR"

cat > "$APPROVED_DIR/plan.json" <<'EOF'
{
  "name": "approved-plan",
  "_receiptMode": "strict",
  "steps": [
    {"id": 1, "title": "Approved step", "status": "pending"}
  ]
}
EOF

cat > "$APPROVED_DIR/masterPlan.md" <<'EOF'
# Approved plan
- [ ] Approved step
EOF

SOURCE_HASH=$(python3 -c "
import hashlib
with open('$APPROVED_DIR/masterPlan.md', 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())
")

cat > "$APPROVED_DIR/masterPlan.md.review.json" <<EOF
{
  "version": 1,
  "sourcePath": "$APPROVED_DIR/masterPlan.md",
  "artifactPath": "$APPROVED_DIR/masterPlan.md.resolved",
  "sourceHash": "$SOURCE_HASH",
  "artifactHash": "fixture-artifact-hash",
  "artifactVersion": 1,
  "reviewState": "approved",
  "generatorVersion": "orbit-plan-resolver@0.1.0",
  "generatedAt": "2026-04-03T00:00:00Z",
  "approvedAt": "2026-04-03T00:01:00Z"
}
EOF

cat > "$OTHER_DIR/plan.json" <<'EOF'
{
  "name": "other-plan",
  "_receiptMode": "strict",
  "steps": [
    {"id": 1, "title": "Other step", "status": "pending"}
  ]
}
EOF

echo "$PPID" > "$APPROVED_DIR/.session-lock"
echo "$PPID" > "$OTHER_DIR/.session-lock"
echo "$APPROVED_DIR/masterPlan.md" > "$APPROVED_DIR/.handoff-pending"

pushd "$TEST_ROOT" >/dev/null
bash "${PLUGIN_ROOT}/hooks/session-start.sh" > "$OUTPUT_FILE" 2>/dev/null || true
popd >/dev/null

if python3 -c "
import json
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
ctx = data.get('hookSpecificOutput', {}).get('additionalContext', '')
assert 'ACTIVE PLAN DETECTED' in ctx
assert 'approved-plan' in ctx
print('OK')
" 2>/dev/null | grep -q "OK"; then
  pass
  echo "  PASS: session-start.sh recovered handoff from Orbit review metadata"
else
  fail "session-start.sh did not recover Orbit-approved handoff. Tail: $(tail -5 "$OUTPUT_FILE")"
fi

PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null) || true
HANDOFF_RECEIPT="$STATE_ROOT/$PROJ_ID/approved-plan/handoff_approved-default.json"
lock_content=$(cat "$APPROVED_DIR/.session-lock" 2>/dev/null || true)
if [ "$lock_content" = "$$" ] && [ ! -f "$APPROVED_DIR/.handoff-pending" ] && [ -f "$HANDOFF_RECEIPT" ]; then
  pass
  echo "  PASS: session-start.sh minted receipt from review metadata and claimed the plan"
else
  fail "session-start.sh did not persist Orbit approval correctly (lock='$lock_content', receipt='$HANDOFF_RECEIPT')"
fi

rm -f "$OUTPUT_FILE"
rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: post-compact.sh recovers approved handoff across live foreign lock ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
APPROVED_DIR="$TEST_ROOT/.temp/plan-mode/active/approved-plan"
OTHER_DIR="$TEST_ROOT/.temp/plan-mode/active/other-plan"
OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/approval-post-compact.XXXXXX")
mkdir -p "$TEST_ROOT/.git" "$APPROVED_DIR" "$OTHER_DIR"

cat > "$APPROVED_DIR/plan.json" <<'EOF'
{
  "name": "approved-plan",
  "_receiptMode": "strict",
  "steps": [
    {"id": 1, "title": "Approved step", "status": "pending"}
  ]
}
EOF

cat > "$OTHER_DIR/plan.json" <<'EOF'
{
  "name": "other-plan",
  "_receiptMode": "strict",
  "steps": [
    {"id": 1, "title": "Other step", "status": "pending"}
  ]
}
EOF

echo "$PPID" > "$APPROVED_DIR/.session-lock"
echo "$PPID" > "$OTHER_DIR/.session-lock"
echo "$APPROVED_DIR/plan.json" > "$APPROVED_DIR/.handoff-pending"

PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null) || true
python3 "$RECEIPT_UTILS" sign "handoff_approved" "$PROJ_ID" "approved-plan" >/dev/null 2>&1

pushd "$TEST_ROOT" >/dev/null
bash "${PLUGIN_ROOT}/hooks/post-compact.sh" > "$OUTPUT_FILE" 2>/dev/null || true
popd >/dev/null

if python3 -c "
import json
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
ctx = data.get('hookSpecificOutput', {}).get('additionalContext', '')
assert 'CONTEXT WAS COMPACTED' in ctx
assert 'approved-plan' in ctx
print('OK')
" 2>/dev/null | grep -q "OK"; then
  pass
  echo "  PASS: post-compact.sh recovered approved handoff plan"
else
  fail "post-compact.sh did not recover approved handoff. Tail: $(tail -5 "$OUTPUT_FILE")"
fi

lock_content=$(cat "$APPROVED_DIR/.session-lock" 2>/dev/null || true)
if [ "$lock_content" = "$$" ] && [ ! -f "$APPROVED_DIR/.handoff-pending" ]; then
  pass
  echo "  PASS: post-compact.sh re-claimed approved plan and cleared marker"
else
  fail "post-compact.sh did not claim approved plan correctly (lock='$lock_content')"
fi

rm -f "$OUTPUT_FILE"
rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: enforce-plan.sh recovers from approved review metadata without receipt ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
PLAN_DIR="$TEST_ROOT/.temp/plan-mode/active/review-plan"
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/src" "$PLAN_DIR"

cat > "$PLAN_DIR/plan.json" <<'EOF'
{
  "name": "review-plan",
  "_receiptMode": "strict",
  "steps": [
    {"id": 1, "title": "Step 1", "status": "pending"}
  ]
}
EOF

cat > "$PLAN_DIR/masterPlan.md" <<'EOF'
# Review plan
- [ ] Step 1
EOF

SOURCE_HASH=$(python3 -c "
import hashlib
with open('$PLAN_DIR/masterPlan.md', 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())
")

cat > "$PLAN_DIR/masterPlan.md.review.json" <<EOF
{
  "version": 1,
  "sourcePath": "$PLAN_DIR/masterPlan.md",
  "artifactPath": "$PLAN_DIR/masterPlan.md.resolved",
  "sourceHash": "$SOURCE_HASH",
  "artifactHash": "fixture-artifact-hash",
  "artifactVersion": 1,
  "reviewState": "approved",
  "generatorVersion": "orbit-plan-resolver@0.1.0",
  "generatedAt": "2026-04-03T00:00:00Z",
  "approvedAt": "2026-04-03T00:01:00Z"
}
EOF

echo "$PPID" > "$PLAN_DIR/.session-lock"
echo "$PLAN_DIR/masterPlan.md" > "$PLAN_DIR/.handoff-pending"

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
  echo "  PASS: enforce-plan.sh trusted Orbit review metadata"
else
  fail "enforce-plan.sh still denied after Orbit review approval (exit=$HOOK_EXIT)"
fi

PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null) || true
HANDOFF_RECEIPT="$STATE_ROOT/$PROJ_ID/review-plan/handoff_approved-default.json"
lock_content=$(cat "$PLAN_DIR/.session-lock" 2>/dev/null || true)
if [ "$lock_content" = "$$" ] && [ ! -f "$PLAN_DIR/.handoff-pending" ] && [ -f "$HANDOFF_RECEIPT" ]; then
  pass
  echo "  PASS: enforce-plan.sh persisted approval from review metadata"
else
  fail "enforce-plan.sh did not persist Orbit review approval correctly (lock='$lock_content', receipt='$HANDOFF_RECEIPT')"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: enforce-plan.sh reclaims approved handoff before no-plan denial ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
APPROVED_DIR="$TEST_ROOT/.temp/plan-mode/active/approved-plan"
OTHER_DIR="$TEST_ROOT/.temp/plan-mode/active/other-plan"
mkdir -p "$TEST_ROOT/.git" "$TEST_ROOT/src" "$APPROVED_DIR" "$OTHER_DIR"

cat > "$APPROVED_DIR/plan.json" <<'EOF'
{
  "name": "approved-plan",
  "_receiptMode": "strict",
  "steps": [
    {"id": 1, "title": "Approved step", "status": "pending"}
  ]
}
EOF

cat > "$OTHER_DIR/plan.json" <<'EOF'
{
  "name": "other-plan",
  "_receiptMode": "strict",
  "steps": [
    {"id": 1, "title": "Other step", "status": "pending"}
  ]
}
EOF

echo "$PPID" > "$APPROVED_DIR/.session-lock"
echo "$PPID" > "$OTHER_DIR/.session-lock"
echo "$APPROVED_DIR/plan.json" > "$APPROVED_DIR/.handoff-pending"

PROJ_ID=$(python3 "$RECEIPT_UTILS" project-id "$TEST_ROOT" 2>/dev/null) || true
python3 "$RECEIPT_UTILS" sign "handoff_approved" "$PROJ_ID" "approved-plan" >/dev/null 2>&1

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
  echo "  PASS: enforce-plan.sh allowed edit by reclaiming approved handoff plan"
else
  fail "enforce-plan.sh still denied after approved handoff recovery (exit=$HOOK_EXIT)"
fi

lock_content=$(cat "$APPROVED_DIR/.session-lock" 2>/dev/null || true)
if [ "$lock_content" = "$$" ] && [ ! -f "$APPROVED_DIR/.handoff-pending" ]; then
  pass
  echo "  PASS: enforce-plan.sh claimed approved plan and cleared stale marker"
else
  fail "enforce-plan.sh did not claim approved plan correctly (lock='$lock_content')"
fi

rm -rf "$TEST_ROOT"

# ============================================================
echo ""
echo "=== Test: enforce-plan.sh points review to masterPlan.md when marker stores plan.json ==="
# ============================================================

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/approval-test.XXXXXX")
PLAN_DIR="$TEST_ROOT/.temp/plan-mode/active/review-plan"
mkdir -p "$TEST_ROOT/.git" "$PLAN_DIR"

cat > "$PLAN_DIR/plan.json" <<'EOF'
{
  "name": "review-plan",
  "steps": [
    {"id": 1, "title": "Step 1", "status": "pending"}
  ]
}
EOF

cat > "$PLAN_DIR/masterPlan.md" <<'EOF'
# Review plan
- [ ] Step 1
EOF

echo "$$" > "$PLAN_DIR/.session-lock"
echo "$PLAN_DIR/plan.json" > "$PLAN_DIR/.handoff-pending"

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
reason = json.loads(sys.stdin.read()).get('hookSpecificOutput', {}).get('permissionDecisionReason', '')
expected = '$PLAN_DIR/masterPlan.md'
sys.exit(0 if expected in reason else 1)
" 2>/dev/null; then
  pass
  echo "  PASS: enforce-plan.sh directs Orbit review to masterPlan.md"
else
  fail "enforce-plan.sh still points Orbit review at plan.json"
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
