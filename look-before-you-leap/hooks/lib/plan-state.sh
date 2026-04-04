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

# Check whether Orbit's durable review metadata records an approved plan.
# This is the fallback authority when the transient PostToolUse approval hook
# does not run for an MCP tool invocation.
#
# Args: $1 = plan.json path
# Returns: "true" or "false" on stdout
plan_review_is_approved() {
  local plan_json="$1"
  python3 - "$plan_json" <<'PYEOF' 2>/dev/null || true
import hashlib
import json
import os
import sys

plan_json = os.path.abspath(sys.argv[1])
plan_dir = os.path.dirname(plan_json)
source_path = os.path.join(plan_dir, "masterPlan.md")
review_path = source_path + ".review.json"

if not os.path.isfile(source_path) or not os.path.isfile(review_path):
    print("false")
    raise SystemExit(0)

try:
    with open(review_path, "r", encoding="utf-8") as fh:
        review = json.load(fh)
    with open(source_path, "rb") as fh:
        source_hash = hashlib.sha256(fh.read()).hexdigest()
except Exception:
    print("false")
    raise SystemExit(0)

recorded_source = review.get("sourcePath", "")
recorded_hash = review.get("sourceHash", "")
review_state = review.get("reviewState", "")

if review_state != "approved":
    print("false")
    raise SystemExit(0)

if recorded_source and os.path.abspath(recorded_source) != source_path:
    print("false")
    raise SystemExit(0)

if recorded_hash and recorded_hash != source_hash:
    print("false")
    raise SystemExit(0)

print("true")
PYEOF
}

# Recover approval from Orbit's durable review metadata by minting the
# handoff receipt ourselves, clearing any stale handoff marker, and optionally
# claiming the plan for the current session.
#
# Args:
#   $1 = plan.json path
#   $2 = optional claim PID (writes .session-lock)
# Returns:
#   receipt path on stdout when recovered, empty if not approved
plan_sync_review_approval() {
  local plan_json="$1"
  local claim_pid="${2:-}"
  local approved=""
  local plan_dir=""
  local project_root=""
  local proj_id=""
  local plan_name=""
  local receipt_path=""

  [ -f "$plan_json" ] || return 1

  approved=$(plan_review_is_approved "$plan_json" 2>/dev/null) || true
  if [ "$approved" != "true" ]; then
    return 1
  fi

  # shellcheck source=/dev/null
  source "${BASH_SOURCE[0]%/*}/receipt-state.sh"
  receipt_bootstrap >/dev/null 2>&1 || true

  project_root="$(find_project_root "$(dirname "$plan_json")")"
  proj_id=$(receipt_project_id "$project_root" 2>/dev/null) || true
  plan_name=$(receipt_plan_id "$plan_json" 2>/dev/null) || true
  if [ -n "$proj_id" ] && [ -n "$plan_name" ]; then
    receipt_path=$(receipt_sign "handoff_approved" "$proj_id" "$plan_name" 2>/dev/null) || true
  fi

  plan_dir="$(dirname "$plan_json")"
  rm -f "$plan_dir/.handoff-pending"
  if [ -n "$claim_pid" ]; then
    echo "$claim_pid" > "$plan_dir/.session-lock"
  fi

  [ -n "$receipt_path" ] && echo "$receipt_path"
}

# Recover a fresh, Orbit-approved plan across session handoff.
# This is used when normal PPID routing cannot find a plan, typically because
# a prior session still owns the .session-lock during handoff. Approval receipts
# are authoritative for fresh plans awaiting execution, so we can reattach the
# new session to the approved plan and clear any stale handoff marker.
#
# Args:
#   $1 = project_root
#   $2 = optional claim PID (writes .session-lock + clears .handoff-pending)
# Returns:
#   plan.json path on stdout (empty if no approved fresh plan found)
plan_resolve_approved_handoff() {
  local project_root="$1"
  local claim_pid="${2:-}"
  local active_dir="${project_root}/.temp/plan-mode/active"
  local candidates=""
  local plan_path=""
  local plan_name=""
  local proj_id=""
  local is_fresh=""

  [ -d "$active_dir" ] || return 0

  # shellcheck source=/dev/null
  source "${BASH_SOURCE[0]%/*}/receipt-state.sh"
  receipt_bootstrap >/dev/null 2>&1 || true
  proj_id=$(receipt_project_id "$project_root" 2>/dev/null) || true
  [ -n "$proj_id" ] || return 0

  candidates=$(python3 - "$active_dir" << 'PYEOF'
import os
import sys

active_dir = sys.argv[1]
candidates = []

for entry in os.listdir(active_dir):
    plan_dir = os.path.join(active_dir, entry)
    plan_path = os.path.join(plan_dir, "plan.json")
    if not os.path.isfile(plan_path):
        continue
    mtime = 0
    for name in ("plan.json", "progress.json"):
        candidate = os.path.join(plan_dir, name)
        if os.path.isfile(candidate):
            mtime = max(mtime, os.path.getmtime(candidate))
    candidates.append((mtime, plan_path))

for _, path in sorted(candidates, reverse=True):
    print(path)
PYEOF
  ) || true

  while IFS= read -r plan_path; do
    [ -n "$plan_path" ] || continue
    [ -f "$plan_path" ] || continue

    plan_name=$(receipt_plan_id "$plan_path" 2>/dev/null) || true
    [ -n "$plan_name" ] || continue

    if ! receipt_check "handoff_approved" "$proj_id" "$plan_name" 2>/dev/null; then
      if ! plan_sync_review_approval "$plan_path" >/dev/null 2>&1; then
        continue
      fi
    fi

    is_fresh=$(plan_is_fresh "$plan_path" 2>/dev/null) || true
    if [ "$is_fresh" != "true" ]; then
      continue
    fi

    if [ -n "$claim_pid" ]; then
      echo "$claim_pid" > "$(dirname "$plan_path")/.session-lock"
      rm -f "$(dirname "$plan_path")/.handoff-pending"
    fi

    echo "$plan_path"
    return 0
  done <<< "$candidates"
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
