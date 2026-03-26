#!/usr/bin/env bash
# PreToolUse hook: Block Claude edits to files owned by codex-impl steps.
#
# When a plan step has owner: "codex" (or a collab-split group has
# owner: "codex"), Claude must NOT directly edit files listed in that
# step/group. Claude can:
#   - Read those files (for review)
#   - Update progress via plan_utils.py (writes to progress.json)
#   - Dispatch Codex via run-codex-implement.sh
#   - Edit files in OTHER steps that Claude owns
#
# Allows:
#   - Edits to .temp/ (plan files)
#   - Edits when no active plan exists
#   - Edits to files not in any codex-owned step
#   - Bash commands (handled by guard-filesystem-mutation.sh)
#
# Input: JSON on stdin with tool_name, tool_input.file_path, cwd

set -euo pipefail

INPUT=$(cat)

# Only check Edit and Write tools
TOOL_NAME=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_name', ''))
" <<< "$INPUT" 2>/dev/null) || true

if [ "$TOOL_NAME" != "Edit" ] && [ "$TOOL_NAME" != "Write" ]; then
  exit 0
fi

# Extract file path
FILE_PATH=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null) || true

[ -z "$FILE_PATH" ] && exit 0

# Always allow edits to .temp/ (plan files, scratch)
if [[ "$FILE_PATH" == *"/.temp/"* ]] || [[ "$FILE_PATH" == *"/.temp" ]]; then
  exit 0
fi

# Find project root
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"

# Find active plan for this session
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"
SESSION_PLAN=$(python3 "$PLAN_UTILS" find-for-session "$PROJECT_ROOT" "$PPID" 2>/dev/null) || true

# No plan → no ownership enforcement
if [ -z "$SESSION_PLAN" ] || [ ! -f "$SESSION_PLAN" ]; then
  exit 0
fi

# Check ownership using Python for complex plan parsing
export HOOK_FILE_PATH="$FILE_PATH"
export HOOK_PLAN_PATH="$SESSION_PLAN"
export HOOK_PROJECT_ROOT="$PROJECT_ROOT"
export HOOK_CWD="${CWD:-$PWD}"
export HOOK_PLAN_UTILS="$PLAN_UTILS"

RESULT=$(python3 << 'PYEOF'
import json, os, sys

plan_path = os.environ.get("HOOK_PLAN_PATH", "")
raw_file_path = os.environ.get("HOOK_FILE_PATH", "")
project_root = os.environ.get("HOOK_PROJECT_ROOT", "")
cwd = os.environ.get("HOOK_CWD", "")

# Normalize the file path: resolve relative paths, collapse ../
if raw_file_path:
    if not os.path.isabs(raw_file_path):
        raw_file_path = os.path.join(cwd or project_root, raw_file_path)
    file_path = os.path.normpath(raw_file_path)
else:
    file_path = ""

# Convert to project-relative path
if project_root and file_path.startswith(os.path.normpath(project_root) + "/"):
    file_path = file_path[len(os.path.normpath(project_root)) + 1:]
elif project_root and file_path == os.path.normpath(project_root):
    file_path = ""

if not plan_path or not file_path:
    print("allow")
    sys.exit(0)

try:
    # Use plan_utils for merged view (plan.json + progress.json)
    plan_utils_path = os.environ.get("HOOK_PLAN_UTILS", "")
    if plan_utils_path:
        sys.path.insert(0, os.path.dirname(plan_utils_path))
        import plan_utils
        plan = plan_utils.read_plan(plan_path)
    else:
        with open(plan_path) as f:
            plan = json.load(f)
except (OSError, json.JSONDecodeError, ImportError):
    print("allow")
    sys.exit(0)

# Find all in_progress steps with codex ownership
for step in plan.get("steps", []):
    if step.get("status") != "in_progress":
        continue

    step_owner = step.get("owner", "claude")
    step_files = step.get("files", [])

    # Check sub-plan groups for collab-split
    sub_plan = step.get("subPlan")
    if sub_plan and "groups" in sub_plan:
        for group in sub_plan["groups"]:
            group_owner = group.get("owner", step_owner)
            if group_owner == "codex":
                group_files = group.get("files", [])
                if file_path in group_files:
                    print(f"deny:step {step['id']}:group {group.get('title', 'unknown')}:codex")
                    sys.exit(0)
    elif step_owner == "codex":
        if file_path in step_files:
            print(f"deny:step {step['id']}::codex")
            sys.exit(0)

print("allow")
PYEOF
) || RESULT="allow"

if [[ "$RESULT" == "allow" ]]; then
  exit 0
fi

# Parse the deny result
STEP_INFO=$(echo "$RESULT" | cut -d: -f2)
GROUP_INFO=$(echo "$RESULT" | cut -d: -f3)

DENY_MSG="BLOCKED: This file is owned by a codex-impl step ($STEP_INFO"
if [ -n "$GROUP_INFO" ]; then
  DENY_MSG="$DENY_MSG, $GROUP_INFO"
fi
DENY_MSG="$DENY_MSG). Claude cannot directly edit files in Codex-owned steps.\n\nTo modify this file:\n1. Dispatch Codex via run-codex-implement.sh to make changes\n2. Then verify Codex's work independently\n\nIf ownership is wrong, update the step's owner field in plan.json."

python3 -c "
import json, sys
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': sys.argv[1]
    }
}
json.dump(output, sys.stdout)
" "$DENY_MSG"
