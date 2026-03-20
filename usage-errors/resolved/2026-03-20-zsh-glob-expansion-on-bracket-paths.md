# zsh glob expansion on bracket paths breaks deps-query.py invocations

## What happened

When Claude invoked `deps-query.py` with a Next.js `[locale]` path as an
unquoted argument, zsh interpreted `[locale]` as a glob pattern (character
class). Since no files matched, zsh errored with:

```
(eval):1: no matches found: apps/web-merchant/src/app/[locale]/dashboard/public-page/page.tsx
```

## Hook/script that errored

- `deps-query.py` — never received the argument (zsh killed the command first)
- `remind-deps-query.sh` — suggested the unquoted command in its deny message

## Full error output

```
Error: Exit code 1
(eval):1: no matches found: apps/web-merchant/src/app/[locale]/dashboard/public-page/page.tsx
```

## Root cause

All documentation, hook messages, and skill text show `deps-query.py` usage
with unquoted `<file_path>` placeholders. Claude follows these examples and
generates unquoted commands. Zsh glob-expands brackets before Python sees them.

Affected files:
- `remind-deps-query.sh` line 90 — deny message shows unquoted path
- `session-start.sh` lines 380, 553 — dep map commands show unquoted paths
- `inject-subagent-context.sh` line 156 — subagent context shows unquoted path
- `engineering-discipline/SKILL.md` — 3 command examples unquoted
- `writing-plans/SKILL.md` — 1 command example unquoted
- `persistent-plans/SKILL.md` — 2 command examples unquoted
- `deps-query.py` docstring + usage message — unquoted
- `deps-generate.py` docstring + usage message — unquoted
- `dependency-mapping.md` — 2 command examples unquoted
- `generate-deps.md` — 1 command example unquoted

## Fix

Quote all `<file_path>` arguments in all examples, hook messages, and skill
text. Use double quotes: `"<file_path>"` — this prevents glob expansion while
allowing variable interpolation if needed.
