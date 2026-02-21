#!/usr/bin/env bash
# SessionStart hook for software-discipline plugin.
#
# On every session start (including after compaction/resume), this hook:
# 1. Reads the software-discipline SKILL.md content
# 2. Checks for active plans in .temp/plan-mode/
# 3. Discovers other installed Claude Code skills
#
# All three pieces are combined into a single additionalContext string.
# JSON output is handled by python3 for bulletproof encoding.

set -euo pipefail

# Determine plugin root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SKILL_FILE="${PLUGIN_ROOT}/skills/software-discipline/SKILL.md"

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
export ACTIVE_PLAN_SUMMARY="$active_plan_summary"
export SKILL_INVENTORY="$skill_inventory"

python3 << 'PYEOF'
import json
import sys
import os

skill_file = os.environ.get("SKILL_FILE_PATH", "")
active_summary = os.environ.get("ACTIVE_PLAN_SUMMARY", "")
skill_inventory = os.environ.get("SKILL_INVENTORY", "")

# Read skill content
try:
    with open(skill_file, "r") as f:
        skill_content = f.read()
except Exception as e:
    skill_content = f"Error reading skill: {e}"

# Build context message
parts = [
    "**Below is the software-discipline skill — follow it for all coding tasks:**",
    "",
    skill_content
]

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
