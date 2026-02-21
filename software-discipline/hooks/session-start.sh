#!/usr/bin/env bash
# SessionStart hook for software-discipline plugin.
#
# On every session start (including after compaction/resume), this hook:
# 1. Reads all three SKILL.md files (conductor + engineering-discipline + persistent-plans)
# 2. Checks for active plans in .temp/plan-mode/
# 3. Discovers other installed Claude Code skills
#
# All pieces are combined into a single additionalContext string.
# JSON output is handled by python3 for bulletproof encoding.

set -euo pipefail

# Determine plugin root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SKILL_FILE="${PLUGIN_ROOT}/skills/software-discipline/SKILL.md"
ENGINEERING_SKILL_FILE="${PLUGIN_ROOT}/skills/engineering-discipline/SKILL.md"
PLANS_SKILL_FILE="${PLUGIN_ROOT}/skills/persistent-plans/SKILL.md"

# --- Function: Find project root ---
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "$PWD"
}

PROJECT_ROOT="$(find_project_root)"
PLAN_DIR="$PROJECT_ROOT/.temp/plan-mode"

# --- Section 1.5: Project config detection ---
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="$PROJECT_ROOT/.claude/software-discipline.local.md"

CONFIG_JUST_CREATED=false
if [ ! -f "$CONFIG_FILE" ] && [ -d "$PROJECT_ROOT" ]; then
  # Auto-detect stack on first session
  config_content=$(python3 "$LIB_DIR/detect-stack.py" "$PROJECT_ROOT" 2>/dev/null) || true
  if [ -n "$config_content" ]; then
    mkdir -p "$PROJECT_ROOT/.claude"
    printf '%s' "$config_content" > "$CONFIG_FILE"
    CONFIG_JUST_CREATED=true
  fi
fi

# Detect whether project has a CLAUDE.md
HAS_CLAUDE_MD=false
if [ -f "$PROJECT_ROOT/CLAUDE.md" ] || [ -f "$PROJECT_ROOT/.claude/CLAUDE.md" ]; then
  HAS_CLAUDE_MD=true
fi

# Read config as JSON (empty object if missing/broken)
PROJECT_CONFIG_JSON=$(python3 "$LIB_DIR/read-config.py" "$PROJECT_ROOT" 2>/dev/null) || PROJECT_CONFIG_JSON="{}"

# --- Section 2: Active plan detection ---
active_plan_summary=""
ACTIVE_DIR="$PLAN_DIR/active"

