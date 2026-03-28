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

### If all acceptance criteria pass

Report: `PASS — all acceptance criteria verified.`

Do NOT write a findings file when the result is PASS.

### If any issues found

Report each finding with this structure:
- **Severity**: HIGH (blocks shipping, runtime failure, data loss, security) / MEDIUM (should fix before merge) / LOW (nit, style)
- **File**: relative path to the file
- **Line**: line number (0 if not applicable)
- **Category**: one of `INCOMPLETE_WORK`, `MISSED_CONSUMER`, `TYPE_SAFETY`, `SILENT_SCOPE_CUT`, `WRONG_PATTERN`, `MISSING_TEST`, `MISSING_I18N`, `OTHER`
- **Summary**: one-line description
- **Detail**: full explanation — what was done, why it is wrong, suggested fix
- **Preventable**: which instruction or checklist could have caught this

### Findings log

When you find issues (anything other than PASS), write a JSON findings
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
