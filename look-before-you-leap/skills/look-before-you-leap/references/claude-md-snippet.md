# Recommended CLAUDE.md Addition

Add this block to your project's `CLAUDE.md` to reinforce look-before-you-leap
behavior on every session.

---

```markdown
## Software Discipline

All tasks use the look-before-you-leap plugin. This is the default operating
mode — not optional.

### Plan Mode
- **Before editing code**: write a plan to `.temp/plan-mode/active/<plan-name>/plan.json` and `masterPlan.md`
- **After any compaction**: IMMEDIATELY read the active plan — do not wait for user prompt
- **Every 2-3 file edits**: checkpoint — update progress via `plan_utils.py` (writes to `progress.json`)
- **After each step**: update progress on disk immediately via `plan_utils.py`
- **Check plan status**: `bash .temp/plan-mode/scripts/plan-status.sh`
- **Find what to resume**: `bash .temp/plan-mode/scripts/resume.sh`
- **Steps with >10 files or sweep keywords**: MUST get a sub-plan with Groups
- **Always ask**: "If compaction fired right now, could I resume from plan.json + progress.json?"

### Verification
- Run type checker, linter, and tests after every task
- Strict plans must use `plan_utils.py complete-step` so verification receipts are checked before a step is marked done
- Check `references/verification-commands.md` for framework-specific commands
```
