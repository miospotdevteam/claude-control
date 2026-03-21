#!/usr/bin/env bash
# PostToolUse hook: Auto-log errors and warnings from plugin scripts.
#
# Fires on every Bash PostToolUse but exits fast (pure bash) for
# non-plugin commands. Only spawns Python when a plugin script is
# detected in the command.
#
# Catches:
# - Crashes: non-zero exit (tool_response contains "Exit code")
# - Warnings: exit 0 but output contains "Warning:"
#
# Logs to ~/Projects/claude-code-setup/usage-errors/script-errors/
# and injects context telling Claude to stop and fix the issue.
#
# Input: JSON on stdin with tool_input.command, tool_response

set -euo pipefail

INPUT=$(cat)

# Fast bash-level check: does the command mention any plugin script?
# This avoids spawning Python for 99% of Bash commands.
case "$INPUT" in
  *plan_utils.py*|*deps-query.py*|*deps-generate.py*|*init-plan-dir.sh*|*plan-status.sh*|*resume.sh*|*look-before-you-leap/scripts/*)
    ;;
  *)
    exit 0
    ;;
esac

# Plugin script detected — use Python for structured parsing and logging.
# Write input to temp file to avoid env var size limits and heredoc conflicts.
# Fail-open: if mktemp or python fails, exit 0 so we don't break the
# original Bash command that triggered this hook.
TMPFILE=$(mktemp 2>/dev/null) || exit 0
trap 'rm -f "$TMPFILE"' EXIT
printf '%s' "$INPUT" > "$TMPFILE" 2>/dev/null || exit 0

export HOOK_TMPFILE="$TMPFILE"

python3 << 'PYEOF' || exit 0
import json, os, sys
from datetime import datetime

try:
    with open(os.environ["HOOK_TMPFILE"]) as f:
        data = json.loads(f.read())
except (json.JSONDecodeError, KeyError, FileNotFoundError):
    sys.exit(0)

LOG_BASE = os.path.expanduser("~/Projects/claude-code-setup/usage-errors/script-errors")

command = data.get("tool_input", {}).get("command", "")
response = str(data.get("tool_response", ""))

# Detect error type from response content
has_crash = any(marker in response for marker in [
    "Exit code", "Traceback", "Error:", "FileNotFoundError",
    "KeyError", "TypeError", "ValueError", "ModuleNotFoundError",
])
has_warning = "Warning:" in response

if not has_crash and not has_warning:
    sys.exit(0)

error_type = "CRASH" if has_crash else "WARNING"
severity = "HIGH" if has_crash else "MEDIUM"

# Identify which script
script_name = "unknown"
for marker in ["plan_utils.py", "deps-query.py", "deps-generate.py",
               "init-plan-dir.sh", "plan-status.sh", "resume.sh"]:
    if marker in command:
        script_name = marker
        break

# Log to disk
log_path = ""
try:
    os.makedirs(LOG_BASE, exist_ok=True)
    cwd = data.get("cwd", "")
    date_str = datetime.now().strftime("%Y-%m-%d")
    filename = f"{date_str}-{script_name.replace('.', '-')}-{error_type.lower()}.md"
    log_path = os.path.join(LOG_BASE, filename)

    with open(log_path, "a") as f:
        f.write(f"## {error_type}: {script_name} ({datetime.now().isoformat()})\n\n")
        f.write(f"- **Project**: {cwd}\n")
        f.write(f"- **Severity**: {severity}\n")
        f.write(f"- **Command**: `{command[:300]}`\n")
        f.write(f"- **Output**:\n```\n{response[:1000]}\n```\n\n---\n\n")
except OSError:
    pass  # fail-open: don't break the hook if logging fails

# Inject context to Claude
if has_crash:
    message = (
        f"PLUGIN SCRIPT ERROR — `{script_name}` crashed.\n\n"
        "**Do NOT ignore this.** The script crashed, which means the operation "
        "you attempted did not complete. Read the error output above, fix the "
        "root cause (wrong arguments? missing file? schema mismatch?), and "
        "retry the command.\n\n"
    )
else:
    message = (
        f"PLUGIN SCRIPT WARNING — `{script_name}` emitted a warning.\n\n"
        "**Do NOT ignore this.** Warnings from plugin scripts indicate "
        "something is incomplete or wrong. Read the warning, fix the issue "
        "(e.g., fill in the result field before marking done), then continue.\n\n"
    )

if log_path:
    message += f"Auto-logged to `{log_path}`.\n"

output = {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": message,
    }
}

json.dump(output, sys.stdout)
PYEOF
