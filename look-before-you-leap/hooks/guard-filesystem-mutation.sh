#!/usr/bin/env bash
# PreToolUse hook: Guard filesystem mutations in Bash commands.
#
# Classifies Bash commands as read-only, mutating, destructive, or file-writing:
#   - Read-only: cat, ls, grep, etc. → always allowed
#   - Mutating: rm, mv, cp, mkdir, rmdir → path-checked (allowed inside project)
#   - Destructive: rm -rf, rm -r, find -delete, git clean → requires receipt
#   - File-writing: redirects, sed -i, tee, dd, tar, unzip, nested bash → requires plan
#
# Path enforcement:
#   - Mutations targeting paths OUTSIDE the project root → denied (need cross_root_confirm receipt)
#   - Destructive mutations INSIDE the project → denied (need destructive_confirm receipt)
#   - File-writing without active plan → denied (same as enforce-plan for Edit/Write)
#   - Mutations inside .temp/ → always allowed
#   - Plugin-owned wrapper scripts → always allowed (via CLAUDE_PLUGIN_ROOT check)
#
# This hook subsumes enforce-plan-bash.sh (file-write detection + plan requirement).
#
# Input: JSON on stdin with tool_name, tool_input.command, cwd

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
hook_read_input

COMMAND=$(hook_get_command)

[ -z "$COMMAND" ] && exit 0

# --- Early allow: known plugin wrapper scripts ---
# NOTE: grant-bypass.sh is NOT in this list — it's blocked separately below.
WRAPPER_RE='(run-codex-verify|run-codex-implement|write-discovery-receipt|write-claude-verify-receipt|init-plan-dir|install-codex-skills)\.sh'
CMD_TRIMMED="${COMMAND#"${COMMAND%%[![:space:]]*}"}"
if [[ "$CMD_TRIMMED" =~ ^bash[[:space:]] ]] && [[ "$CMD_TRIMMED" =~ $WRAPPER_RE ]]; then
  if [[ "$CMD_TRIMMED" != *'&&'* && "$CMD_TRIMMED" != *'||'* && \
        "$CMD_TRIMMED" != *';'* && "$CMD_TRIMMED" != *'|'* ]]; then
    SCRIPT_PATH=$(echo "$CMD_TRIMMED" | awk '{print $2}' | tr -d '"'"'")
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [[ "$SCRIPT_PATH" == "${CLAUDE_PLUGIN_ROOT}/"* ]]; then
      exit 0
    fi
  fi
fi

# --- Block receipt-minting scripts (from enforce-plan-bash.sh) ---
# grant-bypass.sh is user-invocable only (via /bypass command). Claude must
# NOT call it directly — that would let Claude mint its own bypass receipts.
if [[ "$COMMAND" == *"grant-bypass.sh"* ]]; then
  python3 -c "
import json
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': (
            'BLOCKED: grant-bypass.sh is a user-only command. Claude cannot '
            'mint bypass receipts directly. Ask the user to run /bypass.'
        )
    }
}
json.dump(output, __import__('sys').stdout)
"
  exit 0
fi

# --- Early allow: known safe command prefixes (read-only or build tools) ---
# NOTE: echo/printf NOT in safe list — they can write files via redirects.
# The Python classifier handles them (detects redirect patterns).
SAFE_RE='^[[:space:]]*(cat|head|tail|less|more|wc|sort|uniq|diff|comm|file|stat|du|df|which|whereis|type|command|env|printenv|id|whoami|hostname|uname|date|uptime|ps|top|free|lsof|readlink|realpath|basename|dirname|test|true|false|\[|expr|seq|tr|cut|paste|fold|fmt|column|tac|rev|nl|od|xxd|hexdump|md5|md5sum|sha256sum|shasum|strings|git (status|log|show|diff|branch|remote|tag|rev-parse|rev-list|ls-files|ls-tree|describe|config|stash list|blame|shortlog|name-rev|merge-base|for-each-ref)|npm (list|ls|outdated|audit|info|view|search|help|config list)|yarn (list|info|why)|pnpm (list|ls)|rg |grep |bash -n |jq |yq |gh (pr|issue|run|release|api) )[[:space:]]'

if [[ "$CMD_TRIMMED" =~ $SAFE_RE ]]; then
  exit 0
fi

# --- Classify the command ---
# Pass via env to avoid quoting issues
export HOOK_COMMAND="$COMMAND"

HOOK_CWD=$(hook_get_cwd)

source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"
PROJECT_ROOT="$(find_project_root "${HOOK_CWD:-$PWD}")"
export HOOK_PROJECT_ROOT="$PROJECT_ROOT"
export HOOK_CWD="${HOOK_CWD:-$PWD}"

