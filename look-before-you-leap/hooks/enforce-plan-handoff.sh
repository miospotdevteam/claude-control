#!/usr/bin/env bash
# Hook: Enforce plan review handoff for fresh plans.
#
# Blocks while .handoff-pending exists:
#   - Edit/Write tool calls are blocked by enforce-plan.sh before code edits.
#   - Bash execution-phase wrapper calls are blocked here when the command
#     invokes run-codex-implement.sh or run-codex-verify.sh for the pending
#     plan.
#
# Creates .handoff-pending:
#   - PostToolUse after Edit/Write to a fresh plan.json or masterPlan.md.
#
# After every Edit/Write to a masterPlan.md, checks if the plan is fresh
# (all steps are [ ], none are [x] or [~]). If so:
# 1. Creates .handoff-pending marker inside the plan directory
# 2. Injects directive to present the plan via Orbit MCP for user review
#
# The Orbit flow: generate resolved artifact (opens in VS Code) → user
# reviews with inline comments → user approves or requests changes →
# Claude reads feedback, iterates if needed, then proceeds to execution
# via plan mode handoff (EnterPlanMode → summarize → ExitPlanMode).
#
# The marker is cleared by clear-handoff-on-approval.sh when Orbit approval
# is recorded. It is NOT auto-cleared on session start or EnterPlanMode.
# Bypass: ask the user to run /bypass
#
# Input: JSON on stdin with tool_name, tool_input.file_path or
# tool_input.command, cwd

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"
source "${BASH_SOURCE[0]%/*}/lib/plan-state.sh"
hook_read_input

TOOL_NAME=$(hook_get_tool_name)
COMMAND=$(hook_get_command)
CWD=$(hook_get_cwd)

if [ "$TOOL_NAME" = "Bash" ]; then
  CMD_TRIMMED="${COMMAND#"${COMMAND%%[![:space:]]*}"}"
  if [[ "$CMD_TRIMMED" =~ ^bash[[:space:]] ]] && \
     [[ ! "$CMD_TRIMMED" =~ ^bash[[:space:]]+-n[[:space:]] ]] && \
     [[ "$CMD_TRIMMED" =~ run-codex-(implement|verify)\.sh([[:space:]]|$) ]]; then
    PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
    WRAPPER_PLAN=$(HOOK_COMMAND="$COMMAND" HOOK_CWD="${CWD:-$PWD}" python3 << 'PYEOF'
import os
import shlex

cmd = os.environ.get("HOOK_COMMAND", "")
cwd = os.environ.get("HOOK_CWD", "") or os.getcwd()

try:
    parts = shlex.split(cmd)
except ValueError:
    parts = cmd.split()

for part in parts:
    if not part.endswith("plan.json"):
        continue
    path = os.path.expanduser(part)
    if not os.path.isabs(path):
        path = os.path.abspath(os.path.join(cwd, path))
    if os.path.isfile(path):
        print(path)
        break
PYEOF
    ) || true

    SESSION_PLAN="$WRAPPER_PLAN"
    if [ -z "$SESSION_PLAN" ]; then
      SESSION_PLAN=$(plan_resolve_session "$PROJECT_ROOT") || true
    fi

    if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
      HANDOFF_MARKER="$(dirname "$SESSION_PLAN")/.handoff-pending"
      if [ -f "$HANDOFF_MARKER" ]; then
        plan_sync_review_approval "$SESSION_PLAN" "$PPID" >/dev/null 2>&1 || true
      fi
      if [ -f "$HANDOFF_MARKER" ]; then
        hook_deny "BLOCKED: Fresh plan requires Orbit review before Codex execution wrappers can run.\n\nThe pending-review marker is still present: $HANDOFF_MARKER\n\nCall orbit_await_review for the plan and wait for approval before running run-codex-implement.sh or run-codex-verify.sh. The marker must be cleared by Orbit approval, not by inference from task size or interactivity.\n\nTo bypass, ask the user to run exactly /bypass."
        exit 0
      fi
    fi
  fi

  exit 0
