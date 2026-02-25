---
name: refactoring
description: "Use when refactoring, restructuring, extracting, reorganizing, renaming across files, or moving files. Two modes: Full Mode (4-phase refactoring with pre/post contract that catches missed consumers, stale imports, and dead code) and Quick Mode (post-execution simplification pass dispatched after plan steps with `Simplify: true`). Full Mode for intentional refactoring tasks; Quick Mode replaces standalone code-simplifier. Addresses Claude's #1 refactoring failure: incomplete refactoring where consumers, imports, or dead code are left behind. Do NOT use for: single-variable renames within one function, formatting-only changes, changes that don't cross file boundaries (use engineering-discipline directly), or adding new features disguised as refactoring."
---

# Refactoring

Claude's #1 refactoring failure mode: **incomplete refactoring**. You rename
a function but miss 3 consumers. You move a file but leave stale imports.
You extract a module but forget to delete the dead code. The fix: a contract
that catalogs everything before you start, so you can verify everything after
you finish.

This skill has two modes:

- **Full Mode** (Phases 1-4) — For intentional refactoring tasks. Builds a
  contract before changes, verifies against it after.
- **Quick Mode** — For post-step simplification. Dispatched by the conductor
  after plan steps with `Simplify: true`. Progressive, least-invasive-first
  cleanup.

---

## Prerequisites

- An active plan must exist in `.temp/plan-mode/active/`. If none exists,
  create one before proceeding (enforcement hooks will block edits without
  one).
- For Full Mode: the exploration phase (conductor Step 1) should already be
  complete — the contract builds on discovery findings.
- For Quick Mode: a passing test baseline is required before any changes.
  If tests fail pre-existing, stop and report.

---

## Full Mode

Use when the user asks you to refactor, restructure, extract, reorganize,
rename across files, or move files. The 4 phases ensure nothing gets left
behind.

### Phase 1: Inventory (Build the Contract)

Before touching any code, catalog everything that will be affected.

Create `refactoring-contract.md` in the active plan directory:

```markdown
# Refactoring Contract: <brief description>

## Targets (what's being refactored)
- [ ] `path/to/file.ts` — function `oldName` (line 42)
- [ ] `path/to/other.ts` — class `Widget` (lines 10-85)

## Exports affected
- [ ] `oldName` from `path/to/file.ts` — used by 4 consumers
- [ ] `Widget` from `path/to/other.ts` — used by 2 consumers

## Consumers (every file that imports/uses a target)
- [ ] `src/routes/dashboard.tsx:7` — imports `oldName`
- [ ] `src/lib/analytics.ts:23` — imports `oldName`
- [ ] `src/components/Panel.tsx:5` — imports `Widget`
- [ ] `tests/file.test.ts:3` — imports `oldName`

## Tests covering targets
- [ ] `tests/file.test.ts` — tests `oldName` directly
- [ ] `tests/dashboard.test.ts` — tests route that uses `oldName`

## Expected after-state
- `oldName` → `newName` everywhere (0 remaining references to `oldName`)
- `Widget` moved to `src/components/Widget.ts` (0 imports from old path)
```

**How to build it:**

1. **List targets** — the specific functions, classes, types, files being
   refactored
2. **Find all exports** — what does each target expose that others depend on?
3. **Find every consumer** — if dep maps are configured, you MUST use
   `deps-query.py` for instant DEPENDENTS (do NOT grep for consumers when
   dep maps exist); otherwise grep for import statements, direct references,
   re-exports. If `deps-query.py` fails or returns no results, fall back to
   grep-based consumer search and note the tool failure in the contract. Be
   thorough: search for the function name, the file path in imports, type
   references, and string references
4. **Find all tests** — tests that directly test the targets AND tests that
   exercise code paths through the targets
