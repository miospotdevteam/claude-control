# claude-code-setup

Single Claude Code plugin: `look-before-you-leap`. Enforces structured exploration, persistent plans, disciplined execution, and multi-discipline coverage for all coding tasks.

## Repo Layout

- `look-before-you-leap/` — The plugin (three-layer architecture: conductor, checklists, deep guides)
- Everything else is in `look-before-you-leap/` — hooks, skills, references, scripts

## Editing Rules

- These are Claude Code plugins, not application code. Changes affect how Claude behaves across all projects.
- Shell scripts must work on both macOS and Linux (different `stat` flags, `find` options, etc.).
- SKILL.md files use YAML frontmatter — keep the `description` field accurate when changing behavior.
- Test hooks with `bash -n` after editing. Test Python sections by running the hook and checking JSON output.

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
