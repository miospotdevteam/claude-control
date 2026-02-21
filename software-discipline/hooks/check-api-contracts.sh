#!/usr/bin/env bash
# PreToolUse hook: Soft warning when editing API boundary files.
#
# Detects files that define or consume API contracts (tRPC routers,
# API routes, frontend API calls) and reminds Claude to check for
# shared Zod schemas.
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
    is_api_boundary=true; boundary_type="shared API package (packages/api)" ;;
  # Next.js route handlers
  */route.ts|*/route.js|*/route.tsx|*/route.jsx)
    is_api_boundary=true; boundary_type="Next.js route handler" ;;
  # API directories
  */api/*)
    is_api_boundary=true; boundary_type="API route" ;;
  # tRPC routers and procedures
  */trpc/*|*trpc*router*|*trpc*procedure*)
    is_api_boundary=true; boundary_type="tRPC router/procedure" ;;
  */routers/*|*.router.ts|*.router.js)
    is_api_boundary=true; boundary_type="router definition" ;;
  */procedures/*|*.procedure.ts|*.procedure.js)
    is_api_boundary=true; boundary_type="tRPC procedure" ;;
  # Schema/validator directories (app-local — should probably be in packages/api)
  */schemas/*|*/validators/*)
    is_api_boundary=true; boundary_type="schema/validator (check: should this be in packages/api?)" ;;
esac

# --- Content-based detection (only if path didn't match) ---
if [ "$is_api_boundary" = false ] && [ -f "$FILE_PATH" ]; then
  # tRPC server-side patterns
  if grep -qE '(createTRPCRouter|publicProcedure|protectedProcedure|\.input\(z\.|\.output\(z\.)' "$FILE_PATH" 2>/dev/null; then
    is_api_boundary=true
    boundary_type="tRPC procedure (from content)"
  # Next.js route handler patterns
  elif grep -qE '(NextRequest|NextResponse|export\s+(async\s+)?function\s+(GET|POST|PUT|DELETE|PATCH))' "$FILE_PATH" 2>/dev/null; then
    is_api_boundary=true
    boundary_type="Next.js API handler (from content)"
  # tRPC client-side patterns
  elif grep -qE '(trpc\.[a-zA-Z]+\.(useQuery|useMutation|useInfiniteQuery|useSuspenseQuery))' "$FILE_PATH" 2>/dev/null; then
    is_api_boundary=true
    boundary_type="tRPC client consumer (from content)"
  # Raw fetch/axios to API endpoints
  elif grep -qE '(fetch\s*\(\s*['\''"`]/api/|axios\.(get|post|put|patch|delete)\s*\(\s*['\''"`]/api/)' "$FILE_PATH" 2>/dev/null; then
    is_api_boundary=true
    boundary_type="HTTP client calling API (from content)"
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
    "1. Find the shared API package (packages/api/ with @repo/api imports)\n"
    "2. Find the Zod schema for this endpoint in packages/api/src/schemas/\n"
    "3. If no schema exists: create it in packages/api/ FIRST, then use in both server AND client\n"
    "4. Import from @repo/api — NEVER define types locally in an app\n"
    "5. Verify the SAME schema validates input on the server AND types the request on the client\n\n"
    "Quick check: grep for the endpoint/procedure name — are input/output types defined once in packages/api/ or duplicated across apps?\n\n"
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
