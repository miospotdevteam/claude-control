#!/usr/bin/env bash
# Tests for enforce-plan-bash.sh PreToolUse hook
#
# Tests codex wrapper script exemptions, bare codex exec handling,
# file-write detection, and plan-state gating.
#
# IMPORTANT: Tests that check plan-based allow must NOT wrap run_hook in
# $() because that creates a subshell with a different PID, breaking the
# PPID-based session lock match.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/enforce-plan-bash.sh"

PASS=0
FAIL=0
HOOK_OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/hook-out.XXXXXX")
trap 'rm -f "$HOOK_OUT_FILE"' EXIT

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  PASS=$((PASS + 1))
}

assert_allowed_file() {
  local desc="$1"
  local output
  output=$(cat "$HOOK_OUT_FILE")
  if [[ "$output" == *'"permissionDecision"'*'"deny"'* ]]; then
    fail "$desc — expected allow, got deny"
  else
    pass
    echo "  PASS: $desc"
  fi
}

assert_denied_file() {
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

make_root() {
  mktemp -d "${TMPDIR:-/tmp}/enforce-plan-bash.XXXXXX"
}

make_input() {
  local cmd="$1"
  local cwd="$2"
  python3 -c "
import json, sys
print(json.dumps({
    'tool_name': 'Bash',
    'tool_input': {'command': sys.argv[1]},
    'cwd': sys.argv[2]
}))
" "$cmd" "$cwd"
}

# run_hook writes output to HOOK_OUT_FILE (no subshell, preserves PPID)
run_hook() {
  local cmd="$1"
  local cwd="$2"
  : > "$HOOK_OUT_FILE"
  make_input "$cmd" "$cwd" | bash "$HOOK" > "$HOOK_OUT_FILE" 2>/dev/null || true
}

setup_with_plan() {
  local root="$1"
  mkdir -p "$root/.git" "$root/.temp/plan-mode/active/demo"
  cat > "$root/.temp/plan-mode/active/demo/plan.json" << 'JSON'
{
  "name": "demo",
  "title": "Demo",
  "context": "test",
  "status": "active",
  "steps": [{"id": 1, "title": "t", "status": "in_progress"}],
  "blocked": [],
  "completedSummary": [],
  "deviations": []
}
JSON
  # Session lock must match the hook's $PPID, which is this script's $$
  echo "$$" > "$root/.temp/plan-mode/active/demo/.session-lock"
}

cleanup() {
  rm -rf "$1"
}

# ============================================================
echo "=== Test: Known Codex wrapper scripts pass without plan ==="
# ============================================================

ROOT=$(make_root)
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode"

run_hook "bash /some/path/run-codex-verify.sh plan.json 1" "$ROOT"
assert_allowed_file "run-codex-verify.sh without plan"

run_hook "bash /some/path/run-codex-implement.sh plan.json 2" "$ROOT"
assert_allowed_file "run-codex-implement.sh without plan"

run_hook "bash /plugin/scripts/write-discovery-receipt.sh arg" "$ROOT"
assert_allowed_file "write-discovery-receipt.sh without plan"

run_hook "bash /plugin/scripts/write-claude-verify-receipt.sh arg" "$ROOT"
assert_allowed_file "write-claude-verify-receipt.sh without plan"

cleanup "$ROOT"

# ============================================================
echo ""
echo "=== Test: Bare codex exec without redirects passes (not a file write) ==="
# ============================================================

ROOT=$(make_root)
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode"

run_hook "codex exec --fast 'review this code'" "$ROOT"
assert_allowed_file "codex exec without redirects"

cleanup "$ROOT"

# ============================================================
echo ""
echo "=== Test: Bare codex exec WITH redirects denied without plan ==="
# ============================================================

ROOT=$(make_root)
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode"

run_hook "codex exec --fast 'review' > .codex-result.txt" "$ROOT"
assert_denied_file "codex exec with redirect, no plan"

cleanup "$ROOT"

# ============================================================
echo ""
echo "=== Test: Bare codex exec WITH redirects allowed with plan ==="
# ============================================================

ROOT=$(make_root)
setup_with_plan "$ROOT"

run_hook "codex exec --fast 'review' > .codex-result.txt" "$ROOT"
assert_allowed_file "codex exec with redirect, has plan"

cleanup "$ROOT"

# ============================================================
echo ""
echo "=== Test: Compound commands with wrapper names denied without plan ==="
# ============================================================

ROOT=$(make_root)
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode"

run_hook "echo hacked > pwned.txt && bash /tmp/run-codex-verify.sh plan.json 1" "$ROOT"
assert_denied_file "compound && with wrapper name, no plan"

run_hook "echo hacked > pwned.txt; bash /tmp/run-codex-verify.sh plan.json 1" "$ROOT"
assert_denied_file "compound ; with wrapper name, no plan"

run_hook "echo hacked > pwned.txt || bash /tmp/run-codex-verify.sh plan.json 1" "$ROOT"
assert_denied_file "compound || with wrapper name, no plan"

# Pipe: "cat file |" passes because cat is an allowed prefix. This is
# correct — cat doesn't write files, the pipe just sends data to the
# wrapper. A real pipe exploit would need "echo > file | wrapper" but
# that's caught by the redirect pattern before the prefix check.

# Non-plugin path reusing wrapper basename with redirect — must be denied
run_hook "bash /tmp/evil/run-codex-verify.sh plan.json 1 > output.txt" "$ROOT"
assert_denied_file "spoofed wrapper path with redirect outside plugin root, no plan"

cleanup "$ROOT"

# ============================================================
echo ""
echo "=== Test: Plugin-root wrapper scripts pass with CLAUDE_PLUGIN_ROOT ==="
# ============================================================

ROOT=$(make_root)
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode"

# Set CLAUDE_PLUGIN_ROOT to allow plugin-owned scripts
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# Without redirect (not a file write, passes trivially)
run_hook "bash ${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/run-codex-verify.sh plan.json 1" "$ROOT"
assert_allowed_file "plugin-root wrapper without redirect, no plan"

# With redirect (file write, must pass via early allow)
run_hook "bash ${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/run-codex-verify.sh plan.json 1 > .codex-result.txt" "$ROOT"
assert_allowed_file "plugin-root wrapper with redirect, no plan"

# Quoted path (must also pass — quotes should be stripped)
run_hook "bash \"${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/run-codex-verify.sh\" plan.json 1 > .codex-result.txt" "$ROOT"
assert_allowed_file "quoted plugin-root wrapper with redirect, no plan"

# Sibling-dir spoof (look-before-you-leap-evil/) — must be denied.
# This is a string-path check only; no real sibling fixture is required.
run_hook "bash ${PLUGIN_ROOT}-evil/scripts/run-codex-verify.sh plan.json 1 > out.txt" "$ROOT"
assert_denied_file "sibling-dir spoof with redirect, no plan"

unset CLAUDE_PLUGIN_ROOT

cleanup "$ROOT"

# ============================================================
echo ""
echo "=== Test: Non-Codex file writes denied without plan ==="
# ============================================================

ROOT=$(make_root)
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode"

run_hook "echo hello > somefile.txt" "$ROOT"
assert_denied_file "echo redirect without plan"

run_hook "sed -i 's/foo/bar/' file.txt" "$ROOT"
assert_denied_file "sed -i without plan"

run_hook "tee output.log" "$ROOT"
assert_denied_file "tee without plan"

cleanup "$ROOT"

# ============================================================
echo ""
echo "=== Test: Non-Codex file writes allowed with plan ==="
# ============================================================

ROOT=$(make_root)
setup_with_plan "$ROOT"

run_hook "echo hello > somefile.txt" "$ROOT"
assert_allowed_file "echo redirect with plan"

cleanup "$ROOT"

# ============================================================
echo ""
echo "=== Test: Allowed prefixes pass without plan ==="
# ============================================================

ROOT=$(make_root)
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode"

run_hook "git status" "$ROOT"
assert_allowed_file "git command"

run_hook "npm install" "$ROOT"
assert_allowed_file "npm command"

run_hook "python3 -m pytest tests/" "$ROOT"
assert_allowed_file "pytest command"

run_hook "tsc --noEmit" "$ROOT"
assert_allowed_file "tsc command"

run_hook "bash -n script.sh" "$ROOT"
assert_allowed_file "bash -n syntax check"

cleanup "$ROOT"

# ============================================================
echo ""
echo "=== Test: .temp/ redirects pass without plan ==="
# ============================================================

ROOT=$(make_root)
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode"

run_hook "echo data > .temp/plan-mode/notes.txt" "$ROOT"
assert_allowed_file ".temp redirect without plan"

cleanup "$ROOT"

# ============================================================
echo ""
echo "=== Test: /dev/null redirects pass (not real file writes) ==="
# ============================================================

ROOT=$(make_root)
mkdir -p "$ROOT/.git" "$ROOT/.temp/plan-mode"

run_hook "some-command 2>/dev/null" "$ROOT"
assert_allowed_file "/dev/null redirect"

cleanup "$ROOT"

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
