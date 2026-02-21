#!/usr/bin/env bash
# Stop hook: Verify active plan progress before Claude stops.
#
# If an active plan has unchecked items, blocks stopping and reminds Claude
# to either continue working or update the plan status.
#
# Checks stop_hook_active to prevent infinite loops.
#
# Input: JSON on stdin with stop_hook_active, last_assistant_message

set -euo pipefail

INPUT=$(cat)

# Prevent infinite loop: if stop hook already fired, allow stopping
STOP_HOOK_ACTIVE=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print('true' if data.get('stop_hook_active', False) else 'false')
" <<< "$INPUT" 2>/dev/null) || true

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

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

CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
ACTIVE_DIR="$PROJECT_ROOT/.temp/plan-mode/active"

# No active directory — nothing to check
if [ ! -d "$ACTIVE_DIR" ]; then
  exit 0
fi

# Find most recent active plan
latest=""
latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
if [ -z "$latest" ]; then
  latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-) || true
fi

# No plan file — allow stop
if [ -z "$latest" ] || [ ! -f "$latest" ]; then
  exit 0
fi

# Count step statuses
# Match both "[ ] pending" (template format) and bare "[ ]" (common usage)
pending_count=$(grep -cE '\[ \]' "$latest" 2>/dev/null) || true
active_count=$(grep -cE '\[~\]' "$latest" 2>/dev/null) || true
blocked_count=$(grep -cE '\[!\]' "$latest" 2>/dev/null) || true

remaining=$((pending_count + active_count))

# If no remaining work, allow stop
if [ "$remaining" -eq 0 ]; then
  exit 0
fi

# There's remaining work — block the stop
plan_name="$(basename "$(dirname "$latest")")"

export HOOK_PLAN_NAME="$plan_name"
export HOOK_PLAN_PATH="$latest"
export HOOK_PENDING="$pending_count"
export HOOK_ACTIVE="$active_count"
export HOOK_BLOCKED="$blocked_count"

python3 << 'PYEOF'
import json, sys, os

plan_name = os.environ["HOOK_PLAN_NAME"]
plan_path = os.environ["HOOK_PLAN_PATH"]
pending = int(os.environ["HOOK_PENDING"])
active = int(os.environ["HOOK_ACTIVE"])
blocked = int(os.environ["HOOK_BLOCKED"])

reason_parts = [
    f"Active plan '{plan_name}' has unfinished work:",
]

if active > 0:
    reason_parts.append(f"  - {active} step(s) in-progress")
if pending > 0:
    reason_parts.append(f"  - {pending} step(s) pending")
if blocked > 0:
    reason_parts.append(f"  - {blocked} step(s) blocked")

reason_parts.extend([
    "",
    f"Plan file: {plan_path}",
    "",
    "Before stopping, either:",
    "1. Continue with the remaining steps",
    "2. Update the plan to reflect current status",
    "3. Tell the user what's remaining and why you're stopping",
])

output = {
    "decision": "block",
    "reason": "\n".join(reason_parts)
}

json.dump(output, sys.stdout)
PYEOF