5. **Define the expected after-state** — what should be true when you're done?
   Express as zero-reference assertions (e.g., "0 remaining references to
   `oldName`")

The contract is your checklist. Every item gets checked off during execution
and verified during Phase 4.

### Phase 2: Classify and Scope

Categorize the refactoring to set expectations and scope boundaries.

**Categories:**

| Type | What changes | Typical blast radius |
|---|---|---|
| **Rename** | Names only (variables, functions, types, files) | Every consumer of the renamed symbol |
| **Extract** | Code moves into a new module/function/class | Original file + new file + consumers of extracted code |
| **Move** | Files/code relocates to a different path/module | Every import of the moved file |
| **Restructure** | Internal organization changes (split/merge files, reorder modules) | All files in the affected directory + their consumers |

**Set the scope boundary:**

- List exactly which files are in scope
- List files that are explicitly OUT of scope (adjacent but not affected)
- If the refactoring could cascade (rename triggers import changes that
  trigger re-exports), map the full cascade chain before starting — use
  `deps-query.py` (MUST use when dep maps are configured) to trace the chain
  instantly — do NOT grep for consumers when dep maps exist

**Rule: if the blast radius exceeds 10 files, create a sub-plan with groups.**
Do not attempt a 15-file refactoring as one step.

### Phase 3: Execute with Contract Awareness

**User confirmation gate:** If the contract's blast radius exceeds 5 files,
present the contract summary to the user and wait for confirmation before
proceeding. For 5 files or fewer, proceed autonomously.

Apply changes methodically. For each target in the contract:

1. **Make the change** to the target file
2. **Update every consumer** listed in the contract for that target
3. **Update every test** listed in the contract for that target
4. **Check off** the target, its consumers, and its tests in the contract
5. **Grep again** after updating — search for any references you missed
   during inventory (new consumers discovered during execution get added
   to the contract and handled immediately)

**Execution order** (minimizes broken intermediate states):

- **Rename**: Change definition first, then update all consumers, then tests
- **Extract**: Create the new module first, update the original to delegate,
  then update consumers to import from new location
- **Move**: Create at new location first, update imports, then delete old
  location
- **Restructure**: Add new structure first, migrate contents, update
  consumers, then remove old structure

**After every 2-3 file edits**, update both the refactoring contract AND
the masterPlan progress.

### Phase 4: Verify Against Contract

After all changes are applied:

1. **Walk the contract** — every checkbox must be checked. If any item is
   unchecked, go back and handle it
2. **Grep for stale references** — search for the OLD names, OLD paths,
   OLD imports. There should be zero matches (except comments explaining
   the rename, if any)
3. **Grep for dead code** — search for functions/exports that were part of
   the old structure but are no longer imported by anyone. Delete them
4. **Run tests** — all tests that passed before must still pass. Any new
   failures indicate missed consumers or incorrect updates
5. **Run type checker** — catches stale type references that grep might miss
6. **Run linter** — catches unused imports, unused variables from incomplete
   cleanup
7. **Final contract status** — update `refactoring-contract.md` with results:
   ```
   ## Verification
   - Stale references: 0 (grepped for `oldName`, `old/path`)
   - Dead code removed: `unusedHelper` from `utils.ts`
   - Tests: 47 passed (same as baseline)
   - Type checker: clean
   - Linter: clean
   ```

---

## Quick Mode

Use when the conductor dispatches you as a sub-agent after a plan step with
`Simplify: true`. You are a refinement pass — make code clearer, more
consistent, and simpler without changing behavior.

**Announce at start:** "Running refactoring quick mode on Step N."

### QM Phase 1: Discover Conventions

Before touching any code, learn what "good" looks like in this project.

1. **Read CLAUDE.md** (project root) — coding standards, naming conventions,
   formatting rules, preferred patterns
2. **Read `.claude/look-before-you-leap.local.md`** — check for a
   `simplifier` section in the YAML frontmatter with project-specific
   preferences:
   ```yaml
   simplifier:
     prefer_explicit_returns: true
     max_function_length: 50
     prefer_named_exports: true
   ```
3. **Read 2-3 sibling files** near the modified code — learn the implicit
   conventions the project actually follows (these override your defaults)

If CLAUDE.md and sibling files disagree, follow CLAUDE.md. If CLAUDE.md is
silent, follow sibling file patterns. If both are silent, use your judgment.

### QM Phase 2: Establish Test Baseline

Before making any simplification edits:

1. **Find the project's test command** — check `package.json` scripts,
   `Makefile`, `pyproject.toml`, `CLAUDE.md`, or `README.md`
2. **Run the full test suite** (or the relevant subset for the modified files)
3. **Record the result** — all tests must pass. If any tests fail before you
   start, STOP. Report the pre-existing failures and do not proceed.

This baseline proves any subsequent test failure was caused by your changes.

### QM Phase 3: Progressive Neighborhood Discovery

Expand your scope iteratively from the modified files outward.

**Ring 0: Modified files** — Read all files listed in the step's "Files
involved" field. These are your primary targets.

**Ring 1: Direct imports and consumers** — For each modified file: read its
imports (what does it depend on?), grep for consumers (who imports this
file?), read each direct neighbor.

**Ring N: Propagation** — If a simplification in Ring 0 or 1 propagates
(e.g., renaming an export requires updating consumers), follow that file's
imports and consumers.

**Hard scope limits:**
- Quick Mode MUST NOT modify more than 10 files total. If simplification
  opportunities require touching more files, report them as recommendations
  and stop.
- Do NOT expand beyond Ring 1 unless a Ring 0/1 change mechanically requires
  it (e.g., renaming an export forces updating its consumers).

**Stop condition:** Stop expanding when no new simplification opportunities
are discovered at the current ring. Track which files you've read to avoid
cycles.

### QM Phase 4: Simplify

Apply simplifications in order from least to most invasive. After each
level, consider whether the next level is warranted.

**Level 1: Cosmetic**
- Rename variables and functions for clarity (match project conventions)
- Remove dead code (unused imports, unreachable branches, commented-out code)
- Consolidate duplicate imports
- Fix formatting inconsistencies with surrounding code
- Simplify boolean expressions and conditionals

**Level 2: Structural**
- Extract repeated logic into functions (only if used 3+ times)
- Flatten unnecessary nesting (early returns, guard clauses)
- Merge related logic that was unnecessarily split
- Remove unnecessary abstractions (wrappers that just pass through)
- Simplify control flow (reduce cyclomatic complexity)

**Level 3: Internal APIs** *(requires user confirmation before applying)*
- Adjust function signatures between internal modules for consistency
- Reorganize exports within a file for logical grouping
- Merge or split files when it improves cohesion (rare — only when clear)

**When to stop:** If you reach Level 2 and the code is already clean, stop.
If a simplification is ambiguous (reasonable people could disagree), skip it.
If a simplification would make a diff hard to review, skip it.

### QM Phase 5: Verify

After all simplifications:

1. **Run the same test command** from QM Phase 2
2. **Compare results** — all tests that passed before must still pass
3. **If any test fails:** identify which simplification caused it, revert
   that specific change, re-run tests to confirm green, note the reverted
   change in your report
4. **If all tests pass:** proceed to reporting

### QM Phase 6: Report

Summarize what you did. The conductor records this in the step's Result
field.

```
Simplification pass on Step N:
- [Level 1] <what you changed> (files: ...)
- [Level 2] <what you changed> (files: ...)
- Reverted: <anything that broke tests>
- Skipped: <anything you considered but chose not to change, and why>
Tests: all passing (N tests, same as baseline)
```

---

## Boundaries

### What you CAN do
- Rename variables, functions, and internal types for clarity
- Remove dead code, simplify conditionals, flatten nesting
- Extract or inline functions within internal modules
- Change internal function signatures (not public API)
- Reorganize file contents (imports, export order, logical grouping)
- Merge or split internal files for better cohesion
- Move files to better locations (with full consumer updates)

### What you CANNOT do
- Change public API boundaries (anything exported from package/library entry)
- Remove or alter functionality (behavior must be identical)
- Add new dependencies
- Change test assertions (tests are the invariant, not the subject)
- Add new features or functionality
- Change configuration files (tsconfig, package.json, build config) unless
  the refactoring requires it (e.g., path alias updates after file moves)
- Modify files outside the declared scope without expanding the contract

### When in doubt
If you're unsure whether a change is safe, skip it. The goal is confident
refactoring with a verified contract, not maximum diff size. A small, safe
refactoring is better than an ambitious one that leaves orphaned references.

---

## Acceptance Criteria

### Full Mode
- [ ] `refactoring-contract.md` exists with all targets, consumers, and tests
- [ ] Every contract checkbox is checked off
- [ ] Zero stale references (grep for old names/paths confirms)
- [ ] Zero dead code left behind (grep for orphaned exports confirms)
- [ ] All tests passing (same count as baseline)
- [ ] Type checker clean
- [ ] Linter clean
- [ ] Contract updated with final Verification section

### Quick Mode
- [ ] Test baseline established before any changes
- [ ] No more than 10 files modified
- [ ] All tests passing after changes (same count as baseline)
- [ ] Any test-breaking changes reverted and noted
- [ ] Report written with changes by level, reverts, and skips

---

## Principles

- **The contract is the source of truth** — if it's not in the contract, it
  doesn't get refactored; if it's in the contract, it must be verified
- **Zero stale references** — grep for old names/paths after every refactoring;
  the target is always zero
- **Behavior preservation is non-negotiable** — tests before and after must
  match
- **Convention over preference** — follow the project's patterns, not yours
- **Progressive discovery** — start narrow, expand only as needed (Quick Mode)
- **Least invasive first** — cosmetic before structural before API changes
  (Quick Mode)
- **When in doubt, don't** — skip ambiguous changes
