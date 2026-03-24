#!/usr/bin/env bash
# PreToolUse hook: Block moving plans to completed/ if they have unchecked items.
#
# Detects: mv commands that move plan directories from active/ to completed/
# Reads the masterPlan.md and checks for [ ], [~], or [!] markers.
# If any unchecked items remain, denies the mv.
#
# Input: JSON on stdin with tool_name, tool_input.command, cwd

set -euo pipefail

INPUT=$(cat)

# Extract command
COMMAND=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('command', ''))
" <<< "$INPUT" 2>/dev/null) || true

[ -z "$COMMAND" ] && exit 0

# Only check mv commands that reference both active/ and completed/ in plan-mode
export HOOK_COMMAND="$COMMAND"

PLAN_PATH=$(python3 << 'PYEOF'
import re, os, sys

cmd = os.environ.get("HOOK_COMMAND", "")

# Must be a mv command involving plan-mode active/ -> completed/
if not re.search(r'\bmv\b', cmd):
    print("")
    sys.exit(0)

if 'plan-mode/active/' not in cmd and 'plan-mode/completed' not in cmd:
    # Also check if it has both active/ and completed/ in a plan context
    if not ('active/' in cmd and 'completed/' in cmd):
        print("")
        sys.exit(0)

# Try to extract the source path (the active plan directory or masterPlan.md)
# Common patterns:
#   mv '.temp/plan-mode/active/plan-name' '.temp/plan-mode/completed/plan-name'
#   mv '/full/path/.temp/plan-mode/active/plan-name' ...
parts = cmd.split()
source_path = ""
for i, part in enumerate(parts):
    # Skip the 'mv' command and flags
    if part == "mv" or part.startswith("-"):
        continue
    # Remove surrounding quotes
    cleaned = part.strip("'\"")
    if "plan-mode/active/" in cleaned or "/active/" in cleaned:
        source_path = cleaned
        break

if source_path:
    # Find the masterPlan.md in the source
    import os.path
    if source_path.endswith("masterPlan.md"):
        print(source_path)
    elif os.path.isfile(os.path.join(source_path, "masterPlan.md")):
        print(os.path.join(source_path, "masterPlan.md"))
    else:
        # Try appending masterPlan.md
        candidate = os.path.join(source_path, "masterPlan.md")
        print(candidate)
else:
    print("")
PYEOF
) || true

# Not a plan-moving command — allow
[ -z "$PLAN_PATH" ] && exit 0

# Check plan.json for unchecked items (fall back to masterPlan.md grep)
PLAN_DIR="$(dirname "$PLAN_PATH")"
PLAN_JSON="$PLAN_DIR/plan.json"

PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/plan_utils.py"

export HOOK_PLAN_PATH="$PLAN_PATH"
export HOOK_PLAN_JSON="$PLAN_JSON"
export HOOK_PLAN_UTILS="$PLAN_UTILS"

python3 << 'PYEOF'
import json, os, sys

plan_path = os.environ["HOOK_PLAN_PATH"]
plan_json = os.environ["HOOK_PLAN_JSON"]
plan_utils_path = os.environ["HOOK_PLAN_UTILS"]

