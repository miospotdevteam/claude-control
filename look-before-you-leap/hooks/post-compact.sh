#!/usr/bin/env bash
# PostCompact hook for look-before-you-leap plugin.
#
# Fires after context compaction completes. Lightweight: only detects the
# active plan and injects resumption context. Skills and config are already
# in context from SessionStart — no need to re-inject them.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"
PROJECT_ROOT="$(find_project_root)"

PLAN_DIR="$PROJECT_ROOT/.temp/plan-mode"
ACTIVE_DIR="$PLAN_DIR/active"
PLAN_UTILS="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/plan_utils.py"

# Note: handoff-pending is NOT auto-cleared on compaction. It persists until
# the user approves via Orbit or runs /bypass.

active_plan_summary=""

if [ -d "$ACTIVE_DIR" ]; then
  # PPID-based plan routing: find the plan claimed by this session
  latest_json=$(python3 "$PLAN_UTILS" find-for-session "$PROJECT_ROOT" "$PPID" 2>/dev/null) || true

  if [ -n "$latest_json" ] && [ -f "$latest_json" ]; then
    plan_dir="$(dirname "$latest_json")"
    plan_name="$(basename "$plan_dir")"

    export HOOK_PLAN_JSON="$latest_json"
    export HOOK_PLAN_UTILS="$PLAN_UTILS"

    plan_status_info=$(python3 << 'PYEOF'
import json, os, sys

plan_json = os.environ["HOOK_PLAN_JSON"]
plan_utils_path = os.environ["HOOK_PLAN_UTILS"]

sys.path.insert(0, os.path.dirname(plan_utils_path))
import plan_utils

plan = plan_utils.read_plan(plan_json)
counts = plan_utils.count_by_status(plan)

next_step = plan_utils.get_next_step(plan)
next_info = ""
if next_step:
    if next_step["status"] == "in_progress":
        next_info = f"IN PROGRESS: Step {next_step['id']}: {next_step['title']}"
    else:
        next_info = f"NEXT: Step {next_step['id']}: {next_step['title']}"

has_work = counts.get("pending", 0) + counts.get("in_progress", 0) + counts.get("blocked", 0) > 0

print(json.dumps({
    "done": counts.get("done", 0),
    "active": counts.get("in_progress", 0),
    "pending": counts.get("pending", 0),
    "blocked": counts.get("blocked", 0),
    "next_step": next_info,
    "has_work": has_work,
}))
PYEOF
    ) || true

    if [ -n "$plan_status_info" ]; then
      done_count=$(python3 -c "import json; print(json.loads('$plan_status_info').get('done', 0))" 2>/dev/null) || true
      active_count=$(python3 -c "import json; print(json.loads('$plan_status_info').get('active', 0))" 2>/dev/null) || true
      pending_count=$(python3 -c "import json; print(json.loads('$plan_status_info').get('pending', 0))" 2>/dev/null) || true
      blocked_count=$(python3 -c "import json; print(json.loads('$plan_status_info').get('blocked', 0))" 2>/dev/null) || true
      next_step=$(python3 -c "import json; print(json.loads('$plan_status_info').get('next_step', ''))" 2>/dev/null) || true
      has_work=$(python3 -c "import json; print(json.loads('$plan_status_info').get('has_work', False))" 2>/dev/null) || true
    fi

    if [ "$has_work" = "True" ]; then
      # Plan is already claimed by this PPID (find-for-session guarantees it)
      active_plan_summary="CONTEXT WAS COMPACTED — ACTIVE PLAN EXISTS"
      active_plan_summary+=$'\n'"Plan: $plan_name"
      active_plan_summary+=$'\n'"File: $latest_json"
      active_plan_summary+=$'\n'"Status: $done_count done | $active_count active | $pending_count pending | $blocked_count blocked"
      [ -n "$next_step" ] && active_plan_summary+=$'\n'"$next_step"
      active_plan_summary+=$'\n'$'\n'"IMPORTANT: Read plan.json (definition) and progress.json (mutable state) IMMEDIATELY. Do NOT re-plan or re-explore. The plan already exists and was approved. Resume execution from the next pending or in-progress step. Follow the resumption protocol from the persistent-plans skill."
    fi
  else
    # Legacy fallback: find masterPlan.md
    latest=""
    latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
    if [ -z "$latest" ]; then
      latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-) || true
    fi

    if [ -n "$latest" ] && [ -f "$latest" ]; then
      plan_name="$(basename "$(dirname "$latest")")"
      has_pending=$(grep -cE '^\s*-\s*(\[ \]|\[~\]|\[!\])' "$latest" 2>/dev/null) || true

      if [ "$has_pending" -gt 0 ]; then
        done_count=$(grep -cE '^\s*-\s*\[x\]' "$latest" 2>/dev/null) || true
        active_count=$(grep -cE '^\s*-\s*\[~\]' "$latest" 2>/dev/null) || true
        pending_count=$(grep -cE '^\s*-\s*\[ \]' "$latest" 2>/dev/null) || true
        blocked_count=$(grep -cE '^\s*-\s*\[!\]' "$latest" 2>/dev/null) || true

        next_step=""
        if [ "$active_count" -gt 0 ]; then
          next_step=$(grep -B5 -E '\[~\]' "$latest" | grep -E '^### Step' | head -1 | sed 's/^### //' || true)
          [ -n "$next_step" ] && next_step="IN PROGRESS: $next_step"
        elif [ "$pending_count" -gt 0 ]; then
          next_step=$(grep -B5 -E '\[ \]' "$latest" | grep -E '^### Step' | head -1 | sed 's/^### //' || true)
          [ -n "$next_step" ] && next_step="NEXT: $next_step"
        fi

        # Legacy path: claim for this session
        plan_dir="$(dirname "$latest")"
        echo "$PPID" > "$plan_dir/.session-lock"
        active_plan_summary="CONTEXT WAS COMPACTED — ACTIVE PLAN EXISTS"
        active_plan_summary+=$'\n'"Plan: $plan_name"
        active_plan_summary+=$'\n'"File: $latest"
        active_plan_summary+=$'\n'"Status: $done_count done | $active_count active | $pending_count pending | $blocked_count blocked"
        [ -n "$next_step" ] && active_plan_summary+=$'\n'"$next_step"
        active_plan_summary+=$'\n'$'\n'"IMPORTANT: Read the masterPlan.md file IMMEDIATELY. Do NOT re-plan or re-explore. The plan already exists and was approved. Resume execution from the next pending or in-progress step. Follow the resumption protocol from the persistent-plans skill."
      fi
    fi
  fi
fi

# Output — only if there's something to say
if [ -n "$active_plan_summary" ]; then
  export PLAN_SUMMARY="$active_plan_summary"
  python3 -c "
import json, sys, os
summary = os.environ['PLAN_SUMMARY']
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostCompact',
        'additionalContext': summary
    }
}))
"
fi
