#!/usr/bin/env bash
# PreToolUse hook: Block Codex MCP tool — enforce CLI usage.
#
# All Codex interactions MUST go through `codex exec` via Bash.
# The MCP tool bypasses direction-locked scripts (run-codex-verify.sh,
# run-codex-implement.sh), JSONL monitoring, structured result parsing,
# sandbox enforcement, and error logging that the plugin provides.
#
# Blocks: mcp__codex__codex, mcp__codex__codex-reply
# Redirects to: codex exec via Bash
#
# Input: JSON on stdin with tool_name, tool_input

set -euo pipefail

# The matcher already filtered to codex MCP tools — just deny.
python3 -c "
import json, sys

output = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': (
            'BLOCKED: Do NOT use the Codex MCP tool. All Codex interactions '
            'must go through codex exec via the Bash tool.\n\n'
            'The MCP tool bypasses the direction-locked scripts '
            '(run-codex-verify.sh, run-codex-implement.sh), JSONL monitoring, '
            'structured result parsing, and error logging.\n\n'
            'For verification:\n'
            '  bash \${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh <plan.json> <step>\n\n'
            'For codex-impl steps:\n'
            '  bash \${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-implement.sh <plan.json> <step>\n\n'
            'For ad-hoc Codex queries:\n'
            '  codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \"<prompt>\"'
        )
    }
}

json.dump(output, sys.stdout)
"
