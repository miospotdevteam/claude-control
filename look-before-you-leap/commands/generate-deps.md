---
description: "Generate or update dependency maps for all TypeScript modules. Auto-detects modules, configures dep_maps, and runs madge to build import/consumer maps used by the plugin for blast-radius analysis."
allowed-tools: ["Read", "Edit", "Write", "Bash", "Glob", "Grep", "AskUserQuestion"]
argument-hint: "[--update-only]"
---

# Generate Dependency Maps

Your task is to set up or update dependency maps for this project. Dep maps
let the plugin instantly answer "who depends on this file?" without grepping.

**Scripts directory**: `${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts`
**Config file**: `.claude/look-before-you-leap.local.md` (YAML frontmatter)
**Output directory**: `.claude/deps/` (default, configurable via `dep_maps.dir`)

If the user passed `$ARGUMENTS` containing `--update-only`, skip module
discovery and go straight to regenerating all existing maps (Step 4).

---

## Step 1: Read Existing Config

Read `.claude/look-before-you-leap.local.md` in the project root. Check if
a `dep_maps` section exists in the YAML frontmatter.

- If `dep_maps.modules` already has entries, note them as "existing modules"
- If no `dep_maps` section exists, this is a fresh setup

---

## Step 2: Discover TypeScript Modules

Scan the project to find all directories that are TypeScript modules. A
directory is a module if it contains TypeScript source files that should be
tracked as a dependency unit.

**Detection strategy:**

1. Find all `tsconfig.json` files (excluding `node_modules`):
   ```
   Glob for **/tsconfig.json, exclude node_modules
   ```

2. Find all `package.json` files (excluding `node_modules`):
   ```
   Glob for **/package.json, exclude node_modules
   ```

3. For each directory that has `tsconfig.json` OR `package.json`:
   - Check if it contains `.ts` or `.tsx` files (directly or in `src/`)
   - Skip the project root itself (that's not a module, it's the monorepo)
   - Skip directories that are clearly not source modules:
     - `node_modules/`
     - `.next/`, `.turbo/`, `dist/`, `build/`, `.cache/`
     - Directories with only config tsconfigs (e.g., `tsconfig.base.json`
       at root with no source files)

4. Determine module paths relative to project root. Common patterns:
   - `apps/<name>` — application modules
   - `packages/<name>` — shared library modules
   - `libs/<name>` — alternative lib directory
   - `services/<name>` — microservices
   - `src` — single-module project (module = project root subdir)

5. Merge with existing modules (if any). Flag:
   - **New modules** found that aren't in config yet
   - **Missing modules** in config that no longer exist on disk
   - **Unchanged modules** already configured

---

## Step 3: Confirm with User

Present the discovered modules to the user. Show:

- Total modules found
- The full list, grouped by type (apps, packages, etc.)
- Which are new vs already configured
- Any that were in config but no longer exist on disk

Use AskUserQuestion to let the user confirm or adjust. Offer options:
- Accept all discovered modules
- Select specific modules to include/exclude
- (If modules already configured) Keep existing config, only add new ones

---

## Step 4: Update Config

Update `.claude/look-before-you-leap.local.md` with the confirmed module
list. The YAML frontmatter should have:

```yaml
dep_maps:
  dir: .claude/deps
  tool_cmd: "madge --json --extensions ts,tsx"
  modules:
    - apps/api
    - apps/web
    - packages/shared
```

**Rules for editing the config:**
- If the file doesn't exist, create it with the frontmatter
- If it exists but has no `dep_maps` section, add it to the frontmatter
- If it exists with `dep_maps`, update the `modules` list
- Preserve all other frontmatter fields (stack, disciplines, etc.)
- Keep modules sorted alphabetically
- Ensure `.claude/deps` is in `.gitignore` (check and add if missing)

---

## Step 5: Generate All Maps

Run the generation script for all configured modules:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/deps-generate.py <project_root> --all
```

This will:
- Run madge for each module
- Normalize paths to repo-relative
- Write `deps-{slug}.json` files to `.claude/deps/`
- Report per-module status (OK with file count, or FAILED with reason)

If madge is not installed globally, the script falls back to `npx madge`
automatically.

**If any module fails**: Note the failure but continue with remaining
modules. Report failures at the end.

---

## Step 6: Report Results

Summarize what was done:

- How many modules configured
- How many maps generated successfully
- Per-module file counts (how many files in each map)
- Any failures and why
- Total files tracked across all maps

Show the query command so the user can try it:
```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/deps-query.py <project_root> "<any-file-path>"
```

Mention that dep maps auto-refresh: the `mark-deps-stale.sh` hook marks
modules stale when `.ts/.tsx` files are edited, and `deps-query.py`
auto-regenerates stale maps before returning results.
