#!/usr/bin/env bash
# PostToolUse hook: Verify step completion before proceeding to next step.
#
# After Edit/Write to plan.json/masterPlan.md, or after Bash calls that
# update plan.json via plan_utils.py, compares step statuses with a cached
# snapshot. When a step transitions to done/[x]:
# 1. For codexVerify steps: checks if result field contains a Codex verdict
#    (pattern: "Codex: PASS" or "Codex: FAIL"). If missing, reverts the
#    step to in_progress and blocks with instructions to run Codex first.
# 2. For steps that pass the Codex gate (or don't have codexVerify):
#    creates .verify-pending-N marker and injects directive to dispatch
#    a verification sub-agent.
#
# The verification agent checks acceptance criteria, file changes, and
# progress completeness before removing the marker.
#
# Marker: <plan-dir>/.verify-pending-N (N = step number)
# Cache: <plan-dir>/.step-status-cache (N:status per line)
#
# Input: JSON on stdin with tool_name, tool_input, cwd

set -euo pipefail

INPUT=$(cat)

# Find project root first (needed for Bash path)
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"

# Determine PLAN_DIR based on tool type
TOOL_NAME=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_name', ''))
" <<< "$INPUT" 2>/dev/null) || true

PLAN_DIR=""

if [[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" ]]; then
  # Edit/Write: extract file_path and check if it's a plan file
  FILE_PATH=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null) || true

  if [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/plan.json" ]]; then
    PLAN_DIR="$(dirname "$FILE_PATH")"
  elif [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/masterPlan.md" ]]; then
    PLAN_DIR="$(dirname "$FILE_PATH")"
  fi

elif [[ "$TOOL_NAME" == "Bash" ]]; then
  # Bash: check if command is a plan_utils call that marks a step done.
  # Extract the specific plan.json path from the command to handle multiple
  # active plans correctly (not just the first one found on disk).
  COMMAND=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('command', ''))
" <<< "$INPUT" 2>/dev/null) || true

  export HOOK_COMMAND="$COMMAND"
  export HOOK_PROJECT_ROOT="$PROJECT_ROOT"

  PLAN_DIR=$(python3 << 'PYEOF'
import re, os, sys

command = os.environ.get("HOOK_COMMAND", "")
project_root = os.environ.get("HOOK_PROJECT_ROOT", "")

# Must contain plan_utils
if "plan_utils" not in command:
    sys.exit(0)

# Must contain update-step with "done" as the status argument (not a substring)
if not re.search(r"update-step\s+\S+\s+\d+\s+done(?:\s|$|&|;)", command):
    sys.exit(0)

# Extract plan.json path from PLAN_JSON="..." variable assignment in the command
m = re.search(r'PLAN_JSON="(.*?\.temp/plan-mode/active/[^/]+/plan\.json)"', command)
if m:
    print(os.path.dirname(m.group(1)))
    sys.exit(0)

# Fallback: scan active plans directory (for commands where PLAN_JSON was set
# in a previous Bash call and only referenced as $PLAN_JSON here)
active_dir = os.path.join(project_root, ".temp", "plan-mode", "active")
if os.path.isdir(active_dir):
    for name in sorted(os.listdir(active_dir)):
        pj = os.path.join(active_dir, name, "plan.json")
        if os.path.isfile(pj):
            print(os.path.join(active_dir, name))
            break
PYEOF
  ) || true
fi

# No relevant plan file found — exit silently
if [[ -z "$PLAN_DIR" ]]; then
  exit 0
fi

CACHE_FILE="$PLAN_DIR/.step-status-cache"

PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/plan_utils.py"
PLAN_JSON="$PLAN_DIR/plan.json"
MASTER_PLAN="$PLAN_DIR/masterPlan.md"

export HOOK_PLAN_DIR="$PLAN_DIR"
export HOOK_PLAN_JSON="$PLAN_JSON"
export HOOK_MASTER_PLAN="$MASTER_PLAN"
export HOOK_PLAN_UTILS="$PLAN_UTILS"
export HOOK_CACHE_FILE="$CACHE_FILE"

# Compare current step statuses with cached, detect done transitions
RESULT=$(python3 << 'PYEOF'
import json, os, re, sys

plan_json = os.environ["HOOK_PLAN_JSON"]
master_plan = os.environ["HOOK_MASTER_PLAN"]
plan_utils_path = os.environ["HOOK_PLAN_UTILS"]
cache_file = os.environ["HOOK_CACHE_FILE"]
plan_dir_env = os.environ["HOOK_PLAN_DIR"]

# Parse current step statuses — prefer plan.json
current_steps = {}
plan_path_for_marker = master_plan  # default for marker file content

if os.path.isfile(plan_json):
    sys.path.insert(0, os.path.dirname(plan_utils_path))
    import plan_utils
    plan = plan_utils.read_plan(plan_json)
    for step in plan.get("steps", []):
        step_id = str(step["id"])
        # Map JSON statuses to single-char for cache compatibility
        status_map = {"pending": " ", "in_progress": "~", "done": "x", "blocked": "!"}
        current_steps[step_id] = status_map.get(step["status"], " ")
    plan_path_for_marker = plan_json
elif os.path.isfile(master_plan):
    # Legacy: parse masterPlan.md
    with open(master_plan) as f:
        content = f.read()
    step_pattern = re.compile(
        r'^###\s+Step\s+(\d+):.*?\n'
        r'.*?-\s+\*\*Status\*\*:\s*\[(.)\]',
        re.MULTILINE | re.DOTALL
    )
    for match in step_pattern.finditer(content):
        current_steps[match.group(1)] = match.group(2)
    plan_path_for_marker = master_plan
else:
    print(json.dumps({"newly_completed": []}))
    sys.exit(0)

# Read cached statuses
cached_steps = {}
if os.path.exists(cache_file):
    with open(cache_file) as f:
        for line in f:
            line = line.strip()
            if ':' in line:
                num, status = line.split(':', 1)
                cached_steps[num.strip()] = status.strip()

# Find steps that just transitioned to done/[x]
newly_completed = []
for step_num, status in current_steps.items():
    if status == 'x' and cached_steps.get(step_num, ' ') != 'x':
        newly_completed.append(step_num)

# Update cache
os.makedirs(plan_dir_env, exist_ok=True)
with open(cache_file, 'w') as f:
    for num in sorted(current_steps.keys(), key=int):
        f.write(f"{num}:{current_steps[num]}\n")

if not newly_completed:
    print(json.dumps({"newly_completed": []}))
    sys.exit(0)

# Create .verify-pending-N markers
markers_created = []
for step_num in newly_completed:
    marker_path = os.path.join(plan_dir_env, f".verify-pending-{step_num}")
    with open(marker_path, 'w') as f:
        f.write(f"{step_num}\n{plan_path_for_marker}\n")
    markers_created.append(step_num)

print(json.dumps({"newly_completed": markers_created, "plan_path": plan_path_for_marker}))
PYEOF
) || true

# Parse result
newly_completed=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
steps = data.get('newly_completed', [])
print(' '.join(str(s) for s in steps))
" <<< "$RESULT" 2>/dev/null) || true

# No new completions — exit silently
if [ -z "$newly_completed" ]; then
  exit 0
fi

plan_path=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('plan_path', ''))
" <<< "$RESULT" 2>/dev/null) || true

plan_name="$(basename "$(dirname "$plan_path")")"

export HOOK_NEWLY_COMPLETED="$newly_completed"
export HOOK_PLAN_PATH="$plan_path"
export HOOK_PLAN_NAME="$plan_name"

python3 << 'PYEOF'
import json, os, re, sys

steps = os.environ["HOOK_NEWLY_COMPLETED"]
plan_path = os.environ["HOOK_PLAN_PATH"]
plan_name = os.environ["HOOK_PLAN_NAME"]
plan_dir = os.environ["HOOK_PLAN_DIR"]
plan_json_path = os.environ["HOOK_PLAN_JSON"]
plan_utils_path = os.environ["HOOK_PLAN_UTILS"]

step_list = steps.split()
step_display = ", ".join(f"Step {s}" for s in step_list)
markers = ", ".join(f".verify-pending-{s}" for s in step_list)

# Check codexVerify steps and enforce direction-locked verification gate
# - owner=="claude" (claude-impl): result must match "Codex: (PASS|FAIL|skipped)"
# - owner=="codex" (codex-impl): result must match "Claude: verified" AND
#   must NOT contain "Codex: PASS" (prevents Codex self-verification)
codex_blocked_steps = []
direction_blocked_steps = []
plan = None
if os.path.isfile(plan_json_path):
    try:
        sys.path.insert(0, os.path.dirname(plan_utils_path))
        import plan_utils
        plan = plan_utils.read_plan(plan_json_path)
        for step in plan.get("steps", []):
            sid = str(step["id"])
            if sid not in step_list:
                continue
            if not step.get("codexVerify", True):
                continue
            result = step.get("result") or ""
            owner = step.get("owner", "claude")
            mode = step.get("mode", "claude-impl")

            if mode == "collab-split":
                # collab-split: inspect groups to determine required verdicts
                has_codex = re.search(r"Codex:\s*(PASS|FAIL|skipped)", result, re.IGNORECASE)
                has_claude = re.search(r"Claude:\s*verified", result, re.IGNORECASE)
                # Check which owner types exist in the groups
                sub_plan = step.get("subPlan") or {}
                groups = sub_plan.get("groups", [])
                has_claude_groups = any(g.get("owner", owner) == "claude" for g in groups)
                has_codex_groups = any(g.get("owner", owner) == "codex" for g in groups)
                # Require matching verdicts for each owner type present
                missing = False
                if has_claude_groups and not has_codex:
                    missing = True  # Claude groups need Codex verification
                if has_codex_groups and not has_claude:
                    missing = True  # Codex groups need Claude verification
                if not has_codex and not has_claude:
                    missing = True  # No verdicts at all
                if missing:
                    codex_blocked_steps.append(sid)
            elif owner == "codex":
                # codex-impl: Claude must verify independently
                has_claude_verified = re.search(r"Claude:\s*verified", result, re.IGNORECASE)
                has_codex_pass = re.search(r"Codex:\s*PASS", result, re.IGNORECASE)
                if not has_claude_verified:
                    direction_blocked_steps.append(sid)
                elif has_codex_pass:
                    # Codex verified its own work — reject
                    direction_blocked_steps.append(sid)
            else:
                # claude-impl: Codex must verify
                if not re.search(r"Codex:\s*(PASS|FAIL|skipped)", result, re.IGNORECASE):
                    codex_blocked_steps.append(sid)
    except Exception:
        pass

# Handle direction-blocked codex-impl steps
if direction_blocked_steps:
    for sid in direction_blocked_steps:
        try:
            plan_utils.update_step(plan_json_path, int(sid), "in_progress")
        except Exception:
            pass
        marker_path = os.path.join(plan_dir, f".verify-pending-{sid}")
        if os.path.exists(marker_path):
            os.remove(marker_path)

    blocked_display = ", ".join(f"Step {s}" for s in direction_blocked_steps)
    output = {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": (
                f"CLAUDE INDEPENDENT VERIFICATION REQUIRED — "
                f"{blocked_display} {'is' if len(direction_blocked_steps) == 1 else 'are'} "
                "codex-impl (owner: codex) with `codexVerify: true`.\n\n"
                f"{'This step has' if len(direction_blocked_steps) == 1 else 'These steps have'} "
                "been reverted to `in_progress`.\n\n"
                "For codex-impl steps, CLAUDE must verify independently — "
                "Codex cannot verify its own work.\n\n"
                "1. Read `git diff --name-only` to see what Codex changed\n"
                "2. Read EVERY modified file (at least changed sections)\n"
                "3. Run tsc/lint/tests\n"
                "4. Check each acceptance criterion against actual code\n"
                "5. If dep maps exist, run deps-query on modified shared files\n"
                "6. Set the result field to include 'Claude: verified'\n"
                "7. Do NOT include 'Codex: PASS' — that would be rejected\n"
                "8. Then mark the step done again"
            )
        }
    }
    json.dump(output, sys.stdout)
    sys.exit(0)

