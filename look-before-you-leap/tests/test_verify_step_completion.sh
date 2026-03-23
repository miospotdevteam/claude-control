#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/verify-step-completion.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output to not contain: $needle"
}

assert_exists() {
  local path="$1"
  [[ -e "$path" ]] || fail "expected file to exist: $path"
}

assert_not_exists() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "expected file to be absent: $path"
}

make_root() {
  mktemp -d "${TMPDIR:-/tmp}/verify-step-completion.XXXXXX"
}

write_fixture() {
  local root="$1"
  local owner="$2"
  local mode="$3"
  local acceptance="$4"
  local result="$5"

  mkdir -p "$root/.git" "$root/.temp/plan-mode/active/demo"

  python3 - "$root" "$owner" "$mode" "$acceptance" "$result" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
owner = sys.argv[2]
mode = sys.argv[3]
acceptance = sys.argv[4]
result = sys.argv[5]

plan_dir = root / ".temp" / "plan-mode" / "active" / "demo"
plan = {
    "name": "demo",
    "title": "Demo",
    "status": "active",
    "steps": [
        {
            "id": 1,
            "title": "Hook regression",
            "status": "done",
            "owner": owner,
            "mode": mode,
            "skill": "none",
            "codexVerify": True,
            "acceptanceCriteria": acceptance,
            "files": ["look-before-you-leap/tests/test_verify_step_completion.sh"],
            "progress": [],
            "result": result,
        }
    ],
}

(plan_dir / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
payload = {
    "tool_name": "Edit",
    "tool_input": {"file_path": str(plan_dir / "plan.json")},
    "cwd": str(root),
}
(root / "input.json").write_text(json.dumps(payload), encoding="utf-8")
PY
}

run_hook() {
  local root="$1"
  bash "$HOOK" < "$root/input.json"
}

test_claude_impl_with_codex_verdict_passes() {
  local root
  root="$(make_root)"
  trap 'rm -rf "$root"' RETURN

  local result
  result=$'### Criterion: "first criterion"\n- updated implementation\n\n### Criterion: "second criterion"\n- ran verification\n\n### Verdict\nCodex: PASS'
  write_fixture "$root" "claude" "claude-impl" "1. first criterion. 2. second criterion." "$result"

  local output
  output="$(run_hook "$root")"

  assert_contains "$output" "STEP VERIFICATION REQUIRED"
  assert_not_contains "$output" "RESULT TEMPLATE WARNING"
  assert_exists "$root/.temp/plan-mode/active/demo/.verify-pending-1"
  assert_exists "$root/.temp/plan-mode/active/demo/.step-status-cache"
}

test_claude_impl_without_codex_verdict_is_blocked() {
  local root
  root="$(make_root)"
  trap 'rm -rf "$root"' RETURN

  local result
  result=$'### Criterion: "first criterion"\n- updated implementation'
  write_fixture "$root" "claude" "claude-impl" "1. first criterion." "$result"

  local output
  output="$(run_hook "$root")"

  assert_contains "$output" "CODEX VERIFICATION REQUIRED BEFORE MARKING DONE"
  assert_not_exists "$root/.temp/plan-mode/active/demo/.verify-pending-1"
}

test_codex_impl_with_claude_verification_passes() {
  local root
  root="$(make_root)"
  trap 'rm -rf "$root"' RETURN

  local result
  result=$'### Criterion: "only criterion"\n- reviewed changes\n\n### Verdict\nClaude: verified'
  write_fixture "$root" "codex" "codex-impl" "1. only criterion." "$result"

  local output
  output="$(run_hook "$root")"

  assert_contains "$output" "STEP VERIFICATION REQUIRED"
  assert_not_contains "$output" "CLAUDE INDEPENDENT VERIFICATION REQUIRED"
  assert_not_contains "$output" "RESULT TEMPLATE WARNING"
  assert_exists "$root/.temp/plan-mode/active/demo/.verify-pending-1"
}

test_warning_emitted_for_too_few_criterion_markers() {
  local root
  root="$(make_root)"
  trap 'rm -rf "$root"' RETURN

  local result
  result=$'### Criterion: "first criterion"\n- updated implementation\n\n### Verdict\nCodex: PASS'
  write_fixture "$root" "claude" "claude-impl" "1. first criterion. 2. second criterion." "$result"

  local output
  output="$(run_hook "$root")"

  assert_contains "$output" "RESULT TEMPLATE WARNING"
  assert_contains "$output" "Result field has 1 criterion markers but acceptanceCriteria has 2 items"
}

test_matching_criterion_count_emits_no_warning() {
  local root
  root="$(make_root)"
  trap 'rm -rf "$root"' RETURN

  local result
  result=$'### Criterion: "first criterion"\n- updated implementation\n\n### Criterion: "second criterion"\n- ran verification\n\n### Verdict\nCodex: PASS'
  write_fixture "$root" "claude" "claude-impl" "1. first criterion. 2. second criterion." "$result"

  local output
  output="$(run_hook "$root")"

  assert_not_contains "$output" "RESULT TEMPLATE WARNING"
}

test_claude_impl_with_codex_verdict_passes
test_claude_impl_without_codex_verdict_is_blocked
test_codex_impl_with_claude_verification_passes
test_warning_emitted_for_too_few_criterion_markers
test_matching_criterion_count_emits_no_warning

echo "PASS: verify-step-completion regression tests"
