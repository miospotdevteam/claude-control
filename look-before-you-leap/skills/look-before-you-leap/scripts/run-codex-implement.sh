#!/usr/bin/env bash
# Direction-locked Codex implementation script.
#
# Runs `codex exec` for Codex-owned steps
# or Codex-owned groups within a collab-split step.
# Validates that the effective owner is Codex (rejects claude-owned targets).
#
# Usage:
#   run-codex-implement.sh <plan.json-path> <step-number>              # implement whole step
#   run-codex-implement.sh <plan.json-path> <step-number> <group-idx>  # implement one group (0-based)
#
# Output:
#   JSONL stream: <plan-dir>/.codex-stream-step-N.jsonl (or step-N-group-G.jsonl)
#   Result file:  <plan-dir>/.codex-result-step-N.txt (or step-N-group-G.txt)
#
# Exit codes:
#   0 — codex exec completed (check result file for report)
#   1 — validation error (wrong owner, missing codex, bad args)
#   * — codex exec exit code passed through

set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: run-codex-implement.sh <plan.json-path> <step-number> [group-index]" >&2
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
export LBYL_PLAN_JSON="$PLAN_JSON"
export LBYL_STEP_NUM="$STEP_NUM"
export LBYL_GROUP_IDX="$GROUP_IDX"
FILE_SCOPE=$(python3 << 'PYEOF' || exit 1
import json, os, sys

plan_json = os.environ["LBYL_PLAN_JSON"]
step_num = int(os.environ["LBYL_STEP_NUM"])
group_idx_str = os.environ.get("LBYL_GROUP_IDX", "")

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

step_owner = step.get("owner", "claude")

if group_idx_str:
    # Group-scoped: validate group-level ownership
    group_idx = int(group_idx_str)
    sub_plan = step.get("subPlan")
    if not sub_plan or not sub_plan.get("groups"):
        print(f"ERROR: Step {step_num} has no subPlan.groups", file=sys.stderr)
        sys.exit(1)
    groups = sub_plan["groups"]
    if group_idx < 0 or group_idx >= len(groups):
        print(f"ERROR: Group index {group_idx} out of range (0-{len(groups)-1})", file=sys.stderr)
        sys.exit(1)
    group = groups[group_idx]
    effective_owner = group.get("owner", step_owner)
    if effective_owner != "codex":
        print(f"ERROR: Cannot implement a {effective_owner}-owned group (group {group_idx}: '{group['name']}'). This script is for codex-owned targets only.", file=sys.stderr)
        sys.exit(1)
    # Output the group's files as scope for the prompt
    print(" ".join(group.get("files", [])))
else:
    # Step-scoped: validate step-level ownership
    if step_owner != "codex":
        print(f"ERROR: Cannot implement a {step_owner}-owned step. This script is for codex-impl steps only. Claude implements claude-impl steps directly.", file=sys.stderr)
        sys.exit(1)
    print("")  # empty = whole step scope
PYEOF
) || exit 1

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
STREAM_FILE="$PLAN_DIR/.codex-stream-${SUFFIX}.jsonl"
RESULT_FILE="$PLAN_DIR/.codex-result-${SUFFIX}.txt"

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

# Build the prompt
if [ -n "$GROUP_IDX" ] && [ -n "$FILE_SCOPE" ]; then
  PROMPT="Implement group ${GROUP_IDX} of step ${STEP_NUM} in the plan at ${PLAN_JSON}.

This is a collab-split step — implement ONLY the files in this group: ${FILE_SCOPE}

Read the plan file to understand the step's description, acceptance criteria, and the group's scope. Also read discovery.md in the same directory for codebase context (scope, consumers, blast radius, existing patterns).

For each file you need to modify:
- Read the file AND its imports before editing
- Check sibling files for patterns and conventions
- Implement exactly what the step description specifies for this group — no scope additions, no scope cuts

After completing the group's work:
- Run the project's type checker (tsc, tsgo, mypy, etc.) and relevant tests
- Check consumers of any shared code you modified (use deps-query if dep maps are configured)

Report your results as:
- FILES CHANGED: list of files you created or modified
- WHAT WAS DONE: brief summary of changes
- VERIFICATION: type checker and test results (pass/fail with output)
- ISSUES: anything that did not go as expected, or 'none'"
else
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
fi

# Run codex exec
codex exec \
  -C "$PROJECT_ROOT" \
  --dangerously-bypass-approvals-and-sandbox \
  --enable fast_mode \
  --json \
  -o "$RESULT_FILE" \
  "$PROMPT" \
  > "$STREAM_FILE" 2>&1

CODEX_EXIT=$?

# Emit signed receipt on successful implementation
if [ "$CODEX_EXIT" -eq 0 ] && [ -f "$RESULT_FILE" ]; then
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  source "${PLUGIN_ROOT}/hooks/lib/receipt-state.sh"
  receipt_bootstrap 2>/dev/null || true
  PROJ_ID=$(receipt_project_id "$PROJECT_ROOT" 2>/dev/null) || true
  P_ID=$(receipt_plan_id "$PLAN_JSON" 2>/dev/null) || true
  if [ -n "$PROJ_ID" ] && [ -n "$P_ID" ]; then
    receipt_sign "codex_impl" "$PROJ_ID" "$P_ID" "step=$STEP_NUM" >/dev/null 2>&1 || true
  fi
fi

exit $CODEX_EXIT
