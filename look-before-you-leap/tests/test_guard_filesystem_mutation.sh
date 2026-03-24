#!/usr/bin/env bash
# Tests for guard-filesystem-mutation.sh PreToolUse hook
#
# Tests that filesystem mutations are classified and enforced correctly:
#   - Read-only commands pass through
#   - Mutating commands inside project are allowed
#   - Mutating commands outside project are denied
#   - Destructive commands inside project require receipt
#   - Plugin wrapper scripts pass through
#   - .temp/ paths are always allowed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/guard-filesystem-mutation.sh"

# Use a temp dir as fake project root
FAKE_PROJECT=$(mktemp -d "${TMPDIR:-/tmp}/guard-mut-test.XXXXXX")
mkdir -p "$FAKE_PROJECT/.git"
mkdir -p "$FAKE_PROJECT/.temp/plan-mode"

PASS=0
FAIL=0
HOOK_OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/guard-mut-out.XXXXXX")
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
echo "=== Read-only commands pass through ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "cat /etc/hosts"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "cat is read-only"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "ls -la /some/dir"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "ls is read-only"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "git status"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "git status is read-only"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "git log --oneline -5"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "git log is read-only"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "echo hello"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "echo is read-only"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "git diff HEAD~1"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "git diff is read-only"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "wc -l somefile.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "wc is read-only"

# ============================================================
echo ""
echo "=== Mutating inside project allowed ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "rm '"$FAKE_PROJECT"'/some-file.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "rm inside project allowed"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "mv '"$FAKE_PROJECT"'/a.txt '"$FAKE_PROJECT"'/b.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "mv inside project allowed"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "cp '"$FAKE_PROJECT"'/a.txt '"$FAKE_PROJECT"'/b.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "cp inside project allowed"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "mkdir '"$FAKE_PROJECT"'/new-dir"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "mkdir inside project allowed"

# ============================================================
echo ""
echo "=== Mutating inside .temp/ always allowed ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "rm '"$FAKE_PROJECT"'/.temp/plan-mode/some-file"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "rm inside .temp/ allowed"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "rm -rf '"$FAKE_PROJECT"'/.temp/plan-mode/old-plan"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "rm -rf inside .temp/ allowed"

# ============================================================
echo ""
echo "=== Mutating outside project denied ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "rm /other/project/file.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "rm outside project denied"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "mv /other/project/a.txt /other/project/b.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "mv outside project denied"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "cp '"$FAKE_PROJECT"'/a.txt /other/project/b.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "cp to outside project denied"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "mkdir /other/project/new-dir"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "mkdir outside project denied"

# ============================================================
echo ""
echo "=== Mutating with cwd in subdirectory (relative paths resolve correctly) ==="
# ============================================================

# rm ../file from subdir should be inside project, not cross-root
run_hook '{"tool_name": "Bash", "tool_input": {"command": "rm ../some-file.txt"}, "cwd": "'"$FAKE_PROJECT"'/subdir"}'
assert_allowed "rm ../file from subdir is inside project (allowed)"

# ============================================================
echo ""
echo "=== Destructive inside project denied (no receipt) ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "rm -rf '"$FAKE_PROJECT"'/src"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "rm -rf inside project denied"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "rm -r '"$FAKE_PROJECT"'/src"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "rm -r inside project denied"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "find '"$FAKE_PROJECT"' -name \"*.tmp\" -delete"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "find -delete inside project denied (absolute path)"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "find . -name \"*.tmp\" -delete"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "find . -delete inside project denied (relative path)"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "find . -type f -delete"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "find . -type f -delete denied"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "git clean -fd"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "git clean -fd inside project denied"

# ============================================================
echo ""
echo "=== Destructive outside project denied ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "rm -rf /other/project"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "rm -rf outside project denied"

# ============================================================
echo ""
echo "=== Plugin wrapper scripts pass through ==="
# ============================================================

export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "bash '"$PLUGIN_ROOT"'/skills/look-before-you-leap/scripts/run-codex-verify.sh arg1"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Plugin wrapper run-codex-verify.sh allowed"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "bash '"$PLUGIN_ROOT"'/scripts/write-discovery-receipt.sh arg1"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Plugin wrapper write-discovery-receipt.sh allowed"

# Wrapper with compound operator should be denied
run_hook '{"tool_name": "Bash", "tool_input": {"command": "bash '"$PLUGIN_ROOT"'/scripts/write-discovery-receipt.sh arg1 && rm -rf /"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "Plugin wrapper with compound operator denied"

