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
source "${BASH_SOURCE[0]%/*}/lib/plan-state.sh"
PROJECT_ROOT="$(find_project_root)"

PLAN_DIR="$PROJECT_ROOT/.temp/plan-mode"
ACTIVE_DIR="$PLAN_DIR/active"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"

# Note: handoff-pending is NOT auto-cleared on compaction. It persists until
# the user approves via Orbit or runs /bypass.

active_plan_summary=""

if [ -d "$ACTIVE_DIR" ]; then
  # PPID-based plan routing: find the plan claimed by this session
  latest_json=$(plan_resolve_session "$PROJECT_ROOT")

  if [ -n "$latest_json" ] && [ -f "$latest_json" ]; then
    plan_dir="$(dirname "$latest_json")"
    plan_name="$(basename "$plan_dir")"

    plan_status_info=$(plan_get_status "$latest_json") || true

    if [ -n "$plan_status_info" ]; then
      plan_parse_status "$plan_status_info"
      done_count="$PLAN_DONE"
      active_count="$PLAN_ACTIVE"
      pending_count="$PLAN_PENDING"
      blocked_count="$PLAN_BLOCKED"
      next_step="$PLAN_NEXT_STEP"
      has_work="$PLAN_HAS_WORK"
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
    latest=$(plan_find_latest_legacy "$ACTIVE_DIR")

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
