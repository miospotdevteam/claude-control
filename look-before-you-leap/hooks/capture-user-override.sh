#!/usr/bin/env bash
# UserPromptSubmit hook: Capture user override phrases and mint receipts.
#
# When the user types phrases like "just do it", "skip the plan", "no plan",
# "bypass", etc., this hook mints a signed bypass receipt so enforcement
# hooks recognize the user's intent without Claude needing to run commands.
#
# Input: JSON on stdin with prompt (the user's message text)

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
hook_read_input

# Extract the user's prompt text
PROMPT=$(hook_get_prompt)

CWD=$(hook_get_cwd)

[ -z "$PROMPT" ] && exit 0

# Check for explicit override phrases.
# Keep this intentionally narrow: filenames like commands/bypass.md or quoted
# documentation should not mint a bypass receipt.
IS_OVERRIDE=$(PROMPT_TEXT="$PROMPT" python3 << 'PYEOF'
import os
import re

prompt = os.environ["PROMPT_TEXT"].strip().lower()

phrase_patterns = (
    r"(^|[^a-z0-9])just do it([^a-z0-9]|$)",
    r"(^|[^a-z0-9])skip the plan([^a-z0-9]|$)",
    r"(^|[^a-z0-9])skip plan([^a-z0-9]|$)",
    r"(^|[^a-z0-9])no plan([^a-z0-9]|$)",
)

explicit_bypass = (
    prompt == "bypass"
    or re.search(r"(^|[\s\"'])/bypass(?=$|[\s\"'!?.,:;])", prompt) is not None
)

matched_phrase = any(re.search(pattern, prompt) for pattern in phrase_patterns)

print("yes" if explicit_bypass or matched_phrase else "no")
PYEOF
)

[ "$IS_OVERRIDE" != "yes" ] && exit 0

# Mint a bypass receipt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/find-root.sh"
source "${SCRIPT_DIR}/lib/receipt-state.sh"

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
receipt_bootstrap

PROJ_ID=$(receipt_project_id "$PROJECT_ROOT")

# Use a session-scoped plan ID for bypass receipts
PLAN_NAME="user-override-session-$$"

receipt_sign "bypass" "$PROJ_ID" "$PLAN_NAME" "session=$PPID" "maxEdits=10" >/dev/null 2>&1

# Also write legacy marker
mkdir -p "$PROJECT_ROOT/.temp/plan-mode"
echo "${PPID}:10" > "$PROJECT_ROOT/.temp/plan-mode/.no-plan-$PPID"

exit 0
