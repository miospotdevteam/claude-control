#!/usr/bin/env bash
# PreToolUse hook: Soft warning when editing API boundary files.
#
# Config-driven: reads .claude/look-before-you-leap.local.md for stack info.
# Detects files that define or consume API contracts (route handlers,
# API routes, frontend API calls) and reminds Claude to check for
# shared schemas in the appropriate package.
#
# This is a SOFT WARNING — allows the edit but surfaces a reminder.
#
# Input: JSON on stdin with tool_name, tool_input.file_path, cwd

set -euo pipefail

INPUT=$(cat)

# --- Read config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Extract cwd and file path
read -r FILE_PATH CWD <<< "$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
fp = data.get('tool_input', {}).get('file_path', '')
cwd = data.get('cwd', '')
print(fp, cwd)
" <<< "$INPUT" 2>/dev/null)" || true

# Skip if no file path
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Find project root
find_project_root() {
  local dir="${1:-$PWD}"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "${1:-$PWD}"
}

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"

# Read config (graceful fallback to empty object)
CONFIG_JSON=$(python3 "$LIB_DIR/read-config.py" "$PROJECT_ROOT" 2>/dev/null) || CONFIG_JSON="{}"

# Check if api_contracts discipline is enabled
api_contracts_enabled=$(python3 -c "
import json, sys
config = json.loads(sys.stdin.read())
print('true' if config.get('disciplines', {}).get('api_contracts', True) else 'false')
" <<< "$CONFIG_JSON" 2>/dev/null) || api_contracts_enabled="true"

if [ "$api_contracts_enabled" = "false" ]; then
  exit 0
fi

# Skip non-TS/JS files — API contracts only matter in code
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx) ;;
  *.py|*.rs|*.go) ;;
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

# --- Detect API boundary using config-aware Python ---
export HOOK_FILE_PATH="$FILE_PATH"
export HOOK_CONFIG_JSON="$CONFIG_JSON"

python3 << 'PYEOF'
import json
import os
import re
import sys

file_path = os.environ.get("HOOK_FILE_PATH", "")
config = json.loads(os.environ.get("HOOK_CONFIG_JSON", "{}"))

stack = config.get("stack", {})
structure = config.get("structure", {})

backend = stack.get("backend", "")
validation = stack.get("validation", "")
shared_pkg = structure.get("shared_api_package", "")
shared_dir = structure.get("shared_dir", "")

is_api_boundary = False
boundary_type = ""

# --- Path-based detection ---

# Shared API package directory (monorepo)
if shared_dir and f"/{shared_dir}/" in file_path:
    label = f"shared API package ({shared_pkg})" if shared_pkg else "shared API package"
    is_api_boundary = True
    boundary_type = label
# Generic shared package patterns
elif re.search(r'/packages/(api|shared)/', file_path):
    is_api_boundary = True
    boundary_type = "shared API package"

if not is_api_boundary:
    # Route files
    if re.search(r'/routes/|\.routes?\.(ts|js|tsx|jsx)$', file_path):
        is_api_boundary = True
        boundary_type = f"{backend or 'API'} route handler"
    # API directories
    elif '/api/' in file_path:
        is_api_boundary = True
        boundary_type = "API route"
    # Router definitions
    elif re.search(r'/routers/|\.router\.(ts|js)$', file_path):
        is_api_boundary = True
        boundary_type = "router definition"
    # Schema/validator directories
    elif re.search(r'/schemas/|/validators/', file_path):
        is_api_boundary = True
        where = f" (check: should this be in {shared_pkg}?)" if shared_pkg else ""
        boundary_type = f"schema/validator{where}"

# --- Content-based detection (only if path didn't match) ---
if not is_api_boundary and os.path.isfile(file_path):
    try:
        with open(file_path) as f:
            content = f.read(8192)  # only read first 8KB
    except OSError:
        content = ""

    if content:
        # Backend framework patterns
        backend_patterns = {
            "hono": r'(new Hono|app\.(get|post|put|patch|delete)\(|createRoute|OpenAPIHono)',
            "express": r'(express\.Router|router\.(get|post|put|patch|delete)\(|app\.(get|post|put|patch|delete)\()',
            "fastify": r'(fastify\.(get|post|put|patch|delete)\(|\.register\()',
            "nestjs": r'(@Controller|@Get|@Post|@Put|@Patch|@Delete)\(',
            "koa": r'(router\.(get|post|put|patch|delete)\()',
        }
        # Pick pattern for detected backend, or try all
        if backend and backend in backend_patterns:
            patterns_to_try = {backend: backend_patterns[backend]}
        else:
            patterns_to_try = backend_patterns

        for fw, pattern in patterns_to_try.items():
            if re.search(pattern, content):
                is_api_boundary = True
                boundary_type = f"{fw} route handler (from content)"
                break

        # Validation patterns
        if not is_api_boundary:
            validation_patterns = {
                "zod": r'(z\.(safe)?[Pp]arse|\.safeParse\(|zValidator)',
                "valibot": r'(v\.parse|v\.safeParse|parse\(.*Schema)',
                "joi": r'(Joi\.(object|string|number|array)|\.validate\()',
                "yup": r'(yup\.(object|string|number|array)|\.validate\()',
            }
            if validation and validation in validation_patterns:
                patterns_to_try = {validation: validation_patterns[validation]}
            else:
                patterns_to_try = validation_patterns

            for vl, pattern in patterns_to_try.items():
                if re.search(pattern, content):
                    is_api_boundary = True
                    boundary_type = f"{vl} validation in handler (from content)"
                    break

        # Frontend API client calls (framework-agnostic)
        if not is_api_boundary:
            if re.search(r'(fetch\s*\(|axios\.(get|post|put|patch|delete)|\.useQuery|\.useMutation|api\.)', content):
                is_api_boundary = True
                boundary_type = "API client call (from content)"

if not is_api_boundary:
    sys.exit(0)

# --- Emit soft warning ---
# Build advice based on config
if shared_pkg:
    shared_advice = (
        f"1. Find the shared API package ({shared_pkg})\n"
        f"2. Find the {validation or 'validation'} schema for this endpoint in {shared_dir or 'the shared package'}\n"
        f"3. If no schema exists: create it in {shared_pkg} FIRST, then use in both handler AND client\n"
        f"4. Import from {shared_pkg} — NEVER define types locally in an app\n"
    )
    quick_check = f"Quick check: grep for the endpoint name — are input/output types defined once in {shared_pkg} or duplicated across apps?"
else:
    shared_advice = (
        "1. Check if shared types/schemas exist for this endpoint\n"
        "2. If a shared package exists, use it as the single source of truth\n"
        "3. If not, keep request/response types close to the handler and import them in clients\n"
        "4. Avoid duplicating type definitions across modules\n"
    )
    quick_check = "Quick check: are input/output types defined once and imported, or duplicated?"

if validation:
    validate_tip = f"5. Use {validation} schemas for runtime validation in handlers and type inference in clients\n"
else:
    validate_tip = "5. Use a validation library (zod, valibot, etc.) for runtime validation\n"

warning = (
    f"API BOUNDARY DETECTED ({boundary_type})\n\n"
    "Before editing this file, check for shared types:\n"
    f"{shared_advice}"
    f"{validate_tip}\n"
    f"{quick_check}\n\n"
    "Read references/api-contracts-checklist.md for the full checklist."
)

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": warning,
    }
}
json.dump(output, sys.stdout)
PYEOF
