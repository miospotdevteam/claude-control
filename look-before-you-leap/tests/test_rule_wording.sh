#!/usr/bin/env bash
# Regression tests for hard-rule wording in core skill surfaces.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  PASS=$((PASS + 1))
}

assert_contains() {
  local file="$1"
  local needle="$2"
  local desc="$3"
  if grep -Fq "$needle" "$file"; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc"
  fi
}

echo "=== Test: conductor frames rules as binding ==="
assert_contains \
  "${PLUGIN_ROOT}/skills/look-before-you-leap/SKILL.md" \
  "This plugin defines operational rules, not suggestions." \
  "conductor says rules are not suggestions"
assert_contains \
  "${PLUGIN_ROOT}/skills/look-before-you-leap/SKILL.md" \
  "Ambiguity is not permission to explore directly." \
  "conductor removes ambiguous brainstorm escape hatch"

echo ""
echo "=== Test: engineering discipline frames shortcuts as forbidden ==="
assert_contains \
  "${PLUGIN_ROOT}/skills/engineering-discipline/SKILL.md" \
  "Read this skill as an operating contract, not a style guide." \
  "engineering discipline calls itself a contract"
assert_contains \
  "${PLUGIN_ROOT}/skills/engineering-discipline/SKILL.md" \
  "Confidence is not an override. Speed is not an override. Good intentions are" \
  "engineering discipline rejects shortcut rationalization"

echo ""
echo "=== Test: writing plans blocks substitute plans ==="
assert_contains \
  "${PLUGIN_ROOT}/skills/writing-plans/SKILL.md" \
  "Those are all plan-writing attempts. The gate blocks them too." \
  "writing plans blocks quick-plan substitutes"
assert_contains \
  "${PLUGIN_ROOT}/skills/writing-plans/SKILL.md" \
  "Treat an all-claude-impl first draft as a planning failure" \
  "writing plans treats all-claude plan as failure"

echo ""
echo "=== Test: codex dispatch forbids silent substitution ==="
assert_contains \
  "${PLUGIN_ROOT}/skills/codex-dispatch/SKILL.md" \
  "This skill is not advisory. It is the required path for Codex work." \
  "codex dispatch says it is required"
assert_contains \
  "${PLUGIN_ROOT}/skills/codex-dispatch/SKILL.md" \
  "If a dispatch hangs or fails, that is NOT permission to skip Codex" \
  "codex dispatch blocks skip-after-failure behavior"

echo ""
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
