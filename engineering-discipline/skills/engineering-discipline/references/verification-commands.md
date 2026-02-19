# Verification Commands by Ecosystem

Quick reference for what to run after making changes. Always prefer the
project's own scripts (check package.json, Makefile, pyproject.toml) over
these generic commands.

## Node.js / TypeScript (bun, npm, pnpm)

```bash
# Type checking
bun run typecheck          # if script exists
npx tsc --noEmit           # direct tsc
bunx tsc --noEmit          # with bun

# Linting
bun run lint               # if script exists
npx eslint .               # direct eslint
npx eslint --fix .         # auto-fix

# Tests
bun test                   # bun test runner
npx vitest run             # vitest
npx jest                   # jest

# Build
bun run build              # if script exists
npx next build             # Next.js
```

## Python

```bash
# Type checking
mypy .
pyright .

# Linting
ruff check .
ruff check --fix .
flake8 .

# Tests
pytest
python -m pytest

# Formatting
ruff format .
black .
```

## Rust

```bash
# Type checking + compile
cargo check
cargo build

# Linting
cargo clippy

# Tests
cargo test

# Formatting
cargo fmt --check
```

## Go

```bash
# Build/compile check
go build ./...
go vet ./...

# Tests
go test ./...

# Linting
golangci-lint run
```

## General Tips

- Check `package.json` `scripts` section first — projects often have
  custom `typecheck`, `lint`, `test` scripts
- Check for `Makefile` with common targets
- Check `CLAUDE.md` or `README.md` for project-specific commands
- In monorepos, you may need to run checks from the specific package
  directory, not the root
- If the project uses a task runner (turbo, nx, moon), use that instead
  of running tools directly
