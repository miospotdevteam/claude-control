#!/usr/bin/env bash
# Initialize the .temp/plan-mode/ directory structure in the project root.
# Creates the directory, helper scripts, and .gitignore.
# Safe to run multiple times — only creates what's missing.
#
# Usage: bash <this-script>
# Called from the look-before-you-leap skill before creating the first plan.

set -euo pipefail

# Find project root: walk up from cwd looking for .git or CLAUDE.md
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  # Fallback to cwd if no markers found
  echo "$PWD"
}

PROJECT_ROOT="$(find_project_root)"
PLAN_DIR="$PROJECT_ROOT/.temp/plan-mode"
SCRIPTS_DIR="$PLAN_DIR/scripts"

# Create directories
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$PLAN_DIR/active"
mkdir -p "$PLAN_DIR/completed"

# Create .gitignore in .temp/ if it doesn't exist
GITIGNORE="$PROJECT_ROOT/.temp/.gitignore"
if [ ! -f "$GITIGNORE" ]; then
  cat > "$GITIGNORE" << 'GITIGNORE_EOF'
# AI working files - do not commit
*
GITIGNORE_EOF
  echo "Created $GITIGNORE"
fi

# Determine the plugin root to find script templates
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Copy plan-status.sh if missing or outdated
STATUS_SCRIPT="$SCRIPTS_DIR/plan-status.sh"
if [ ! -f "$STATUS_SCRIPT" ] || [ "$SCRIPT_DIR/plan-status.sh" -nt "$STATUS_SCRIPT" ]; then
  cp "$SCRIPT_DIR/plan-status.sh" "$STATUS_SCRIPT"
  chmod +x "$STATUS_SCRIPT"
  echo "Installed $STATUS_SCRIPT"
fi

# Copy resume.sh if missing or outdated
RESUME_SCRIPT="$SCRIPTS_DIR/resume.sh"
if [ ! -f "$RESUME_SCRIPT" ] || [ "$SCRIPT_DIR/resume.sh" -nt "$RESUME_SCRIPT" ]; then
  cp "$SCRIPT_DIR/resume.sh" "$RESUME_SCRIPT"
  chmod +x "$RESUME_SCRIPT"
  echo "Installed $RESUME_SCRIPT"
fi

echo "Plan directory ready at $PLAN_DIR"
