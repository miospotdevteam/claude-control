#!/usr/bin/env bash
# PreToolUse(Grep) hook: Block grepping for import/consumer patterns when
# dep maps are configured — forces use of deps-query.py instead.
#
# This hook DENIES the grep when dep maps are configured AND the pattern
# looks like an import/consumer search on TypeScript files.
#
# Input: JSON on stdin with tool_name, tool_input (pattern, type, glob), cwd

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
hook_read_input

# Extract grep pattern and file type/glob filters
PATTERN=$(hook_get_pattern) || exit 0
FILE_TYPE=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('type', ''))
" <<< "$HOOK_INPUT" 2>/dev/null) || true
FILE_GLOB=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('glob', ''))
" <<< "$HOOK_INPUT" 2>/dev/null) || true

# Quick exit: only care about patterns that look like import/consumer searches
# Match: import, from, require — common patterns when searching for consumers
case "$PATTERN" in
  *import*|*from\ *|*from\\s*|*require*|*"from ["*|*"from '"*)
    ;;
  *)
    exit 0
    ;;
esac

# Quick exit: only care about TypeScript-related searches
case "${FILE_TYPE}${FILE_GLOB}" in
  *ts*|*tsx*|"")
    # Empty type+glob means searching all files, which includes TS — proceed
    ;;
  *)
    exit 0
    ;;
esac

# Check if dep maps are configured
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

CWD=$(hook_get_cwd)

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
CONFIG_FILE="$PROJECT_ROOT/.claude/look-before-you-leap.local.md"

[ -f "$CONFIG_FILE" ] || exit 0

# Check if dep_maps with modules is configured (use read-config.py via subprocess)
LIB_DIR="${BASH_SOURCE[0]%/*}/lib"
has_dep_maps=$(python3 -c "
import json, subprocess, sys
result = subprocess.run(
    [sys.executable, '$LIB_DIR/read-config.py', '$PROJECT_ROOT'],
    capture_output=True, text=True
)
config = json.loads(result.stdout) if result.stdout.strip() else {}
dm = config.get('dep_maps', {})
modules = dm.get('modules', [])
print('yes' if modules else 'no')
" 2>/dev/null) || true

# If no dep maps or parse failed, nothing to remind about
if [ "$has_dep_maps" != "yes" ]; then
  exit 0
fi

# Allow grep for patterns containing path alias prefixes (@/, ~/, #/).
# Dep maps rely on madge's tsconfig resolution which can be incomplete when
# tsconfig uses extends chains, monorepo path mappings, or custom resolvers.
# These aliases are the #1 source of dep-map blind spots — let grep through.
case "$PATTERN" in
  *'@/'*|*'~/'*|*'#/'*)
    exit 0
    ;;
esac

# Also check the project's tsconfig.json for custom path aliases.
# If the grep pattern contains any configured alias prefix, allow it.
if [ -n "$PROJECT_ROOT" ]; then
  custom_hit=$(python3 -c "
import json, re, os, sys
project_root = sys.argv[1]
pattern = sys.argv[2]
for tc in ['tsconfig.json', 'tsconfig.base.json']:
    path = os.path.join(project_root, tc)
    if not os.path.exists(path):
        continue
    try:
        with open(path) as f:
            content = f.read()
        content = re.sub(r'//.*?$', '', content, flags=re.MULTILINE)
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        data = json.loads(content)
        paths = data.get('compilerOptions', {}).get('paths', {})
        for key in paths:
            prefix = key.replace('/*', '/').replace('*', '')
            if prefix and prefix != '/' and prefix in pattern:
                print('yes')
                sys.exit(0)
    except Exception:
        pass
" "$PROJECT_ROOT" "$PATTERN" 2>/dev/null) || true

  if [ "$custom_hit" = "yes" ]; then
    exit 0
  fi
fi

# Dep maps ARE configured and the pattern looks like an import/consumer search.
# DENY the grep — Claude must use deps-query.py instead.
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
SCRIPTS_DIR="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts"

python3 << PYEOF
import json, sys

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "Dep maps are configured — grepping for import/consumer patterns is blocked. "
            "Use deps-query.py instead, which is faster and catches cross-module consumers.\n\n"
            "Run: python3 ${SCRIPTS_DIR}/deps-query.py ${PROJECT_ROOT} \"<file_path>\"\n\n"
            "Grep is only allowed for:\n"
            "- Non-TypeScript files\n"
            "- String references (config keys, env vars, literal text)\n"
            "- Aliased imports (@/, ~/, #/, or tsconfig paths aliases)\n"
            "- Projects without dep maps configured"
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
