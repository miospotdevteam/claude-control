---
name: "lbyl-verify"
description: "Verification protocol for reviewing Claude-implemented plan steps. Read plan.json, check every acceptance criterion mechanically, run type checker/linter/tests, check consumers via deps-query, report PASS or structured findings. Never modify source files."
---

# Look Before You Leap — Verification Protocol

You are verifying work done by another AI agent (Claude). Your job is to
independently confirm that the changes match the specification. You are a
reviewer, not an implementer.

**You must NEVER modify project source files.** You may only read files,
run commands, and write findings logs.

---

## Step 1: Read the Plan

1. Read `plan.json` at the path given in the prompt
2. Find the step by its ID number
3. Extract:
   - `title` — what the step is about
   - `description` — what was supposed to be implemented
   - `acceptanceCriteria` — the concrete conditions to verify
   - `files` — which files should have been modified
   - `progress` — the sub-tasks and their expected statuses
4. Read `discovery.md` in the same directory for codebase context:
   - Scope, consumers, blast radius, existing patterns

---

## Step 2: Check What Changed

1. Run `git diff --name-only` to see modified tracked files
2. Run `git status --short` for untracked new files
3. Compare against the step's `files` array — every listed file should
   appear as modified or newly created
4. Flag any files in the step's list that were NOT modified (possible
   missed work)
5. Flag any files modified that are NOT in the step's list (possible
   scope creep)

---

## Step 3: Verify Each Acceptance Criterion

Go through the `acceptanceCriteria` string word by word. For each
concrete condition:

1. **Identify the check** — what specifically needs to be true?
2. **Run the check** — read files, run commands, grep for patterns
3. **Record the result** — pass or fail with evidence

Common verification commands:
- Type checker: `tsc --noEmit`, `bun run tsgo`, `mypy`, `cargo check`
- Linter: `eslint`, `ruff`, `clippy`
- Tests: check `package.json` scripts, `Makefile`, `pyproject.toml` for
  the project's standard test command
- Syntax check for shell scripts: `bash -n <script>`

**Pre-existing failures are NOT exempt.** If the acceptance criteria say
"tsc passes" and tsc does not pass, report it as a finding — regardless
of whether the failure was introduced by this step or existed before.

---

## Step 3.5: Standard Checks (always run)

These checks run on EVERY step regardless of what the acceptance criteria
say. They catch the most common failure patterns from historical findings.

### i18n completeness

If the step modified or created files with user-visible strings:
1. Grep for new translation keys or literal strings in the changed files
2. Check ALL locale files (e.g., `packages/i18n/messages/*.json`) for
   corresponding entries
3. Flag any new user-visible string that does not exist in all locales
4. English-only fallbacks (`t("key", "English text")`) count as missing
5. Hardcoded default props on shared components (`accessibilityLabel=
   "Close"`, `placeholder="Search"`) count as missing — they bypass the
   translation pipeline
6. **Mechanical audit**: run `grep -rn 't(' <changed-files>` to list every
   new translation call, then cross-check each key against every locale
   file. Flag any key missing from any locale as MISSING_I18N

### State transitions

If the step modified UI code:
1. Don't just check the initial render — check what happens when:
   - The user switches between items (e.g., selecting a different season,
     tab, or entity). Does stale data from the previous selection leak?
   - Data is loading (is there a loading state, or does old data show?)
   - An API call fails (is there error handling, or silent failure?)
   - Form fields display defaults — are those defaults actually in form
     state, or just cosmetic? If Save sends form state, cosmetic defaults
     cause data loss.
2. Trace the save path: for every editable field, verify onChange → state
   → mutation → API. If a field shows a value but the value isn't in state,
   saving will drop it.
3. **Async-transition matrix**: for each async data source in the changed
   UI, verify these transitions and flag any that are unhandled:
   - Switch item while request in flight → stale response ignored?
   - Request fails → error state shown or silent failure?
   - Close and reopen view → state reset or stale cache?
   - Stale response arrives late → ignored or overwrites current?
   - Cosmetic default vs persisted → default in form state or visual only?
   List each state producer (effect, URL init, wizard nav, event source)
   with pending/success/failure/switched-away outcomes.

### Description parity

The step description often has more detail than the acceptance criteria.
1. Re-read the step `description` word by word
2. List every deliverable mentioned (features, buttons, behaviors, states)
3. Verify each deliverable exists in the implementation
4. Flag deliverables that are in the description but missing from the code
   — these are silent scope cuts

### Companion file completeness

If the step adds new behavior, verify companion artifacts exist:
1. **Tests** — new logic, API endpoints, handlers must have at least one
   targeted test. Flag missing tests as MISSING_TEST.
2. **Locale entries** — new user-visible strings must have entries in all
   locale files. Flag gaps as MISSING_I18N.
