#!/usr/bin/env bash
# Shell helpers for receipt-based enforcement in hooks.
#
# Provides functions to check receipts from shell hooks without
# spawning a full Python process for simple checks.
#
# Usage: source this file from hook scripts.
#   source "${BASH_SOURCE[0]%/*}/lib/receipt-state.sh"

# Resolve the receipt_utils.py path relative to the plugin structure.
# Hooks live at hooks/, scripts at scripts/, both under the plugin root.
_RECEIPT_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"
RECEIPT_UTILS="${_RECEIPT_UTILS_DIR}/receipt_utils.py"

# State root path (matches receipt_utils.py)
RECEIPT_STATE_ROOT="${HOME}/.claude/look-before-you-leap/state"

receipt_bootstrap() {
  # Ensure state root and secret exist. Safe to call multiple times.
  python3 "$RECEIPT_UTILS" bootstrap >/dev/null 2>&1
}

receipt_project_id() {
  # Get stable project ID for a project root path.
  # Usage: receipt_project_id /path/to/project
  python3 "$RECEIPT_UTILS" project-id "$1" 2>/dev/null
}

receipt_plan_id() {
  # Get plan ID from a plan.json path (extracts the "name" field).
  # Usage: receipt_plan_id /path/to/plan.json
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get('name', 'unknown'))
" "$1" 2>/dev/null
}

receipt_check() {
  # Check if a valid receipt exists.
  # Usage: receipt_check <type> <projectId> <planId> [key=value ...]
  # Returns 0 if exists, 1 if missing.
  python3 "$RECEIPT_UTILS" check "$@" >/dev/null 2>&1
}

receipt_sign() {
  # Create a signed receipt.
  # Usage: receipt_sign <type> <projectId> <planId> [key=value ...]
  # Prints the receipt path.
  python3 "$RECEIPT_UTILS" sign "$@" 2>/dev/null
}

receipt_verify() {
  # Verify a receipt file's signature.
  # Usage: receipt_verify /path/to/receipt.json
  # Returns 0 if valid, 1 if invalid.
  python3 "$RECEIPT_UTILS" verify "$1" >/dev/null 2>&1
}

receipt_classify() {
  # Classify a plan as legacy or strict.
  # Usage: receipt_classify /path/to/plan.json
  # Prints "legacy" or "strict".
  python3 "$RECEIPT_UTILS" classify "$1" 2>/dev/null
}

receipt_state_root() {
  echo "$RECEIPT_STATE_ROOT"
}
