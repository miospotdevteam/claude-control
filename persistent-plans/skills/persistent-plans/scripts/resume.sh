#!/usr/bin/env bash
# Shows what to resume after compaction or session restart.
# Only scans active/ — completed plans are never resumed.
# Usage: bash .temp/plan-mode/scripts/resume.sh
#        bash <plugin-root>/skills/persistent-plans/scripts/resume.sh
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

# Find most recently modified masterPlan.md in active/
# macOS stat and Linux stat have different flags, try both
latest=""

# Try macOS stat first
if command -v stat &>/dev/null; then
  latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
fi

# Fallback: try GNU find with -printf (Linux)
if [ -z "$latest" ]; then
  latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-) || true
fi

# Last resort: just pick the first one alphabetically
if [ -z "$latest" ]; then
  latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f 2>/dev/null | head -1)
fi

if [ -z "$latest" ]; then
  echo "No active plans found."
  exit 0
fi

plan_name="$(basename "$(dirname "$latest")")"

echo "========================================"
echo "  Resume: $plan_name"
echo "========================================"
echo ""
echo "Plan file: $latest"
echo ""

# Show context section (first few lines of the Context block)
echo "--- Context ---"
sed -n '/^## Context/,/^## /{/^## Context/d;/^## /d;p;}' "$latest" | head -5
echo ""

# Find in-progress steps first (highest priority)
in_progress=$(grep -n '\[~\] in-progress' "$latest" || true)
if [ -n "$in_progress" ]; then
  echo "--- IN PROGRESS (resume here) ---"
  # Show the step headers for in-progress steps
  while IFS= read -r line; do
    line_num=$(echo "$line" | cut -d: -f1)
    # Look backwards from the status line to find the step header
    step_header=$(head -n "$line_num" "$latest" | grep -E '^### Step' | tail -1)
    echo "  >> $step_header"
  done <<< "$in_progress"
  echo ""
fi

# Find next pending steps
pending=$(grep -n '\[ \] pending' "$latest" || true)
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

# Check for sub-plans on in-progress steps
dir="$(dirname "$latest")"
for sub in "$dir"/sub-plan-*.md; do
  [ -f "$sub" ] || continue
  substatus=$(grep -m1 '^\*\*Status\*\*:' "$sub" || echo "")
  if echo "$substatus" | grep -q 'in-progress\|pending'; then
    subname="$(basename "$sub")"
    echo "--- Active sub-plan: $subname ---"
    # Show first pending/in-progress sub-step
    grep -n -E '\[ \] pending|\[~\] in-progress' "$sub" | head -3
    echo ""
  fi
done

# Check for blocked items
blocked=$(grep -n '\[!\] blocked' "$latest" || true)
if [ -n "$blocked" ]; then
  echo "--- BLOCKED ---"
  echo "$blocked"
  echo ""
fi

echo "To resume, tell Claude: 'continue with the plan'"