3. **Consumer updates** — changed exports must have updated consumers.
   Flag missed consumers as MISSED_CONSUMER.
4. **Migrations** — new DB columns/tables must have migration files.
A step that ships behavior without its companions is incomplete.

### Empty and edge states

If the step added conditional UI (`{data && ...}`, `data?.length > 0`,
guards):
1. Check what renders when the guard is false (null, empty array, error)
2. If "nothing renders" — is that acceptable, or should there be a
   placeholder, empty state message, or fallback?
3. Specifically check: empty list, zero count, null data, single item
   (when the UI assumes multiple)

### Existing pattern matching

If the step implements a pattern that already exists elsewhere in the
codebase (swipeable rows, modals, steppers, pickers):
1. Grep for existing instances of that pattern
2. Compare configuration (thresholds, props, styling) against the existing
   pattern
3. Flag inconsistencies — the new instance should match unless the step
   explicitly says otherwise

---

## Step 4: Check Consumers

If the step modified shared code (types, utilities, API signatures,
exports):

1. Check if dep maps are configured — look for `.claude/look-before-you-leap.local.md`
   with a `dep_maps` section
2. If dep maps exist, find and run `deps-query.py` on each modified shared file:
   ```bash
   # Find deps-query.py in the plugin
   find ~/.claude/plugins -name "deps-query.py" -path "*/look-before-you-leap/*" 2>/dev/null | head -1
   # Run it
   python3 <path-to-deps-query.py> <project-root> "<modified-file>"
   ```
3. If dep maps are not configured, grep for import statements referencing
   the modified files
4. Verify consumers still work with the changes

---

## Step 5: Report

Your output is consumed by `run-codex-verify.sh`. It is both a human trace
and the source for `<plan-dir>/codex-receipt-step-N.json`.

You MUST emit:

1. A short human-readable summary.
2. A final fenced JSON block with this exact delimiter:

````text
```codex-receipt-v1
{ ...valid JSON... }
```
````

The fenced block MUST be the last block in the response. Do not put prose
inside the fence. Do not emit more than one `codex-receipt-v1` fence.

### Receipt JSON contract

The fenced JSON block MUST match `look-before-you-leap/references/codex-receipt-schema.md`
schema version `1.0.0`.

Required top-level fields:
- `schemaVersion`: exactly `"1.0.0"`
- `kind`: exactly `"verify"`
- `stepId`: numeric plan step id
- `owner`: step owner from `plan.json`
- `mode`: step mode from `plan.json`
- `planName`: plan `.name`
- `codexExitCode`: `0` when Codex completed normally
- `criteria`: one entry per acceptance criterion
- `filesChanged`: changed files inspected during verification
- `findings`: `[]` on PASS, otherwise structured finding objects
- `finalVerdict`: `"PASS"` or `"FINDINGS"`; use `"FAIL"` only when Codex
  itself could not complete verification
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

`finalVerdict` MUST be:
- `"PASS"` only when every `criteria[].verdict` is `"PASS"`, `findings` is
  empty, and `codexExitCode` is `0`.
- `"FINDINGS"` when verification completed but any criterion failed, was
  skipped, or any finding exists.
- `"FAIL"` only when verification could not complete because Codex or the
  verification environment failed.

### Human summary headings

Before the fenced JSON, use these exact headings:

```
VERDICT:
<PASS|FINDINGS|FAIL> — <one sentence>

CRITERIA:
- C<id> <PASS|FAIL|SKIPPED>: <brief result>

FINDINGS:
- none
```

When findings exist, replace `- none` with one bullet per finding:

```
- HIGH INCOMPLETE_WORK path/to/file.ts:42 — <summary>
```

### PASS example

```
VERDICT:
PASS — all acceptance criteria verified.

CRITERIA:
- C1 PASS: Verified exact headings and receipt fence in the modified skill.

FINDINGS:
- none
```

```codex-receipt-v1
{
  "schemaVersion": "1.0.0",
  "kind": "verify",
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
          "file": "look-before-you-leap/codex-skills/lbyl-verify/SKILL.md",
          "lineStart": 176,
          "lineEnd": 260,
          "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "note": "Output contract includes exact heading and fence delimiters."
        },
        {
          "type": "command",
          "command": "python3 - <<'PY' ... yaml frontmatter validation ... PY",
          "exitCode": 0,
          "stdoutSha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        }
      ]
    }
  ],
  "filesChanged": [
    {
      "path": "look-before-you-leap/codex-skills/lbyl-verify/SKILL.md",
      "changeType": "modified",
      "sha256After": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    }
  ],
  "commands": [
    {
      "command": "python3 - <<'PY' ... assert removed mode token absent ... PY",
      "exitCode": 0,
      "stdoutSha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }
  ],
  "findings": [],
  "finalVerdict": "PASS",
  "generatedAt": "2026-04-24T18:32:11Z"
}
```

