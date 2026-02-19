# claude-code-setup

Two Claude Code plugins: `engineering-discipline` and `persistent-plans`. They work together to make Opus behave like a disciplined engineer.

## Repo Layout

- `engineering-discipline/` — Behavioral override plugin (explore before editing, verify work, no shortcuts)
- `persistent-plans/` — Workflow plugin (plans on disk survive context compaction)
- Both plugins are also installed at `~/.claude/plugins/` — when modifying files, update both the repo copy and the installed copy

## Editing Rules

- These are Claude Code plugins, not application code. Changes affect how Claude behaves across all projects.
- When editing any file under `persistent-plans/` or `engineering-discipline/`, always copy the modified file to the corresponding path under `~/.claude/plugins/` and verify with `diff`.
- Shell scripts must work on both macOS and Linux (different `stat` flags, `find` options, etc.).
- SKILL.md files use YAML frontmatter — keep the `description` field accurate when changing behavior.

## Plan Mode

All tasks use persistent plans in `.temp/plan-mode/`. This is the default operating mode — not optional.

- **Before editing code**: write a plan to `.temp/plan-mode/active/<plan-name>/masterPlan.md`
- **After any compaction**: IMMEDIATELY read the active plan — do not wait for user prompt
- **Every 2-3 file edits**: checkpoint — update Progress checklist in the plan on disk
- **After each step**: update the plan file on disk immediately
- **Check plan status**: `bash .temp/plan-mode/scripts/plan-status.sh`
- **Find what to resume**: `bash .temp/plan-mode/scripts/resume.sh`
- **Steps with >10 files or sweep keywords**: MUST get a sub-plan with Groups
- **Always ask**: "If compaction fired right now, could I resume from the plan file?"
