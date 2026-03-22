---
name: "lbyl-implement"
description: "Implementation protocol for Codex-owned plan steps. Read plan.json for step description, files, and progress items. Read discovery.md for codebase context. Implement exactly what the step specifies — no scope additions, no scope cuts. Run verification after changes. Report FILES CHANGED, WHAT WAS DONE, VERIFICATION, ISSUES."
---

# Look Before You Leap — Implementation Protocol

You are implementing a plan step. Your job is to produce working code that
meets the step's acceptance criteria exactly.

---

## Step 1: Read the Plan

1. Read `plan.json` at the path given in the prompt
2. Find the step by its ID number
3. Extract:
   - `title` — what the step is about
   - `description` — what to implement (the specification)
   - `acceptanceCriteria` — concrete conditions your work must satisfy
   - `files` — which files to create or modify
   - `progress` — the sub-tasks to work through in order
4. Read `discovery.md` in the same directory for codebase context:
   - Scope, consumers, blast radius, existing patterns, conventions

---

## Step 2: Explore Before Editing

For each file you need to modify:

1. **Read the file** — understand its current structure and purpose
2. **Read its imports** — what does it depend on?
3. **Check sibling files** — how do adjacent files solve similar problems?
   Follow existing patterns for naming, error handling, return types
4. **Check consumers** — if you change an export, who imports this file?
   - If dep maps are configured (check `.claude/look-before-you-leap.local.md`):
     ```bash
     find ~/.claude/plugins -name "deps-query.py" -path "*/look-before-you-leap/*" 2>/dev/null | head -1
     python3 <path-to-deps-query.py> <project-root> "<file>"
     ```
   - If no dep maps, grep for import statements referencing the file

---

## Step 3: Implement

Work through the step's `progress` items in order. For each:

1. Make the changes described in the progress item's `task` field
2. Focus on the files listed in the progress item's `files` array
3. Follow existing codebase conventions — do not introduce new patterns

### Scope discipline

- **Implement exactly what the step description says** — no more, no less
- **Do NOT add features** not mentioned in the description
- **Do NOT refactor** surrounding code unless the step description asks for it
- **Do NOT skip items** from the progress array
- **If something is blocked**, report it explicitly in your final report —
  do not silently drop it

### Code quality

- No `any` or `as any` in TypeScript — figure out the correct type
- No swallowed errors (`.catch(() => {})` or `.catch(() => null)`)
- Install before import — verify packages exist in package.json
- Definitions before consumers — if adding a type, add it before using it

---

## Step 4: Verify

After completing all progress items:

1. **Type checker**: run `tsc --noEmit`, `bun run tsgo`, `mypy`, `cargo check`,
   or whatever the project uses (check `package.json`, `Makefile`, `pyproject.toml`)
2. **Linter**: run the project's linter if configured
3. **Tests**: run relevant tests (at minimum tests for files you changed)
4. **Consumer check**: if you modified shared code (types, utilities, exports),
   verify consumers still work — run deps-query on modified shared files
5. **Shell scripts**: run `bash -n` on any new or modified shell scripts

Fix any failures before reporting.

---

## Step 5: Report

Format your report exactly as:

```
FILES CHANGED:
- path/to/file1.ts (created|modified)
- path/to/file2.ts (created|modified)

WHAT WAS DONE:
- Progress item 1: <brief summary of what you did>
- Progress item 2: <brief summary of what you did>

VERIFICATION:
- Type checker: PASS|FAIL (with output if FAIL)
- Linter: PASS|FAIL|N/A
- Tests: PASS|FAIL|N/A (with output if FAIL)
- Consumer check: PASS|N/A

ISSUES:
- <any issues encountered, or "none">
```

---

## Rules

1. **Read before editing** — always read the target file and its imports first
2. **No scope creep** — only implement what the step describes
3. **No silent scope cuts** — if you cannot complete something, report it
4. **Follow patterns** — match existing codebase conventions
5. **Verify your work** — run the type checker and tests before reporting
6. **Be explicit** — your report is what Claude uses to verify your work
