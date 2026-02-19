#!/usr/bin/env bash
# SessionStart hook for persistent-plans plugin.
#
# On every session start (including after compaction/resume), this hook:
# 1. Reads the persistent-plans skill content
# 2. Checks for active plans in .temp/plan-mode/
# 3. If an active plan exists, reads its status and injects it into context
#
# This is the magic that makes plans survive compaction — Claude gets told
# about the active plan automatically, without the user having to say anything.

set -euo pipefail

# Determine plugin root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SKILL_FILE="${PLUGIN_ROOT}/skills/persistent-plans/SKILL.md"

# Find project root: walk up from cwd looking for .git or CLAUDE.md
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "$PWD"
}

PROJECT_ROOT="$(find_project_root)"
PLAN_DIR="$PROJECT_ROOT/.temp/plan-mode"

# Build the active plan summary as plain text
active_plan_summary=""

ACTIVE_DIR="$PLAN_DIR/active"

if [ -d "$ACTIVE_DIR" ]; then
  # Find the most recently modified masterPlan.md in active/
  latest=""

  # macOS stat
  latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | awk '{print $2}')

  # Linux fallback
  if [ -z "$latest" ]; then
    latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-) || true
  fi

  if [ -n "$latest" ] && [ -f "$latest" ]; then
    plan_name="$(basename "$(dirname "$latest")")"

    # Check if the plan has any non-complete steps (i.e., is still active)
    has_pending=$(grep -c '\[ \] pending\|\[~\] in-progress\|\[!\] blocked' "$latest" 2>/dev/null) || true

    if [ "$has_pending" -gt 0 ]; then
      # Count statuses
      done_count=$(grep -c '\[x\] complete' "$latest" 2>/dev/null) || true
      active_count=$(grep -c '\[~\] in-progress' "$latest" 2>/dev/null) || true
      pending_count=$(grep -c '\[ \] pending' "$latest" 2>/dev/null) || true
      blocked_count=$(grep -c '\[!\] blocked' "$latest" 2>/dev/null) || true

      # Find the next step to work on
      next_step=""
      if [ "$active_count" -gt 0 ]; then
        next_step=$(grep -B5 '\[~\] in-progress' "$latest" | grep -E '^### Step' | head -1 | sed 's/^### //')
        next_step="IN PROGRESS: $next_step"
      elif [ "$pending_count" -gt 0 ]; then
        next_step=$(grep -B5 '\[ \] pending' "$latest" | grep -E '^### Step' | head -1 | sed 's/^### //')
        next_step="NEXT: $next_step"
      fi

      # Check for active sub-plans
      active_subplan=""
      plan_dir="$(dirname "$latest")"
      for sub in "$plan_dir"/sub-plan-*.md; do
        [ -f "$sub" ] || continue
        if grep -q '\[~\] in-progress\|\[ \] pending' "$sub" 2>/dev/null; then
          subname="$(basename "$sub")"
          active_subplan="Active sub-plan: $subname"
          break
        fi
      done

      active_plan_summary="ACTIVE PLAN DETECTED"
      active_plan_summary+=$'\n'"Plan: $plan_name"
      active_plan_summary+=$'\n'"File: $latest"
      active_plan_summary+=$'\n'"Status: $done_count done | $active_count active | $pending_count pending | $blocked_count blocked"
      [ -n "$next_step" ] && active_plan_summary+=$'\n'"$next_step"
      [ -n "$active_subplan" ] && active_plan_summary+=$'\n'"$active_subplan"
      active_plan_summary+=$'\n'$'\n'"IMPORTANT: Read the masterPlan.md file at the path above BEFORE doing any work. The plan is your source of truth. Follow the resumption protocol from the persistent-plans skill."
    fi
  fi
fi

# Use python3 for bulletproof JSON encoding
export SKILL_FILE_PATH="$SKILL_FILE"
export ACTIVE_PLAN_SUMMARY="$active_plan_summary"

python3 << 'PYEOF'
import json
import sys
import os

skill_file = os.environ.get("SKILL_FILE_PATH", "")
active_summary = os.environ.get("ACTIVE_PLAN_SUMMARY", "")

# Read skill content
try:
    with open(skill_file, "r") as f:
        skill_content = f.read()
except Exception as e:
    skill_content = f"Error reading skill: {e}"

# Build context message
parts = ["**Below is the persistent-plans skill -- follow it for all tasks:**", "", skill_content]

if active_summary:
    parts.extend(["", "---", "", active_summary])

context = "\n".join(parts)

output = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": context
    }
}

json.dump(output, sys.stdout)
PYEOF
