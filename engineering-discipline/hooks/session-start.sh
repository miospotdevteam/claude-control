#!/usr/bin/env bash
# SessionStart hook for engineering-discipline plugin

set -euo pipefail

# Determine plugin root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Use python3 for bulletproof JSON encoding
SKILL_FILE="${PLUGIN_ROOT}/skills/engineering-discipline/SKILL.md"
export SKILL_FILE_PATH="$SKILL_FILE"

python3 << 'PYEOF'
import json
import sys
import os

skill_file = os.environ.get("SKILL_FILE_PATH", "")

try:
    with open(skill_file, "r") as f:
        skill_content = f.read()
except Exception as e:
    skill_content = f"Error reading skill: {e}"

context = "\n".join([
    "**Below is the full content of the 'engineering-discipline' skill — follow it for all coding tasks:**",
    "",
    skill_content
])

output = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": context
    }
}

json.dump(output, sys.stdout)
PYEOF