CLASSIFICATION=$(python3 << 'PYEOF'
import re, os, sys, json

cmd = os.environ.get("HOOK_COMMAND", "")
project_root = os.environ.get("HOOK_PROJECT_ROOT", "")
cwd = os.environ.get("HOOK_CWD", "") or project_root

if not cmd:
    print(json.dumps({"class": "safe", "paths": []}))
    sys.exit(0)

cmd_stripped = cmd.lstrip()

# --- Destructive patterns (require receipt even inside project) ---
DESTRUCTIVE_PATTERNS = [
    r'\brm\b.*\s-[a-zA-Z]*r[a-zA-Z]*f',    # rm -rf, rm -rfi, etc.
    r'\brm\b.*\s-[a-zA-Z]*f[a-zA-Z]*r',    # rm -fr
    r'\brm\b\s+-r\b',                        # rm -r (recursive without force)
    r'\bfind\b.*\s-delete\b',                # find -delete
    r'\bgit\b\s+clean\b',                     # git clean (any flags)
    r'\brm\b\s+-rf\s+\.',                    # rm -rf . (current dir wipe)
]

# --- Mutating patterns (path-checked, allowed inside project) ---
MUTATING_COMMANDS = [
    r'\brm\b\s',                # rm (non-recursive)
    r'\brmdir\b\s',             # rmdir
    r'\bmv\b\s',                # mv
    r'\bcp\b\s',                # cp
    r'\bmkdir\b\s',             # mkdir
    r'\bchmod\b\s',             # chmod
    r'\bchown\b\s',             # chown
    r'\bln\b\s',                # ln (symlinks)
    r'\binstall\b\s+-',         # install command
    r'\btar\b\s',                # tar (extract/create)
    r'\bunzip\b\s',              # unzip
    r'\bzip\b\s',                # zip
]

# --- File-writing patterns (require active plan, from enforce-plan-bash) ---
FILE_WRITE_PATTERNS = [
    r'[^-]>\s*\S',              # redirect: > file (but not ->)
    r'>>\s*\S',                  # append: >> file
    r'\bsed\b.*\s-i',           # sed in-place
    r'\bawk\b.*-i',             # awk in-place (gawk)
    r'\btee\b',                  # tee writes to files
    r'\bdd\b.*\bof=',           # dd output file
    r'\bpython[23]?\s+\S+\.py\b.*\b(open|write|Path)\b',  # python script with file writes
    r'\bpython[23]?\s+-c\b.*\b(open|write|Path)\b',      # python -c with file writes
    r'\bnode\b.*\b(writeFile|appendFile)',    # node file writes
    r'\bruby\b.*\bFile\.(write|open)\b',     # ruby file writes
    r'\bperl\b.*\bopen\b',                    # perl file writes
]

# --- Nested bash/sh script patterns (could write files) ---
# Match shell interpreter + any executable path (not just .sh extension)
NESTED_SCRIPT_PATTERNS = [
    r'\bbash\b\s+(?!-)[/.\w][\S]*',  # bash <path> (not flags like -n)
    r'\bsh\b\s+(?!-)[/.\w][\S]*',    # sh <path> (not flags)
    r'(?:^|[\s;|&])\./[\S]+',         # ./some-script (any extension or none)
]

def extract_paths(cmd_text):
    """Extract file/directory paths from a command string.

    Handles quoted paths and unquoted paths. Returns absolute paths
    where possible, resolving relative paths against project root.
    """
    paths = []
    # Match quoted strings and unquoted path-like tokens
    # Skip flags (tokens starting with -)
    tokens = []
    # Simple tokenizer: split on whitespace but respect quotes
    in_quote = None
    current = []
    for ch in cmd_text:
        if ch in ('"', "'") and in_quote is None:
            in_quote = ch
            current.append(ch)
        elif ch == in_quote:
            in_quote = None
            current.append(ch)
        elif ch in (' ', '\t') and in_quote is None:
            if current:
                tokens.append(''.join(current))
                current = []
        else:
            current.append(ch)
    if current:
        tokens.append(''.join(current))

    for token in tokens:
        # Strip quotes
        t = token.strip('"').strip("'")
        # Skip flags, operators, and command names
        if not t or t.startswith('-') or t in ('&&', '||', ';', '|', '>', '>>', '<'):
            continue
        # Keep tokens that look like paths
        if '/' in t or t.startswith('.') or t.startswith('~'):
            # Expand ~
            if t.startswith('~/'):
                t = os.path.expanduser(t)
            elif not os.path.isabs(t):
                t = os.path.join(cwd, t) if cwd else t
            paths.append(t)

    return paths


def is_inside_project(path, root):
    """Check if a path is inside the project root."""
    if not root:
        return True  # No root detected, can't enforce
    try:
        rp = os.path.realpath(path)
        rr = os.path.realpath(root)
        return rp.startswith(rr + '/') or rp == rr
    except (OSError, ValueError):
        return path.startswith(root + '/') or path == root


def is_temp_path(path, root):
    """Check if path is inside .temp/ directory."""
    if not root:
        return False
    try:
        rp = os.path.realpath(path)
        rr = os.path.realpath(root)
        temp = os.path.join(rr, '.temp')
        return rp.startswith(temp + '/') or rp == temp
    except (OSError, ValueError):
        return '.temp/' in path or path.endswith('.temp')


def classify_paths(paths):
    """Classify extracted paths into inside/outside root, filtering .temp."""
    outside = []
    inside = []
    for p in paths:
        if is_temp_path(p, project_root):
            continue  # .temp paths are always allowed
        if is_inside_project(p, project_root):
            inside.append(p)
        else:
            outside.append(p)
    return outside, inside


def get_effective_paths(cmd_text):
    """Extract paths from command, using project root as implicit path
    for commands that operate on cwd without explicit path args."""
    paths = extract_paths(cmd_text)
    if not paths and project_root:
        # Commands like 'git clean -fd' operate on cwd implicitly
        paths = [project_root]
    return paths


# Check destructive patterns first
for pattern in DESTRUCTIVE_PATTERNS:
    if re.search(pattern, cmd):
        paths = get_effective_paths(cmd)
        outside, inside = classify_paths(paths)
        result = {
            "class": "destructive",
            "paths": paths,
            "outside_root": outside,
            "inside_root": inside,
        }
        print(json.dumps(result))
        sys.exit(0)

# Check mutating patterns
for pattern in MUTATING_COMMANDS:
    if re.search(pattern, cmd):
        paths = get_effective_paths(cmd)
        outside, inside = classify_paths(paths)
        result = {
            "class": "mutating",
            "paths": paths,
            "outside_root": outside,
            "inside_root": inside,
        }
        print(json.dumps(result))
        sys.exit(0)

# Check file-writing patterns (redirects, sed -i, tee, etc.)
# Strip safe redirect patterns first (these don't create/modify real files)
cmd_for_write_check = re.sub(r'\d*&?>>?\s*/dev/null\b', '', cmd)
cmd_for_write_check = re.sub(r'\d+>&\d+', '', cmd_for_write_check)

# Allow if redirect target is inside .temp/
temp_redirect = re.search(r">\s*[\"']?[^\"']*[/.]temp/", cmd_for_write_check)

if not temp_redirect:
    for pattern in FILE_WRITE_PATTERNS:
        if re.search(pattern, cmd_for_write_check):
            print(json.dumps({"class": "file_write", "paths": []}))
            sys.exit(0)

    # Check nested bash scripts (could write files)
    for pattern in NESTED_SCRIPT_PATTERNS:
        if re.search(pattern, cmd):
            print(json.dumps({"class": "file_write", "paths": []}))
            sys.exit(0)

# Not a filesystem mutation
print(json.dumps({"class": "safe", "paths": []}))
PYEOF
) || true