unset CLAUDE_PLUGIN_ROOT

# ============================================================
echo ""
echo "=== Empty/missing command passes ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": ""}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Empty command passes"

run_hook '{"tool_name": "Bash", "tool_input": {}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Missing command passes"

# ============================================================
echo ""
echo "=== Build/package commands pass (not classified as mutations) ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "npm install"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "npm install passes safe regex"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "find . -name \"*.txt\" -type f"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "find without -delete is read-only"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "python3 -c \"print(42)\""}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "python3 -c passes safe regex"

# ============================================================
echo ""
echo "=== File-writing commands denied without plan ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "echo hello > '"$FAKE_PROJECT"'/output.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "Redirect > denied without plan"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "echo hello >> '"$FAKE_PROJECT"'/output.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "Append >> denied without plan"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "sed -i s/old/new/g '"$FAKE_PROJECT"'/file.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "sed -i denied without plan"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "tee '"$FAKE_PROJECT"'/output.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "tee denied without plan"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "dd if=/dev/zero of='"$FAKE_PROJECT"'/file bs=1k count=1"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "dd of= denied without plan"

# ============================================================
echo ""
echo "=== Nested bash scripts denied without plan ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "bash /tmp/random-script.sh"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "bash random-script.sh denied without plan"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "bash /tmp/random-script"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "bash extensionless script denied without plan"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "sh ./deploy.sh"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "sh ./deploy.sh denied without plan"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "sh ./deploy"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "sh extensionless script denied without plan"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "./install.sh"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "./install.sh denied without plan"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "./install"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "./install (no ext) denied without plan"

# ============================================================
echo ""
echo "=== tar/unzip denied outside project ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "tar xzf archive.tar.gz -C /other/project"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "tar to outside project denied"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "unzip archive.zip -d /other/project"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "unzip to outside project denied"

# tar inside project requires plan (archive extraction writes files)
run_hook '{"tool_name": "Bash", "tool_input": {"command": "tar xzf '"$FAKE_PROJECT"'/archive.tar.gz -C '"$FAKE_PROJECT"'/out"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "tar inside project denied without plan"

# ============================================================
echo ""
echo "=== /dev/null and .temp redirects pass through ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "some-command > /dev/null 2>&1"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "/dev/null redirect passes"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "echo test > '"$FAKE_PROJECT"'/.temp/plan-mode/scratch.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed ".temp redirect passes"

# ============================================================
echo ""
echo "=== grant-bypass.sh blocked ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "bash /some/path/grant-bypass.sh"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "grant-bypass.sh blocked"

# ============================================================
echo ""
echo "=== grant-bypass.sh via wrapper path denied ==="
# ============================================================

export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "bash '"$PLUGIN_ROOT"'/scripts/grant-bypass.sh"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "grant-bypass.sh via plugin root denied"

unset CLAUDE_PLUGIN_ROOT

# ============================================================
echo ""
echo "=== Interpreter writes denied without plan ==="
# ============================================================

run_hook '{"tool_name": "Bash", "tool_input": {"command": "python3 -c \"open('"'"'/tmp/evil.txt'"'"','"'"'w'"'"').write('"'"'x'"'"')\""}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "python3 -c write denied"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "node -e \"require('"'"'fs'"'"').writeFileSync('"'"'/tmp/evil.txt'"'"','"'"'x'"'"')\""}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_denied "node -e writeFile denied"

# python3 -c with no file writes should be safe (classified as safe by Python block)
run_hook '{"tool_name": "Bash", "tool_input": {"command": "python3 -c \"print(42)\""}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "python3 -c print is safe"

# ============================================================
echo ""
echo "=== File-writing allowed WITH plan ==="
# ============================================================

# Create a fake plan to test plan-based allow
mkdir -p "$FAKE_PROJECT/.temp/plan-mode/active/test-plan"
echo '{"name":"test-plan","status":"active","steps":[]}' > "$FAKE_PROJECT/.temp/plan-mode/active/test-plan/plan.json"
echo "$$" > "$FAKE_PROJECT/.temp/plan-mode/active/test-plan/.session-lock"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "echo hello > '"$FAKE_PROJECT"'/output.txt"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Redirect allowed with plan"

run_hook '{"tool_name": "Bash", "tool_input": {"command": "bash /tmp/random-script.sh"}, "cwd": "'"$FAKE_PROJECT"'"}'
assert_allowed "Nested script allowed with plan"

# Clean up fake plan
rm -rf "$FAKE_PROJECT/.temp/plan-mode/active/test-plan"

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
