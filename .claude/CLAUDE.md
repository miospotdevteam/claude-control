# claude-code-setup

Three Claude Code plugins: `software-discipline` (unified, recommended), `engineering-discipline`, and `persistent-plans`. The unified plugin combines and extends the individual ones.

## Repo Layout

- `software-discipline/` — Unified plugin with three-layer architecture (conductor, checklists, deep guides)
- `engineering-discipline/` — Standalone behavioral override plugin (explore before editing, verify work, no shortcuts)
- `persistent-plans/` — Standalone workflow plugin (plans on disk survive context compaction)
- Plugins are symlinked to `~/.claude/plugins/` — when modifying files, the symlink keeps them in sync

## Editing Rules

- These are Claude Code plugins, not application code. Changes affect how Claude behaves across all projects.
- When editing any plugin file, verify the symlink at `~/.claude/plugins/<plugin-name>` points to the repo copy.
- Shell scripts must work on both macOS and Linux (different `stat` flags, `find` options, etc.).
- SKILL.md files use YAML frontmatter — keep the `description` field accurate when changing behavior.
- Do not install both `software-discipline` and the individual plugins simultaneously — they duplicate context injection.

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