# Parse classification
CLASS=$(echo "$CLASSIFICATION" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('class', 'safe'))
" 2>/dev/null) || CLASS="safe"

# Safe commands pass through
if [ "$CLASS" = "safe" ]; then
  exit 0
fi

OUTSIDE_ROOT=$(echo "$CLASSIFICATION" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(json.dumps(data.get('outside_root', [])))
" 2>/dev/null) || OUTSIDE_ROOT="[]"

INSIDE_ROOT=$(echo "$CLASSIFICATION" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(json.dumps(data.get('inside_root', [])))
" 2>/dev/null) || INSIDE_ROOT="[]"

# --- Check receipts and plan state ---
source "${BASH_SOURCE[0]%/*}/lib/receipt-state.sh"
receipt_bootstrap 2>/dev/null || true

PROJ_ID=$(receipt_project_id "$PROJECT_ROOT" 2>/dev/null) || true

# Find active plan ID for receipt checks
PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"
SESSION_PLAN=$(python3 "$PLAN_UTILS" find-for-session "$PROJECT_ROOT" "$PPID" 2>/dev/null) || true
PLAN_ID=""
if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
  PLAN_ID=$(receipt_plan_id "$SESSION_PLAN" 2>/dev/null) || true
fi

# --- Allow mutations where all paths are inside .temp/ (no paths flagged) ---
# Only applies to mutating/destructive — file_write is handled separately below
if [ "$CLASS" != "file_write" ] && [ "$OUTSIDE_ROOT" = "[]" ] && [ "$INSIDE_ROOT" = "[]" ]; then
  exit 0
fi

deny() {
  local reason="$1"
  python3 -c "
import json, sys
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': sys.argv[1]
    }
}
json.dump(output, sys.stdout)
" "$reason"
  exit 0
}

