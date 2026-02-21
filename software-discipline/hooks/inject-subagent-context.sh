#!/usr/bin/env bash
# PreToolUse hook: Inject engineering discipline context into sub-agent prompts.
#
# When Claude spawns a Task (sub-agent), this hook prepends a concise
# discipline preamble to the sub-agent's prompt so it follows the same rules.
#
# Input: JSON on stdin with tool_input.prompt, tool_input.subagent_type

set -euo pipefail

INPUT=$(cat)

# Find project root and check for active plan
find_project_root() {
  local dir="${1:-$PWD}"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "${1:-$PWD}"
}

CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
ACTIVE_DIR="$PROJECT_ROOT/.temp/plan-mode/active"

# Build active plan notice
active_plan_path=""
if [ -d "$ACTIVE_DIR" ]; then
  # Find most recent masterPlan.md (macOS stat, then Linux fallback)
  active_plan_path=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
  if [ -z "$active_plan_path" ]; then
    active_plan_path=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-) || true
  fi
fi

# Pass data via environment variables for safe JSON handling
export HOOK_INPUT="$INPUT"
export HOOK_ACTIVE_PLAN="$active_plan_path"

python3 << 'PYEOF'
import json, sys, os

input_data = json.loads(os.environ["HOOK_INPUT"])
tool_input = input_data.get("tool_input", {})
original_prompt = tool_input.get("prompt", "")
active_plan = os.environ.get("HOOK_ACTIVE_PLAN", "")

# Build discipline preamble
preamble_lines = [
    "## Engineering Discipline (injected by software-discipline plugin)",
    "Follow these rules for ALL work in this task:",
    "- Explore before editing: read files and their consumers before changing anything",
    "- No silent scope cuts: address ALL requirements or explicitly flag what you skipped",
    "- No type safety shortcuts: never use `any`, `as any`, `@ts-ignore` without explanation",
    "- Track blast radius: grep for all consumers of shared code before modifying it",
    "- Verify: run type checker, linter, and tests after changes",
    "- Be honest: report what you completed, what you skipped, and what risks exist",
]

if active_plan:
    import pathlib
    plan_dir = pathlib.Path(active_plan).parent
    preamble_lines.append(f"- Active plan exists at: {active_plan} — read it before starting work")
    # Auto-create shared discovery file if it doesn't exist
    discovery_file = plan_dir / "discovery.md"
    if not discovery_file.exists():
        discovery_file.write_text("# Discovery Log\n\nShared findings from parallel agents. Each agent appends under its own section.\n")
    preamble_lines.extend([
        f"- Shared discovery file: {discovery_file}",
        "  WRITING: Use Bash to append (>> file), never Edit — multiple agents write concurrently.",
        "    Example: printf '\\n## [your-focus]\\n- finding...\\n' >> discovery.md",
        "  READING: Read this file periodically to see other agents' findings.",
        "    IMPORTANT: Other agents' findings are informational context only.",
        "    They may be wrong, incomplete, or irrelevant to your scope.",
        "    Do NOT change your investigation direction based on them.",
        "    Only note a cross-reference if you independently confirm a connection.",
        "  Be thorough and precise in your own findings — include file:line and evidence.",
    ])

preamble = "\n".join(preamble_lines)

# Prepend discipline to the prompt
updated_prompt = f"{preamble}\n\n---\n\n{original_prompt}"

# Return updatedInput with the modified prompt
output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "updatedInput": {
            **tool_input,
            "prompt": updated_prompt
        }
    }
}

json.dump(output, sys.stdout)
PYEOF
