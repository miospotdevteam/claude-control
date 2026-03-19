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
#   - Commands when .no-plan-$PPID per-session counter-based bypass is active (max N edits)
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
    "cat ", "head ", "tail ", "wc ", "sort ", "uniq ", "diff ",
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
    # Scripting language file writes (prevent creative bypasses)
    # Only match python scripts that write to files (not stdin reads or -c inline)
    r"\bpython[23]?\s+\S+\.py\b.*\b(open|write|Path)\b",  # python3 script.py with file writes
    r"\bnode\b.*\b(writeFile|appendFile)",         # node -e "fs.writeFileSync..."
    r"\bruby\b.*\bFile\.(write|open)\b",         # ruby -e "File.write..."
    r"\bperl\b.*\bopen\b",                       # perl -e "open(F,'>file')..."
]

# Strip safe redirect patterns before checking (these don't create/modify real files)
# - Redirects to /dev/null: >/dev/null, 2>/dev/null, &>/dev/null, >>/dev/null, etc.
# - FD duplications: 2>&1, 1>&2
cmd_for_check = re.sub(r'\d*&?>>?\s*/dev/null\b', '', cmd)
cmd_for_check = re.sub(r'\d+>&\d+', '', cmd_for_check)

for pattern in WRITE_PATTERNS:
    if re.search(pattern, cmd_for_check):
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

source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

HOOK_CWD=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('cwd', ''))
" <<< "$INPUT" 2>/dev/null) || true

PROJECT_ROOT="$(find_project_root "${HOOK_CWD:-$PWD}")"

# Check for per-session bypass (counter-based: contains PID:remaining_edits)
NO_PLAN_FILE="$PROJECT_ROOT/.temp/plan-mode/.no-plan-$PPID"
if [ -f "$NO_PLAN_FILE" ]; then
  bypass_content=$(cat "$NO_PLAN_FILE" 2>/dev/null) || true
  if [[ "$bypass_content" == *:* ]]; then
    bypass_pid="${bypass_content%%:*}"
    bypass_count="${bypass_content##*:}"
  else
    rm -f "$NO_PLAN_FILE"
    bypass_pid=""
    bypass_count=""
  fi
  if [ -n "$bypass_pid" ] && [ "$bypass_pid" = "$PPID" ] && [ -n "$bypass_count" ]; then
    # Decrement counter
    new_count=$((bypass_count - 1))
    if [ "$new_count" -le 0 ]; then
      rm -f "$NO_PLAN_FILE"
    else
      echo "${bypass_pid}:${new_count}" > "$NO_PLAN_FILE"
    fi
    exit 0
  else
    # Wrong session or invalid format — stale bypass, remove it
    rm -f "$NO_PLAN_FILE"
    # Fall through to deny
  fi
fi

# PPID-scoped plan check: this session must have a claimed plan
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/skills/look-before-you-leap/scripts/plan_utils.py"
SESSION_PLAN=$(python3 "$PLAN_UTILS" find-for-session "$PROJECT_ROOT" "$PPID" 2>/dev/null) || true

if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
  exit 0
fi

# No plan for this session + file-writing Bash command — deny
python3 << 'PYEOF'
import json, sys

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "Bash command appears to write files, but no active plan exists for "
            "this session. Using Bash to bypass the Edit/Write plan enforcement "
            "is not allowed.\n\n"
            "The enforce-plan hook exists for a reason. Do NOT work around it.\n\n"
            "To proceed:\n"
            "1. Create a plan: write masterPlan.md to "
            ".temp/plan-mode/active/<plan-name>/masterPlan.md\n"
            "2. Use the Edit or Write tool (not Bash) to modify files\n\n"
            "For trivial changes (max 3 edits): echo \"$PPID:3\" > .temp/plan-mode/.no-plan-$PPID"
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
