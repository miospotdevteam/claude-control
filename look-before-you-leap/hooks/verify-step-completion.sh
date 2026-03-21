#!/usr/bin/env bash
# PostToolUse hook: Verify step completion before proceeding to next step.
#
# After every Edit/Write to a masterPlan.md, compares step statuses with
# a cached snapshot. When a step transitions to [x]:
# 1. Creates .verify-pending-N marker
# 2. Injects directive to dispatch a verification sub-agent
#
# The verification agent checks acceptance criteria, file changes, and
# Progress completeness before removing the marker.
#
# Marker: <plan-dir>/.verify-pending-N (N = step number)
# Cache: <plan-dir>/.step-status-cache (N:status per line)
#
# Input: JSON on stdin with tool_name, tool_input.file_path, cwd

set -euo pipefail

INPUT=$(cat)

# Extract file path
FILE_PATH=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null) || true

# Act on plan.json OR masterPlan.md in active plans
if [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/plan.json" ]]; then
  PLAN_DIR="$(dirname "$FILE_PATH")"
elif [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/masterPlan.md" ]]; then
  PLAN_DIR="$(dirname "$FILE_PATH")"
else
  exit 0
fi

# Find project root
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
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
import json, os, sys

steps = os.environ["HOOK_NEWLY_COMPLETED"]
plan_path = os.environ["HOOK_PLAN_PATH"]
plan_name = os.environ["HOOK_PLAN_NAME"]
plan_dir = os.environ["HOOK_PLAN_DIR"]
plan_json_path = os.environ["HOOK_PLAN_JSON"]
plan_utils_path = os.environ["HOOK_PLAN_UTILS"]

step_list = steps.split()
step_display = ", ".join(f"Step {s}" for s in step_list)
markers = ", ".join(f".verify-pending-{s}" for s in step_list)

# Check which completed steps have codexVerify: true
codex_verify_steps = []
if os.path.isfile(plan_json_path):
    try:
        sys.path.insert(0, os.path.dirname(plan_utils_path))
        import plan_utils
        plan = plan_utils.read_plan(plan_json_path)
        for step in plan.get("steps", []):
            if str(step["id"]) in step_list and step.get("codexVerify", False):
                codex_verify_steps.append(str(step["id"]))
    except Exception:
        pass

# Build Codex verification directive if any steps have codexVerify
codex_directive = ""
if codex_verify_steps:
    codex_step_display = ", ".join(f"Step {s}" for s in codex_verify_steps)
    codex_directive = (
        f"\n\n## Codex Independent Verification\n\n"
        f"{codex_step_display} {'has' if len(codex_verify_steps) == 1 else 'have'} "
        "`codexVerify: true` — after the verification agent passes, also run "
        "Codex MCP verification for an independent second opinion.\n\n"
        "1. Read `references/codex-verify-template.md` for the prompt template\n"
        "2. Assemble the MCP call by interpolating plan.json values:\n"
        "   - `developer-instructions`: discovery scope/consumers/blast radius "
        "+ step title/acceptance criteria/files/description\n"
        "   - `prompt`: verification task for the step\n"
        "3. Call `mcp__codex__codex` with:\n"
        "   ```json\n"
        "   {\n"
        '     "prompt": "<assembled prompt>",\n'
        '     "developer-instructions": "<assembled instructions>",\n'
        '     "sandbox": "workspace-write",\n'
        '     "approval-policy": "never",\n'
        '     "cwd": "<project root>"\n'
        "   }\n"
        "   ```\n"
        "4. Read the response. If Codex found issues:\n"
        "   - **Log findings first** to `${CLAUDE_PLUGIN_DATA}/codex-findings/` "
        "as `YYYY-MM-DD-<plan>-step-N.md` (see conductor skill for format)\n"
        "   - Fix them, then call `mcp__codex__codex-reply` with the "
        "`threadId` and re-verify prompt\n"
        "5. Record the Codex verdict in the step's `result` field\n\n"
        "If `mcp__codex__codex` is not available (Codex MCP server not "
        "configured), skip gracefully and note in the result field."
    )

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
            "2. Check `git diff --name-only` to confirm every file listed in "
            "the step's `files` array was actually modified.\n"
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
            + codex_directive
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
