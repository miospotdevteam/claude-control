#!/usr/bin/env bash
# PostToolUse hook: Migrate discovery + detect plan completion.
#
# After every Edit/Write to a plan.json or masterPlan.md:
# 1. Migrates any fallback discovery.md (.temp/discovery/) into the plan dir
# 2. Checks if all steps are done (via plan.json) — if so, advises Claude to finalize
#
# Does NOT auto-move — Claude needs to make final edits first.
#
# Input: JSON on stdin with tool_name, tool_input.file_path, cwd

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
hook_read_input

# Extract file path from tool input
FILE_PATH=$(hook_get_file_path)

# Act on plan.json, progress.json, OR masterPlan.md inside .temp/plan-mode/active/
if [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/plan.json" ]]; then
  PLAN_DIR_PATH="$(dirname "$FILE_PATH")"
elif [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/progress.json" ]]; then
  PLAN_DIR_PATH="$(dirname "$FILE_PATH")"
elif [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/masterPlan.md" ]]; then
  PLAN_DIR_PATH="$(dirname "$FILE_PATH")"
else
  exit 0
fi

# Verify the directory exists
if [ ! -d "$PLAN_DIR_PATH" ]; then
  exit 0
fi

source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

MIGRATE_CWD=$(hook_get_cwd)

MIGRATE_ROOT="$(find_project_root "${MIGRATE_CWD:-$PWD}")"
FALLBACK_DIR="$MIGRATE_ROOT/.temp/discovery"
FALLBACK_FILE="$FALLBACK_DIR/discovery.md"
PLAN_DISCOVERY="$PLAN_DIR_PATH/discovery.md"

if [ -f "$FALLBACK_FILE" ]; then
  if [ ! -f "$PLAN_DISCOVERY" ]; then
    # Simple move — no plan-scoped discovery yet
    mv "$FALLBACK_FILE" "$PLAN_DISCOVERY"
  else
    # Both exist — append fallback content into plan-scoped file
    printf '\n\n# --- Migrated from pre-plan discovery ---\n' >> "$PLAN_DISCOVERY"
    cat "$FALLBACK_FILE" >> "$PLAN_DISCOVERY"
    rm "$FALLBACK_FILE"
  fi
  # Clean up empty fallback dir
  rmdir "$FALLBACK_DIR" 2>/dev/null || true
fi

# Check if all steps are complete — prefer plan.json, fall back to masterPlan.md
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"
PLAN_JSON="$PLAN_DIR_PATH/plan.json"
MASTER_PLAN="$PLAN_DIR_PATH/masterPlan.md"

plan_name="$(basename "$PLAN_DIR_PATH")"
active_parent="$(dirname "$PLAN_DIR_PATH")"
completed_dir="$(dirname "$active_parent")/completed"

if [ -f "$PLAN_JSON" ]; then
  is_complete=$(python3 "$PLAN_UTILS" is-complete "$PLAN_JSON" 2>/dev/null) || true
  if [ "$is_complete" != "true" ]; then
    exit 0
  fi
  done_count=$(python3 -c "
import json, os, sys
sys.path.insert(0, os.path.dirname('$PLAN_UTILS'))
import plan_utils
plan = plan_utils.read_plan('$PLAN_JSON')
print(sum(1 for s in plan.get('steps', []) if s.get('status') == 'done'))
" 2>/dev/null) || true
elif [ -f "$MASTER_PLAN" ]; then
  # Legacy: grep masterPlan.md
  pending=$(grep -cE '^\s*-\s*\[ \]' "$MASTER_PLAN" 2>/dev/null) || true
  active=$(grep -cE '^\s*-\s*\[~\]' "$MASTER_PLAN" 2>/dev/null) || true
  blocked=$(grep -cE '^\s*-\s*\[!\]' "$MASTER_PLAN" 2>/dev/null) || true
  done_count=$(grep -cE '^\s*-\s*\[x\]' "$MASTER_PLAN" 2>/dev/null) || true
  remaining=$((pending + active + blocked))
  if [ "$remaining" -gt 0 ] || [ "$done_count" -eq 0 ]; then
    exit 0
  fi
else
  exit 0
fi

# All steps done — tell Claude to VERIFY before finalizing
export HOOK_PLAN_NAME="$plan_name"
export HOOK_DONE_COUNT="${done_count:-0}"
export HOOK_PLAN_DIR="$PLAN_DIR_PATH"
export HOOK_COMPLETED_DIR="$completed_dir"

python3 << 'PYEOF'
import json, sys, os

plan_name = os.environ["HOOK_PLAN_NAME"]
done_count = os.environ["HOOK_DONE_COUNT"]
plan_dir = os.environ["HOOK_PLAN_DIR"]
completed_dir = os.environ["HOOK_COMPLETED_DIR"]

output = {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            f"All {done_count} steps done in plan '{plan_name}'.\n\n"
            "STOP. Before closing this plan, complete ALL of the following:\n\n"
            "1. VERIFY: Run the project's verification commands (type checker, "
            "linter, tests). If any fail, the plan is NOT done — fix them first.\n"
            "2. RE-READ the user's original request word by word. Is every "
            "requirement actually implemented and working? If not, the plan is "
            "NOT done.\n"
            "3. UPDATE the completedSummary via plan_utils.py add-summary (writes to progress.json).\n"
            "4. REPORT to the user what was completed, what was verified, and "
            "any caveats.\n\n"
            "Only AFTER steps 1-4 are done, move the plan:\n"
            f"  mv '{plan_dir}' '{completed_dir}/{plan_name}'\n\n"
            "WARNING: Do NOT move the plan just because steps are marked done. "
            "If you have ANY doubt, re-check."
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
