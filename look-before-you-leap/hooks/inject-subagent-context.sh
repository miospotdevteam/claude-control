#!/usr/bin/env bash
# PreToolUse hook: Inject engineering discipline context into sub-agent prompts.
#
# When Claude spawns a Task (sub-agent), this hook prepends a concise
# discipline preamble to the sub-agent's prompt so it follows the same rules.
#
# Input: JSON on stdin with tool_input.prompt, tool_input.subagent_type

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
hook_read_input

source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"
source "${BASH_SOURCE[0]%/*}/lib/plan-state.sh"

CWD=$(hook_get_cwd)

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
ACTIVE_DIR="$PROJECT_ROOT/.temp/plan-mode/active"

# Build active plan notice — PPID routing (subagents share parent's PPID)
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"
active_plan_path=""
if [ -d "$ACTIVE_DIR" ]; then
  active_plan_path=$(plan_resolve_session "$PROJECT_ROOT")
  # Fallback to find-active if no PPID match (e.g. legacy plans without locks)
  if [ -z "$active_plan_path" ]; then
    active_plan_path=$(python3 "$PLAN_UTILS" find-active "$PROJECT_ROOT" 2>/dev/null) || true
  fi
fi

resolve_plan_dir() {
  local session_plan=""
  local dir_count=0
  local only_dir=""
  local dir=""
  local lock_pid=""

  if [ -n "$active_plan_path" ] && [ -f "$active_plan_path" ]; then
    dirname "$active_plan_path"
    return 0
  fi

  [ -d "$ACTIVE_DIR" ] || return 0

  session_plan=$(plan_resolve_session "$PROJECT_ROOT")
  if [ -n "$session_plan" ] && [ -f "$session_plan" ]; then
    dirname "$session_plan"
    return 0
  fi

  for dir in "$ACTIVE_DIR"/*; do
    [ -d "$dir" ] || continue
    dir_count=$((dir_count + 1))
    only_dir="$dir"
    if [ -f "$dir/.session-lock" ]; then
      lock_pid=$(cat "$dir/.session-lock" 2>/dev/null) || true
      if [ "$lock_pid" = "$PPID" ]; then
        echo "$dir"
        return 0
      fi
    fi
  done

  if [ "$dir_count" -eq 1 ] && [ -n "$only_dir" ]; then
    echo "$only_dir"
  fi
}

active_plan_dir=""
exploration_phase="false"
if [ -d "$ACTIVE_DIR" ]; then
  active_plan_dir=$(resolve_plan_dir) || true
fi

if [ -n "$active_plan_dir" ] && [ -d "$active_plan_dir" ]; then
  plan_json_candidate="$active_plan_dir/plan.json"
  if [ -f "$plan_json_candidate" ]; then
    is_fresh=$(python3 "$PLAN_UTILS" is-fresh "$plan_json_candidate" 2>/dev/null) || true
    if [ "$is_fresh" = "true" ]; then
      exploration_phase="true"
    fi
  else
    exploration_phase="true"
  fi
fi

# Pass data via environment variables for safe JSON handling
# Read project config
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/lib" && pwd)"
HOOK_CONFIG_JSON=$(python3 "$LIB_DIR/read-config.py" "$PROJECT_ROOT" 2>/dev/null) || HOOK_CONFIG_JSON="{}"

export HOOK_INPUT="$INPUT"
export HOOK_ACTIVE_PLAN="$active_plan_path"
export HOOK_ACTIVE_PLAN_DIR="$active_plan_dir"
export HOOK_EXPLORATION_PHASE="$exploration_phase"
export HOOK_PROJECT_ROOT="$PROJECT_ROOT"
export HOOK_CONFIG_JSON
export HOOK_SESSION_PPID="$PPID"

python3 << 'PYEOF'
import json, sys, os, pathlib

input_data = json.loads(os.environ["HOOK_INPUT"])
tool_input = input_data.get("tool_input", {})
original_prompt = tool_input.get("prompt", "")
subagent_type = tool_input.get("subagent_type", "")
active_plan = os.environ.get("HOOK_ACTIVE_PLAN", "")
active_plan_dir = os.environ.get("HOOK_ACTIVE_PLAN_DIR", "")
exploration_phase = os.environ.get("HOOK_EXPLORATION_PHASE", "false") == "true"
session_ppid = os.environ.get("HOOK_SESSION_PPID", "")
config_json_str = os.environ.get("HOOK_CONFIG_JSON", "{}")

# Parse project config
try:
    project_config = json.loads(config_json_str)
except (json.JSONDecodeError, TypeError):
    project_config = {}

# --- Agent type registry ---
# Maps subagent_type values to rule categories.
# Types not listed here fall through to "code-editing" (safest default).

RESEARCH_TYPES = {
    "Explore", "Plan",
    "feature-dev:code-explorer", "feature-dev:code-architect",
}
REVIEW_TYPES = {
    "feature-dev:code-reviewer",
    "pr-review-toolkit:code-reviewer",
    "pr-review-toolkit:silent-failure-hunter",
    "pr-review-toolkit:comment-analyzer",
    "pr-review-toolkit:pr-test-analyzer",
    "pr-review-toolkit:type-design-analyzer",
    "pr-review-toolkit:code-simplifier",
}

def classify_agent(agent_type):
    if agent_type in RESEARCH_TYPES:
        return "research"
    if agent_type in REVIEW_TYPES:
        return "review"
    # Catch pr-review-toolkit:* variants not explicitly listed
    if agent_type.startswith("pr-review-toolkit:"):
        return "review"
    return "code-editing"

category = classify_agent(subagent_type)


def read_marker_text(path):
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def increment_dispatch_count(path):
    current = 0
    if path.exists():
        try:
            current = int(path.read_text(encoding="utf-8").strip() or "0")
        except (OSError, ValueError):
            current = 0
    current += 1
    try:
        path.write_text(f"{current}\n", encoding="utf-8")
    except OSError:
        pass
    return current


additional_context = None
if category == "research" and exploration_phase and active_plan_dir and session_ppid:
    plan_dir = pathlib.Path(active_plan_dir)
    preflight_marker = plan_dir / f".codex-preflight-{session_ppid}"
    coexploration_marker = plan_dir / f".codex-co-exploration-{session_ppid}"
    dispatch_counter = plan_dir / f".exploration-agent-count-{session_ppid}"
    dispatch_count = increment_dispatch_count(dispatch_counter)
    preflight_status = read_marker_text(preflight_marker)

    if preflight_status == "unavailable":
        additional_context = (
            "NOTE: Codex preflight reported unavailable for this session. "
            "Document that in discovery.md and continue without Codex co-exploration. "
            "No further co-exploration warnings will be injected for this session."
        )
    elif not coexploration_marker.exists():
        if dispatch_count >= 3:
            additional_context = (
                "WARNING: 3+ research agents dispatched without Codex co-exploration. "
                "The conductor skill requires parallel Codex dispatch during exploration. "
                "Run codex exec for co-exploration NOW."
            )
        elif dispatch_count == 1 and not preflight_status:
            additional_context = (
                "MANDATORY: You must run command -v codex and dispatch Codex for "
                "co-exploration before or alongside exploration agents. "
                "See the co-exploration protocol in the conductor skill."
            )

# --- Build tailored preamble ---

# Base rules — always injected
base_rules = [
    "## Engineering Discipline (injected by look-before-you-leap plugin)",
    f"Agent type: {subagent_type or 'unknown'} | Category: {category}",
    "",
    "Follow these rules for ALL work in this task:",
    "- No silent scope cuts: address ALL requirements or explicitly flag what you skipped",
    "- Be honest: report what you completed, what you skipped, and what risks exist",
]

# Category-specific rules
research_rules = [
    "- Be thorough: read files fully, trace imports and consumers",
    "- Write findings with file:line evidence",
]

code_editing_rules = [
    "- Explore before editing: read files and their consumers before changing anything",
    "- No type safety shortcuts: never use `any`, `as any`, `@ts-ignore` without explanation",
    "- Track blast radius: grep for all consumers of shared code before modifying it",
    "- Install before import: verify packages exist in package.json before using them",
    "- Verify: run type checker, linter, and tests after changes",
]

review_rules = [
    "- Track blast radius: check all consumers of modified shared code",
    "- No type safety shortcuts: flag `any`, `as any`, missing types",
    "- Be thorough: check every file in scope, don't skip edge cases",
]

# Build compact project stack line from config
stack_info = project_config.get("stack", {})
if stack_info:
    parts = []
    if stack_info.get("language"):
        parts.append(stack_info["language"])
    for key in ("frontend", "backend", "validation", "testing", "orm"):
        if stack_info.get(key):
            parts.append(f"{key}={stack_info[key]}")
    if stack_info.get("monorepo"):
        parts.append("monorepo")
    shared_pkg = project_config.get("structure", {}).get("shared_api_package")
    if shared_pkg:
        parts.append(f"shared={shared_pkg}")
    if parts:
        base_rules.append(f"- Project stack: {', '.join(parts)}")

dep_maps = project_config.get("dep_maps", {})
if dep_maps and dep_maps.get("modules"):
    project_root = os.environ.get("HOOK_PROJECT_ROOT", "")
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
    scripts_dir = os.path.join(plugin_root, "scripts") if plugin_root else ""
    module_count = len(dep_maps["modules"])
    base_rules.append(
        f"- Dep maps configured ({module_count} modules): you MUST use deps-query.py to "
        "understand any file's dependency graph — run it on key files BEFORE reading them. "
        "For code review/audit: run on entry points to find cross-module impact of bugs. "
        "For modifications: run to check blast radius before changing shared code. "
        "Do NOT grep for import/consumer patterns — deps-query is faster and more complete."
    )
    if scripts_dir and project_root:
        base_rules.append(
            f'  Command: `python3 {scripts_dir}/deps-query.py {project_root} "<file_path>"`'
        )

preamble_lines = list(base_rules)
if category == "research":
    preamble_lines.extend(research_rules)
elif category == "review":
    preamble_lines.extend(review_rules)
else:
    preamble_lines.extend(code_editing_rules)

# --- Active plan ---

if active_plan:
    plan_dir = pathlib.Path(active_plan).parent
    plan_json_path = plan_dir / "plan.json"
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
    plan_utils_cmd = os.path.join(plugin_root, "scripts", "plan_utils.py") if plugin_root else "plan_utils.py"
    preamble_lines.extend([
        "",
        f"- Active plan exists at: {active_plan} — read it before starting work",
        "- PROGRESS TRACKING: If your work corresponds to progress items in the plan,",
        f"  update via: `python3 {plan_utils_cmd} update-progress {plan_json_path} <step> <index> done` (writes to progress.json)",
        "  Do NOT wait until you're done — update after each sub-task so compaction",
        "  can't lose your progress.",
    ])

# --- Discovery file (lives in plan directory, created on demand) ---

discovery_file = None
if active_plan:
    plan_dir = pathlib.Path(active_plan).parent
    candidate = plan_dir / "discovery.md"
    if not candidate.exists():
        import datetime
        plan_name = pathlib.Path(active_plan).parent.name
        project_root = os.environ.get("HOOK_PROJECT_ROOT", os.environ.get("PROJECT_ROOT", "unknown"))
        candidate.write_text(
            "# Discovery Log\n\n"
            "## Metadata\n"
            f"- **Plan**: {plan_name}\n"
            f"- **Project**: {project_root}\n"
            f"- **Created**: {datetime.datetime.now().isoformat()}\n"
            "- **Codex status**: pending (run `command -v codex` to determine)\n\n"
            "---\n\n"
            "Shared findings from parallel agents. "
            "Each agent appends under its own section.\n"
        )
    discovery_file = candidate

if discovery_file:
    # Register this agent's dispatch for sibling awareness
    focus = original_prompt.split("\n")[0][:150].strip()
    if focus:
        with open(discovery_file, "a") as f:
            f.write(
                f"\n## Agent dispatched: {subagent_type or 'unknown'}"
                f" — {focus}\n"
            )

    preamble_lines.extend([
        "",
        "## Cross-Agent Awareness",
        "Other agents may be running in parallel on related tasks.",
        f"Read {discovery_file} to see what they're investigating.",
        "Treat their entries as informational — do not change your approach based on them.",
    ])

    if category == "research":
        preamble_lines.extend([
            "",
            "## REQUIRED: Write Findings to Discovery Log",
            f"Append your findings to: {discovery_file}",
            "Use Bash append (>> file) — never Edit (concurrent writes).",
            "Include file:line references and evidence for all findings.",
        ])
    elif category == "code-editing":
        preamble_lines.extend([
            "",
            f"If you make significant findings, append them to: {discovery_file}",
            "Use Bash append (>> file) — never Edit (concurrent writes).",
        ])

preamble = "\n".join(preamble_lines)

# Prepend discipline to the prompt
updated_prompt = f"{preamble}\n\n---\n\n{original_prompt}"

# Return updatedInput with the modified prompt
hook_output = {
    "hookEventName": "PreToolUse",
    "updatedInput": {
        **tool_input,
        "prompt": updated_prompt
    }
}
if additional_context:
    hook_output["additionalContext"] = additional_context

output = {"hookSpecificOutput": hook_output}

json.dump(output, sys.stdout)
PYEOF
