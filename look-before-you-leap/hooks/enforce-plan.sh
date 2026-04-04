#!/usr/bin/env bash
# PreToolUse hook: Enforce that an active plan exists before Edit/Write.
#
# Allows:
#   - Edits to .temp/ (plan files themselves)
#   - Edits when .temp/plan-mode/.no-plan-$PPID exists (per-session counter-based bypass, max N edits)
#   - Edits when an active plan.json exists
#
# Denies:
#   - All other Edit/Write calls — forces plan creation first.
#
# Input: JSON on stdin with tool_name, tool_input.file_path, cwd

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
hook_read_input

# Extract file path from tool input (works for both Edit and Write)
FILE_PATH=$(hook_get_file_path)

# Allow edits to .temp/ directory — EXCEPT plan.json after approval
if [[ "$FILE_PATH" == *"/.temp/"* ]] || [[ "$FILE_PATH" == *"/.temp" ]]; then
  # Guard plan.json immutability: block direct edits after plan is no longer fresh
  if [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/plan.json" ]]; then
    PLUGIN_ROOT_EARLY="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
    PLAN_UTILS_EARLY="${PLUGIN_ROOT_EARLY}/scripts/plan_utils.py"
    is_fresh=$(python3 "$PLAN_UTILS_EARLY" is-fresh "$FILE_PATH" 2>/dev/null) || true
    if [ "$is_fresh" = "false" ]; then
      python3 << 'PYEOF'
import json, sys

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "BLOCKED: plan.json is immutable after approval. "
            "All mutable state (step status, results, progress items, "
            "completedSummary, deviations, codexSessions) lives in progress.json.\n\n"
            "Use plan_utils.py commands to update progress:\n"
            "  update-step, update-progress, set-result, add-summary, "
            "add-deviation, complete-step\n\n"
            "These commands automatically write to progress.json, not plan.json."
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
      exit 0
    fi
  fi
  exit 0
fi

# Find project root (prefers root with .temp/plan-mode/ for monorepo support)
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"
source "${BASH_SOURCE[0]%/*}/lib/plan-state.sh"

CWD=$(hook_get_cwd)

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"

# Allow edits to known safe paths outside the project root
# (e.g., ~/.claude/plans/ scratch pad, plugin plan files)
# NOTE: cross-project edits to OTHER project roots are no longer blanket-allowed.
# The filesystem mutation guard handles Bash; this narrowing handles Edit/Write.
if [[ -n "$FILE_PATH" ]] && [[ "$FILE_PATH" != "$PROJECT_ROOT"* ]]; then
  # Allow only the plan-mode scratch pad under ~/.claude/plans/
  if [[ "$FILE_PATH" == "$HOME/.claude/plans/"* ]]; then
    exit 0
  fi
  # Allow /tmp and temp dirs (test fixtures, scratch files)
  if [[ "$FILE_PATH" == "/tmp/"* ]] || [[ "$FILE_PATH" == "${TMPDIR:-/nonexistent}/"* ]]; then
    exit 0
  fi
  # Other outside-root edits: deny (requires plan or bypass)
  # Fall through to plan check below
fi

# Check for receipt-based bypass (strict mode — receipts are authority)
source "${BASH_SOURCE[0]%/*}/lib/receipt-state.sh"
receipt_bootstrap 2>/dev/null || true
PROJ_ID=$(receipt_project_id "$PROJECT_ROOT" 2>/dev/null) || true
if [ -n "$PROJ_ID" ]; then
  # Check any plan ID that has a bypass receipt for this project
  # (bypass receipts use session-scoped plan IDs)
  BYPASS_DIR="${RECEIPT_STATE_ROOT}/${PROJ_ID}"
  if [ -d "$BYPASS_DIR" ]; then
    for plan_dir in "$BYPASS_DIR"/*/; do
      [ -d "$plan_dir" ] || continue
      if [ -f "${plan_dir}bypass-default.json" ]; then
        if receipt_verify_bypass "${plan_dir}bypass-default.json" "$PPID" 2>/dev/null; then
          exit 0
        fi
      fi
    done
  fi
fi

# Classify the active plan (if any) to determine enforcement mode
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"
SESSION_PLAN=$(plan_resolve_session "$PROJECT_ROOT")
if [ -z "$SESSION_PLAN" ]; then
  SESSION_PLAN=$(plan_resolve_approved_handoff "$PROJECT_ROOT" "$PPID")
fi
PLAN_MODE="legacy"
if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
  PLAN_MODE=$(receipt_classify "$SESSION_PLAN" 2>/dev/null) || PLAN_MODE="legacy"
fi

# Check for per-session bypass (legacy: counter-based .no-plan-$PPID marker)
# Skip for strict plans — they require signed receipts (checked above)
NO_PLAN_FILE="$PROJECT_ROOT/.temp/plan-mode/.no-plan-$PPID"
if [ "$PLAN_MODE" != "strict" ] && [ -f "$NO_PLAN_FILE" ]; then
  bypass_content=$(cat "$NO_PLAN_FILE" 2>/dev/null) || true
  if [[ "$bypass_content" == *:* ]]; then
    bypass_pid="${bypass_content%%:*}"
    bypass_count="${bypass_content##*:}"
    # Bypass counter is set by user via /bypass command
  else
    rm -f "$NO_PLAN_FILE"
    bypass_pid=""
    bypass_count=""
  fi
  if [ -n "$bypass_pid" ] && [ "$bypass_pid" = "$PPID" ] && [ -n "$bypass_count" ]; then
    # Decrement counter
    new_count=$((bypass_count - 1))
    if [ "$new_count" -le 0 ]; then
      rm -f "$NO_PLAN_FILE"
    else
      echo "${bypass_pid}:${new_count}" > "$NO_PLAN_FILE"
    fi
    exit 0
  else
    # Wrong session or invalid format — stale bypass, remove it
    rm -f "$NO_PLAN_FILE"
    # Fall through to deny
  fi
fi

# Check for per-plan handoff-pending marker (fresh plan needs plan mode handoff first)
# SESSION_PLAN already computed above during plan classification

if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
  SESSION_PLAN_DIR="$(dirname "$SESSION_PLAN")"
  HANDOFF_MARKER="$SESSION_PLAN_DIR/.handoff-pending"

  if [ -f "$HANDOFF_MARKER" ]; then
    # Approval receipts are authoritative. If approval was recorded but the
    # marker lingered, clear it here so the session can recover cleanly.
    if [ -n "${PROJ_ID:-}" ]; then
      SESSION_PLAN_NAME=$(receipt_plan_id "$SESSION_PLAN" 2>/dev/null) || true
      if [ -n "$SESSION_PLAN_NAME" ] && receipt_check "handoff_approved" "$PROJ_ID" "$SESSION_PLAN_NAME" 2>/dev/null; then
        rm -f "$HANDOFF_MARKER"
      else
        plan_sync_review_approval "$SESSION_PLAN" "$PPID" >/dev/null 2>&1 || true
      fi
    else
      plan_sync_review_approval "$SESSION_PLAN" "$PPID" >/dev/null 2>&1 || true
    fi
  fi

  if [ -f "$HANDOFF_MARKER" ]; then
    # Read the plan path stored in the marker
    PLAN_PATH=$(cat "$HANDOFF_MARKER" 2>/dev/null) || true
    if [ -z "$PLAN_PATH" ] || [ "$PLAN_PATH" = "unknown" ]; then
      PLAN_PATH="${SESSION_PLAN_DIR}/masterPlan.md"
    elif [[ "$PLAN_PATH" == *"/plan.json" ]]; then
      MASTER_PLAN_CANDIDATE="$(dirname "$PLAN_PATH")/masterPlan.md"
      if [ -f "$MASTER_PLAN_CANDIDATE" ]; then
        PLAN_PATH="$MASTER_PLAN_CANDIDATE"
      fi
    fi

    # Auto-clear if plan has progressed
    if [ -n "$PLAN_PATH" ]; then
      plan_dir="$(dirname "$PLAN_PATH")"
      plan_json="$plan_dir/plan.json"
      if [ -f "$plan_json" ]; then
        is_fresh=$(python3 "$PLAN_UTILS" is-fresh "$plan_json" 2>/dev/null) || true
        if [ "$is_fresh" = "false" ]; then
          rm -f "$HANDOFF_MARKER"
          # Fall through — plan is active, allow edit
        fi
      elif [ -f "$PLAN_PATH" ]; then
        done_count=$(grep -cE '^\s*-\s*\[x\]' "$PLAN_PATH" 2>/dev/null) || true
        active_count=$(grep -cE '^\s*-\s*\[~\]' "$PLAN_PATH" 2>/dev/null) || true
        if [ "$done_count" -gt 0 ] || [ "$active_count" -gt 0 ]; then
          rm -f "$HANDOFF_MARKER"
        fi
      else
        rm -f "$HANDOFF_MARKER"
      fi
    else
      rm -f "$HANDOFF_MARKER"
    fi

    # Re-check: if marker still exists after auto-clear attempts, deny
    if [ -f "$HANDOFF_MARKER" ]; then
      export HOOK_MARKER_PATH="$HANDOFF_MARKER"
      export HOOK_PLAN_PATH="${PLAN_PATH:-unknown}"
      python3 << 'PYEOF'
import json, sys, os

marker = os.environ["HOOK_MARKER_PATH"]
plan_path = os.environ.get("HOOK_PLAN_PATH", "unknown")

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "BLOCKED: Fresh plan requires Orbit review before code edits.\n\n"
            "## Step 1: Discover Orbit tools\n\n"
            "Use ToolSearch to find orbit_await_review:\n"
            "  ToolSearch query: \"+orbit await_review\"\n\n"
            "## Step 2: Submit for review (blocking)\n\n"
            "1. Tell the user: \"The plan is open in VS Code for review. "
            "Add inline comments, then click Approve or Request Changes.\"\n"
            f"2. Call orbit_await_review with sourcePath: {plan_path}\n"
            "   This opens the plan in VS Code and BLOCKS until user responds.\n\n"
            "## Step 3: Handle the response\n\n"
            "- approved → proceed to Step 4\n"
            "- changes_requested → update plan, re-submit\n"
            "- timeout → ask user to review when ready\n\n"
            "## Step 4: Plan mode handoff\n\n"
            "The pending-review marker is cleared only when "
            "orbit_await_review returns approved. EnterPlanMode happens "
            "after approval; it does not clear a pending review marker.\n\n"
            "FIRST: Kill ALL running background tasks (background Bash, "
            "Agents, Codex exec). They are no longer needed. Stale results "
            "leak into the new session after context clears.\n\n"
            "1. Call EnterPlanMode — do NOT output text in the same response\n"
            "2. After EnterPlanMode, a system message gives you the scratch "
            "pad file path (under ~/.claude/plans/). Write to THAT file — "
            "NOT to masterPlan.md or plan.json. Content: plan title, path "
            "to plan.json, step count, one-liner context, and 'Read "
            "plan.json to begin execution.' Nothing else.\n"
            "3. Call ExitPlanMode — do NOT output text in the same response\n\n"
            "IMPORTANT: Do not output explanatory text alongside "
            "EnterPlanMode or ExitPlanMode calls. Extra text can cause "
            "the plan mode transition to fail.\n\n"
            "If Orbit is unavailable, ask the user to run exactly /bypass."
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
      exit 0
    fi
  fi
fi

# Check for per-plan step verification pending
if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
  VERIFY_MARKERS=("$SESSION_PLAN_DIR"/.verify-pending-*)
  if [ -e "${VERIFY_MARKERS[0]}" ]; then
    export HOOK_FILE_PATH="$FILE_PATH"
    export HOOK_PLAN_PATH="$SESSION_PLAN"
    export HOOK_PROJECT_ROOT="$PROJECT_ROOT"
    export HOOK_CWD="${CWD:-$PWD}"
    export HOOK_PLAN_UTILS="$PLAN_UTILS"
    export HOOK_VERIFY_MARKERS="$(printf '%s\n' "${VERIFY_MARKERS[@]}")"

    VERIFY_RESULT=$(python3 << 'PYEOF'
import json, os, sys

plan_path = os.environ.get("HOOK_PLAN_PATH", "")
raw_file_path = os.environ.get("HOOK_FILE_PATH", "")
project_root = os.environ.get("HOOK_PROJECT_ROOT", "")
cwd = os.environ.get("HOOK_CWD", "")
plan_utils_path = os.environ.get("HOOK_PLAN_UTILS", "")
marker_paths = [
    line for line in os.environ.get("HOOK_VERIFY_MARKERS", "").splitlines() if line
]


def normalize_file_path(path):
    if not path:
        return ""
    if not os.path.isabs(path):
        path = os.path.join(cwd or project_root, path)
    path = os.path.normpath(path)

    root = os.path.normpath(project_root) if project_root else ""
    if root and path.startswith(root + os.sep):
        return path[len(root) + 1:]
    if root and path == root:
        return ""
    return path


normalized_path = normalize_file_path(raw_file_path)
if not plan_path or not normalized_path:
    print(json.dumps({"matching": [], "pending": []}))
    sys.exit(0)

try:
    if plan_utils_path:
        sys.path.insert(0, os.path.dirname(plan_utils_path))
        import plan_utils
        plan = plan_utils.read_plan(plan_path)
    else:
        with open(plan_path) as f:
            plan = json.load(f)
except (OSError, json.JSONDecodeError, ImportError):
    print(json.dumps({"matching": [], "pending": []}))
    sys.exit(0)

pending = []
matching = []
seen = set()

for marker_path in marker_paths:
    marker_name = os.path.basename(marker_path)
    prefix = ".verify-pending-"
    if not marker_name.startswith(prefix):
        continue
    try:
        step_id = int(marker_name[len(prefix):])
    except ValueError:
        continue

    if step_id not in seen:
        pending.append(step_id)
        seen.add(step_id)

    step = None
    for candidate in plan.get("steps", []):
        if candidate.get("id") == step_id:
            step = candidate
            break
    if step and normalized_path in step.get("files", []):
        matching.append(step_id)

print(json.dumps({"matching": matching, "pending": pending}))
PYEOF
) || VERIFY_RESULT='{"matching":[],"pending":[]}'

    matching_steps=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
steps = data.get('matching', [])
print(', '.join(f'Step {step}' for step in steps))
" <<< "$VERIFY_RESULT" 2>/dev/null) || true

    if [ -n "$matching_steps" ]; then
      export HOOK_MATCHING_STEPS="$matching_steps"
      python3 << 'PYEOF'
import json, os, sys

matching = os.environ["HOOK_MATCHING_STEPS"]

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"Step verification pending for {matching}. This edit targets a file "
            "owned by the step being verified, so code edits remain blocked until "
            "a verification sub-agent confirms the completed step was implemented "
            "correctly and fully.\n\n"
            "Dispatch a verification agent now (see the directive injected when "
            "the step was marked [x]).\n\n"
            "To bypass, ask the user to run /bypass."
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
      exit 0
    fi
  fi
fi

# PPID-scoped plan check: this session must have a claimed plan
# SESSION_PLAN was already computed above via find-for-session
if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
  # --- Step ownership enforcement (merged from enforce-step-ownership.sh) ---
  # Block Claude edits to files owned by codex-impl steps/groups
  export HOOK_FILE_PATH="$FILE_PATH"
  export HOOK_PLAN_PATH="$SESSION_PLAN"
  export HOOK_PROJECT_ROOT="$PROJECT_ROOT"
  export HOOK_CWD="${CWD:-$PWD}"
  export HOOK_PLAN_UTILS="$PLAN_UTILS"

  OWNERSHIP_RESULT=$(python3 << 'PYEOF'
import json, os, sys

plan_path = os.environ.get("HOOK_PLAN_PATH", "")
raw_file_path = os.environ.get("HOOK_FILE_PATH", "")
project_root = os.environ.get("HOOK_PROJECT_ROOT", "")
cwd = os.environ.get("HOOK_CWD", "")

# Normalize the file path: resolve relative paths, collapse ../
if raw_file_path:
    if not os.path.isabs(raw_file_path):
        raw_file_path = os.path.join(cwd or project_root, raw_file_path)
    file_path = os.path.normpath(raw_file_path)
else:
    file_path = ""

# Convert to project-relative path
if project_root and file_path.startswith(os.path.normpath(project_root) + "/"):
    file_path = file_path[len(os.path.normpath(project_root)) + 1:]
elif project_root and file_path == os.path.normpath(project_root):
    file_path = ""

if not plan_path or not file_path:
    print("allow")
    sys.exit(0)

try:
    plan_utils_path = os.environ.get("HOOK_PLAN_UTILS", "")
    if plan_utils_path:
        sys.path.insert(0, os.path.dirname(plan_utils_path))
        import plan_utils
        plan = plan_utils.read_plan(plan_path)
    else:
        with open(plan_path) as f:
            plan = json.load(f)
except (OSError, json.JSONDecodeError, ImportError):
    print("allow")
    sys.exit(0)

# Find all in_progress steps with codex ownership
for step in plan.get("steps", []):
    if step.get("status") != "in_progress":
        continue

    step_owner = step.get("owner", "claude")
    step_files = step.get("files", [])

    # Check sub-plan groups for collab-split
    sub_plan = step.get("subPlan")
    if sub_plan and "groups" in sub_plan:
        for group in sub_plan["groups"]:
            group_owner = group.get("owner", step_owner)
            if group_owner == "codex":
                group_files = group.get("files", [])
                if file_path in group_files:
                    print(f"deny:step {step['id']}:group {group.get('title', 'unknown')}:codex")
                    sys.exit(0)
    elif step_owner == "codex":
        if file_path in step_files:
            print(f"deny:step {step['id']}::codex")
            sys.exit(0)

print("allow")
PYEOF
  ) || OWNERSHIP_RESULT="allow"

  if [[ "$OWNERSHIP_RESULT" == "allow" ]]; then
    exit 0
  fi

  # Parse the deny result and emit deny JSON
  STEP_INFO=$(echo "$OWNERSHIP_RESULT" | cut -d: -f2)
  GROUP_INFO=$(echo "$OWNERSHIP_RESULT" | cut -d: -f3)

  DENY_MSG="BLOCKED: This file is owned by a codex-impl step ($STEP_INFO"
  if [ -n "$GROUP_INFO" ]; then
    DENY_MSG="$DENY_MSG, $GROUP_INFO"
  fi
  DENY_MSG="$DENY_MSG). Claude cannot directly edit files in Codex-owned steps.\n\nTo modify this file:\n1. Dispatch Codex via run-codex-implement.sh to make changes\n2. Then verify Codex's work independently\n\nIf ownership is wrong, update the step's owner field in plan.json."

  hook_deny "$DENY_MSG"
  exit 0
fi

# No plan for this session — deny the edit
python3 << 'PYEOF'
import json, sys

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "No active plan found for this session. The look-before-you-leap plugin "
            "requires a plan before editing code.\n\n"
            "To create a plan:\n"
            "1. Explore the codebase (read files, grep consumers)\n"
            "2. Write plan.json + masterPlan.md to .temp/plan-mode/active/<plan-name>/\n"
            "3. Then proceed with edits\n\n"
            "For trivial changes, ask the user to run /bypass."
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
