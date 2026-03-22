#!/usr/bin/env bash
# Direction-locked Codex verification script.
#
# Runs `codex exec` in read-only sandbox to verify a Claude-implemented step.
# Validates that the step is owned by Claude (rejects codex-impl steps).
#
# Usage: run-codex-verify.sh <plan.json-path> <step-number>
#
# Output:
#   JSONL stream: <plan-dir>/.codex-stream-step-N.jsonl
#   Result file:  <plan-dir>/.codex-result-step-N.txt
#
# Exit codes:
#   0 — codex exec completed (check result file for PASS/findings)
#   1 — validation error (wrong owner, missing codex, bad args)
#   * — codex exec exit code passed through

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: run-codex-verify.sh <plan.json-path> <step-number>" >&2
  exit 1
fi

PLAN_JSON="$1"
STEP_NUM="$2"

if [ ! -f "$PLAN_JSON" ]; then
  echo "Error: plan.json not found at $PLAN_JSON" >&2
  exit 1
fi

# Validate ownership FIRST — direction lock must reject before anything else
export LBYL_PLAN_JSON="$PLAN_JSON"
export LBYL_STEP_NUM="$STEP_NUM"
python3 << 'PYEOF' || exit 1
import json, os, sys

plan_json = os.environ["LBYL_PLAN_JSON"]
step_num = int(os.environ["LBYL_STEP_NUM"])

with open(plan_json) as f:
    plan = json.load(f)

step = None
for s in plan.get("steps", []):
    if s["id"] == step_num:
        step = s
        break

if not step:
    print(f"ERROR: Step {step_num} not found in plan.json", file=sys.stderr)
    sys.exit(1)

owner = step.get("owner", "claude")
if owner != "claude":
    print(f"ERROR: Cannot verify a {owner}-owned step. Codex verifies Claude's work only. Claude must verify codex-impl steps independently.", file=sys.stderr)
    sys.exit(1)
PYEOF

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI not found. Install with: npm install -g @openai/codex" >&2
  exit 1
fi

PLAN_DIR="$(cd "$(dirname "$PLAN_JSON")" && pwd)"
STREAM_FILE="$PLAN_DIR/.codex-stream-step-${STEP_NUM}.jsonl"
RESULT_FILE="$PLAN_DIR/.codex-result-step-${STEP_NUM}.txt"

# Find project root: walk up from plan.json looking for .git or CLAUDE.md
find_project_root() {
  local dir="$1"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "$1"
}

PROJECT_ROOT="$(find_project_root "$PLAN_DIR")"

# Build the prompt — minimal, since Codex reads plan.json and discovery.md itself
PROMPT="Verify step ${STEP_NUM} of the plan at ${PLAN_JSON}.

Read the plan file to understand the step's acceptance criteria, description, and files list. Also read discovery.md in the same directory for codebase context (scope, consumers, blast radius).

Check every acceptance criterion mechanically:
- Run the project's type checker (tsc, tsgo, mypy, etc.) and relevant tests
- Read the modified files and verify changes match the specification
- Use deps-query on modified shared files to check consumer integrity (if dep maps are configured)
- Look for bugs, type safety holes, silent scope cuts, and missed consumers

Report PASS if all criteria are met, or report structured findings with:
- Severity: HIGH (blocks shipping) / MEDIUM (should fix) / LOW (nit)
- File and line number
- What is wrong and why
- Suggested fix
- Failure category: INCOMPLETE_WORK, MISSED_CONSUMER, TYPE_SAFETY, SILENT_SCOPE_CUT, WRONG_PATTERN, MISSING_TEST, MISSING_I18N, or OTHER"

# Run codex exec with read-only sandbox
codex exec \
  -C "$PROJECT_ROOT" \
  --sandbox read-only \
  --dangerously-bypass-approvals-and-sandbox \
  --json \
  -o "$RESULT_FILE" \
  "$PROMPT" \
  > "$STREAM_FILE" 2>&1

exit $?