# --- File-writing commands: require active plan (mirrors enforce-plan for Edit/Write) ---
if [ "$CLASS" = "file_write" ]; then
  # Check for receipt-based bypass
  if [ -n "$PROJ_ID" ]; then
    BYPASS_DIR="${RECEIPT_STATE_ROOT}/${PROJ_ID}"
    if [ -d "$BYPASS_DIR" ]; then
      for plan_dir in "$BYPASS_DIR"/*/; do
        [ -d "$plan_dir" ] || continue
        if [ -f "${plan_dir}bypass-default.json" ]; then
          if receipt_verify_bypass "${plan_dir}bypass-default.json" "$PPID" 2>/dev/null; then
            exit 0
          fi
        fi
      done
    fi
  fi

  # Check for legacy .no-plan bypass
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
      new_count=$((bypass_count - 1))
      if [ "$new_count" -le 0 ]; then
        rm -f "$NO_PLAN_FILE"
      else
        echo "${bypass_pid}:${new_count}" > "$NO_PLAN_FILE"
      fi
      exit 0
    else
      rm -f "$NO_PLAN_FILE"
    fi
  fi

  # Check for active plan
  if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
    exit 0
  fi

  # No plan — deny
  deny "Bash command appears to write files, but no active plan exists for this session. Using Bash to bypass the Edit/Write plan enforcement is not allowed.\n\nThe enforce-plan hook exists for a reason. Do NOT work around it.\n\nTo proceed:\n1. Create a plan: write masterPlan.md to .temp/plan-mode/active/<plan-name>/masterPlan.md\n2. Use the Edit or Write tool (not Bash) to modify files\n\nFor trivial changes, ask the user to run /bypass."
fi

# --- Cross-root mutations: deny unless receipt exists ---
if [ "$OUTSIDE_ROOT" != "[]" ]; then
  if [ -n "$PROJ_ID" ] && [ -n "$PLAN_ID" ]; then
    if receipt_check cross_root_confirm "$PROJ_ID" "$PLAN_ID" 2>/dev/null; then
      # Receipt exists, allow
      :
    else
      deny "BLOCKED: Filesystem mutation targets paths outside the project root ($PROJECT_ROOT). Cross-project mutations require explicit user approval. Ask the user to run /bypass."
    fi
  else
    deny "BLOCKED: Filesystem mutation targets paths outside the project root ($PROJECT_ROOT). Cross-project mutations require explicit user approval. Ask the user to run /bypass."
  fi
fi

# --- Destructive mutations inside project: deny unless receipt exists ---
if [ "$CLASS" = "destructive" ] && [ "$INSIDE_ROOT" != "[]" ]; then
  if [ -n "$PROJ_ID" ] && [ -n "$PLAN_ID" ]; then
    # Check for destructive_confirm receipt OR bypass receipt
    if receipt_check destructive_confirm "$PROJ_ID" "$PLAN_ID" 2>/dev/null; then
      exit 0
    fi
    # Also check bypass receipt (bypass overrides all)
    BYPASS_DIR="${RECEIPT_STATE_ROOT}/${PROJ_ID}"
    if [ -d "$BYPASS_DIR" ]; then
      for plan_dir in "$BYPASS_DIR"/*/; do
        [ -d "$plan_dir" ] || continue
        if [ -f "${plan_dir}bypass-default.json" ]; then
          if receipt_verify_bypass "${plan_dir}bypass-default.json" "$PPID" 2>/dev/null; then
            exit 0
          fi
        fi
      done
    fi
  fi
  deny "BLOCKED: Destructive filesystem operation (rm -rf, rm -r, find -delete, git clean -f) inside project. Destructive mutations require explicit user approval. Ask the user to run /bypass."
fi

# --- Archive commands (tar/unzip/zip) inside project: require plan ---
# These write files during extraction, so they need a plan like file_write
if [ "$CLASS" = "mutating" ]; then
  ARCHIVE_RE='(^|[[:space:]])(tar|unzip|zip)([[:space:]]|$)'
  if [[ "$COMMAND" =~ $ARCHIVE_RE ]]; then
    if [ -n "$SESSION_PLAN" ] && [ -f "$SESSION_PLAN" ]; then
      exit 0
    fi
    deny "Archive command (tar/unzip/zip) requires an active plan. These commands extract or create files and need plan oversight.\n\nTo proceed:\n1. Create a plan first\n2. Or ask the user to run /bypass."
  fi
fi

# Mutating but inside project root (non-destructive, non-archive) → allowed
exit 0
