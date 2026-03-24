#!/usr/bin/env bash
# Shows what to resume after compaction or session restart.
# Only scans active/ — completed plans are never resumed.
# Reads plan.json when available, falls back to masterPlan.md for legacy.
# Usage: bash .temp/plan-mode/scripts/resume.sh
#        bash <plugin-root>/skills/look-before-you-leap/scripts/resume.sh
#
# Works on both macOS and Linux.

set -euo pipefail

# Find plan directory (same logic as plan-status.sh)
find_plan_dir() {
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

  if [[ "$script_dir" == *".temp/plan-mode/scripts" ]]; then
    echo "$(dirname "$script_dir")"
    return 0
  fi

  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.temp/plan-mode" ]; then
      echo "$dir/.temp/plan-mode"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  echo ""
}

PLAN_DIR="$(find_plan_dir)"

if [ -z "$PLAN_DIR" ] || [ ! -d "$PLAN_DIR" ]; then
  echo "No plans found."
  exit 0
fi

ACTIVE_DIR="$PLAN_DIR/active"

if [ ! -d "$ACTIVE_DIR" ]; then
  echo "No active plans found."
  exit 0
fi

# --- Try plan.json first ---
# Find most recently modified plan using max(plan.json, progress.json) mtime
latest_json=""

PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/plan_utils.py"
latest_json=$(python3 "$PLAN_UTILS" find-active "$(dirname "$(dirname "$ACTIVE_DIR")")" 2>/dev/null) || true

# Fallback: direct filesystem search if plan_utils fails
if [ -z "$latest_json" ]; then
  if command -v stat &>/dev/null; then
    latest_json=$(find "$ACTIVE_DIR" -name "plan.json" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
  fi
  if [ -z "$latest_json" ]; then
    latest_json=$(find "$ACTIVE_DIR" -name "plan.json" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-) || true
  fi
  if [ -z "$latest_json" ]; then
    latest_json=$(find "$ACTIVE_DIR" -name "plan.json" -type f 2>/dev/null | head -1)
  fi
fi

if [ -n "$latest_json" ]; then
  plan_name="$(basename "$(dirname "$latest_json")")"

  echo "========================================"
  echo "  Resume: $plan_name"
  echo "========================================"
  echo ""
  echo "Plan file: $latest_json"
  echo ""

  export HOOK_PLAN_UTILS="$PLAN_UTILS"
  python3 -c "
import json, os, sys

# Use plan_utils for merged view (plan.json + progress.json)
plan_utils_path = os.environ.get('HOOK_PLAN_UTILS', '')
if plan_utils_path:
    sys.path.insert(0, os.path.dirname(plan_utils_path))
    import plan_utils
    plan = plan_utils.read_plan(sys.argv[1])
else:
    with open(sys.argv[1]) as f:
        plan = json.load(f)

# Context
print('--- Context ---')
ctx = plan.get('context', '')
lines = [l.strip() for l in ctx.split('.') if l.strip()]
for line in lines[:3]:
    print(line + '.')
print()

# Find in-progress steps
in_progress = [s for s in plan.get('steps', []) if s['status'] == 'in_progress']
if in_progress:
    print('--- IN PROGRESS (resume here) ---')
    for s in in_progress:
        print(f'  >> Step {s[\"id\"]}: {s[\"title\"]}')
        for p in s.get('progress', []):
            marker = '[x]' if p['status'] == 'done' else '[~]' if p['status'] == 'in_progress' else '[ ]'
            print(f'       {marker} {p[\"task\"]}')
    print()

# Find next pending steps
pending = [s for s in plan.get('steps', []) if s['status'] == 'pending']
if pending:
    print('--- Next pending steps ---')
    print(f'  >> Step {pending[0][\"id\"]}: {pending[0][\"title\"]}')
    if len(pending) > 1:
        print(f'  ... and {len(pending) - 1} more pending steps')
    print()

# Check sub-plan groups on in-progress steps
for s in in_progress if in_progress else []:
    sp = s.get('subPlan')
    if sp and sp.get('groups'):
        active_groups = [g for g in sp['groups'] if g.get('status') in ('pending', 'in_progress')]
        if active_groups:
            print(f'--- Active sub-groups for Step {s[\"id\"]} ---')
            for g in active_groups[:3]:
                print(f'  {g[\"name\"]} ({g[\"status\"]})')
            print()

# Blocked
blocked = [s for s in plan.get('steps', []) if s['status'] == 'blocked']
if blocked:
    print('--- BLOCKED ---')
    for s in blocked:
        print(f'  Step {s[\"id\"]}: {s[\"title\"]}')
    print()
" "$latest_json"

  echo "To resume, tell Claude: 'continue with the plan'"
  exit 0
fi

# --- Fall back to masterPlan.md (legacy) ---
latest=""

if command -v stat &>/dev/null; then
  latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
fi

if [ -z "$latest" ]; then
  latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-) || true
fi

if [ -z "$latest" ]; then
  latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f 2>/dev/null | head -1)
fi

if [ -z "$latest" ]; then
  echo "No active plans found."
  exit 0
fi

plan_name="$(basename "$(dirname "$latest")")"

echo "========================================"
echo "  Resume: $plan_name  [legacy masterPlan.md]"
echo "========================================"
echo ""
echo "Plan file: $latest"
echo ""

# Show context section
echo "--- Context ---"
sed -n '/^## Context/,/^## /{/^## Context/d;/^## /d;p;}' "$latest" | head -5
echo ""

# Find in-progress steps first
in_progress=$(grep -nE '\[~\]' "$latest" || true)
if [ -n "$in_progress" ]; then
  echo "--- IN PROGRESS (resume here) ---"
  while IFS= read -r line; do
    line_num=$(echo "$line" | cut -d: -f1)
    step_header=$(head -n "$line_num" "$latest" | grep -E '^### Step' | tail -1)
    echo "  >> $step_header"
  done <<< "$in_progress"
  echo ""
fi

# Find next pending steps
pending=$(grep -nE '\[ \]' "$latest" || true)
if [ -n "$pending" ]; then
  echo "--- Next pending steps ---"
  first_pending_line=$(echo "$pending" | head -1 | cut -d: -f1)
  step_header=$(head -n "$first_pending_line" "$latest" | grep -E '^### Step' | tail -1)
  echo "  >> $step_header"

  remaining=$(echo "$pending" | wc -l | tr -d ' ')
  if [ "$remaining" -gt 1 ]; then
    echo "  ... and $((remaining - 1)) more pending steps"
  fi
  echo ""
fi

# Check for blocked items
blocked=$(grep -nE '\[!\]' "$latest" || true)
if [ -n "$blocked" ]; then
  echo "--- BLOCKED ---"
  echo "$blocked"
  echo ""
fi

echo "To resume, tell Claude: 'continue with the plan'"