### FINDINGS example

```
VERDICT:
FINDINGS — one acceptance criterion is not satisfied.

CRITERIA:
- C1 FAIL: Required fenced JSON delimiter is missing.
- C2 PASS: Frontmatter remains valid.

FINDINGS:
- HIGH INCOMPLETE_WORK look-before-you-leap/codex-skills/lbyl-verify/SKILL.md:176 — Missing codex-receipt-v1 output fence.
```

```codex-receipt-v1
{
  "schemaVersion": "1.0.0",
  "kind": "verify",
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
      "rationale": "The output contract still describes prose-only PASS reporting.",
      "evidence": [
        {
          "type": "file",
          "file": "look-before-you-leap/codex-skills/lbyl-verify/SKILL.md",
          "lineStart": 176,
          "lineEnd": 180,
          "sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
          "note": "No codex-receipt-v1 fence is specified."
        }
      ]
    },
    {
      "id": 2,
      "acceptanceCriterion": "Frontmatter stays valid.",
      "acceptanceCriterionSha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      "verdict": "PASS",
      "evidence": [
        {
          "type": "command",
          "command": "python3 - <<'PY' ... yaml frontmatter validation ... PY",
          "exitCode": 0,
          "stdoutSha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        }
      ]
    }
  ],
  "filesChanged": [
    {
      "path": "look-before-you-leap/codex-skills/lbyl-verify/SKILL.md",
      "changeType": "modified"
    }
  ],
  "commands": [
    {
      "command": "rg -n \"codex-receipt-v1\" look-before-you-leap/codex-skills/lbyl-verify/SKILL.md",
      "exitCode": 1,
      "stdoutSha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }
  ],
  "findings": [
    {
      "severity": "HIGH",
      "category": "INCOMPLETE_WORK",
      "file": "look-before-you-leap/codex-skills/lbyl-verify/SKILL.md",
      "lineStart": 176,
      "lineEnd": 180,
      "summary": "Missing codex-receipt-v1 output fence.",
      "rationale": "The wrapper cannot extract a parseable JSON receipt from prose-only output.",
      "suggestedFix": "Add the exact codex-receipt-v1 fenced JSON block required by the schema.",
      "criterionId": 1
    }
  ],
  "finalVerdict": "FINDINGS",
  "generatedAt": "2026-04-24T18:55:09Z"
}
```

### Findings log

When you find issues (`finalVerdict` is not `"PASS"`), write a JSON findings
report to the plugin repo's `usage-errors/codex-findings/` directory.
The plugin repo is always at `~/Projects/claude-code-setup` — write
findings there regardless of which project the plan runs in. Create the
directory if it does not exist.

**Filename**: `YYYY-MM-DD-{plan-name}-step-{N}.json`
**Re-verify rounds**: `YYYY-MM-DD-{plan-name}-step-{N}-reverify-{M}.json`

Get the plan name from `plan.json`'s `.name` field. Use today's date.

```json
{
  "plan": "<plan.name>",
  "project": "<project root path>",
  "step": <step id>,
  "stepTitle": "<step.title>",
  "acceptanceCriteria": "<step.acceptanceCriteria>",
  "date": "YYYY-MM-DD",
  "findings": [
    {
      "severity": "HIGH | MEDIUM | LOW",
      "category": "INCOMPLETE_WORK | MISSED_CONSUMER | TYPE_SAFETY | SILENT_SCOPE_CUT | WRONG_PATTERN | MISSING_TEST | MISSING_I18N | OTHER",
      "file": "relative/path/to/file",
      "line": 0,
      "summary": "One-line description",
      "detail": "Full explanation with suggested fix",
      "preventable": "Which instruction could have prevented this"
    }
  ]
}
```

Severity guide:
- **HIGH**: blocks shipping — runtime failure, data loss, security issue,
  type error, missing core functionality
- **MEDIUM**: should fix before merge — incorrect behavior in edge cases,
  missing validation, weak error handling
- **LOW**: nit — style inconsistency, naming, minor documentation gap

---

## Rules

1. **Never modify source files** — you are a reviewer only
2. **Check every criterion** — do not skip criteria that seem obvious
3. **Be specific** — cite file paths and line numbers in findings
4. **No pre-existing exemptions** — if the criteria require it to pass and
   it does not, report it
5. **Do not invent criteria beyond the standard checks** — verify what the
   acceptance criteria, step description, and Step 3.5 standard checks
   specify. Do not add ad-hoc checks beyond these three sources
6. **Run real commands** — do not guess whether tsc passes; run it