# Handle codex-blocked claude-impl steps
if codex_blocked_steps:
    for sid in codex_blocked_steps:
        try:
            plan_utils.update_step(plan_json_path, int(sid), "in_progress")
        except Exception:
            pass
        marker_path = os.path.join(plan_dir, f".verify-pending-{sid}")
        if os.path.exists(marker_path):
            os.remove(marker_path)

    blocked_display = ", ".join(f"Step {s}" for s in codex_blocked_steps)
    output = {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": (
                f"CODEX VERIFICATION REQUIRED BEFORE MARKING DONE — "
                f"{blocked_display} {'has' if len(codex_blocked_steps) == 1 else 'have'} "
                "`codexVerify: true` but no Codex verdict in the result field.\n\n"
                f"{'This step has' if len(codex_blocked_steps) == 1 else 'These steps have'} "
                "been reverted to `in_progress`.\n\n"
                "You must run Codex verification via `run-codex-verify.sh` and get a "
                "PASS verdict BEFORE marking the step done:\n\n"
                "1. Invoke `Skill(skill: 'look-before-you-leap:codex-dispatch')`\n"
                "2. The skill runs `run-codex-verify.sh` in the background\n"
                "3. Fix any findings, then re-run verification\n"
                "4. Repeat until Codex reports PASS\n"
                "5. Set the result field to include 'Codex: PASS' (or the verdict)\n"
                "6. Then mark the step done again\n\n"
                "If `codex` CLI is not available, note 'Codex: skipped — "
                "codex CLI not installed' in the result field."
            )
        }
    }
    json.dump(output, sys.stdout)
    sys.exit(0)

