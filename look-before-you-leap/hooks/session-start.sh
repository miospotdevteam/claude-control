#!/usr/bin/env bash
# SessionStart hook for look-before-you-leap plugin.
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

SKILL_FILE="${PLUGIN_ROOT}/skills/look-before-you-leap/SKILL.md"
ENGINEERING_SKILL_FILE="${PLUGIN_ROOT}/skills/engineering-discipline/SKILL.md"
PLANS_SKILL_FILE="${PLUGIN_ROOT}/skills/persistent-plans/SKILL.md"

source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

PROJECT_ROOT="$(find_project_root)"
PLAN_DIR="$PROJECT_ROOT/.temp/plan-mode"

# --- Section 1.2: Bootstrap receipt state ---
RECEIPT_UTILS="${PLUGIN_ROOT}/scripts/receipt_utils.py"
python3 "$RECEIPT_UTILS" bootstrap >/dev/null 2>&1 || true

# --- Section 1.3: Install Codex skills ---
INSTALL_CODEX_SKILLS="${PLUGIN_ROOT}/scripts/install-codex-skills.sh"
if [ -f "$INSTALL_CODEX_SKILLS" ]; then
  bash "$INSTALL_CODEX_SKILLS" "$PLUGIN_ROOT" 2>/dev/null || true
fi

# --- Section 1.5: Project config detection ---
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="$PROJECT_ROOT/.claude/look-before-you-leap.local.md"

if [ ! -f "$CONFIG_FILE" ] && [ -d "$PROJECT_ROOT" ]; then
  # Auto-detect stack on first session
  config_content=$(python3 "$LIB_DIR/detect-stack.py" "$PROJECT_ROOT" 2>/dev/null) || true
  if [ -n "$config_content" ]; then
    mkdir -p "$PROJECT_ROOT/.claude"
    printf '%s' "$config_content" > "$CONFIG_FILE"
    # Create marker for UserPromptSubmit onboarding hook
    touch "$PROJECT_ROOT/.claude/.onboarding-pending"
  fi
fi

# Read config as JSON (empty object if missing/broken)
PROJECT_CONFIG_JSON=$(python3 "$LIB_DIR/read-config.py" "$PROJECT_ROOT" 2>/dev/null) || PROJECT_CONFIG_JSON="{}"

# --- Section 1.7: Handoff-pending marker ---
# No longer auto-cleared on session start. The handoff marker persists until
# the user explicitly approves via Orbit (clear-handoff-on-approval.sh mints
# a handoff_approved receipt) or runs /bypass.

# --- Section 1.8: Clean up stale .no-plan-* files (dead PIDs) ---
if [ -d "$PROJECT_ROOT/.temp/plan-mode" ]; then
  for no_plan_file in "$PROJECT_ROOT/.temp/plan-mode"/.no-plan-*; do
    [ -f "$no_plan_file" ] || continue
    stale_pid="${no_plan_file##*.no-plan-}"
    if [ -n "$stale_pid" ] && ! kill -0 "$stale_pid" 2>/dev/null; then
      rm -f "$no_plan_file"
    fi
  done
fi

# --- Section 2: Active plan detection ---
active_plan_summary=""
ACTIVE_DIR="$PLAN_DIR/active"
PLAN_UTILS="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/plan_utils.py"

