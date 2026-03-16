# Dependency Mapping

Instant dependency and consumer analysis using pre-generated maps from
[madge](https://github.com/pahen/madge). Replaces manual grep for
import/consumer discovery in TypeScript projects.

---

## Quick Start

```bash
# Query a file's dependencies and dependents (auto-regens if stale)
python3 <plugin>/scripts/deps-query.py <project_root> <file_path>

# Same, JSON output for machine consumption
python3 <plugin>/scripts/deps-query.py <project_root> <file_path> --json
```

The output shows:
- **DEPENDENCIES**: files this file imports
- **DEPENDENTS**: files that import this file (across ALL modules)
- **BLAST RADIUS**: count of direct consumers + which modules they're in

---

## Generation Commands

```bash
# Generate dep map for one module
python3 <plugin>/scripts/deps-generate.py <project_root> --module apps/api

# Generate all configured modules
python3 <plugin>/scripts/deps-generate.py <project_root> --all

# Generate only stale modules (marked by hook or mtime check)
python3 <plugin>/scripts/deps-generate.py <project_root> --stale-only
```

---

## Configuration

In `.claude/look-before-you-leap.local.md` YAML frontmatter:

```yaml
dep_maps:
  dir: .claude/deps                              # where dep maps live
  tool_cmd: "madge --json --extensions ts,tsx"   # madge command
  modules:                                        # modules to track
    - apps/api
    - apps/web-consumer
    - packages/shared
```

Each module gets its own dep map file: `deps-{slug}.json` where slug
replaces `/` with `-` (e.g., `deps-apps-api.json`).

Convention: madge uses `{module}/tsconfig.json` for resolution and
`{module}/src` as the source directory (falls back to `{module}` if no
`src/` exists).

---

## Staleness Mechanism

Dep maps stay fresh through two mechanisms:

1. **Hook-based marking**: The `mark-deps-stale.sh` PostToolUse hook fires
   on every `.ts/.tsx` edit. It determines which module the file belongs to
   (longest-prefix match) and appends the module slug to
   `.claude/deps/.stale`.

2. **mtime comparison**: `deps-generate.py --stale-only` also checks if
   any source file in a module is newer than its dep map file.

When `deps-query.py` runs, it checks `.stale` and auto-regenerates any
stale modules before returning results.

---

## When to Use

| Situation | Use dep maps? |
|---|---|
| Finding consumers of a .ts/.tsx file | Yes — primary method |
| Checking blast radius before modifying shared code | Yes |
| Finding what a file depends on (imports) | Yes |
| Cross-module consumer analysis (e.g., who uses packages/shared) | Yes — scans ALL maps |
| Searching for string references (env vars, config keys) | No — use Grep |
| Non-TypeScript files | No — use Grep |
| Dep maps not configured for project | No — use Grep |

---

## Dynamic Import Support

After madge generates the static import graph, a second pass scans all
source files for `import()` expressions with string literals. This catches
components loaded via:

- `import('./path')` — bare dynamic imports
- `React.lazy(() => import('./Component'))` — React lazy loading
- `dynamic(() => import('./Component'))` — Next.js dynamic
- `defineAsyncComponent(() => import('./Component'))` — Vue async components
- Any wrapper that uses `import('...')` with a string literal

Resolved paths use the same logic as static imports: relative paths,
tsconfig `paths` aliases, and `baseUrl`. Extension probing tries `.ts`,
`.tsx`, `.js`, `.jsx`, and `/index.*` variants.

**Still not tracked**: `import(variable)`, template literal imports
(`` import(`./path/${name}`) ``), and string-based references that don't
use `import()`.

---

## Limitations

- **TypeScript only**: madge parses TS/TSX imports. Other file types need
  manual grep.
- **Dynamic imports with variables**: `import(variable)` and template
  literal imports cannot be resolved at static analysis time. Only
  `import('string-literal')` patterns are tracked.
- **Re-exports**: madge follows re-exports through barrel files (index.ts),
  but the dep map shows the barrel as the consumer, not the final consumer.
  For deep analysis of barrel file consumers, query the barrel file itself.
- **Generated files**: files generated at build time (e.g., from codegen)
  won't appear until they exist on disk.

---

## Prerequisites

- **madge** installed (globally or via npx): `npm install -g madge`
- **TypeScript** project with tsconfig.json per module
- **dep_maps** section in `.claude/look-before-you-leap.local.md`

The generate script falls back to `npx madge` if the direct `madge`
command is not found.

---

## Output Format

### Human-readable (default)

```
FILE: packages/shared/src/types.ts
MODULE: packages/shared

DEPENDENCIES (3):
  packages/shared/src/constants.ts
  packages/shared/src/utils.ts
  packages/shared/src/validators.ts

DEPENDENTS (12):
  apps/api/src/routes/booking.ts
  apps/api/src/routes/merchant.ts
  apps/web-consumer/src/lib/api.ts
  ...

BLAST RADIUS: 12 direct consumer(s)
  Across 4 module(s): apps/api, apps/web-consumer, apps/web-merchant, packages/booking-logic
```

### JSON (`--json`)

```json
{
  "file": "packages/shared/src/types.ts",
  "found_in": "deps-packages-shared.json",
  "dependencies": ["packages/shared/src/constants.ts", "..."],
  "dependents": ["apps/api/src/routes/booking.ts", "..."]
}
```
