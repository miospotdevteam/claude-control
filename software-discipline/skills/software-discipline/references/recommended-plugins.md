# Recommended Plugins

Official Anthropic plugins from `claude-plugins-official`. Suggest these
during first-run onboarding based on the detected stack.

## Universal (recommend for all projects)

| Plugin | What it does |
|---|---|
| `commit-commands` | `/commit`, `/commit-push-pr`, branch cleanup |
| `pr-review-toolkit` | Parallel PR review with 5 specialized agents |
| `code-review` | Code review a pull request |
| `claude-md-management` | Audit and improve CLAUDE.md files |
| `hookify` | Create hooks to prevent unwanted behaviors |
| `context7` | Up-to-date library docs via MCP |

## Stack-specific

| Plugin | When to suggest | Detected by |
|---|---|---|
| `typescript-lsp` | TypeScript projects | `stack.language == "TypeScript"` |
| `pyright-lsp` | Python projects | `stack.language == "Python"` |
| `frontend-design` | Projects with a frontend framework | `stack.frontend` is set |
| `security-guidance` | Projects handling auth, APIs, user data | `disciplines.security == true` |
| `feature-dev` | Larger projects that benefit from guided development | Always suggest |
| `plugin-dev` | Only if user is developing Claude Code plugins | Ask user |
| `agent-sdk-dev` | Only if user is building Agent SDK apps | Ask user |

## Niche (mention but don't push)

| Plugin | When |
|---|---|
| `code-simplifier` | User wants automated code simplification |
| `skill-creator` | User wants to create custom skills |

## Install command

```
claude plugin install <name>@claude-plugins-official --scope <scope>
```

Scopes:
- `user` — available in all your projects (recommended default)
- `project` — only this repository (stored in `.claude/plugins.json`)
