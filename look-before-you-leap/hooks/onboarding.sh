#!/usr/bin/env bash
# UserPromptSubmit hook: first-run onboarding.
#
# Checks for .claude/.onboarding-pending marker (created by session-start.sh
# on first config detection). If found, outputs onboarding instructions and
# removes the marker so it only fires once.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# --- Find project root ---
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
MARKER="$PROJECT_ROOT/.claude/.onboarding-pending"

# No marker = not a first run, exit silently
if [ ! -f "$MARKER" ]; then
  exit 0
fi

# Remove marker immediately so this only fires once
rm -f "$MARKER"

# Read config JSON for stack info
CONFIG_FILE="$PROJECT_ROOT/.claude/look-before-you-leap.local.md"
PROJECT_CONFIG_JSON=$(python3 "$LIB_DIR/read-config.py" "$PROJECT_ROOT" 2>/dev/null) || PROJECT_CONFIG_JSON="{}"

# Detect CLAUDE.md
HAS_CLAUDE_MD=false
if [ -f "$PROJECT_ROOT/CLAUDE.md" ] || [ -f "$PROJECT_ROOT/.claude/CLAUDE.md" ]; then
  HAS_CLAUDE_MD=true
fi

# Export everything the Python builder needs
export PROJECT_CONFIG_JSON
export HAS_CLAUDE_MD
export PLUGIN_ROOT

python3 << 'PYEOF'
import json
import sys
import os

config_json_str = os.environ.get("PROJECT_CONFIG_JSON", "{}")
has_claude_md = os.environ.get("HAS_CLAUDE_MD", "false") == "true"
plugin_root = os.environ.get("PLUGIN_ROOT", "")

# Read recommended plugins reference
rec_plugins_content = ""
rec_plugins_path = os.path.join(plugin_root, "skills", "look-before-you-leap",
                                 "references", "recommended-plugins.md")
try:
    with open(rec_plugins_path, "r") as f:
        rec_plugins_content = f.read()
except Exception:
    pass

# Read CLAUDE.md snippet template
claude_md_snippet = ""
claude_md_snippet_path = os.path.join(plugin_root, "skills", "look-before-you-leap",
                                       "references", "claude-md-snippet.md")
try:
    with open(claude_md_snippet_path, "r") as f:
        claude_md_snippet = f.read()
except Exception:
    pass

# Summarize detected stack
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

# Build onboarding instructions
lines = []
lines.append("FIRST-RUN SETUP: The look-before-you-leap plugin just ran for the first time in this project.")
lines.append(f"A config was auto-created at .claude/look-before-you-leap.local.md"
             + (f" with detected stack: {stack_summary}." if stack_summary else "."))
lines.append("")
lines.append("Before doing anything else, walk the user through setup:")
lines.append("")
lines.append("1. Tell the user what was detected and show the stack summary.")
lines.append("")
lines.append("2. Offer to enrich the config by exploring the codebase deeper.")
lines.append("   If yes, read key files (package.json, tsconfig, project structure)")
lines.append("   and update .claude/look-before-you-leap.local.md with richer content:")
lines.append("   verification commands, gotchas, blast radius areas, conventions.")
lines.append("   Use brainstorming style — one question at a time, multiple choice where possible.")
lines.append("")

step = 3
if not has_claude_md:
    lines.append(f"{step}. Offer to create a CLAUDE.md — this project has none.")
    lines.append("   If they agree, create .claude/CLAUDE.md using this template:")
    lines.append("")
    if claude_md_snippet:
        for snippet_line in claude_md_snippet.split("\n"):
            lines.append(f"   {snippet_line}")
    lines.append("")
    lines.append("   Tailor it to the detected stack. Ask the user if they want to add")
    lines.append("   project-specific conventions, coding style preferences, or other notes.")
    lines.append("")
    step += 1

lines.append(f"{step}. Suggest useful plugins to install.")
lines.append("   Check which official Anthropic plugins would benefit this project.")
lines.append("   For each suggestion, ask whether to install at user, project, or global scope")
lines.append("   (user = all your projects, project = just this repo, global = all users on machine).")
lines.append("   Install command: claude plugin install <name>@claude-plugins-official --scope <scope>")
lines.append("")

if rec_plugins_content:
    lines.append("Recommended plugins reference:")
    lines.append(rec_plugins_content)
    lines.append("")

lines.append("Use a conversational, brainstorming style. One question at a time.")
lines.append("Don't dump everything at once. Guide the user through setup step by step.")
lines.append("If the user declines any step, skip it and move to the next.")
lines.append("Once onboarding is complete (or declined), proceed normally with whatever the user asked.")

context = "\n".join(lines)

output = {
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": context
    }
}

json.dump(output, sys.stdout)
PYEOF
