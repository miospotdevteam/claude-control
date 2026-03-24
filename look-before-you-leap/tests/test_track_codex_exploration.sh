#!/usr/bin/env bash
# Tests for track-codex-exploration.sh PostToolUse hook.
#
# Covers:
# - command -v codex preflight marker creation
# - codex exec co-exploration marker creation
# - exploration-phase gating (skip once plan execution starts)
# - silent pass-through for unrelated Bash commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/track-codex-exploration.sh"

PASS=0
FAIL=0
HOOK_OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/track-codex-out.XXXXXX")
trap 'rm -f "$HOOK_OUT_FILE"' EXIT

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  PASS=$((PASS + 1))
}

assert_empty_output() {
  local desc="$1"
  local output
  output=$(cat "$HOOK_OUT_FILE")
  if [ -n "$output" ]; then
    fail "$desc — expected no hook output, got: $output"
  else
    pass
    echo "  PASS: $desc"
  fi
}

assert_exists() {
  local path="$1"
  local desc="$2"
  if [ -e "$path" ]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc — expected file to exist: $path"
  fi
}

assert_not_exists() {
  local path="$1"
  local desc="$2"
  if [ ! -e "$path" ]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc — expected file to be absent: $path"
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
  mktemp -d "${TMPDIR:-/tmp}/track-codex-exploration.XXXXXX"
}

setup_plan_dir() {
  local root="$1"
  mkdir -p "$root/.git" "$root/.temp/plan-mode/active/demo"
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
            "title": "Track Codex exploration",
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
  local cmd="$1"
  local cwd="$2"
  local response="$3"
  python3 -c "
import json, sys
print(json.dumps({
    'tool_name': 'Bash',
    'tool_input': {'command': sys.argv[1]},
    'tool_response': sys.argv[3],
    'cwd': sys.argv[2],
}))
" "$cmd" "$cwd" "$response"
}

run_hook() {
  local cmd="$1"
  local cwd="$2"
  local response="${3:-}"
  : > "$HOOK_OUT_FILE"
  make_input "$cmd" "$cwd" "$response" | bash "$HOOK" > "$HOOK_OUT_FILE" 2>/dev/null || true
}

# ============================================================
echo "=== Test: command -v codex creates preflight marker ==="
# ============================================================

ROOT=$(make_root)
setup_plan_dir "$ROOT"
write_plan "$ROOT" "pending"

run_hook "command -v codex" "$ROOT" "/usr/local/bin/codex"
assert_empty_output "preflight hook stays silent"
assert_exists "$ROOT/.temp/plan-mode/active/demo/.codex-preflight-$$" "preflight marker created for fresh plan"
assert_file_content "$ROOT/.temp/plan-mode/active/demo/.codex-preflight-$$" "available" "preflight marker records availability"

rm -rf "$ROOT"

ROOT=$(make_root)
setup_plan_dir "$ROOT"

run_hook "command -v codex" "$ROOT" "Exit code 1"
assert_empty_output "pre-plan hook stays silent"
assert_exists "$ROOT/.temp/plan-mode/active/demo/.codex-preflight-$$" "preflight marker created before plan.json exists"
assert_file_content "$ROOT/.temp/plan-mode/active/demo/.codex-preflight-$$" "unavailable" "preflight marker records unavailable state"

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: codex exec creates co-exploration marker ==="
# ============================================================

ROOT=$(make_root)
setup_plan_dir "$ROOT"
write_plan "$ROOT" "pending"

run_hook "codex exec --fast 'inspect repository'" "$ROOT" "Exploration complete"
assert_empty_output "codex exec hook stays silent"
assert_exists "$ROOT/.temp/plan-mode/active/demo/.codex-co-exploration-$$" "co-exploration marker created for fresh plan"

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: markers skipped after execution begins ==="
# ============================================================

ROOT=$(make_root)
setup_plan_dir "$ROOT"
write_plan "$ROOT" "in_progress"

run_hook "command -v codex" "$ROOT" "/usr/local/bin/codex"
assert_empty_output "in-progress preflight hook stays silent"
assert_not_exists "$ROOT/.temp/plan-mode/active/demo/.codex-preflight-$$" "preflight marker skipped when plan is no longer fresh"

run_hook "codex exec --fast 'late consensus run'" "$ROOT" "ok"
assert_empty_output "in-progress codex exec hook stays silent"
assert_not_exists "$ROOT/.temp/plan-mode/active/demo/.codex-co-exploration-$$" "co-exploration marker skipped when step is in progress"

rm -rf "$ROOT"

# ============================================================
echo ""
echo "=== Test: unrelated commands pass through silently ==="
# ============================================================

ROOT=$(make_root)
setup_plan_dir "$ROOT"
write_plan "$ROOT" "pending"

run_hook "git status" "$ROOT" "On branch main"
assert_empty_output "unrelated command produces no hook output"
assert_not_exists "$ROOT/.temp/plan-mode/active/demo/.codex-preflight-$$" "unrelated command does not create preflight marker"
assert_not_exists "$ROOT/.temp/plan-mode/active/demo/.codex-co-exploration-$$" "unrelated command does not create co-exploration marker"

rm -rf "$ROOT"

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "FAIL: track-codex-exploration tests failed ($FAIL failures, $PASS passes)" >&2
  exit 1
fi

echo ""
echo "PASS: track-codex-exploration regression tests"
