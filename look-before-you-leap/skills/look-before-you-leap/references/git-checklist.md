# Git Checklist

## Before

- [ ] Check `git status` — know the current state before making changes
- [ ] Check current branch — are you on the right one?
- [ ] Check for uncommitted work from previous tasks
- [ ] If starting a feature: consider creating a feature branch

## During

- [ ] Commit after each meaningful chunk of work (completed step, working feature)
- [ ] Write commit messages that explain WHY, not just WHAT
- [ ] Don't mix unrelated changes in one commit (bug fix + feature = two commits)
- [ ] Stage specific files, not `git add .` (avoid accidentally committing secrets or temp files)
- [ ] Never commit `.env`, credentials, or large binary files

## After

- [ ] Run `git status` to confirm only intended files were committed
- [ ] Verify no sensitive files were accidentally staged
- [ ] If creating a PR: write a clear title and description
- [ ] Check if the branch needs to be pushed

## Red Flags

| Pattern | Problem |
|---|---|
| `git add .` or `git add -A` without checking status | Risk of committing secrets |
| Commit message: "fix" or "update" | No context for future readers |
| Multiple unrelated changes in one commit | Hard to review, hard to revert |
| Force-pushing without asking the user | Can destroy remote history |
| Committing without being asked | Premature — user may want to review |
| `.env` or credentials in staged files | Security breach |
| Amending when the previous commit wasn't yours | Rewriting shared history |

## Commit Message Format

```
<type>: <short description of WHY>

<optional body with details>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`

Good: `fix: prevent double-submit on payment form by disabling button after click`
Bad: `fix: update button`