# Try plan.json first
if os.path.isfile(plan_json):
    sys.path.insert(0, os.path.dirname(plan_utils_path))
    import plan_utils
    plan = plan_utils.read_plan(plan_json)
    counts = plan_utils.count_by_status(plan)
    pending = counts.get("pending", 0)
    active = counts.get("in_progress", 0)
    blocked = counts.get("blocked", 0)
    done = counts.get("done", 0)

    # Even if all steps are "done", check result quality
    if pending == 0 and active == 0 and blocked == 0 and done > 0:
        # Check for steps marked done but missing results or with incomplete progress
        null_result_steps = []
        incomplete_progress_steps = []
        for step in plan.get("steps", []):
            if step["status"] != "done":
                continue
            sid = step["id"]
            # Check result field
            result = step.get("result")
            if not result or (isinstance(result, str) and not result.strip()):
                null_result_steps.append(sid)
            # Check progress items
            for p in step.get("progress", []):
                if p.get("status") != "done":
                    incomplete_progress_steps.append(sid)
                    break

        if null_result_steps or incomplete_progress_steps:
            problems = []
            if null_result_steps:
                ids = ", ".join(str(s) for s in null_result_steps)
                problems.append(
                    f"Steps with empty/null result: {ids}\n"
                    "  Every done step MUST have a result describing what was implemented."
                )
            if incomplete_progress_steps:
                ids = ", ".join(str(s) for s in incomplete_progress_steps)
                problems.append(
                    f"Steps with incomplete progress items: {ids}\n"
                    "  All progress items must be 'done' before the step is complete."
                )
            detail = "\n".join(problems)
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": (
                        f"Cannot move plan to completed/ — steps are marked done but "
                        f"work is not fully verified:\n\n{detail}\n\n"
                        f"Plan: {plan_json}\n\n"
                        "Fix: fill in result fields (via plan_utils.py set-result) and "
                        "mark all progress items done (via plan_utils.py update-progress) before moving."
                    )
                }
            }
            json.dump(output, sys.stdout)
            sys.exit(0)

        # For strict plans, check that all steps have receipts
        receipt_mode = plan.get("_receiptMode", "legacy")
        if receipt_mode == "strict":
            # Find project root from plan path
            import pathlib
            plan_dir_path = pathlib.Path(plan_json).parent
            # Walk up to find .git
            project_root = str(plan_dir_path)
            p = plan_dir_path
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
                missing_receipts = []
                for step in plan.get("steps", []):
                    sid = step["id"]
                    owner = step.get("owner", "claude")
                    mode = step.get("mode", "claude-impl")
                    extra = {"step": sid}
                    if mode in ("claude-impl", "dual-pass") or owner == "claude":
                        exists, _ = ru.check("codex_verify", proj_id, plan_name_val, extra)
                        if not exists:
                            missing_receipts.append(f"Step {sid}: missing codex_verify receipt")
                    elif mode == "codex-impl" or owner == "codex":
                        impl_exists, _ = ru.check("codex_impl", proj_id, plan_name_val, extra)
                        verify_exists, _ = ru.check("claude_verify", proj_id, plan_name_val, extra)
                        if not impl_exists:
                            missing_receipts.append(f"Step {sid}: missing codex_impl receipt")
                        if not verify_exists:
                            missing_receipts.append(f"Step {sid}: missing claude_verify receipt")
                if missing_receipts:
                    detail = "\n".join(missing_receipts)
                    output = {
                        "hookSpecificOutput": {
                            "hookEventName": "PreToolUse",
                            "permissionDecision": "deny",
                            "permissionDecisionReason": (
                                f"Cannot move strict plan to completed/ — "
                                f"verification receipts missing:\n\n{detail}\n\n"
                                f"Plan: {plan_json}\n\n"
                                "Run verification scripts for each step to mint receipts."
                            )
                        }
                    }
                    json.dump(output, sys.stdout)
                    sys.exit(0)
            except ImportError:
                pass  # receipt_utils not available — allow

        # All checks pass — allow
        sys.exit(0)

elif os.path.isfile(plan_path):
    # Legacy: grep masterPlan.md
    import re
    with open(plan_path) as f:
        content = f.read()
    pending = len(re.findall(r'^\s*-\s*\[ \]', content, re.MULTILINE))
    active = len(re.findall(r'^\s*-\s*\[~\]', content, re.MULTILINE))
    blocked = len(re.findall(r'^\s*-\s*\[!\]', content, re.MULTILINE))
    done = len(re.findall(r'^\s*-\s*\[x\]', content, re.MULTILINE))
else:
    # Can't verify — allow
    sys.exit(0)

remaining = pending + active + blocked
if remaining == 0 and done > 0:
    # All done — allow
    sys.exit(0)

# Incomplete — deny
status_parts = []
if active > 0:
    status_parts.append(f"{active} in-progress")
if pending > 0:
    status_parts.append(f"{pending} pending")
if blocked > 0:
    status_parts.append(f"{blocked} blocked")

status = ", ".join(status_parts) if status_parts else "no completed items"

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"Cannot move plan to completed/ — it has unfinished work: {status}.\n\n"
            f"Plan: {plan_path}\n"
            f"Progress: {done} done, {remaining} remaining\n\n"
            "A plan is only complete when ALL steps are done. "
            "Complete the remaining steps or explicitly flag them to the user "
            "before moving the plan."
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
