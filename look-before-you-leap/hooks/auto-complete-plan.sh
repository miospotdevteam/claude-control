#!/usr/bin/env bash
# PostToolUse hook: Migrate discovery + detect plan completion.
#
# After every Edit/Write to a masterPlan.md:
# 1. Migrates any fallback discovery.md (.temp/discovery/) into the plan dir
# 2. Checks if all steps are [x] — if so, advises Claude to finalize
#
# Does NOT auto-move — Claude needs to make final edits first.
#
# Input: JSON on stdin with tool_name, tool_input.file_path, cwd

set -euo pipefail

INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null) || true

# Only act on masterPlan.md files inside .temp/plan-mode/active/
if [[ "$FILE_PATH" != *"/.temp/plan-mode/active/"*"/masterPlan.md" ]]; then
  exit 0
fi

# Verify the file exists
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# --- Migrate fallback discovery.md into the plan directory ---
# When agents run before a plan exists, findings go to .temp/discovery/discovery.md.
# Now that a plan exists, migrate that file into the plan directory.
PLAN_DIR_PATH="$(dirname "$FILE_PATH")"

# Find project root
find_project_root() {
  local dir="${1:-$PWD}"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "${1:-$PWD}"
}

MIGRATE_CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

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

# Check if all steps are complete
pending=$(grep -cE '\[ \]' "$FILE_PATH" 2>/dev/null) || true
active=$(grep -cE '\[~\]' "$FILE_PATH" 2>/dev/null) || true
blocked=$(grep -cE '\[!\]' "$FILE_PATH" 2>/dev/null) || true
done_count=$(grep -cE '\[x\]' "$FILE_PATH" 2>/dev/null) || true

remaining=$((pending + active + blocked))

# Not all done yet — nothing to do
if [ "$remaining" -gt 0 ] || [ "$done_count" -eq 0 ]; then
  exit 0
fi

# All steps complete — tell Claude to finalize
plan_dir="$(dirname "$FILE_PATH")"
plan_name="$(basename "$plan_dir")"
active_parent="$(dirname "$plan_dir")"
completed_dir="$(dirname "$active_parent")/completed"

export HOOK_PLAN_NAME="$plan_name"
export HOOK_DONE_COUNT="$done_count"
export HOOK_PLAN_DIR="$plan_dir"
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
            f"ALL STEPS COMPLETE in plan '{plan_name}' ({done_count} steps done).\n\n"
            "Before closing this plan:\n"
            "1. Update the Completed Summary section with final results\n"
            "2. Verify all work (run type checker, linter, tests if applicable)\n"
            "3. Report completion to the user\n"
            f"4. Move the plan folder to completed/:\n"
            f"   mv '{plan_dir}' '{completed_dir}/{plan_name}'\n"
            "5. Remove .no-plan bypass if it exists:\n"
            f"   rm -f '{os.path.dirname(completed_dir)}/.no-plan'"
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
