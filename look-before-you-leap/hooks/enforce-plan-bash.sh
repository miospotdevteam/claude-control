#!/usr/bin/env bash
# PreToolUse hook: Block Bash file-writing commands that bypass Edit/Write hooks.
#
# Detects common file-writing patterns in Bash commands:
#   - Redirects: > >> (not inside git/npm/build commands)
#   - In-place edits: sed -i, awk -i
#   - File writers: tee, dd of=
#
# Allows:
#   - Commands targeting .temp/ paths
#   - Git commands, package managers, build tools, etc.
#   - Commands when .no-plan bypass is active
#   - Commands when an active plan exists
#
# Input: JSON on stdin with tool_name, tool_input.command, cwd

set -euo pipefail

INPUT=$(cat)

# Extract command and cwd from JSON input
COMMAND=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('tool_input', {}).get('command', ''))
" <<< "$INPUT" 2>/dev/null) || true

[ -z "$COMMAND" ] && exit 0

# --- Check if this command writes files ---
# Pass command via env var to avoid quoting issues with heredoc

export HOOK_COMMAND="$COMMAND"

IS_FILE_WRITE=$(python3 << 'PYEOF'
import re, os, sys

cmd = os.environ.get("HOOK_COMMAND", "")
if not cmd:
    print("no")
    sys.exit(0)

# Allowlisted command prefixes — these tools legitimately write files
ALLOWED_PREFIXES = [
    "git ", "npm ", "yarn ", "pnpm ", "bun ", "npx ", "bunx ",
    "pip ", "pip3 ", "cargo ", "go ", "poetry ",
    "make", "cmake", "gradle", "mvn ",
    "docker ", "docker-compose ",
    "brew ", "apt ", "apt-get ",
    "chmod ", "chown ",
    "mkdir ", "rmdir ", "rm ",
    "cp ", "mv ",
    "curl ", "wget ",
    "tar ", "unzip ", "zip ",
    "python3 -m pytest", "python3 -m pip", "python -m pytest", "python -m pip",
    "pytest ", "jest ", "vitest ", "mocha ",
    "eslint ", "prettier ", "ruff ", "mypy ", "tsc ",
    "bash -n ", "bash ",
]

# Check if command starts with an allowed tool
cmd_stripped = cmd.lstrip()
for prefix in ALLOWED_PREFIXES:
    if cmd_stripped.startswith(prefix):
        print("no")
        sys.exit(0)

# Allow if the redirect target is inside .temp/
if re.search(r">\s*[\"']?[^\"']*[/.]temp/", cmd):
    print("no")
    sys.exit(0)

# Detect file-writing patterns
WRITE_PATTERNS = [
    r"[^-]>\s*\S",       # redirect: > file (but not ->)
    r">>\s*\S",           # append: >> file
    r"\bsed\b.*\s-i",    # sed in-place
    r"\bawk\b.*-i",      # awk in-place (gawk)
    r"\btee\b",           # tee writes to files
    r"\bdd\b.*\bof=",    # dd output file
]

for pattern in WRITE_PATTERNS:
    if re.search(pattern, cmd):
        print("yes")
        sys.exit(0)

print("no")
PYEOF
) || true

# Not a file-writing command — allow
if [ "$IS_FILE_WRITE" != "yes" ]; then
  exit 0
fi

# --- It writes files. Check plan state (mirrors enforce-plan.sh) ---

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

HOOK_CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${HOOK_CWD:-$PWD}")"

# Check for explicit bypass
NO_PLAN_FILE="$PROJECT_ROOT/.temp/plan-mode/.no-plan"
if [ -f "$NO_PLAN_FILE" ]; then
  bypass_pid=$(cat "$NO_PLAN_FILE" 2>/dev/null) || true
  if [ -n "$bypass_pid" ] && kill -0 "$bypass_pid" 2>/dev/null; then
    exit 0
  else
    rm -f "$NO_PLAN_FILE"
  fi
fi

# Check for active plan — if one exists, allow
ACTIVE_DIR="$PROJECT_ROOT/.temp/plan-mode/active"
if [ -d "$ACTIVE_DIR" ]; then
  for plan in "$ACTIVE_DIR"/*/masterPlan.md; do
    if [ -f "$plan" ]; then
      exit 0
    fi
  done
fi

# No plan + file-writing Bash command — deny
python3 << 'PYEOF'
import json, sys

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "Bash command appears to write files, but no active plan exists. "
            "Using Bash to bypass the Edit/Write plan enforcement is not allowed.\n\n"
            "The enforce-plan hook exists for a reason. Do NOT work around it.\n\n"
            "To proceed:\n"
            "1. Create a plan: write masterPlan.md to "
            ".temp/plan-mode/active/<plan-name>/masterPlan.md\n"
            "2. Use the Edit or Write tool (not Bash) to modify files\n\n"
            "For trivial changes: echo $PPID > .temp/plan-mode/.no-plan"
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
