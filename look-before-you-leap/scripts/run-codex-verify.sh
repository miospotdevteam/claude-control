#!/usr/bin/env bash
# Direction-locked Codex verification script.
#
# Runs `codex exec` to verify a Claude-implemented step
# or a Claude-owned group within a collab-split step.
# Validates that the effective owner is Claude (rejects codex-owned targets).
#
# Usage:
#   run-codex-verify.sh <plan.json-path> <step-number>              # verify whole step
#   run-codex-verify.sh <plan.json-path> <step-number> <group-idx>  # verify one group (0-based)
#
# Output:
#   JSONL stream: <plan-dir>/.codex-stream-step-N.jsonl (or step-N-group-G.jsonl)
#   Result file:  <plan-dir>/.codex-result-step-N.txt (or step-N-group-G.txt)
#
# Exit codes:
#   0 — codex exec completed (check result file for PASS/findings)
#   1 — validation error (wrong owner, missing codex, bad args)
#   * — codex exec exit code passed through

set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: run-codex-verify.sh <plan.json-path> <step-number> [group-index]" >&2
  exit 1
fi

PLAN_JSON="$1"
STEP_NUM="$2"
GROUP_IDX="${3:-}"

if [ ! -f "$PLAN_JSON" ]; then
  echo "Error: plan.json not found at $PLAN_JSON" >&2
  exit 1
fi

# Validate ownership FIRST — direction lock must reject before anything else
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
FILE_SCOPE=$(python3 "$SCRIPT_DIR/validate_step_ownership.py" "$PLAN_JSON" "$STEP_NUM" $GROUP_IDX --direction verify) || exit 1

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI not found. Install with: npm install -g @openai/codex" >&2
  exit 1
fi

PLAN_DIR="$(cd "$(dirname "$PLAN_JSON")" && pwd)"

# Output file naming: step-N or step-N-group-G
if [ -n "$GROUP_IDX" ]; then
  SUFFIX="step-${STEP_NUM}-group-${GROUP_IDX}"
else
  SUFFIX="step-${STEP_NUM}"
fi

# Write in-flight PID marker so guard-handoff-background.sh can detect running Codex tasks
# Uses SUFFIX to avoid collisions between concurrent group runs on the same step
INFLIGHT_MARKER="$PLAN_DIR/.codex-inflight-${SUFFIX}.pid"
echo $$ > "$INFLIGHT_MARKER"
cleanup_inflight() {
  rm -f "$INFLIGHT_MARKER"
}
trap cleanup_inflight EXIT
STREAM_FILE="$PLAN_DIR/.codex-stream-${SUFFIX}.jsonl"
RESULT_FILE="$PLAN_DIR/.codex-result-${SUFFIX}.txt"

# Source canonical find_project_root from hooks/lib/
source "${SCRIPT_DIR}/../hooks/lib/find-root.sh"

PROJECT_ROOT="$(find_project_root "$PLAN_DIR")"

# Build the prompt
if [ -n "$GROUP_IDX" ] && [ -n "$FILE_SCOPE" ]; then
  PROMPT="Verify group ${GROUP_IDX} of step ${STEP_NUM} in the plan at ${PLAN_JSON}.

This is a collab-split step — verify ONLY the files in this group: ${FILE_SCOPE}

Read the plan file to understand the step's acceptance criteria and the group's scope. Also read discovery.md in the same directory for codebase context.

Check the group's files mechanically:
- Run the project's type checker (tsc, tsgo, mypy, etc.) and relevant tests
- Read the modified files and verify changes match the specification
- Use deps-query on modified shared files to check consumer integrity (if dep maps are configured)
- Look for bugs, type safety holes, silent scope cuts, and missed consumers

Also run the standard checks from the lbyl-verify skill (Step 3.5) regardless of criteria:
- i18n: check new user-visible strings exist in ALL locale files
- State transitions: check loading, switching, error paths — not just the initial render
- Description parity: compare step description deliverables against actual implementation
- Empty/edge states: check what happens when data is null, empty, zero, or error
- Pattern matching: if a UI pattern exists elsewhere, verify config matches

Report PASS if the group's work is correct, or report structured findings with:
- Severity: HIGH (blocks shipping) / MEDIUM (should fix) / LOW (nit)
- File and line number
- What is wrong and why
- Suggested fix
- Failure category: INCOMPLETE_WORK, MISSED_CONSUMER, TYPE_SAFETY, SILENT_SCOPE_CUT, WRONG_PATTERN, MISSING_TEST, MISSING_I18N, or OTHER"
else
  PROMPT="Verify step ${STEP_NUM} of the plan at ${PLAN_JSON}.

Read the plan file to understand the step's acceptance criteria, description, and files list. Also read discovery.md in the same directory for codebase context (scope, consumers, blast radius).

Check every acceptance criterion mechanically:
- Run the project's type checker (tsc, tsgo, mypy, etc.) and relevant tests
- Read the modified files and verify changes match the specification
- Use deps-query on modified shared files to check consumer integrity (if dep maps are configured)
- Look for bugs, type safety holes, silent scope cuts, and missed consumers

Also run the standard checks from the lbyl-verify skill (Step 3.5) regardless of criteria:
- i18n: check new user-visible strings exist in ALL locale files
- State transitions: check loading, switching, error paths — not just the initial render
- Description parity: compare step description deliverables against actual implementation
- Empty/edge states: check what happens when data is null, empty, zero, or error
- Pattern matching: if a UI pattern exists elsewhere, verify config matches

Report PASS if all criteria are met, or report structured findings with:
- Severity: HIGH (blocks shipping) / MEDIUM (should fix) / LOW (nit)
- File and line number
- What is wrong and why
- Suggested fix
- Failure category: INCOMPLETE_WORK, MISSED_CONSUMER, TYPE_SAFETY, SILENT_SCOPE_CUT, WRONG_PATTERN, MISSING_TEST, MISSING_I18N, or OTHER"
fi

# Run codex exec
codex exec \
  -C "$PROJECT_ROOT" \
  --dangerously-bypass-approvals-and-sandbox \
  --json \
  -o "$RESULT_FILE" \
  "$PROMPT" \
  > "$STREAM_FILE" 2>&1

CODEX_EXIT=$?

# Emit signed receipt ONLY if codex exited 0 AND result starts with PASS
if [ "$CODEX_EXIT" -eq 0 ] && [ -f "$RESULT_FILE" ]; then
  RESULT_FIRST_LINE=$(head -1 "$RESULT_FILE" | tr '[:lower:]' '[:upper:]')
  if [[ "$RESULT_FIRST_LINE" == "PASS"* ]]; then
    # Mint codex_verify receipt
    PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${PLUGIN_ROOT}/hooks/lib/receipt-state.sh"
    receipt_bootstrap 2>/dev/null || true
    PROJ_ID=$(receipt_project_id "$PROJECT_ROOT" 2>/dev/null) || true
    P_ID=$(receipt_plan_id "$PLAN_JSON" 2>/dev/null) || true
    if [ -n "$PROJ_ID" ] && [ -n "$P_ID" ]; then
      receipt_sign "codex_verify" "$PROJ_ID" "$P_ID" "step=$STEP_NUM" >/dev/null 2>&1 || true
    fi
  fi
fi

exit $CODEX_EXIT
