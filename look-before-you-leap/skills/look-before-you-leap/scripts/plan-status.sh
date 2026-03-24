#!/usr/bin/env bash
# Shows status of all active plans (default) or all plans (--all).
# Reads plan.json when available, falls back to masterPlan.md grep for legacy.
# Usage: bash .temp/plan-mode/scripts/plan-status.sh [--all]
#        bash <plugin-root>/skills/look-before-you-leap/scripts/plan-status.sh [--all]
#
# Works on both macOS and Linux.

set -euo pipefail

SHOW_ALL=false
if [[ "${1:-}" == "--all" ]]; then
  SHOW_ALL=true
fi

# Try to find plan directory: first check relative to script location,
# then check common project locations
find_plan_dir() {
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

  # If we're inside .temp/plan-mode/scripts/, use the parent
  if [[ "$script_dir" == *".temp/plan-mode/scripts" ]]; then
    echo "$(dirname "$script_dir")"
    return 0
  fi

  # Otherwise, look for .temp/plan-mode/ from the project root
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
  echo "No plans found. (.temp/plan-mode/ does not exist)"
  exit 0
fi

# Set up plan_utils path for merged reads
SCRIPT_DIR_ABS="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export PLAN_UTILS_DIR="$SCRIPT_DIR_ABS"

# Display a plan from plan.json
show_plan_json() {
  local plan_json="$1"
  local dir="$(dirname "$plan_json")"
  local name="$(basename "$dir")"
  local label="${2:-}"

  # Read owner PID from .session-lock
  local owner_pid=""
  local owner_status=""
  if [ -f "$dir/.session-lock" ]; then
    owner_pid=$(cat "$dir/.session-lock" 2>/dev/null) || true
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      owner_status="PID $owner_pid (alive)"
    elif [ -n "$owner_pid" ]; then
      owner_status="PID $owner_pid (dead)"
    else
      owner_status="unclaimed"
    fi
  else
    owner_status="unclaimed"
  fi

  echo "========================================"
  if [ -n "$label" ]; then
    echo "  Plan: $name  [$label]  Owner: $owner_status"
  else
    echo "  Plan: $name  Owner: $owner_status"
  fi
  echo "----------------------------------------"

  python3 -c "
import json, os, sys

# Use plan_utils for merged view (plan.json + progress.json)
plan_utils_dir = os.environ.get('PLAN_UTILS_DIR', '')
if plan_utils_dir:
    sys.path.insert(0, plan_utils_dir)
    import plan_utils
    plan = plan_utils.read_plan(sys.argv[1])
else:
    with open(sys.argv[1]) as f:
        plan = json.load(f)
counts = {'pending': 0, 'in_progress': 0, 'done': 0, 'blocked': 0}
for s in plan.get('steps', []):
    st = s.get('status', 'pending')
    counts[st] = counts.get(st, 0) + 1
print(f'  Steps:  {counts[\"done\"]} done  |  {counts[\"in_progress\"]} active  |  {counts[\"pending\"]} pending  |  {counts[\"blocked\"]} blocked')
for s in plan.get('steps', []):
    st = s.get('status', 'pending')
    markers = {'done': '[done]    ', 'in_progress': '[ACTIVE]  ', 'pending': '[pending] ', 'blocked': '[BLOCKED] '}
    marker = markers.get(st, '[?]       ')
    print(f'    {marker} Step {s[\"id\"]}: {s[\"title\"]}')
    sp = s.get('subPlan')
    if sp and sp.get('groups'):
        for g in sp['groups']:
            gst = g.get('status', 'pending')
            print(f'      sub-group: {g[\"name\"]} ({gst})')
" "$plan_json"
  echo ""
}

# Display a plan from masterPlan.md (legacy fallback)
show_plan_md() {
  local plan="$1"
  local dir="$(dirname "$plan")"
  local name="$(basename "$dir")"
  local label="${2:-}"

  echo "========================================"
  if [ -n "$label" ]; then
    echo "  Plan: $name  [$label]"
  else
    echo "  Plan: $name"
  fi
  echo "----------------------------------------"

  # Count step statuses
  pending=$(grep -cE '\[ \]' "$plan" 2>/dev/null || true)
  in_progress=$(grep -cE '\[~\]' "$plan" 2>/dev/null || true)
  complete=$(grep -cE '\[x\]' "$plan" 2>/dev/null || true)
  blocked=$(grep -cE '\[!\]' "$plan" 2>/dev/null || true)

  echo "  Steps:  $complete done  |  $in_progress active  |  $pending pending  |  $blocked blocked"

  # Show step titles with their statuses
  grep -E '^### Step [0-9]+:' "$plan" | while read -r line; do
    step_title=$(echo "$line" | sed 's/^### //')

    # Find the status line right after this step header
    status=$(grep -A2 "$line" "$plan" | grep -o '\[.\]' | head -1 || echo "[?]")

    case "$status" in
      "[x]") marker="[done]    " ;;
      "[~]") marker="[ACTIVE]  " ;;
      "[ ]") marker="[pending] " ;;
      "[!]") marker="[BLOCKED] " ;;
      *)     marker="[?]       " ;;
    esac

    echo "    $marker $step_title"
  done

  echo ""
}

# Show plans from a directory, preferring plan.json over masterPlan.md
show_plans() {
  local search_dir="$1"
  local label="$2"
  local found=false

  for dir in "$search_dir"/*/; do
    [ -d "$dir" ] || continue

    # Prefer plan.json, fall back to masterPlan.md
    if [ -f "$dir/plan.json" ]; then
      show_plan_json "$dir/plan.json" "$label"
      found=true
    elif [ -f "$dir/masterPlan.md" ]; then
      show_plan_md "$dir/masterPlan.md" "$label"
      found=true
    fi
  done

  if [ "$found" = false ]; then
    return 1
  fi
  return 0
}

found_any=false

# Show active plans
if [ -d "$PLAN_DIR/active" ]; then
  if show_plans "$PLAN_DIR/active" ""; then
    found_any=true
  fi
fi

# Show completed plans if --all
if [ "$SHOW_ALL" = true ] && [ -d "$PLAN_DIR/completed" ]; then
  if show_plans "$PLAN_DIR/completed" "COMPLETED"; then
    found_any=true
  fi
fi

if [ "$found_any" = false ]; then
  if [ "$SHOW_ALL" = true ]; then
    echo "No plans found in $PLAN_DIR"
  else
    echo "No active plans found. Use --all to include completed plans."
  fi
fi
