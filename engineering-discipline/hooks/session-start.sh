#!/usr/bin/env bash
# SessionStart hook for engineering-discipline plugin

set -euo pipefail

# Determine plugin root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read engineering-discipline skill content
skill_content=$(cat "${PLUGIN_ROOT}/skills/engineering-discipline/SKILL.md" 2>&1 || echo "Error reading engineering-discipline skill")

# Escape string for JSON embedding
escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

skill_escaped=$(escape_for_json "$skill_content")

# Output context injection as JSON
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "**Below is the full content of the 'engineering-discipline' skill — follow it for all coding tasks:**\n\n${skill_escaped}"
  }
}
EOF

exit 0
