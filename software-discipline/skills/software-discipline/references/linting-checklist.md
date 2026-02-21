# Linting Checklist

## Before

- [ ] Identify the project's linter (check package.json, .eslintrc, ruff.toml, .golangci.yml)
- [ ] Find the lint command (package.json scripts, Makefile, pyproject.toml)
- [ ] Check for formatter config (Prettier, Black, rustfmt, gofmt)
- [ ] Note any project-specific lint rules or custom plugins

## During

- [ ] Follow existing code style — match the file you're editing, not your preference
- [ ] Don't add `eslint-disable`, `noqa`, or `#[allow]` without a documented reason
- [ ] If a lint rule is genuinely wrong for this case, explain why in a comment
- [ ] Auto-fixable issues: use the auto-fix command, don't fix manually
- [ ] Non-auto-fixable issues: fix them before moving on, don't accumulate

## After

- [ ] Run the project's lint command on changed files
- [ ] Run the formatter if the project uses one
- [ ] Fix any new warnings you introduced — don't leave them for the next person
- [ ] If you disabled any lint rules, verify the justification is documented

## Red Flags

| Pattern | Problem |
|---|---|
| `// eslint-disable-next-line` with no comment | Hiding a real issue |
| Reformatting untouched code | Noisy diff, harder to review |
| Ignoring lint warnings "because they're just warnings" | Warnings accumulate into debt |
| Using a different style than the rest of the file | Inconsistency |
| Adding lint exceptions to fix type errors | Masking a deeper problem |
| Not running the linter at all | Shipping code that fails CI |
