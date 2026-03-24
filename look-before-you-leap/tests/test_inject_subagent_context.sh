#!/usr/bin/env bash
# Tests for inject-subagent-context.sh PreToolUse hook.
#
# Covers:
# - first-dispatch warning without Codex preflight
# - 3+ dispatch escalation without Codex co-exploration
# - silent pass-through when Codex co-exploration is present
# - graceful handling when Codex is unavailable
# - non-research agents remain unaffected

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/inject-subagent-context.sh"

PASS=0
FAIL=0
HOOK_OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/inject-subagent-context-out.XXXXXX")
trap 'rm -f "$HOOK_OUT_FILE"' EXIT

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  PASS=$((PASS + 1))
}

json_extract() {
  local path="$1"
  python3 - "$HOOK_OUT_FILE" "$path" <<'PY'
import json
import sys

out_file = sys.argv[1]
path = sys.argv[2].split(".")

with open(out_file, encoding="utf-8") as f:
    data = json.load(f)

value = data
for part in path:
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

print("" if value is None else value)
PY
}

assert_prompt_contains() {
  local expected="$1"
  local desc="$2"
  local prompt
  prompt=$(json_extract "hookSpecificOutput.updatedInput.prompt")
  if [[ "$prompt" == *"$expected"* ]]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc — expected prompt to contain: $expected"
  fi
}

assert_additional_context_contains() {
  local expected="$1"
  local desc="$2"
  local context
  context=$(json_extract "hookSpecificOutput.additionalContext")
  if [[ "$context" == *"$expected"* ]]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc — expected additionalContext to contain: $expected"
  fi
}

assert_no_additional_context() {
  local desc="$1"
  local context
  context=$(json_extract "hookSpecificOutput.additionalContext")
  if [ -z "$context" ]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc — expected no additionalContext, got: $context"
  fi
}

assert_file_exists() {
  local path="$1"
  local desc="$2"
  if [ -f "$path" ]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc — expected file to exist: $path"
  fi
}

assert_file_contains() {
  local path="$1"
  local expected="$2"
  local desc="$3"
  if [ ! -f "$path" ]; then
    fail "$desc — missing file: $path"
    return
  fi
  if grep -Fq "$expected" "$path"; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc — expected file to contain: $expected"
  fi
}

assert_file_content() {
  local path="$1"
  local expected="$2"
  local desc="$3"
  local content
  if [ ! -f "$path" ]; then
    fail "$desc — missing file: $path"
    return
  fi
  content=$(cat "$path")
  if [ "$content" = "$expected" ]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc — expected '$expected', got '$content'"
  fi
}

make_root() {
  mktemp -d "${TMPDIR:-/tmp}/inject-subagent-context.XXXXXX"
}

setup_plan_dir() {
  local root="$1"
  mkdir -p "$root/.git" "$root/.claude" "$root/.temp/plan-mode/active/demo"
  cat > "$root/.claude/look-before-you-leap.local.md" <<'EOF'
---
stack:
  language: shell-python-markdown
---
EOF
  echo "$$" > "$root/.temp/plan-mode/active/demo/.session-lock"
}

write_plan() {
  local root="$1"
  local step_status="$2"
  python3 - "$root" "$step_status" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
step_status = sys.argv[2]
plan = {
    "name": "demo",
    "title": "Demo",
    "status": "active",
    "steps": [
        {
            "id": 1,
            "title": "Explore",
            "status": step_status,
            "progress": [],
        }
    ],
    "blocked": [],
}
(root / ".temp" / "plan-mode" / "active" / "demo" / "plan.json").write_text(
    json.dumps(plan),
    encoding="utf-8",
)
PY
}

make_input() {
  local prompt="$1"
  local subagent_type="$2"
  local cwd="$3"
  python3 -c "
import json, sys
print(json.dumps({
    'tool_name': 'Task',
    'tool_input': {
        'prompt': sys.argv[1],
        'subagent_type': sys.argv[2],
    },
    'cwd': sys.argv[3],
}))
" "$prompt" "$subagent_type" "$cwd"
}

run_hook() {
  local prompt="$1"
  local subagent_type="$2"
  local cwd="$3"
  : > "$HOOK_OUT_FILE"
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    make_input "$prompt" "$subagent_type" "$cwd" | \
    bash "$HOOK" > "$HOOK_OUT_FILE" 2>/dev/null || true
}

