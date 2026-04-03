#!/usr/bin/env bash
# Shared library for plan discovery and status reading.
#
# Usage: source "${BASH_SOURCE[0]%/*}/lib/plan-state.sh"
#
# Requires PLUGIN_ROOT to be set (or derives it from BASH_SOURCE).
# Requires find-root.sh to be sourced first (for find_project_root).

# Resolve plugin root if not set
: "${PLUGIN_ROOT:=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)}"

_PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"

# Find plan.json for the current session via PPID routing.
# Args: $1 = project_root
# Returns: plan.json path on stdout (empty if none found)
plan_resolve_session() {
  local project_root="$1"
  local session_plan=""
  local active_dir="${project_root}/.temp/plan-mode/active"
  local dir_count=0
  local only_dir=""
  local dir=""

  session_plan=$(python3 "$_PLAN_UTILS" find-for-session "$project_root" "$PPID" 2>/dev/null) || true
  if [ -n "$session_plan" ]; then
    echo "$session_plan"
    return 0
  fi

  [ -d "$active_dir" ] || return 0

  for dir in "$active_dir"/*; do
    [ -d "$dir" ] || continue
    dir_count=$((dir_count + 1))
    only_dir="$dir"
  done

  if [ "$dir_count" -eq 1 ] && [ -f "$only_dir/plan.json" ]; then
    echo "$only_dir/plan.json"
  fi
}

# Extract plan directory from a plan.json path.
# Args: $1 = plan.json path
# Returns: directory path on stdout
plan_resolve_dir() {
  dirname "$1"
}

# Get plan status summary as JSON.
# Args: $1 = plan.json path
# Returns: JSON string with done, active, pending, blocked, next_step, has_work
plan_get_status() {
  local plan_json="$1"
  python3 << PYEOF
import sys, os, json

sys.path.insert(0, os.path.dirname("$_PLAN_UTILS"))
import plan_utils

plan = plan_utils.read_plan("$plan_json")
progress = plan_utils.read_progress("$plan_json")
merged = plan_utils.merge_plan_progress(plan, progress)
counts = plan_utils.count_by_status(merged)

next_step = plan_utils.get_next_step(merged)
next_title = ""
has_work = False
if next_step:
    next_title = next_step.get("title", "Step " + str(next_step.get("id", "?")))
    if next_step["status"] == "in_progress":
        next_title += " [resuming]"
    has_work = True

print(json.dumps({
    "done": counts.get("done", 0),
    "active": counts.get("in_progress", 0),
    "pending": counts.get("pending", 0),
    "blocked": counts.get("blocked", 0),
    "next_step": next_title,
    "has_work": has_work
}))
PYEOF
}

# Parse plan status JSON into shell variables.
# Args: $1 = JSON string from plan_get_status
# Sets: PLAN_DONE, PLAN_ACTIVE, PLAN_PENDING, PLAN_BLOCKED, PLAN_NEXT_STEP, PLAN_HAS_WORK
plan_parse_status() {
  local status_json="$1"
  local parsed=""
  parsed=$(python3 - "$status_json" << 'PYEOF' 2>/dev/null
import json
import sys

data = json.loads(sys.argv[1])
print(
    "\t".join(
        [
            str(data.get("done", 0)),
            str(data.get("active", 0)),
            str(data.get("pending", 0)),
            str(data.get("blocked", 0)),
            str(data.get("next_step", "")),
            str(data.get("has_work", False)),
        ]
    )
)
PYEOF
  ) || true

  if [ -z "$parsed" ]; then
    PLAN_DONE=0
    PLAN_ACTIVE=0
    PLAN_PENDING=0
    PLAN_BLOCKED=0
    PLAN_NEXT_STEP=""
    PLAN_HAS_WORK=false
    return 0
  fi

  IFS=$'\t' read -r PLAN_DONE PLAN_ACTIVE PLAN_PENDING PLAN_BLOCKED PLAN_NEXT_STEP PLAN_HAS_WORK <<< "$parsed"
}

# Check if a plan is fresh (no completed steps).
# Args: $1 = plan.json path
# Returns: "true" or "false" on stdout
plan_is_fresh() {
  local plan_json="$1"
  python3 "$_PLAN_UTILS" is-fresh "$plan_json" 2>/dev/null || true
}

# Find the most recently modified masterPlan.md in active plans.
# Portable: uses Python for mtime comparison (works on macOS + Linux).
# Args: $1 = active directory path
# Returns: path to masterPlan.md on stdout (empty if none found)
plan_find_latest_legacy() {
  local active_dir="$1"
  python3 -c "
import os, sys

active_dir = sys.argv[1]
best_path = ''
best_mtime = 0

for entry in os.listdir(active_dir):
    candidate = os.path.join(active_dir, entry, 'masterPlan.md')
    if os.path.isfile(candidate):
        mtime = os.path.getmtime(candidate)
        if mtime > best_mtime:
            best_mtime = mtime
            best_path = candidate

print(best_path)
" "$active_dir" 2>/dev/null || true
}
