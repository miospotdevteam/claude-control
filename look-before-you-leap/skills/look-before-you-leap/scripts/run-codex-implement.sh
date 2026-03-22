#!/usr/bin/env bash
# Direction-locked Codex implementation script.
#
# Runs `codex exec` in workspace-write sandbox for Codex-owned steps.
# Validates that the step is owned by Codex (rejects claude-impl steps).
#
# Usage: run-codex-implement.sh <plan.json-path> <step-number>
#
# Output:
#   JSONL stream: <plan-dir>/.codex-stream-step-N.jsonl
#   Result file:  <plan-dir>/.codex-result-step-N.txt
#
# Exit codes:
#   0 — codex exec completed (check result file for report)
#   1 — validation error (wrong owner, missing codex, bad args)
#   * — codex exec exit code passed through

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: run-codex-implement.sh <plan.json-path> <step-number>" >&2
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
if owner != "codex":
    print(f"ERROR: Cannot implement a {owner}-owned step. This script is for codex-impl steps only. Claude implements claude-impl steps directly.", file=sys.stderr)
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

# Build the prompt — minimal, Codex reads plan.json and discovery.md itself
PROMPT="Implement step ${STEP_NUM} of the plan at ${PLAN_JSON}.

Read the plan file to understand the step's description, acceptance criteria, files list, and progress items. Also read discovery.md in the same directory for codebase context (scope, consumers, blast radius, existing patterns).

For each file you need to modify:
- Read the file AND its imports before editing
- Check sibling files for patterns and conventions
- Implement exactly what the step description specifies — no scope additions, no scope cuts

After completing all progress items:
- Run the project's type checker (tsc, tsgo, mypy, etc.) and relevant tests
- Check consumers of any shared code you modified (use deps-query if dep maps are configured)

Report your results as:
- FILES CHANGED: list of files you created or modified
- WHAT WAS DONE: brief summary per progress item
- VERIFICATION: type checker and test results (pass/fail with output)
- ISSUES: anything that did not go as expected, or 'none'"

# Run codex exec with workspace-write sandbox
codex exec \
  -C "$PROJECT_ROOT" \
  --sandbox workspace-write \
  --dangerously-bypass-approvals-and-sandbox \
  --json \
  -o "$RESULT_FILE" \
  "$PROMPT" \
  > "$STREAM_FILE" 2>&1

exit $?
