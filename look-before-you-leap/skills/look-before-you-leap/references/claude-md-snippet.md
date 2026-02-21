# Recommended CLAUDE.md Addition

Add this block to your project's `CLAUDE.md` to reinforce look-before-you-leap
behavior on every session.

---

```markdown
## Software Discipline

All tasks use the look-before-you-leap plugin. This is the default operating
mode — not optional.

### Plan Mode
- **Before editing code**: write a plan to `.temp/plan-mode/active/<plan-name>/masterPlan.md`
- **After any compaction**: IMMEDIATELY read the active plan — do not wait for user prompt
- **Every 2-3 file edits**: checkpoint — update Progress checklist in the plan on disk
- **After each step**: update the plan file on disk immediately
- **Check plan status**: `bash .temp/plan-mode/scripts/plan-status.sh`
- **Find what to resume**: `bash .temp/plan-mode/scripts/resume.sh`
- **Steps with >10 files or sweep keywords**: MUST get a sub-plan with Groups
- **Always ask**: "If compaction fired right now, could I resume from the plan file?"

### Verification
- Run type checker, linter, and tests after every task
- Check `references/verification-commands.md` for framework-specific commands
```
