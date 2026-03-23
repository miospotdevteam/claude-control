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

## Package & README Sync

- When a skill starts recommending a new npm package, add it to `look-before-you-leap/PACKAGES.md`.
- When a package is removed from skill guidance, remove it from PACKAGES.md.
- When adding new skills, reference files, or hooks, update the Repo Structure tree in `README.md`.
- Keep PACKAGES.md and README.md accurate — they are user-facing docs that must reflect the current state.

## Codex Findings Location

`usage-errors/codex-findings/` lives in THIS repo (claude-code-setup), not in the project being verified. This is intentional — findings feed back into plugin improvement (rule gaps, behavioral patterns) rather than being disposable per-project artifacts. Do NOT "fix" the path to point at the project repo.

## Codex Lessons Pipeline

`codex-lessons/` (repo root) tracks behavioral rules derived from Codex verification findings. When Codex catches a pattern that existing engineering-discipline rules should have prevented, the lesson is captured as a proposal and eventually promoted to a plugin rule.

- `proposals/` (gitignored) — new lessons awaiting review, may contain project-specific details
- `promoted/` — generalized lessons that became plugin rules (pattern, evidence, where promoted)
- After sessions where Codex finds genuine bugs, analyze root causes and write proposals for rule gaps
- During plugin maintenance, review proposals: generalize and promote to SKILL.md rules, or discard

## References

- Skill evaluation scaffold: `~/Projects/claude-tests` — use this project when running skill-creator evals

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