fi

# Extract file path from tool input
FILE_PATH=$(hook_get_file_path)

# Act on plan.json OR masterPlan.md inside .temp/plan-mode/active/
if [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/plan.json" ]]; then
  PLAN_DIR="$(dirname "$FILE_PATH")"
elif [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/masterPlan.md" ]]; then
  PLAN_DIR="$(dirname "$FILE_PATH")"
else
  exit 0
fi

# Determine freshness — prefer plan.json
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"
PLAN_JSON="$PLAN_DIR/plan.json"
MASTER_PLAN="$PLAN_DIR/masterPlan.md"

if [ -f "$PLAN_JSON" ]; then
  is_fresh=$(python3 "$PLAN_UTILS" is-fresh "$PLAN_JSON" 2>/dev/null) || true
  if [ "$is_fresh" != "true" ]; then
    exit 0
  fi
  pending_count=$(python3 -c "
import json
plan = json.load(open('$PLAN_JSON'))
print(sum(1 for s in plan.get('steps', []) if s.get('status') == 'pending'))
" 2>/dev/null) || true
  # For the FILE_PATH used in the directive, prefer masterPlan.md (user-facing)
  if [ -f "$MASTER_PLAN" ]; then
    FILE_PATH="$MASTER_PLAN"
  fi
elif [ -f "$MASTER_PLAN" ]; then
  # Legacy: grep masterPlan.md
  done_count=$(grep -cE '^\s*-\s*\[x\]' "$MASTER_PLAN" 2>/dev/null) || true
  active_count=$(grep -cE '^\s*-\s*\[~\]' "$MASTER_PLAN" 2>/dev/null) || true
  pending_count=$(grep -cE '^\s*-\s*\[ \]' "$MASTER_PLAN" 2>/dev/null) || true
  if [ "$done_count" -gt 0 ] || [ "$active_count" -gt 0 ]; then
    exit 0
  fi
  if [ "$pending_count" -eq 0 ]; then
    exit 0
  fi
  FILE_PATH="$MASTER_PLAN"
else
  exit 0
fi

# --- Fresh plan detected: all steps are [ ] ---

# Write marker to per-plan directory (not global)
MARKER_FILE="$PLAN_DIR/.handoff-pending"

# Don't re-fire if handoff is already pending (prevents re-injection after Orbit approval)
if [ -f "$MARKER_FILE" ]; then
  exit 0
fi

# Create the marker in the plan directory
echo "$FILE_PATH" > "$MARKER_FILE"

# Inject directive
plan_dir="$(dirname "$FILE_PATH")"
plan_name="$(basename "$plan_dir")"

export HOOK_PLAN_NAME="$plan_name"
export HOOK_PLAN_PATH="$FILE_PATH"
export HOOK_PENDING_COUNT="$pending_count"
export HOOK_MARKER_FILE="$MARKER_FILE"
export HOOK_PLUGIN_ROOT="$PLUGIN_ROOT"

python3 << 'PYEOF'
import json, os, sys

plan_name = os.environ["HOOK_PLAN_NAME"]
plan_path = os.environ["HOOK_PLAN_PATH"]
pending = os.environ["HOOK_PENDING_COUNT"]
marker = os.environ["HOOK_MARKER_FILE"]
plugin_root = os.environ["HOOK_PLUGIN_ROOT"]

output = {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            f"PLAN REVIEW REQUIRED — Fresh plan '{plan_name}' detected "
            f"({pending} steps, all pending).\n\n"
            "STOP. Do NOT start editing code files. Present the plan to the "
            "user for review via Orbit MCP, then do the plan mode handoff.\n\n"
            "## Step A: Discover Orbit tools\n\n"
            "Use ToolSearch to load the orbit_await_review tool:\n"
            "  ToolSearch query: \"+orbit await_review\"\n\n"
            "## Step B: Submit for review (blocking)\n\n"
            "1. Tell the user: \"The plan is open in VS Code for review. "
            "Add inline comments on any section, then click Approve or "
            "Request Changes.\"\n"
            f"2. Call `orbit_await_review` with sourcePath: `{plan_path}`\n"
            "   This generates the artifact, opens it in VS Code, and BLOCKS "
            "until the user clicks Approve or Request Changes. Do NOT call "
            "orbit_generate_resolved separately — orbit_await_review does it.\n\n"
            "## Step C: Handle the response\n\n"
            "orbit_await_review returns a JSON with `status` and `threads`.\n\n"
            "- **If status is `approved` with no threads**: Proceed to Step D.\n"
            "- **If status is `approved` with threads**: Read each thread, "
            "reply as agent acknowledging the feedback, resolve threads, "
            "then proceed to Step D.\n"
            "- **If status is `changes_requested`**: Read all threads. Update "
            "masterPlan.md to address the feedback. Reply to each thread "
            "explaining what you changed. Resolve threads. Then call "
            f"`orbit_await_review` again on `{plan_path}` for re-review. "
            "Loop back to handle the new response.\n"
            "- **If status is `timeout`**: Tell the user the review timed out "
            "and ask them to review when ready.\n\n"
            "## Step D: Plan mode handoff (post-approval)\n\n"
            "The pending-review marker is cleared only when "
            "orbit_await_review returns approved. EnterPlanMode happens "
            "after approval; it does not clear a pending review marker.\n\n"
            "3. Call `EnterPlanMode` — do NOT output any text in the same "
            "response. Call the tool and NOTHING ELSE.\n"
            "4. After EnterPlanMode succeeds, a system message tells you the "
            "**scratch pad file path** (it will be under `~/.claude/plans/`). "
            "Write to THAT file — NOT to masterPlan.md or plan.json. Use "
            "this exact format:\n\n"
            "   # Plan: <title>\n"
            "   Path: <absolute path to plan.json>\n"
            "   Steps: <N> total\n"
            "   Context: <one-liner from plan.json.context>\n\n"
            "   ## FIRST ACTION — Reload behavioral rules\n\n"
            "   Context was cleared by plan mode handoff. Skill rules are\n"
            "   NOT in context. Read these 3 files IMMEDIATELY before any\n"
            "   other work:\n"
            f"   1. {plugin_root}/skills/look-before-you-leap/SKILL.md\n"
            f"   2. {plugin_root}/skills/engineering-discipline/SKILL.md\n"
            f"   3. {plugin_root}/skills/persistent-plans/SKILL.md\n\n"
            "   ## Critical rules (apply before skills are loaded)\n\n"
            "   - NEVER use mcp__codex__codex or mcp__codex__codex-reply.\n"
            "     All Codex interactions go through codex exec via Bash.\n"
            "   - For Codex-owned steps, invoke:\n"
            "     Skill(skill: \"look-before-you-leap:codex-dispatch\")\n\n"
            "   Read plan.json at the path above to begin execution.\n"
            "   Respect step ownership exactly.\n"
            "   Do NOT implement Codex-owned steps yourself.\n"
            "   Do NOT mark any step done before independent verification passes.\n\n"
            "   Do NOT include step descriptions, acceptance criteria, file "
            "lists, Codex consensus results, exploration findings, or "
            "transcript references. All of that lives on disk. The scratch "
            "pad is a pointer, not a copy.\n"
            "5. Call `ExitPlanMode` — again, do NOT output text in the same "
            "response. Just call the tool.\n\n"
            "This gives the user the 'autoaccept edits and clear context?' "
            "prompt. If they accept, context clears and execution starts "
            "fresh.\n\n"
            "IMPORTANT: Do not output explanatory text alongside EnterPlanMode "
            "or ExitPlanMode calls. Extra text can interfere with the plan "
            "mode transition and cause the scratch pad to appear as a stashed "
            "message instead of the plan mode UI.\n\n"
            "Code edits are BLOCKED until this handoff is complete (or "
            "bypassed).\n"
            "To bypass, ask the user to run exactly /bypass."
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
