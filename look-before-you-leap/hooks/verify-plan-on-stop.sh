#!/usr/bin/env bash
# Stop hook: Verify active plan progress before Claude stops.
#
# If this session's active plan has unchecked items, blocks stopping and
# reminds Claude to either continue working or update the plan status.
#
# Session-scoped: only checks plans claimed by this session's PPID.
# Plans owned by other sessions are ignored.
#
# Checks stop_hook_active to prevent infinite loops.
#
# Input: JSON on stdin with stop_hook_active, last_assistant_message

set -euo pipefail

INPUT=$(cat)

# Prevent infinite loop: if stop hook already fired, allow stopping
STOP_HOOK_ACTIVE=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print('true' if data.get('stop_hook_active', False) else 'false')
" <<< "$INPUT" 2>/dev/null) || true

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
ACTIVE_DIR="$PROJECT_ROOT/.temp/plan-mode/active"

# No active directory — nothing to check
if [ ! -d "$ACTIVE_DIR" ]; then
  exit 0
fi

# Find this session's plan via PPID routing
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/plan_utils.py"
latest_json=$(python3 "$PLAN_UTILS" find-for-session "$PROJECT_ROOT" "$PPID" 2>/dev/null) || true

# Allow stopping during plan review (per-plan handoff pending = waiting for user in Orbit)
if [ -n "$latest_json" ] && [ -f "$latest_json" ]; then
  if [ -f "$(dirname "$latest_json")/.handoff-pending" ]; then
    exit 0
  fi
fi

# No plan claimed by this session — allow stopping
if [ -z "$latest_json" ] || [ ! -f "$latest_json" ]; then
  exit 0
fi

# Use plan.json for status check
plan_name="$(basename "$(dirname "$latest_json")")"

export HOOK_PLAN_JSON="$latest_json"
export HOOK_PLAN_NAME="$plan_name"
export HOOK_PLAN_UTILS="$PLAN_UTILS"

python3 << 'PYEOF'
import json, os, sys

plan_json = os.environ["HOOK_PLAN_JSON"]
plan_name = os.environ["HOOK_PLAN_NAME"]
plan_utils_path = os.environ["HOOK_PLAN_UTILS"]

sys.path.insert(0, os.path.dirname(plan_utils_path))
import plan_utils

plan = plan_utils.read_plan(plan_json)
counts = plan_utils.count_by_status(plan)
pending = counts.get("pending", 0)
active = counts.get("in_progress", 0)
blocked = counts.get("blocked", 0)

remaining = pending + active
if remaining == 0:
    # All steps done — but check for steps with null/empty results
    null_result_steps = []
    for step in plan.get("steps", []):
        if step.get("status") == "done":
            result = step.get("result")
            if not result or (isinstance(result, str) and not result.strip()):
                null_result_steps.append(step["id"])

    if null_result_steps:
        ids = ", ".join(str(s) for s in null_result_steps)
        reason_parts = [
            f"Active plan '{plan_name}' has steps marked done with no result:",
            f"  - Steps missing results: {ids}",
            "",
            f"Plan file: {plan_json}",
            "",
            "Before stopping, fill in the result field for each done step.",
            "The result should describe what was implemented, files changed,",
            "and decisions made. Use plan_utils.py set-result to update progress.",
        ]
        output = {"decision": "block", "reason": "\n".join(reason_parts)}
        json.dump(output, sys.stdout)
        sys.exit(0)

    # For strict plans, check receipt coverage before allowing stop
    receipt_mode = plan.get("_receiptMode", "legacy")
    if receipt_mode == "strict":
        import pathlib
        plan_dir = pathlib.Path(plan_json).parent
        project_root = str(plan_dir)
        p = plan_dir
        while p != p.parent:
            if (p / ".git").exists():
                project_root = str(p)
                break
            p = p.parent

        receipt_utils_dir = os.path.join(
            os.path.dirname(os.path.dirname(plan_utils_path)),
            "..", "scripts"
        )
        try:
            sys.path.insert(0, os.path.realpath(receipt_utils_dir))
            import receipt_utils as ru
            proj_id = ru.project_id(project_root)
            plan_name_val = plan.get("name", "unknown")
            missing = []
            for step in plan.get("steps", []):
                if step.get("status") != "done":
                    continue
                sid = step["id"]
                owner = step.get("owner", "claude")
                mode = step.get("mode", "claude-impl")
                extra = {"step": sid}
                if mode in ("claude-impl", "dual-pass") or owner == "claude":
                    exists, _ = ru.check("codex_verify", proj_id, plan_name_val, extra)
                    if not exists:
                        missing.append(f"Step {sid}: missing codex_verify")
                elif mode == "codex-impl" or owner == "codex":
                    impl_exists, _ = ru.check("codex_impl", proj_id, plan_name_val, extra)
                    verify_exists, _ = ru.check("claude_verify", proj_id, plan_name_val, extra)
                    if not impl_exists:
                        missing.append(f"Step {sid}: missing codex_impl")
                    if not verify_exists:
                        missing.append(f"Step {sid}: missing claude_verify")
            if missing:
                detail = "\n  - ".join(missing)
                reason_parts = [
                    f"Active strict plan '{plan_name}' is missing verification receipts:",
                    f"  - {detail}",
                    "",
                    f"Plan file: {plan_json}",
                    "",
                    "Before stopping, run verification for steps missing receipts.",
                ]
                output = {"decision": "block", "reason": "\n".join(reason_parts)}
                json.dump(output, sys.stdout)
                sys.exit(0)
        except ImportError:
            pass

    sys.exit(0)

reason_parts = [f"Active plan '{plan_name}' has unfinished work:"]
if active > 0:
    reason_parts.append(f"  - {active} step(s) in-progress")
if pending > 0:
    reason_parts.append(f"  - {pending} step(s) pending")
if blocked > 0:
    reason_parts.append(f"  - {blocked} step(s) blocked")

reason_parts.extend([
    "", f"Plan file: {plan_json}", "",
    "Before stopping, either:",
    "1. Continue with the remaining steps",
    "2. Update the plan to reflect current status",
    "3. Tell the user what's remaining and why you're stopping",
])

output = {"decision": "block", "reason": "\n".join(reason_parts)}
json.dump(output, sys.stdout)
PYEOF
