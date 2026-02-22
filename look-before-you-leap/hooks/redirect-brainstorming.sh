#!/usr/bin/env bash
# PreToolUse hook: Block superpowers:brainstorming, redirect to look-before-you-leap:brainstorming.
#
# Input: JSON on stdin with tool_name, tool_input (skill, args), cwd

set -euo pipefail

INPUT=$(cat)

SKILL=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('skill', ''))
" <<< "$INPUT" 2>/dev/null) || true

# Block superpowers:brainstorming — redirect to look-before-you-leap:brainstorming
if [[ "$SKILL" == "superpowers:brainstorming" ]]; then
  python3 << 'PYEOF'
import json, sys

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "BLOCKED: Use look-before-you-leap:brainstorming instead of superpowers:brainstorming. "
            "The look-before-you-leap plugin provides the authoritative brainstorming skill "
            "that integrates with persistent plans. "
            "Invoke: Skill tool with skill='look-before-you-leap:brainstorming'"
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
  exit 0
fi

# All other skills — allow
exit 0