if [ -d "$ACTIVE_DIR" ]; then
  # PPID-based plan routing: find the plan claimed by this session
  latest_json=$(python3 "$PLAN_UTILS" find-for-session "$PROJECT_ROOT" "$PPID" 2>/dev/null) || true

  # If no plan claimed by this PPID, try to auto-claim an unclaimed (orphaned) plan
  if [ -z "$latest_json" ]; then
    unclaimed_line=$(python3 "$PLAN_UTILS" find-unclaimed "$PROJECT_ROOT" 2>/dev/null | head -1) || true
    if [ -n "$unclaimed_line" ]; then
      unclaimed_path="${unclaimed_line#*	}"
      if [ -n "$unclaimed_path" ] && [ -f "$unclaimed_path" ]; then
        # Auto-claim by writing PPID to .session-lock
        echo "$PPID" > "$(dirname "$unclaimed_path")/.session-lock"
        latest_json="$unclaimed_path"
      fi
    fi
  fi

  if [ -n "$latest_json" ] && [ -f "$latest_json" ]; then
    plan_dir="$(dirname "$latest_json")"
    plan_name="$(basename "$plan_dir")"

    # Read status from plan.json via plan_utils
    export HOOK_PLAN_JSON="$latest_json"
    export HOOK_PLAN_UTILS="$PLAN_UTILS"

    plan_status_info=$(python3 << 'PYEOF'
import json, os, sys

plan_json = os.environ["HOOK_PLAN_JSON"]
plan_utils_path = os.environ["HOOK_PLAN_UTILS"]

sys.path.insert(0, os.path.dirname(plan_utils_path))
import plan_utils

plan = plan_utils.read_plan(plan_json)
counts = plan_utils.count_by_status(plan)

# Find next step
next_step = plan_utils.get_next_step(plan)
next_info = ""
if next_step:
    if next_step["status"] == "in_progress":
        next_info = f"IN PROGRESS: Step {next_step['id']}: {next_step['title']}"
    else:
        next_info = f"NEXT: Step {next_step['id']}: {next_step['title']}"

has_work = counts.get("pending", 0) + counts.get("in_progress", 0) + counts.get("blocked", 0) > 0

print(json.dumps({
    "done": counts.get("done", 0),
    "active": counts.get("in_progress", 0),
    "pending": counts.get("pending", 0),
    "blocked": counts.get("blocked", 0),
    "next_step": next_info,
    "has_work": has_work,
}))
PYEOF
    ) || true

    if [ -n "$plan_status_info" ]; then
      done_count=$(python3 -c "import json; print(json.loads('$plan_status_info').get('done', 0))" 2>/dev/null) || true
      active_count=$(python3 -c "import json; print(json.loads('$plan_status_info').get('active', 0))" 2>/dev/null) || true
      pending_count=$(python3 -c "import json; print(json.loads('$plan_status_info').get('pending', 0))" 2>/dev/null) || true
      blocked_count=$(python3 -c "import json; print(json.loads('$plan_status_info').get('blocked', 0))" 2>/dev/null) || true
      next_step=$(python3 -c "import json; print(json.loads('$plan_status_info').get('next_step', ''))" 2>/dev/null) || true
      has_work=$(python3 -c "import json; print(json.loads('$plan_status_info').get('has_work', False))" 2>/dev/null) || true
    fi

    if [ "$has_work" = "True" ]; then
      # Plan is already claimed by this PPID (either found or just auto-claimed)
      active_plan_summary="ACTIVE PLAN DETECTED"
      active_plan_summary+=$'\n'"Plan: $plan_name"
      active_plan_summary+=$'\n'"File: $latest_json"
      active_plan_summary+=$'\n'"Status: $done_count done | $active_count active | $pending_count pending | $blocked_count blocked"
      [ -n "$next_step" ] && active_plan_summary+=$'\n'"$next_step"
      active_plan_summary+=$'\n'$'\n'"IMPORTANT: Read plan.json (definition) and progress.json (mutable state) at the plan directory BEFORE doing any work. The plan + progress files are your source of truth. Follow the resumption protocol from the look-before-you-leap skill."
    fi

  # No plan found for this session — check if OTHER sessions own plans (informational)
  elif [ -z "$latest_json" ]; then
    other_plan=$(python3 "$PLAN_UTILS" find-active "$PROJECT_ROOT" 2>/dev/null) || true
    if [ -n "$other_plan" ] && [ -f "$other_plan" ]; then
      other_dir="$(dirname "$other_plan")"
      other_name="$(basename "$other_dir")"
      other_lock_pid=$(cat "$other_dir/.session-lock" 2>/dev/null) || true

      export HOOK_PLAN_JSON="$other_plan"
      export HOOK_PLAN_UTILS="$PLAN_UTILS"

      other_status_info=$(python3 << 'PYEOF'
import json, os, sys
plan_json = os.environ["HOOK_PLAN_JSON"]
plan_utils_path = os.environ["HOOK_PLAN_UTILS"]
sys.path.insert(0, os.path.dirname(plan_utils_path))
import plan_utils
plan = plan_utils.read_plan(plan_json)
counts = plan_utils.count_by_status(plan)
next_step = plan_utils.get_next_step(plan)
next_info = ""
if next_step:
    if next_step["status"] == "in_progress":
        next_info = f"IN PROGRESS: Step {next_step['id']}: {next_step['title']}"
    else:
        next_info = f"NEXT: Step {next_step['id']}: {next_step['title']}"
print(json.dumps({
    "done": counts.get("done", 0),
    "active": counts.get("in_progress", 0),
    "pending": counts.get("pending", 0),
    "blocked": counts.get("blocked", 0),
    "next_step": next_info,
}))
PYEOF
      ) || true

      if [ -n "$other_status_info" ]; then
        done_count=$(python3 -c "import json; print(json.loads('$other_status_info').get('done', 0))" 2>/dev/null) || true
        active_count=$(python3 -c "import json; print(json.loads('$other_status_info').get('active', 0))" 2>/dev/null) || true
        pending_count=$(python3 -c "import json; print(json.loads('$other_status_info').get('pending', 0))" 2>/dev/null) || true
        blocked_count=$(python3 -c "import json; print(json.loads('$other_status_info').get('blocked', 0))" 2>/dev/null) || true
        next_step=$(python3 -c "import json; print(json.loads('$other_status_info').get('next_step', ''))" 2>/dev/null) || true
      fi

      active_plan_summary="NOTE: Active plan exists but is owned by another Claude session"
      active_plan_summary+=$'\n'"Plan: $other_name"
      active_plan_summary+=$'\n'"File: $other_plan"
      active_plan_summary+=$'\n'"Status: $done_count done | $active_count active | $pending_count pending | $blocked_count blocked"
      [ -n "$next_step" ] && active_plan_summary+=$'\n'"$next_step"
      active_plan_summary+=$'\n'$'\n'"This plan is being worked on by another Claude session (PID: $other_lock_pid). Do NOT auto-resume it."
    fi
  fi

  # Legacy fallback only if no plan.json found at all via any method
  if [ -z "$latest_json" ] && [ -z "$active_plan_summary" ]; then
    # Legacy fallback: find masterPlan.md
    latest=""
    latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
    if [ -z "$latest" ]; then
      latest=$(find "$ACTIVE_DIR" -name "masterPlan.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-) || true
    fi

    if [ -n "$latest" ] && [ -f "$latest" ]; then
      plan_name="$(basename "$(dirname "$latest")")"
      has_pending=$(grep -cE '^\s*-\s*(\[ \]|\[~\]|\[!\])' "$latest" 2>/dev/null) || true

      if [ "$has_pending" -gt 0 ]; then
        done_count=$(grep -cE '^\s*-\s*\[x\]' "$latest" 2>/dev/null) || true
        active_count=$(grep -cE '^\s*-\s*\[~\]' "$latest" 2>/dev/null) || true
        pending_count=$(grep -cE '^\s*-\s*\[ \]' "$latest" 2>/dev/null) || true
        blocked_count=$(grep -cE '^\s*-\s*\[!\]' "$latest" 2>/dev/null) || true

        next_step=""
        if [ "$active_count" -gt 0 ]; then
          next_step=$(grep -B5 -E '\[~\]' "$latest" | grep -E '^### Step' | head -1 | sed 's/^### //' || true)
          [ -n "$next_step" ] && next_step="IN PROGRESS: $next_step"
        elif [ "$pending_count" -gt 0 ]; then
          next_step=$(grep -B5 -E '\[ \]' "$latest" | grep -E '^### Step' | head -1 | sed 's/^### //' || true)
          [ -n "$next_step" ] && next_step="NEXT: $next_step"
        fi

        plan_dir="$(dirname "$latest")"
        lock_file="$plan_dir/.session-lock"
        own_plan=true

        if [ -f "$lock_file" ]; then
          lock_pid=$(cat "$lock_file" 2>/dev/null) || true
          if [ -n "$lock_pid" ] && [ "$lock_pid" != "$PPID" ]; then
            if kill -0 "$lock_pid" 2>/dev/null; then
              own_plan=false
            fi
          fi
        fi

        if $own_plan; then
          echo "$PPID" > "$lock_file"
          active_plan_summary="ACTIVE PLAN DETECTED"
          active_plan_summary+=$'\n'"Plan: $plan_name"
          active_plan_summary+=$'\n'"File: $latest"
          active_plan_summary+=$'\n'"Status: $done_count done | $active_count active | $pending_count pending | $blocked_count blocked"
          [ -n "$next_step" ] && active_plan_summary+=$'\n'"$next_step"
          active_plan_summary+=$'\n'$'\n'"IMPORTANT: Read the masterPlan.md file at the path above BEFORE doing any work. The plan is your source of truth. Follow the resumption protocol from the look-before-you-leap skill."
        else
          active_plan_summary="NOTE: Active plan exists but is owned by another Claude session"
          active_plan_summary+=$'\n'"Plan: $plan_name"
          active_plan_summary+=$'\n'"File: $latest"
          active_plan_summary+=$'\n'"Status: $done_count done | $active_count active | $pending_count pending | $blocked_count blocked"
          [ -n "$next_step" ] && active_plan_summary+=$'\n'"$next_step"
          active_plan_summary+=$'\n'$'\n'"This plan is being worked on by another Claude session (PID: $lock_pid). Do NOT auto-resume it."
        fi
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
    if [ "$plugin_name" = "look-before-you-leap" ]; then
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
export HOOK_PLUGIN_ROOT="$PLUGIN_ROOT"
export HOOK_PROJECT_ROOT="$PROJECT_ROOT"

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

def read_file(path):
    try:
        with open(path, "r") as f:
            return f.read()
    except Exception as e:
        return f"Error reading {path}: {e}"

skill_content = read_file(skill_file)
engineering_content = read_file(engineering_file)
plans_content = read_file(plans_file)

# --- Resolve deps-query commands inline in skill text ---
# Instead of burying the command in the project profile where Claude won't
# find it, we replace marker sections in the skills with the actual resolved
# command (when dep_maps configured) or simplified instructions (when not).

def replace_between_markers(content, start_marker, end_marker, replacement):
    """Replace everything between start_marker and end_marker (inclusive) with replacement."""
    start_idx = content.find(start_marker)
    end_idx = content.find(end_marker)
    if start_idx != -1 and end_idx != -1:
        return content[:start_idx] + replacement + content[end_idx + len(end_marker):]
    return content

project_profile = ""
try:
    config = json.loads(config_json_str)
    stack = config.get("stack", {})
    structure = config.get("structure", {})
    disciplines = config.get("disciplines", {})
    dep_maps = config.get("dep_maps", {})

    plugin_root = os.environ.get("HOOK_PLUGIN_ROOT", "")
    project_root = os.environ.get("HOOK_PROJECT_ROOT", "")
    scripts_dir = os.path.join(plugin_root, "skills", "look-before-you-leap", "scripts")

    if dep_maps.get("modules"):
        module_count = len(dep_maps["modules"])
        deps_cmd = f'python3 {scripts_dir}/deps-query.py {project_root} "<file_path>"'
        gen_cmd = f"python3 {scripts_dir}/deps-generate.py {project_root} --stale-only"

        # Conductor skill: replace exploration preamble with resolved command
        skill_content = replace_between_markers(
            skill_content,
            "<!-- deps-exploration-start -->",
            "<!-- deps-exploration-end -->",
            (
                f"**Dep maps ARE configured** ({module_count} modules). Run this on every file\n"
                f"in scope (modify, audit, or review) BEFORE the steps below:\n"
                f"```\n"
                f"{deps_cmd}\n"
                f"```\n"
                f"The output reveals consumers, cross-module dependencies, and blast radius.\n"
                f"For audits/reviews: run on key entry points per module to understand the\n"
                f"dependency architecture BEFORE dispatching sub-agents.\n"
                f"Refresh stale maps: `{gen_cmd}`"
            )
        )

        # Engineering discipline: consumer read section
        engineering_content = replace_between_markers(
            engineering_content,
            "<!-- deps-consumer-read-start -->",
            "<!-- deps-consumer-read-end -->",
            (
                f"- **Its consumers** — who imports THIS file? Dep maps ARE configured —\n"
                f"  you MUST run `{deps_cmd}` to find all consumers.\n"
                f"  Do NOT grep for consumers. If you change an export, every consumer is affected."
            )
        )

        # Engineering discipline: blast radius section
        engineering_content = replace_between_markers(
            engineering_content,
            "<!-- deps-consumer-blast-start -->",
            "<!-- deps-consumer-blast-end -->",
            (
                f"1. Find all consumers: dep maps ARE configured — run\n"
                f"   `{deps_cmd}` to get the DEPENDENTS list.\n"
                f"   Do NOT grep for consumers."
            )
        )
    else:
        # No dep maps — remove preamble entirely
        skill_content = replace_between_markers(
            skill_content,
            "<!-- deps-exploration-start -->",
            "<!-- deps-exploration-end -->",
            ""
        )

        engineering_content = replace_between_markers(
            engineering_content,
            "<!-- deps-consumer-read-start -->",
            "<!-- deps-consumer-read-end -->",
            (
                "- **Its consumers** — who imports THIS file? Use `Grep` to search for\n"
                "  import/require statements referencing this file. If you change an export,\n"
                "  every consumer is affected.\n"
                "  *Tip: If this is a TypeScript project, suggest `/generate-deps` to the\n"
                "  user — dep maps provide faster, more complete consumer analysis than grep.*"
            )
        )

        engineering_content = replace_between_markers(
            engineering_content,
            "<!-- deps-consumer-blast-start -->",
            "<!-- deps-consumer-blast-end -->",
            (
                "1. Find all consumers: use `Grep` to search for import statements\n"
                "   referencing the changed file.\n"
                "   *Tip: If this is a TypeScript project, suggest `/generate-deps` — dep\n"
                "   maps make blast-radius analysis instant and catch cross-module consumers.*"
            )
        )

    # --- Resolve plan_utils.py path in persistent-plans skill ---
    # Replace the marker block with a resolved absolute path so Claude never
    # depends on CLAUDE_PLUGIN_ROOT (which can become stale after cache
    # invalidation or compaction).
    plan_utils_path = os.path.join(scripts_dir, "plan_utils.py")
    plans_content = replace_between_markers(
        plans_content,
        "<!-- plan-utils-cmd-start -->",
        "<!-- plan-utils-cmd-end -->",
        (
            "```bash\n"
            f"PLAN_UTILS=\"{plan_utils_path}\"\n"
            "PLAN_JSON=\".temp/plan-mode/active/<plan-name>/plan.json\"\n"
            "\n"
            "# Mark step 3 as in_progress\n"
            "python3 \"$PLAN_UTILS\" update-step \"$PLAN_JSON\" 3 in_progress\n"
            "\n"
            "# Mark progress item 0 of step 3 as done\n"
            "python3 \"$PLAN_UTILS\" update-progress \"$PLAN_JSON\" 3 0 done\n"
            "\n"
            "# Set the result field on step 3\n"
            "python3 \"$PLAN_UTILS\" set-result \"$PLAN_JSON\" 3 \"Migrated all hooks to new format\"\n"
            "\n"
            "# Mark step 3 as done (legacy plans)\n"
            "python3 \"$PLAN_UTILS\" update-step \"$PLAN_JSON\" 3 done\n"
            "\n"
            "# Mark step 3 as done (strict plans — gates on receipts)\n"
            "# python3 \"$PLAN_UTILS\" complete-step \"$PLAN_JSON\" 3 \"result text\" \"$PROJECT_ROOT\"\n"
            "\n"
            "# Add to completed summary\n"
            "python3 \"$PLAN_UTILS\" add-summary \"$PLAN_JSON\" \"Step 3: Migrated all hooks\"\n"
            "\n"
            "# Get status overview\n"
            "python3 \"$PLAN_UTILS\" status \"$PLAN_JSON\"\n"
            "\n"
            "# Get next step\n"
            "python3 \"$PLAN_UTILS\" next-step \"$PLAN_JSON\"\n"
            "```"
        )
    )

    # Build project profile from config
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

        # Dep maps status
        if dep_maps.get("modules"):
            profile_parts.append(f"Dep maps: configured ({len(dep_maps['modules'])} modules)")
        elif stack.get("language") == "typescript":
            profile_parts.append("Dep maps: **not configured** — run `/generate-deps` for faster consumer & blast-radius analysis")

        if profile_parts:
            project_profile = "**Project Profile** (auto-detected, edit .claude/look-before-you-leap.local.md to customize):\n" + "\n".join(f"- {p}" for p in profile_parts)
except (json.JSONDecodeError, TypeError):
    pass

# Build context message
parts = [
    "**Below is the look-before-you-leap skill — follow it for all coding tasks:**",
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

# Dep maps awareness — explicit callout when configured
if dep_maps.get("modules"):
    module_list = ", ".join(dep_maps["modules"])
    deps_cmd = f'python3 {scripts_dir}/deps-query.py {project_root} "<file_path>"'
    gen_cmd = f"python3 {scripts_dir}/deps-generate.py {project_root} --stale-only"
    dep_maps_notice = (
        "**Dependency Maps Available**\n\n"
        f"This project has dep maps configured for {len(dep_maps['modules'])} module(s): {module_list}\n\n"
        "Dep maps give you instant, complete consumer and dependency analysis for any file. "
        "They are MORE RELIABLE than grepping for imports — they catch re-exports, barrel files, "
        "and cross-module consumers that grep misses.\n\n"
        "**When to use dep maps (MANDATORY):**\n"
        "- Before editing any shared/exported code — find all consumers first\n"
        "- During exploration — understand the dependency graph of files in scope\n"
        "- For blast radius analysis — know exactly what breaks if you change something\n"
        "- When planning — identify all files that need updating\n\n"
        f"**Query command:** `{deps_cmd}`\n"
        f"**Refresh stale maps:** `{gen_cmd}`\n\n"
        "Dep maps are auto-refreshed at session end. If you see a stale warning in query output, "
        "run the refresh command."
    )
    parts.extend(["", "---", "", dep_maps_notice])

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