if [ -d "$ACTIVE_DIR" ]; then
  latest=""

  # macOS stat
  latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | awk '{print $2}')

  # Linux fallback
  if [ -z "$latest" ]; then
    latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-) || true
  fi

  if [ -n "$latest" ] && [ -f "$latest" ]; then
    plan_name="$(basename "$(dirname "$latest")")"

    # Check if the plan has any non-complete steps
    # Match both "[ ] pending" (template format) and bare "[ ]" (common usage)
    has_pending=$(grep -cE '\[ \]|\[~\]|\[!\]' "$latest" 2>/dev/null) || true

    if [ "$has_pending" -gt 0 ]; then
      done_count=$(grep -cE '\[x\]' "$latest" 2>/dev/null) || true
      active_count=$(grep -cE '\[~\]' "$latest" 2>/dev/null) || true
      pending_count=$(grep -cE '\[ \]' "$latest" 2>/dev/null) || true
      blocked_count=$(grep -cE '\[!\]' "$latest" 2>/dev/null) || true

      # Find the next step to work on
      next_step=""
      if [ "$active_count" -gt 0 ]; then
        next_step=$(grep -B5 -E '\[~\]' "$latest" | grep -E '^### Step' | head -1 | sed 's/^### //' || true)
        [ -n "$next_step" ] && next_step="IN PROGRESS: $next_step"
      elif [ "$pending_count" -gt 0 ]; then
        next_step=$(grep -B5 -E '\[ \]' "$latest" | grep -E '^### Step' | head -1 | sed 's/^### //' || true)
        [ -n "$next_step" ] && next_step="NEXT: $next_step"
      fi

      # Check for active sub-plans
      active_subplan=""
      plan_dir="$(dirname "$latest")"
      for sub in "$plan_dir"/sub-plan-*.md; do
        [ -f "$sub" ] || continue
        if grep -qE '\[~\]|\[ \]' "$sub" 2>/dev/null; then
          subname="$(basename "$sub")"
          active_subplan="Active sub-plan: $subname"
          break
        fi
      done

      # --- Session lock: prevent multiple instances from claiming the same plan ---
      lock_file="$plan_dir/.session-lock"
      own_plan=true

      if [ -f "$lock_file" ]; then
        lock_pid=$(cat "$lock_file" 2>/dev/null) || true
        if [ -n "$lock_pid" ] && [ "$lock_pid" != "$PPID" ]; then
          # Lock belongs to a different process — check if it's still alive
          if kill -0 "$lock_pid" 2>/dev/null; then
            own_plan=false
          fi
          # If the process is dead, the lock is stale — we can reclaim
        fi
      fi

      if $own_plan; then
        # Claim (or re-claim) the plan for this session
        echo "$PPID" > "$lock_file"

        active_plan_summary="ACTIVE PLAN DETECTED"
        active_plan_summary+=$'\n'"Plan: $plan_name"
        active_plan_summary+=$'\n'"File: $latest"
        active_plan_summary+=$'\n'"Status: $done_count done | $active_count active | $pending_count pending | $blocked_count blocked"
        [ -n "$next_step" ] && active_plan_summary+=$'\n'"$next_step"
        [ -n "$active_subplan" ] && active_plan_summary+=$'\n'"$active_subplan"
        active_plan_summary+=$'\n'$'\n'"IMPORTANT: Read the masterPlan.md file at the path above BEFORE doing any work. The plan is your source of truth. Follow the resumption protocol from the software-discipline skill."
      else
        active_plan_summary="NOTE: Active plan exists but is owned by another Claude session"
        active_plan_summary+=$'\n'"Plan: $plan_name"
        active_plan_summary+=$'\n'"File: $latest"
        active_plan_summary+=$'\n'"Status: $done_count done | $active_count active | $pending_count pending | $blocked_count blocked"
        [ -n "$next_step" ] && active_plan_summary+=$'\n'"$next_step"
        [ -n "$active_subplan" ] && active_plan_summary+=$'\n'"$active_subplan"
        active_plan_summary+=$'\n'$'\n'"This plan is being worked on by another Claude session (PID: $lock_pid). Do NOT auto-resume it. Start fresh — only resume this plan if the user explicitly asks you to."
      fi
    fi
  fi
fi

# --- Section 3: Skill discovery ---
# Scan ~/.claude/plugins/ for other installed plugins, extract name + description
skill_inventory=""
PLUGINS_DIR="$HOME/.claude/plugins"

