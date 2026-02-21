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
export HOOK_PROJECT_ROOT="$PROJECT_ROOT"

python3 << 'PYEOF'
import json, sys, os, pathlib, shutil

input_data = json.loads(os.environ["HOOK_INPUT"])
tool_input = input_data.get("tool_input", {})
original_prompt = tool_input.get("prompt", "")
subagent_type = tool_input.get("subagent_type", "")
active_plan = os.environ.get("HOOK_ACTIVE_PLAN", "")

# --- Agent type registry ---
# Maps subagent_type values to rule categories.
# Types not listed here fall through to "code-editing" (safest default).

RESEARCH_TYPES = {
    "Explore", "Plan",
    "feature-dev:code-explorer", "feature-dev:code-architect",
}
REVIEW_TYPES = {
    "feature-dev:code-reviewer",
    "superpowers:code-reviewer",
    "pr-review-toolkit:code-reviewer",
    "pr-review-toolkit:silent-failure-hunter",
    "pr-review-toolkit:comment-analyzer",
    "pr-review-toolkit:pr-test-analyzer",
    "pr-review-toolkit:type-design-analyzer",
    "pr-review-toolkit:code-simplifier",
    "code-simplifier:code-simplifier",
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

# --- Build tailored preamble ---

# Base rules — always injected
base_rules = [
    "## Engineering Discipline (injected by software-discipline plugin)",
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
    preamble_lines.extend([
        "",
        f"- Active plan exists at: {active_plan} — read it before starting work",
        "- PROGRESS TRACKING: If your work corresponds to Progress items in the plan,",
        f"  mark each `- [ ]` item `- [x]` in {active_plan} as you complete it.",
        "  Use Edit tool on the masterPlan.md file. Do NOT wait until you're done —",
        "  update after each sub-task so compaction can't lose your progress.",
    ])

# --- Discovery file (works with or without an active plan) ---

project_root = os.environ.get("HOOK_PROJECT_ROOT", "")
discovery_header = (
    "# Discovery Log\n\n"
    "Shared findings from parallel agents. "
    "Each agent appends under its own section.\n"
)

fallback_dir = pathlib.Path(project_root) / ".temp" / "discovery"
fallback_file = fallback_dir / "discovery.md"

if active_plan:
    # Plan-scoped discovery
    discovery_file = pathlib.Path(active_plan).parent / "discovery.md"

    # Migrate: if a fallback discovery exists from pre-plan agents, adopt it
    if fallback_file.exists() and not discovery_file.exists():
        shutil.move(str(fallback_file), str(discovery_file))
        # Clean up empty fallback dir
        try:
            fallback_dir.rmdir()
        except OSError:
            pass  # dir not empty or already gone
    elif fallback_file.exists() and discovery_file.exists():
        # Both exist — append fallback content into plan-scoped file
        with open(fallback_file) as f:
            fallback_content = f.read()
        with open(discovery_file, "a") as f:
            f.write(f"\n\n# --- Migrated from pre-plan discovery ---\n{fallback_content}")
        fallback_file.unlink()
        try:
            fallback_dir.rmdir()
        except OSError:
            pass
else:
    # Fallback: session-scoped discovery when no plan exists.
    # When a plan is created later, the next agent dispatch migrates this file.
    fallback_dir.mkdir(parents=True, exist_ok=True)
    discovery_file = fallback_file

if not discovery_file.exists():
    discovery_file.write_text(discovery_header)

# Register this agent's dispatch in discovery.md for sibling awareness
focus = original_prompt.split("\n")[0][:150].strip()
if focus:
    with open(discovery_file, "a") as f:
        f.write(
            f"\n## Agent dispatched: {subagent_type or 'unknown'}"
            f" — {focus}\n"
        )

# Cross-agent awareness instructions
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
        f"Before you return your final answer, you MUST append your findings to: {discovery_file}",
        "",
        "Use Bash to append (>> file) — never Edit, because multiple agents write concurrently:",
        f"  printf '\\n## [Your Focus Area]\\n- **finding** `file:line` — description\\n' >> {discovery_file}",
        "",
        "Write ALL key findings — file paths, types found, patterns, counts, anomalies.",
        "Include file:line references and evidence. Be thorough — this file is how parallel",
        "agents share knowledge and how the parent agent gets structured data.",
    ])
elif category == "code-editing":
    preamble_lines.extend([
        "",
        "## Discovery Log",
        f"If you make significant findings during your work, append them to: {discovery_file}",
        "Use Bash to append (>> file) — never Edit, because multiple agents write concurrently.",
    ])
# Review agents: no discovery write requirement (they report via their return value)

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
