#!/usr/bin/env bash
# UserPromptSubmit hook: Capture user override phrases and mint receipts.
#
# When the user types phrases like "just do it", "skip the plan", "no plan",
# "bypass", etc., this hook mints a signed bypass receipt so enforcement
# hooks recognize the user's intent without Claude needing to run commands.
#
# Input: JSON on stdin with prompt (the user's message text)

set -euo pipefail

INPUT=$(cat)

# Extract the user's prompt text
PROMPT=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('prompt', ''))
" <<< "$INPUT" 2>/dev/null) || true

[ -z "$PROMPT" ] && exit 0

# Check for override phrases (case-insensitive)
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Match known override phrases
IS_OVERRIDE="no"
case "$PROMPT_LOWER" in
  *"just do it"*|*"skip the plan"*|*"no plan"*|*"bypass"*|*"skip plan"*)
    IS_OVERRIDE="yes"
    ;;
esac

[ "$IS_OVERRIDE" != "yes" ] && exit 0

# Mint a bypass receipt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/lib/find-root.sh"
source "${SCRIPT_DIR}/lib/receipt-state.sh"

PROJECT_ROOT="$(find_project_root)"
receipt_bootstrap

PROJ_ID=$(receipt_project_id "$PROJECT_ROOT")

# Use a session-scoped plan ID for bypass receipts
PLAN_NAME="user-override-session-$$"

receipt_sign "bypass" "$PROJ_ID" "$PLAN_NAME" "session=$PPID" "maxEdits=10" >/dev/null 2>&1

# Also write legacy marker
mkdir -p "$PROJECT_ROOT/.temp/plan-mode"
echo "${PPID}:10" > "$PROJECT_ROOT/.temp/plan-mode/.no-plan-$PPID"

exit 0