# All codexVerify gates passed (or no codexVerify steps) — proceed with
# generic verification sub-agent flow
output = {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            f"STEP VERIFICATION REQUIRED — {step_display} just marked [x] in "
            f"plan '{plan_name}'.\n\n"
            "STOP. Before proceeding to the next step, you MUST dispatch a "
            "verification sub-agent to confirm the completed step was "
            "implemented correctly and fully.\n\n"
            "## Dispatch verification agent\n\n"
            "Use the Agent tool (general-purpose, foreground) with this prompt:\n\n"
            "```\n"
            f"Verify that {step_display} of the plan at `{plan_path}` was "
            "implemented correctly and FULLY. Do the following checks:\n\n"
            "1. Read the step from plan.json — note its acceptanceCriteria, "
            "files array, and progress items.\n"
            "2. Check `git diff --name-only` for modified tracked files AND "
            "`git status --short` for untracked new files. Every file in "
            "the step's `files` array should appear in one of these — "
            "either as a modified tracked file or as a new untracked file.\n"
            "3. Check that ALL progress items in the step have status 'done' — "
            "none should be 'pending' or 'in_progress'.\n"
            "4. If the acceptance criteria include a test or verification "
            "command, run it.\n"
            "5. Read the modified files briefly to confirm the changes match "
            "the step's description.\n\n"
            "If ALL checks pass:\n"
            f"- Remove the verification marker(s): "
            + " && ".join(f"rm {plan_dir}/.verify-pending-{s}" for s in step_list)
            + "\n"
            "- Report: 'Verification PASSED for " + step_display + "'\n\n"
            "If ANY check fails:\n"
            "- Report exactly what is missing or incomplete\n"
            "- Do NOT remove the marker — code edits remain blocked until "
            "the issues are fixed\n"
            "```\n\n"
            "Code file edits are BLOCKED until verification passes (the "
            f"enforce-plan hook checks for {markers}).\n\n"
            f"To bypass: rm {plan_dir}/.verify-pending-* "
            "(only if you're sure the step is fully implemented)"
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
