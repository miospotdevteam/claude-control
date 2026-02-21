#!/usr/bin/env bash
# Shows status of all active plans (default) or all plans (--all).
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

# Function to display plans from a given directory with an optional label
show_plans() {
  local search_dir="$1"
  local label="$2"
  local found=false

  for plan in "$search_dir"/*/masterPlan.md; do
    [ -f "$plan" ] || continue
    found=true

    dir="$(dirname "$plan")"
    name="$(basename "$dir")"

    echo "========================================"
    if [ -n "$label" ]; then
      echo "  Plan: $name  [$label]"
    else
      echo "  Plan: $name"
    fi
    echo "----------------------------------------"

    # Count step statuses
    # Match both "[ ] pending" (template format) and bare "[ ]" (common usage)
    pending=$(grep -cE '\[ \]' "$plan" 2>/dev/null || true)
    in_progress=$(grep -cE '\[~\]' "$plan" 2>/dev/null || true)
    complete=$(grep -cE '\[x\]' "$plan" 2>/dev/null || true)
    blocked=$(grep -cE '\[!\]' "$plan" 2>/dev/null || true)

    echo "  Steps:  $complete done  |  $in_progress active  |  $pending pending  |  $blocked blocked"

    # Show step titles with their statuses
    grep -E '^### Step [0-9]+:' "$plan" | while read -r line; do
      step_num=$(echo "$line" | grep -o 'Step [0-9]*')
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

    # Show sub-plans
    for sub in "$dir"/sub-plan-*.md; do
      [ -f "$sub" ] || continue
      subname="$(basename "$sub")"
      substatus=$(grep -m1 '^\*\*Status\*\*:' "$sub" | sed 's/.*\*\*Status\*\*: //' || echo "unknown")
      echo "    sub-plan: $subname ($substatus)"
    done

    echo ""
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