# ============================================================
echo "=== Test: first research dispatch warns without preflight ==="
# ============================================================

ROOT=$(make_root)
setup_plan_dir "$ROOT"
write_plan "$ROOT" "pending"

run_hook "Inspect the repository structure" "Explore" "$ROOT"
assert_prompt_contains "## Engineering Discipline (injected by look-before-you-leap plugin)" "existing preamble preserved"
assert_prompt_contains "## REQUIRED: Write Findings to Discovery Log" "research discovery instructions preserved"
assert_additional_context_contains "MANDATORY: You must run command -v codex and dispatch Codex for co-exploration before or alongside exploration agents." "first dispatch warning injected"
assert_file_exists "$ROOT/.temp/plan-mode/active/demo/discovery.md" "discovery log still created"
assert_file_contains "$ROOT/.temp/plan-mode/active/demo/discovery.md" "## Agent dispatched: Explore — Inspect the repository structure" "dispatch still logged to discovery"
assert_file_content "$ROOT/.temp/plan-mode/active/demo/.exploration-agent-count-$$" "1" "research dispatch count initialized"

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: third research dispatch escalates without co-exploration ==="
# ============================================================

ROOT=$(make_root)
setup_plan_dir "$ROOT"
write_plan "$ROOT" "pending"
printf '2\n' > "$ROOT/.temp/plan-mode/active/demo/.exploration-agent-count-$$"
printf 'available\n' > "$ROOT/.temp/plan-mode/active/demo/.codex-preflight-$$"

run_hook "Inspect consumers of the hook" "Plan" "$ROOT"
assert_additional_context_contains "WARNING: 3+ research agents dispatched without Codex co-exploration." "third dispatch warning escalates"
assert_file_content "$ROOT/.temp/plan-mode/active/demo/.exploration-agent-count-$$" "3" "research dispatch count increments on escalation"

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: co-exploration marker suppresses warnings ==="
# ============================================================

ROOT=$(make_root)
setup_plan_dir "$ROOT"
write_plan "$ROOT" "pending"
printf '2\n' > "$ROOT/.temp/plan-mode/active/demo/.exploration-agent-count-$$"
printf 'available\n' > "$ROOT/.temp/plan-mode/active/demo/.codex-preflight-$$"
touch "$ROOT/.temp/plan-mode/active/demo/.codex-co-exploration-$$"

run_hook "Review architecture options" "feature-dev:code-architect" "$ROOT"
assert_no_additional_context "co-exploration marker bypasses warnings"
assert_file_content "$ROOT/.temp/plan-mode/active/demo/.exploration-agent-count-$$" "3" "research dispatch count still increments with co-exploration marker"

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: codex unavailable is handled gracefully ==="
# ============================================================

ROOT=$(make_root)
setup_plan_dir "$ROOT"
write_plan "$ROOT" "pending"
printf '2\n' > "$ROOT/.temp/plan-mode/active/demo/.exploration-agent-count-$$"
printf 'unavailable\n' > "$ROOT/.temp/plan-mode/active/demo/.codex-preflight-$$"

run_hook "Inspect affected entry points" "feature-dev:code-explorer" "$ROOT"
assert_additional_context_contains "Codex preflight reported unavailable for this session." "unavailable note injected"
assert_additional_context_contains "Document that in discovery.md" "unavailable note tells agent to document the fallback"
assert_file_content "$ROOT/.temp/plan-mode/active/demo/.exploration-agent-count-$$" "3" "research dispatch count increments when codex is unavailable"

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: non-research agents are unaffected ==="
# ============================================================

ROOT=$(make_root)
setup_plan_dir "$ROOT"
write_plan "$ROOT" "pending"

run_hook "Implement the fix directly" "general-purpose" "$ROOT"
assert_prompt_contains "Category: code-editing" "non-research agent keeps existing category classification"
assert_no_additional_context "non-research agent gets no codex warning"

if [ ! -f "$ROOT/.temp/plan-mode/active/demo/.exploration-agent-count-$$" ]; then
  pass
  echo "  PASS: non-research agent does not increment exploration counter"
else
  fail "non-research agent unexpectedly incremented exploration counter"
fi

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: syntax check ==="
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
