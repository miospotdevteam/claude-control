#!/usr/bin/env bash
# Stop hook: Refresh stale dep maps before session ends.
#
# When dep maps are configured and modules are marked stale (by the
# mark-deps-stale PostToolUse hook), regenerates them so the next session
# starts with up-to-date maps.
#
# Silent hook — no JSON output (does not block stopping).

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"
hook_read_input

CWD=$(hook_get_cwd)

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/lib" && pwd)"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
SCRIPTS_DIR="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts"

# Check if dep maps are configured and have stale modules
export HOOK_PROJECT_ROOT="$PROJECT_ROOT"
export HOOK_LIB_DIR="$LIB_DIR"
export HOOK_SCRIPTS_DIR="$SCRIPTS_DIR"

python3 << 'PYEOF'
import json, os, subprocess, sys

project_root = os.environ["HOOK_PROJECT_ROOT"]
lib_dir = os.environ["HOOK_LIB_DIR"]
scripts_dir = os.environ["HOOK_SCRIPTS_DIR"]

# Read config
read_config = os.path.join(lib_dir, "read-config.py")
try:
    result = subprocess.run(
        [sys.executable, read_config, project_root],
        capture_output=True, text=True, timeout=5,
    )
    config = json.loads(result.stdout) if result.returncode == 0 else {}
except Exception:
    sys.exit(0)

dep_maps = config.get("dep_maps", {})
modules = dep_maps.get("modules", [])
if not modules:
    sys.exit(0)

deps_dir = os.path.join(project_root, dep_maps.get("dir", ".claude/deps"))
stale_file = os.path.join(deps_dir, ".stale")

if not os.path.exists(stale_file):
    sys.exit(0)

# Check if there are actually stale modules
try:
    with open(stale_file) as f:
        stale = {line.strip() for line in f if line.strip()}
except Exception:
    sys.exit(0)

if not stale:
    sys.exit(0)

# Regenerate stale dep maps
deps_generate = os.path.join(scripts_dir, "deps-generate.py")
try:
    subprocess.run(
        [sys.executable, deps_generate, project_root, "--stale-only"],
        capture_output=True, text=True, timeout=30,
    )
except Exception:
    pass  # Best-effort — don't block session end
PYEOF
