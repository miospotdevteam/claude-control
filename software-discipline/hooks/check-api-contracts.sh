#!/usr/bin/env bash
# PreToolUse hook: Soft warning when editing API boundary files.
#
# Detects files that define or consume API contracts (Hono route handlers,
# API routes, frontend API calls) and reminds Claude to check for
# shared Zod schemas in the @miospot/api package.
#
# This is a SOFT WARNING — allows the edit but surfaces a reminder.
#
# Input: JSON on stdin with tool_name, tool_input.file_path, cwd

set -euo pipefail

INPUT=$(cat)

# Extract file path
FILE_PATH=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null) || true

# Skip if no file path
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Skip non-TS/JS files — API contracts only matter in code
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx) ;;
  *) exit 0 ;;
esac

# Skip files that are never API boundaries
case "$FILE_PATH" in
  */.temp/*|*/node_modules/*|*.config.*|*.d.ts)
    exit 0 ;;
  *.test.*|*.spec.*|*__tests__/*|*__mocks__/*)
    exit 0 ;;
  */.claude/*|*/claude-code-setup/*)
    exit 0 ;;
esac

# --- Path-based detection ---
is_api_boundary=false
boundary_type=""

case "$FILE_PATH" in
  # Shared API package (monorepo) — the single source of truth
  */packages/api/*|*/packages/shared/*)
    is_api_boundary=true; boundary_type="shared API package (@miospot/api)" ;;
  # Hono route files
  */routes/*|*.route.ts|*.route.js|*.routes.ts|*.routes.js)
    is_api_boundary=true; boundary_type="Hono route handler" ;;
  # API directories
  */api/*)
    is_api_boundary=true; boundary_type="API route" ;;
  # Router definitions
  */routers/*|*.router.ts|*.router.js)
    is_api_boundary=true; boundary_type="router definition" ;;
  # Schema/validator directories (app-local — should probably be in @miospot/api)
  */schemas/*|*/validators/*)
    is_api_boundary=true; boundary_type="schema/validator (check: should this be in @miospot/api?)" ;;
esac

# --- Content-based detection (only if path didn't match) ---
if [ "$is_api_boundary" = false ] && [ -f "$FILE_PATH" ]; then
  # Hono route patterns
  if grep -qE '(new Hono|app\.(get|post|put|patch|delete)\(|createRoute|OpenAPIHono)' "$FILE_PATH" 2>/dev/null; then
    is_api_boundary=true
    boundary_type="Hono route handler (from content)"
  # Zod schema validation in handlers
  elif grep -qE '(z\.(safe)?[Pp]arse|\.safeParse\(|zValidator)' "$FILE_PATH" 2>/dev/null; then
    is_api_boundary=true
    boundary_type="Zod validation in handler (from content)"
  # Frontend API client calls
  elif grep -qE '(fetch\s*\(|axios\.(get|post|put|patch|delete)|\.useQuery|\.useMutation|api\.)' "$FILE_PATH" 2>/dev/null; then
    is_api_boundary=true
    boundary_type="API client call (from content)"
  fi
fi

if [ "$is_api_boundary" = false ]; then
  exit 0
fi

# --- Emit soft warning ---
BOUNDARY_TYPE="$boundary_type" python3 << 'PYEOF'
import json, os, sys

boundary_type = os.environ.get("BOUNDARY_TYPE", "unknown")

warning = (
    f"API BOUNDARY DETECTED ({boundary_type})\n\n"
    "Before editing this file, check for shared types:\n"
    "1. Find the shared API package (packages/api/ with @miospot/api imports)\n"
    "2. Find the Zod schema for this endpoint in packages/api/\n"
    "3. If no schema exists: create it in @miospot/api FIRST, then use in both Hono handler AND client\n"
    "4. Import from @miospot/api — NEVER define types locally in an app\n"
    "5. Use z.safeParse() with the shared schema in the handler, and the same schema to type the client\n\n"
    "Quick check: grep for the endpoint name — are input/output types defined once in @miospot/api or duplicated across apps?\n\n"
    "Read references/api-contracts-checklist.md for the full checklist."
)

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": warning
    }
}
json.dump(output, sys.stdout)
PYEOF
