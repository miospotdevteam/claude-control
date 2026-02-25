#!/usr/bin/env bash
# PreToolUse hook: Block moving plans to completed/ if they have unchecked items.
#
# Detects: mv commands that move plan directories from active/ to completed/
# Reads the masterPlan.md and checks for [ ], [~], or [!] markers.
# If any unchecked items remain, denies the mv.
#
# Input: JSON on stdin with tool_name, tool_input.command, cwd

set -euo pipefail

INPUT=$(cat)

# Extract command
COMMAND=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('command', ''))
" <<< "$INPUT" 2>/dev/null) || true

[ -z "$COMMAND" ] && exit 0

# Only check mv commands that reference both active/ and completed/ in plan-mode
export HOOK_COMMAND="$COMMAND"

PLAN_PATH=$(python3 << 'PYEOF'
import re, os, sys

cmd = os.environ.get("HOOK_COMMAND", "")

# Must be a mv command involving plan-mode active/ -> completed/
if not re.search(r'\bmv\b', cmd):
    print("")
    sys.exit(0)

if 'plan-mode/active/' not in cmd and 'plan-mode/completed' not in cmd:
    # Also check if it has both active/ and completed/ in a plan context
    if not ('active/' in cmd and 'completed/' in cmd):
        print("")
        sys.exit(0)

# Try to extract the source path (the active plan directory or masterPlan.md)
# Common patterns:
#   mv '.temp/plan-mode/active/plan-name' '.temp/plan-mode/completed/plan-name'
#   mv '/full/path/.temp/plan-mode/active/plan-name' ...
parts = cmd.split()
source_path = ""
for i, part in enumerate(parts):
    # Skip the 'mv' command and flags
    if part == "mv" or part.startswith("-"):
        continue
    # Remove surrounding quotes
    cleaned = part.strip("'\"")
    if "plan-mode/active/" in cleaned or "/active/" in cleaned:
        source_path = cleaned
        break

if source_path:
    # Find the masterPlan.md in the source
    import os.path
    if source_path.endswith("masterPlan.md"):
        print(source_path)
    elif os.path.isfile(os.path.join(source_path, "masterPlan.md")):
        print(os.path.join(source_path, "masterPlan.md"))
    else:
        # Try appending masterPlan.md
        candidate = os.path.join(source_path, "masterPlan.md")
        print(candidate)
else:
    print("")
PYEOF
) || true

# Not a plan-moving command — allow
[ -z "$PLAN_PATH" ] && exit 0

# Check if the masterPlan.md exists and has unchecked items
if [ ! -f "$PLAN_PATH" ]; then
  # Can't verify — allow (the mv will fail anyway if path is wrong)
  exit 0
fi

# Only match checklist lines: "  - [ ] ...", "- [x] ...", "  - [~] ...", etc.
# This avoids false positives from prose text that mentions [ ] or [~] literally.
pending=$(grep -cE '^\s*-\s*\[ \]' "$PLAN_PATH" 2>/dev/null) || true
active=$(grep -cE '^\s*-\s*\[~\]' "$PLAN_PATH" 2>/dev/null) || true
blocked=$(grep -cE '^\s*-\s*\[!\]' "$PLAN_PATH" 2>/dev/null) || true
done_count=$(grep -cE '^\s*-\s*\[x\]' "$PLAN_PATH" 2>/dev/null) || true

remaining=$((pending + active + blocked))

# All done — allow the move
if [ "$remaining" -eq 0 ] && [ "$done_count" -gt 0 ]; then
  exit 0
fi

# Incomplete plan — deny the move
export HOOK_PLAN_PATH="$PLAN_PATH"
export HOOK_PENDING="$pending"
export HOOK_ACTIVE="$active"
export HOOK_BLOCKED="$blocked"
export HOOK_DONE="$done_count"

python3 << 'PYEOF'
import json, sys, os

plan_path = os.environ["HOOK_PLAN_PATH"]
pending = int(os.environ["HOOK_PENDING"])
active = int(os.environ["HOOK_ACTIVE"])
blocked = int(os.environ["HOOK_BLOCKED"])
done = int(os.environ["HOOK_DONE"])

status_parts = []
if active > 0:
    status_parts.append(f"{active} in-progress")
if pending > 0:
    status_parts.append(f"{pending} pending")
if blocked > 0:
    status_parts.append(f"{blocked} blocked")

status = ", ".join(status_parts) if status_parts else "no completed items"

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"Cannot move plan to completed/ — it has unfinished work: {status}.\n\n"
            f"Plan: {plan_path}\n"
            f"Progress: {done} done, {pending + active + blocked} remaining\n\n"
            "A plan is only complete when ALL steps are marked [x]. "
            "Complete the remaining steps or explicitly flag them to the user "
            "before moving the plan."
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
