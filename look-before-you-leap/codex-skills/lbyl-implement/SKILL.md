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

Your output is consumed by `run-codex-implement.sh`. It is both a human
trace and the source for `<plan-dir>/codex-receipt-step-N.json`.

You MUST emit:

1. The exact human-readable sections below.
2. A final fenced JSON block with this exact delimiter:

````text
```codex-receipt-v1
{ ...valid JSON... }
```
````

The fenced block MUST be the last block in the response. Do not put prose
inside the fence. Do not emit more than one `codex-receipt-v1` fence.

### Human section contract

Format your human trace exactly as:

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

The section headings are exact and all-caps. Keep each item on a single
line when possible so the wrapper can lift section bodies into the receipt
artifact.

### Receipt JSON contract

The fenced JSON block MUST match `look-before-you-leap/references/codex-receipt-schema.md`
schema version `1.0.0`.

Required top-level fields:
- `schemaVersion`: exactly `"1.0.0"`
- `kind`: exactly `"implement"`
- `stepId`: numeric plan step id
- `owner`: step owner from `plan.json`
- `mode`: step mode from `plan.json`
- `planName`: plan `.name`
- `codexExitCode`: `0` when Codex completed normally
- `criteria`: one entry per acceptance criterion
- `filesChanged`: structured version of the `FILES CHANGED` section
- `findings`: `[]` on clean implementation, otherwise structured issue objects
- `finalVerdict`: `"PASS"` or `"FINDINGS"`; use `"FAIL"` only when Codex
  itself could not complete implementation
- `generatedAt`: UTC ISO-8601 timestamp

Optional but preferred fields:
- `projectRoot`, `planPath`
- `resultTxtPath`, `resultTxtSha256`
- `streamJsonlPath`, `streamJsonlSha256`
- `commands`
- `digestHints`

Each `criteria[]` item MUST include:
- `id`: 1-based criterion index
- `acceptanceCriterion`: verbatim criterion text from `plan.json`
- `acceptanceCriterionSha256`: sha256 of the normalized criterion text
- `verdict`: `"PASS"`, `"FAIL"`, or `"SKIPPED"`
- `evidence`: array of addressable evidence

For file evidence, use:
- `type`: `"file"`
- `file`: project-relative path
- `lineStart` and `lineEnd`: the evidence range; these are the schema fields
  for the required `evidence[].range`
- `sha256`: sha of the referenced file or relevant excerpt when available

For command evidence, use:
- `type`: `"command"`
- `command`: exact command run
- `exitCode`: command exit code
- `stdoutSha256` and/or `stderrSha256`: output shas when available

For output evidence, use:
- `type`: `"output"`
- `label`: output label
- `sha256`: output sha

`filesChanged[]` MUST be the parseable source of the human `FILES CHANGED`
section. Each item includes:
- `path`: project-relative path
- `changeType`: `"added"`, `"modified"`, `"deleted"`, or `"renamed"`
- `sha256After`: sha after the change when the file still exists
- `linesAdded` and `linesDeleted` when available

`commands[]` MUST include every verification command reported in the
`VERIFICATION` section with `command`, `exitCode`, and output shas when
available.

`finalVerdict` MUST be:
- `"PASS"` only when all progress items were completed, every
  `criteria[].verdict` is `"PASS"`, `findings` is empty, and `codexExitCode`
  is `0`.
- `"FINDINGS"` when implementation completed but a requested item is blocked,
  a verification command failed, any criterion failed or was skipped, or any
  issue exists.
- `"FAIL"` only when Codex could not complete the implementation run.

### PASS example

```
FILES CHANGED:
- look-before-you-leap/codex-skills/lbyl-implement/SKILL.md (modified)

WHAT WAS DONE:
- Progress item 1: Replaced prose-only reporting with exact parseable sections.
- Progress item 2: Added the required codex-receipt-v1 JSON output contract.

VERIFICATION:
- Type checker: N/A (markdown-only change)
- Linter: N/A
- Tests: PASS (frontmatter validation and grep checks passed)
- Consumer check: PASS (wrapper script prompt consumers reviewed)

ISSUES:
- none
```

