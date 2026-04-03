---
stack:
  monorepo: false
  language: shell-python-markdown
  type: claude-code-plugin
disciplines:
  api_contracts: false
  plan_enforcement: true
  security: false
---

# Project Notes

## What This Repo Is

A single Claude Code plugin (`look-before-you-leap`) that enforces engineering discipline across all coding tasks. Not an application — changes here affect Claude's behavior in every project that installs it.

## Key File Categories

- **Hooks** (`look-before-you-leap/hooks/`): Shell scripts handling lifecycle events. Output JSON with `hookSpecificOutput`. Test with `bash -n` after editing.
- **Python libs** (`look-before-you-leap/hooks/lib/`): `detect-stack.py` (stack auto-detection), `read-config.py` (YAML parsing). No external deps - stdlib only.
- **Skills** (`look-before-you-leap/skills/`): SKILL.md files with YAML frontmatter. Four core skills: conductor, engineering-discipline, persistent-plans, brainstorming.
- **References** (`look-before-you-leap/skills/look-before-you-leap/references/`): Layer 2 checklists and Layer 3 deep guides, plus templates.
- **Scripts** (`look-before-you-leap/scripts/`): Plan directory init, status reporting, resumption helper, and direction-locked Codex entrypoints.

## Verification Commands

- Shell syntax: `bash -n <script.sh>`
- Python syntax: `python3 -c "import py_compile; py_compile.compile('<file.py>', doraise=True)"`
- Hook JSON output: Run the hook script and validate JSON structure
- Cross-platform: Test `stat` flags for both macOS (`-f '%m %N'`) and Linux (`-printf`)

## Blast Radius Areas

- `session-start.sh` — Changes affect EVERY session start across all projects
- `enforce-plan.sh` — Changes can block ALL file edits if broken
- `verify-plan-on-stop.sh` — Changes can prevent Claude from stopping
- `inject-subagent-context.sh` — Changes affect ALL sub-agent behavior
- SKILL.md files — Injected into context; size changes affect token budget
