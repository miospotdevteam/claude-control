#!/usr/bin/env bash
# Tests for enforce-step-ownership.sh PreToolUse hook
#
# Tests that Claude cannot edit files owned by codex-impl steps,
# while allowing edits to Claude-owned files and plan files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/enforce-step-ownership.sh"

# Use a temp dir as fake project root
FAKE_PROJECT=$(mktemp -d "${TMPDIR:-/tmp}/ownership-test.XXXXXX")
mkdir -p "$FAKE_PROJECT/.git"
mkdir -p "$FAKE_PROJECT/.temp/plan-mode/active/test-plan"

PASS=0
FAIL=0
HOOK_OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/ownership-out.XXXXXX")
trap 'rm -f "$HOOK_OUT_FILE"; rm -rf "$FAKE_PROJECT"' EXIT

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

# ============================================================
echo "=== No plan: all edits allowed ==="
# ============================================================

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/src/app.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Edit without plan allowed"

# ============================================================
echo ""
echo "=== Legacy plan: all edits allowed ==="
# ============================================================

# Create a legacy plan (no _receiptMode)
cat > "$FAKE_PROJECT/.temp/plan-mode/active/test-plan/plan.json" << 'EOF'
{
  "name": "test-plan",
  "status": "active",
  "steps": [
    {
      "id": 1,
      "title": "Codex step",
      "status": "in_progress",
      "owner": "codex",
      "mode": "codex-impl",
      "files": ["src/codex-file.ts"]
    }
  ]
}
EOF
echo "$$" > "$FAKE_PROJECT/.temp/plan-mode/active/test-plan/.session-lock"

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/src/codex-file.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Edit codex file in legacy plan allowed"

# ============================================================
echo ""
echo "=== Strict plan: codex-owned file denied ==="
# ============================================================

# Create a strict plan with a codex-impl step
cat > "$FAKE_PROJECT/.temp/plan-mode/active/test-plan/plan.json" << 'EOF'
{
  "name": "test-plan",
  "status": "active",
  "_receiptMode": "strict",
  "steps": [
    {
      "id": 1,
      "title": "Codex step",
      "status": "in_progress",
      "owner": "codex",
      "mode": "codex-impl",
      "files": ["src/codex-file.ts", "src/codex-helper.ts"]
    },
    {
      "id": 2,
      "title": "Claude step",
      "status": "pending",
      "owner": "claude",
      "mode": "claude-impl",
      "files": ["src/claude-file.ts"]
    }
  ]
}
EOF

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/src/codex-file.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "Edit codex-owned file denied"

run_hook '{"tool_name": "Write", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/src/codex-helper.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "Write codex-owned file denied"

# ============================================================
echo ""
echo "=== Strict plan: Claude-owned file allowed ==="
# ============================================================

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/src/claude-file.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Edit Claude-owned file allowed"

# ============================================================
echo ""
echo "=== Strict plan: file not in any step allowed ==="
# ============================================================

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/src/other-file.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Edit file not in any step allowed"

# ============================================================
echo ""
echo "=== .temp/ edits always allowed ==="
# ============================================================

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/.temp/plan-mode/active/test-plan/plan.json"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Edit plan.json allowed"

# ============================================================
echo ""
echo "=== Codex step not in_progress: edits allowed ==="
# ============================================================

# Change step 1 to done
cat > "$FAKE_PROJECT/.temp/plan-mode/active/test-plan/plan.json" << 'EOF'
{
  "name": "test-plan",
  "status": "active",
  "_receiptMode": "strict",
  "steps": [
    {
      "id": 1,
      "title": "Codex step",
      "status": "done",
      "owner": "codex",
      "mode": "codex-impl",
      "files": ["src/codex-file.ts"]
    }
  ]
}
EOF

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/src/codex-file.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Edit codex file when step is done allowed"

# ============================================================
echo ""
echo "=== Collab-split: codex-owned group denied ==="
# ============================================================

cat > "$FAKE_PROJECT/.temp/plan-mode/active/test-plan/plan.json" << 'EOF'
{
  "name": "test-plan",
  "status": "active",
  "_receiptMode": "strict",
  "steps": [
    {
      "id": 1,
      "title": "Split step",
      "status": "in_progress",
      "owner": "claude",
      "mode": "collab-split",
      "files": ["src/claude-part.ts", "src/codex-part.ts"],
      "subPlan": {
        "groups": [
          {
            "title": "Claude group",
            "owner": "claude",
            "files": ["src/claude-part.ts"],
            "status": "in_progress"
          },
          {
            "title": "Codex group",
            "owner": "codex",
            "files": ["src/codex-part.ts"],
            "status": "in_progress"
          }
        ]
      }
    }
  ]
}
EOF

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/src/codex-part.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "Edit codex-owned group file denied"

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/src/claude-part.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Edit claude-owned group file allowed"

# ============================================================
echo ""
echo "=== Path normalization: ../ bypass denied ==="
# ============================================================

# Restore the strict plan with codex step
cat > "$FAKE_PROJECT/.temp/plan-mode/active/test-plan/plan.json" << 'EOF'
{
  "name": "test-plan",
  "status": "active",
  "_receiptMode": "strict",
  "steps": [
    {
      "id": 1,
      "title": "Codex step",
      "status": "in_progress",
      "owner": "codex",
      "mode": "codex-impl",
      "files": ["src/codex-file.ts"]
    }
  ]
}
EOF
echo "$$" > "$FAKE_PROJECT/.temp/plan-mode/active/test-plan/.session-lock"

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/src/../src/codex-file.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "Edit via ../ path denied"

run_hook '{"tool_name": "Edit", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/./src/codex-file.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "Edit via ./ path denied"

# ============================================================
echo ""
echo "=== Bash commands pass through ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "cat '"$FAKE_PROJECT"'/src/codex-part.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Bash commands not checked by this hook"

# ============================================================
echo ""
echo "=== Read tool passes through ==="
# ============================================================

run_hook '{"tool_name": "Read", "tool_input": {"file_path": "'"$FAKE_PROJECT"'/src/codex-part.ts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Read codex file allowed (read-only)"

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