```codex-receipt-v1
{
  "schemaVersion": "1.0.0",
  "kind": "implement",
  "stepId": 15,
  "owner": "codex",
  "mode": "codex-impl",
  "projectRoot": "/Users/me/Projects/claude-code-setup",
  "planPath": ".temp/plan-mode/active/codex-first-conductor/plan.json",
  "planName": "codex-first-conductor",
  "codexExitCode": 0,
  "criteria": [
    {
      "id": 1,
      "acceptanceCriterion": "Both SKILL.md files specify exact headings / fenced-JSON delimiters.",
      "acceptanceCriterionSha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "verdict": "PASS",
      "evidence": [
        {
          "type": "file",
          "file": "look-before-you-leap/codex-skills/lbyl-implement/SKILL.md",
          "lineStart": 90,
          "lineEnd": 210,
          "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "note": "Human headings and codex-receipt-v1 fence are specified."
        },
        {
          "type": "command",
          "command": "rg -n \"codex-receipt-v1|FILES CHANGED|WHAT WAS DONE|VERIFICATION|ISSUES\" look-before-you-leap/codex-skills/lbyl-implement/SKILL.md",
          "exitCode": 0,
          "stdoutSha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        }
      ]
    }
  ],
  "filesChanged": [
    {
      "path": "look-before-you-leap/codex-skills/lbyl-implement/SKILL.md",
      "changeType": "modified",
      "sha256After": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    }
  ],
  "commands": [
    {
      "command": "python3 - <<'PY' ... yaml frontmatter validation ... PY",
      "exitCode": 0,
      "stdoutSha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
    }
  ],
  "findings": [],
  "finalVerdict": "PASS",
  "generatedAt": "2026-04-24T18:32:11Z"
}
```

### FINDINGS example

```
FILES CHANGED:
- look-before-you-leap/codex-skills/lbyl-implement/SKILL.md (modified)

WHAT WAS DONE:
- Progress item 1: Added exact human headings.
- Progress item 2: Blocked because the receipt JSON fence was not added.

VERIFICATION:
- Type checker: N/A (markdown-only change)
- Linter: N/A
- Tests: FAIL (rg did not find codex-receipt-v1)
- Consumer check: PASS (wrapper script prompt consumers reviewed)

ISSUES:
- Missing required codex-receipt-v1 fenced JSON block.
```

```codex-receipt-v1
{
  "schemaVersion": "1.0.0",
  "kind": "implement",
  "stepId": 15,
  "owner": "codex",
  "mode": "codex-impl",
  "projectRoot": "/Users/me/Projects/claude-code-setup",
  "planPath": ".temp/plan-mode/active/codex-first-conductor/plan.json",
  "planName": "codex-first-conductor",
  "codexExitCode": 0,
  "criteria": [
    {
      "id": 1,
      "acceptanceCriterion": "Both SKILL.md files specify exact headings / fenced-JSON delimiters.",
      "acceptanceCriterionSha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "verdict": "FAIL",
      "rationale": "The human headings exist but the required JSON fence is missing.",
      "evidence": [
        {
          "type": "file",
          "file": "look-before-you-leap/codex-skills/lbyl-implement/SKILL.md",
          "lineStart": 90,
          "lineEnd": 110,
          "sha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        },
        {
          "type": "command",
          "command": "rg -n \"codex-receipt-v1\" look-before-you-leap/codex-skills/lbyl-implement/SKILL.md",
          "exitCode": 1,
          "stdoutSha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        }
      ]
    }
  ],
  "filesChanged": [
    {
      "path": "look-before-you-leap/codex-skills/lbyl-implement/SKILL.md",
      "changeType": "modified"
    }
  ],
  "commands": [
    {
      "command": "rg -n \"codex-receipt-v1\" look-before-you-leap/codex-skills/lbyl-implement/SKILL.md",
      "exitCode": 1,
      "stdoutSha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }
  ],
  "findings": [
    {
      "severity": "HIGH",
      "category": "INCOMPLETE_WORK",
      "file": "look-before-you-leap/codex-skills/lbyl-implement/SKILL.md",
      "lineStart": 90,
      "lineEnd": 110,
      "summary": "Missing codex-receipt-v1 output fence.",
      "rationale": "The wrapper cannot extract a parseable JSON receipt from sectioned prose alone.",
      "suggestedFix": "Add the exact codex-receipt-v1 fenced JSON block required by the schema.",
      "criterionId": 1
    }
  ],
  "finalVerdict": "FINDINGS",
  "generatedAt": "2026-04-24T18:55:09Z"
}
```

---

## Rules

1. **Read before editing** — always read the target file and its imports first
2. **No scope creep** — only implement what the step describes
3. **No silent scope cuts** — if you cannot complete something, report it
4. **Follow patterns** — match existing codebase conventions
5. **Verify your work** — run the type checker and tests before reporting
6. **Be explicit** — your report is what Claude uses to verify your work