if [ -d "$PLUGINS_DIR" ]; then
  for plugin_dir in "$PLUGINS_DIR"/*/; do
    [ -d "$plugin_dir" ] || continue

    # Skip ourselves
    plugin_name="$(basename "$plugin_dir")"
    if [ "$plugin_name" = "software-discipline" ]; then
      continue
    fi

    # Check for plugin.json
    manifest="$plugin_dir/.claude-plugin/plugin.json"
    [ -f "$manifest" ] || continue

    # Extract name from plugin.json and description from SKILL.md frontmatter
    name=""
    desc=""

    # Get name from manifest
    name=$(python3 -c "import json; print(json.load(open('$manifest')).get('name',''))" 2>/dev/null) || true

    # Try to get description from first SKILL.md found
    for skill_file in "$plugin_dir"/skills/*/SKILL.md; do
      [ -f "$skill_file" ] || continue
      desc=$(python3 -c "
import sys
with open('$skill_file') as f:
    content = f.read()
if content.startswith('---'):
    end = content.index('---', 3)
    front = content[3:end]
    for line in front.split('\n'):
        if line.strip().startswith('description:'):
            d = line.split(':', 1)[1].strip().strip('>')
            if d:
                print(d[:120])
                break
" 2>/dev/null) || true
      break
    done

    if [ -n "$name" ]; then
      if [ -n "$desc" ]; then
        skill_inventory+="- $name: $desc"$'\n'
      else
        skill_inventory+="- $name"$'\n'
      fi
    fi
  done
fi

# --- Combine and output via python3 ---
export SKILL_FILE_PATH="$SKILL_FILE"
export ENGINEERING_SKILL_FILE_PATH="$ENGINEERING_SKILL_FILE"
export PLANS_SKILL_FILE_PATH="$PLANS_SKILL_FILE"
export ACTIVE_PLAN_SUMMARY="$active_plan_summary"
export SKILL_INVENTORY="$skill_inventory"
export PROJECT_CONFIG_JSON
export CONFIG_JUST_CREATED
export HAS_CLAUDE_MD
export PLUGIN_ROOT

python3 << 'PYEOF'
import json
import sys
import os

skill_file = os.environ.get("SKILL_FILE_PATH", "")
engineering_file = os.environ.get("ENGINEERING_SKILL_FILE_PATH", "")
plans_file = os.environ.get("PLANS_SKILL_FILE_PATH", "")
active_summary = os.environ.get("ACTIVE_PLAN_SUMMARY", "")
skill_inventory = os.environ.get("SKILL_INVENTORY", "")
config_json_str = os.environ.get("PROJECT_CONFIG_JSON", "{}")
config_just_created = os.environ.get("CONFIG_JUST_CREATED", "false") == "true"
has_claude_md = os.environ.get("HAS_CLAUDE_MD", "false") == "true"
plugin_root = os.environ.get("PLUGIN_ROOT", "")

def read_file(path):
    try:
        with open(path, "r") as f:
            return f.read()
    except Exception as e:
        return f"Error reading {path}: {e}"

skill_content = read_file(skill_file)
engineering_content = read_file(engineering_file)
plans_content = read_file(plans_file)

# Build project profile from config
project_profile = ""
try:
    config = json.loads(config_json_str)
    stack = config.get("stack", {})
    structure = config.get("structure", {})
    disciplines = config.get("disciplines", {})

    if stack:
        profile_parts = []
        if stack.get("language"):
            profile_parts.append(f"Language: {stack['language']}")
        if stack.get("package_manager"):
            profile_parts.append(f"Package manager: {stack['package_manager']}")
        if stack.get("monorepo"):
            profile_parts.append("Monorepo: yes")
        frameworks = []
        for key in ("frontend", "backend", "validation", "styling", "testing", "orm"):
            if stack.get(key):
                frameworks.append(f"{key}={stack[key]}")
        if frameworks:
            profile_parts.append(f"Stack: {', '.join(frameworks)}")
        if structure.get("shared_api_package"):
            profile_parts.append(f"Shared API package: {structure['shared_api_package']}")
        active_disciplines = [k for k, v in disciplines.items() if v]
        if active_disciplines:
            profile_parts.append(f"Active disciplines: {', '.join(active_disciplines)}")
        if profile_parts:
            project_profile = "**Project Profile** (auto-detected, edit .claude/software-discipline.local.md to customize):\n" + "\n".join(f"- {p}" for p in profile_parts)
except (json.JSONDecodeError, TypeError):
    pass

# Build first-run onboarding block
onboarding_block = ""
if config_just_created:
    # Read recommended plugins reference
    rec_plugins_path = os.path.join(plugin_root, "skills", "software-discipline",
                                     "references", "recommended-plugins.md")
    rec_plugins_content = ""
    try:
        with open(rec_plugins_path, "r") as f:
            rec_plugins_content = f.read()
    except Exception:
        pass

    # Read CLAUDE.md snippet template
    claude_md_snippet_path = os.path.join(plugin_root, "skills", "software-discipline",
                                           "references", "claude-md-snippet.md")
    claude_md_snippet = ""
    try:
        with open(claude_md_snippet_path, "r") as f:
            claude_md_snippet = f.read()
    except Exception:
        pass

    # Summarize detected stack for the greeting
    stack_summary = ""
    try:
        config = json.loads(config_json_str)
        s = config.get("stack", {})
        bits = []
        if s.get("language"): bits.append(s["language"])
        if s.get("frontend"): bits.append(s["frontend"])
        if s.get("backend"): bits.append(s["backend"])
        if s.get("package_manager"): bits.append(s["package_manager"])
        if s.get("monorepo"): bits.append("monorepo")
        if bits:
            stack_summary = ", ".join(bits)
    except (json.JSONDecodeError, TypeError):
        pass

    lines = []
    lines.append("## FIRST-RUN ONBOARDING — Act on this NOW")
    lines.append("")
    lines.append("The software-discipline plugin just ran for the **first time** in this project.")
    lines.append(f"A config file was auto-created at `.claude/software-discipline.local.md`"
                 + (f" with detected stack: **{stack_summary}**." if stack_summary else "."))
    lines.append("")
    lines.append("**Your immediate task** (before doing anything else the user asks):")
    lines.append("")
    lines.append("1. **Greet the user** and tell them software-discipline detected their project stack.")
    lines.append("   Show what was detected (from the Project Profile above).")
    lines.append("")
    lines.append("2. **Offer to enrich the config** by exploring the codebase deeper.")
    lines.append("   If they say yes, read key files (package.json, tsconfig, project structure)")
    lines.append("   and update `.claude/software-discipline.local.md` with richer content:")
    lines.append("   verification commands, gotchas, blast radius areas, conventions.")
    lines.append("   Use brainstorming style — one question at a time, multiple choice where possible.")
    lines.append("")

    if not has_claude_md:
        lines.append("3. **Offer to create a CLAUDE.md** — this project has none.")
        lines.append("   If they agree, create `.claude/CLAUDE.md` using this template as a starting point:")
        lines.append("")
        if claude_md_snippet:
            # Extract just the markdown code block content from the snippet
            lines.append("   ```")
            for snippet_line in claude_md_snippet.split("\n"):
                lines.append(f"   {snippet_line}")
            lines.append("   ```")
        lines.append("   Tailor it to the detected stack. Ask the user if they want to add")
        lines.append("   project-specific conventions, coding style preferences, or other notes.")
        lines.append("")

    lines.append(f"{'4' if not has_claude_md else '3'}. **Suggest useful plugins** to install.")
    lines.append("   Check which official Anthropic plugins would benefit this project.")
    lines.append("   For each suggestion, ask whether to install at user, project, or global scope")
    lines.append("   (explain: user = all your projects, project = just this repo, global = all users on machine).")
    lines.append("   Install using: `claude plugin install <name>@claude-plugins-official --scope <scope>`")
    lines.append("")

    if rec_plugins_content:
        lines.append("### Recommended plugins reference")
        lines.append("")
        lines.append(rec_plugins_content)
        lines.append("")

    lines.append("**Important**: Use a conversational, brainstorming style. One question at a time.")
    lines.append("Don't dump everything at once. Guide the user through setup step by step.")
    lines.append("If the user declines any step, skip it gracefully and move to the next.")
    lines.append("Once onboarding is complete (or declined), proceed normally with whatever the user asked.")

    onboarding_block = "\n".join(lines)

# Build context message
parts = [
    "**Below is the software-discipline skill — follow it for all coding tasks:**",
    "",
    skill_content,
    "",
    "---",
    "",
    "**Engineering Discipline (companion skill — follow for all code changes):**",
    "",
    engineering_content,
    "",
    "---",
    "",
    "**Persistent Plans (companion skill — follow for all task planning):**",
    "",
    plans_content,
]

if project_profile:
    parts.extend(["", "---", "", project_profile])

if onboarding_block:
    parts.extend(["", "---", "", onboarding_block])

if active_summary:
    parts.extend(["", "---", "", active_summary])

if skill_inventory:
    parts.extend([
        "", "---", "",
        "**Installed skills (available for routing):**",
        "",
        skill_inventory
    ])

context = "\n".join(parts)

output = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": context
    }
}

json.dump(output, sys.stdout)
PYEOF
