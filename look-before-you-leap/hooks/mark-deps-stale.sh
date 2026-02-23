#!/usr/bin/env bash
# PostToolUse hook: Mark dep map modules stale when .ts/.tsx files are edited.
#
# When a .ts/.tsx file is edited, determines which configured module it
# belongs to (longest-prefix match) and appends the module slug to
# .claude/deps/.stale for lazy regeneration on next query.
#
# Silent hook — no JSON output. Exits early if dep_maps not configured.
#
# Input: JSON on stdin with tool_input.file_path, cwd

set -euo pipefail

INPUT=$(cat)

# Extract file path
FILE_PATH=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null) || true

[ -z "$FILE_PATH" ] && exit 0

# Only care about .ts/.tsx files
case "$FILE_PATH" in
  *.ts|*.tsx) ;;
  *) exit 0 ;;
esac

# Skip test files and node_modules
case "$FILE_PATH" in
  *.test.ts|*.test.tsx|*.spec.ts|*.spec.tsx) exit 0 ;;
  *node_modules*) exit 0 ;;
  *__tests__*) exit 0 ;;
esac

# Find project root
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/lib" && pwd)"

# Read config — exit silently if dep_maps not configured
export HOOK_PROJECT_ROOT="$PROJECT_ROOT"
export HOOK_FILE_PATH="$FILE_PATH"
export HOOK_LIB_DIR="$LIB_DIR"

python3 << 'PYEOF'
import json, os, subprocess, sys

project_root = os.environ["HOOK_PROJECT_ROOT"]
file_path = os.environ["HOOK_FILE_PATH"]
lib_dir = os.environ["HOOK_LIB_DIR"]

# Read config
read_config = os.path.join(lib_dir, "read-config.py")
try:
    result = subprocess.run(
        [sys.executable, read_config, project_root],
        capture_output=True, text=True, timeout=5,
    )
    config = json.loads(result.stdout) if result.returncode == 0 else {}
except Exception:
    config = {}

dep_maps = config.get("dep_maps", {})
modules = dep_maps.get("modules", [])
if not modules:
    sys.exit(0)

deps_dir = os.path.join(project_root, dep_maps.get("dir", ".claude/deps"))

# Make file path repo-relative
if os.path.isabs(file_path):
    rel_path = os.path.relpath(file_path, project_root)
else:
    rel_path = file_path

# Longest-prefix match to find module
best_module = None
for mod in modules:
    if rel_path.startswith(mod + "/") or rel_path == mod:
        if best_module is None or len(mod) > len(best_module):
            best_module = mod

if not best_module:
    sys.exit(0)

slug = best_module.replace("/", "-")
stale_file = os.path.join(deps_dir, ".stale")

# Check if already marked stale (deduplicate)
existing = set()
if os.path.exists(stale_file):
    try:
        with open(stale_file) as f:
            existing = {line.strip() for line in f if line.strip()}
    except (FileNotFoundError, PermissionError):
        pass

if slug in existing:
    sys.exit(0)

# Append slug to .stale
os.makedirs(deps_dir, exist_ok=True)
with open(stale_file, "a") as f:
    f.write(slug + "\n")
PYEOF
