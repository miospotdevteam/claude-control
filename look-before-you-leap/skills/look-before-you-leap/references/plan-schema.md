# plan.json Schema

The immutable plan definition. Frozen after Orbit approval — never edited
during execution. Hooks read this file for step structure, ownership, and
acceptance criteria.

Mutable execution state (step statuses, results, progress items,
completedSummary, deviations, codexSession) lives in **progress.json**,
which is auto-created by `plan_utils.py` on first mutation.

masterPlan.md is the human-facing presentation document.

## Location

```
.temp/plan-mode/active/<plan-name>/plan.json      # immutable definition
.temp/plan-mode/active/<plan-name>/progress.json   # mutable execution state
```

## Full Schema (plan.json at creation time)

The example below shows plan.json as written during plan creation. Fields
like `status`, `result`, and `progress[].status` are set to initial values
(`"pending"`, `null`). **After Orbit approval, plan.json is frozen.**
Runtime updates to these fields go to `progress.json` via `plan_utils.py`.

```json
{
  "name": "plan-name-kebab-case",
  "title": "Descriptive Title",
  "context": "What the user asked for — enough for a fresh context window to understand the task without the original conversation.",
  "status": "active",
  "requiredSkills": ["look-before-you-leap:frontend-design"],
  "disciplines": ["testing-checklist.md", "security-checklist.md"],
  "discovery": {
    "scope": "Files/directories in scope. Be explicit about boundaries.",
    "entryPoints": "Primary files to modify and their current state.",
    "consumers": "Who imports/uses the files you're changing. Include file paths.",
    "existingPatterns": "How similar problems are already solved in this codebase.",
    "testInfrastructure": "Test framework, where tests live, how to run them.",
    "conventions": "Project-specific conventions from CLAUDE.md or observed patterns.",
    "blastRadius": "What could break if you get this wrong.",
    "confidence": "high"
  },
  "steps": [
    {
      "id": 1,
      "title": "Step title",
      "status": "pending",
      "owner": "claude",
      "mode": "claude-impl",
      "skill": "none",
      "simplify": false,
      "codexVerify": true,
      "files": ["src/foo.ts", "src/bar.ts"],
      "description": "What needs to happen. Specific enough for a fresh context window.",
      "acceptanceCriteria": "Concrete, verifiable conditions (e.g., 'tsc --noEmit passes').",
      "progress": [
        {"task": "Sub-task description", "status": "pending", "files": ["src/foo.ts"]},
        {"task": "Another sub-task", "status": "pending", "files": ["src/bar.ts"]}
      ],
      "subPlan": null,
      "result": null,
      "routingJustification": "Frontend UI / visual design → claude-impl"
    },
    {
      "id": 2,
      "title": "Large sweep step",
      "status": "pending",
      "owner": "codex",
      "mode": "codex-impl",
      "skill": "none",
      "simplify": false,
      "codexVerify": true,
      "files": ["a.tsx", "b.tsx", "c.tsx", "d.tsx"],
      "description": "A step large enough to warrant a sub-plan.",
      "acceptanceCriteria": "All files updated, tsc clean.",
      "progress": [
        {"task": "Group 1: Dashboard pages", "status": "pending", "files": ["a.tsx", "b.tsx"]},
        {"task": "Group 2: Modal components", "status": "pending", "files": ["c.tsx", "d.tsx"]}
      ],
      "subPlan": {
        "groups": [
          {"name": "Dashboard pages", "owner": "claude", "files": ["a.tsx", "b.tsx"]},
          {"name": "Modal components", "owner": "codex", "files": ["c.tsx", "d.tsx"]}
        ]
      },
      "result": null,
      "routingJustification": "Refactor across many files → codex-impl"
    }
  ],
  "blocked": []
}
```

## progress.json Schema

Auto-created by `plan_utils.py` on first mutation. All mutable state lives here.

```json
{
  "steps": {
    "1": {
      "status": "in_progress",
      "result": "### Criterion: ...\nCodex: PASS",
      "progress": [
        {"status": "done"},
        {"status": "pending"}
      ],
      "groups": {
        "0": {"status": "done", "notes": "Group 0: Codex: PASS"},
        "1": {"status": "in_progress"}
      }
    }
  },
  "completedSummary": ["Step 1: implemented auth flow"],
  "deviations": ["Used OAuth2 instead of SAML"],
  "codexSession": {
    "threadId": "...",
    "phase": "verify",
    "interactionCount": 3,
    "lastInteraction": "2026-03-24T10:00:00Z"
  }
}
```

### Mutable fields (progress.json)

| Field | Type | Description |
|---|---|---|
| `steps.<id>.status` | string | `"pending"`, `"in_progress"`, `"done"`, `"blocked"` |
| `steps.<id>.result` | string | What was implemented (required before marking done) |
| `steps.<id>.progress` | object[] | Status of each progress item: `{"status": "..."}` |
| `steps.<id>.groups` | object | Group-level status/notes keyed by index: `{"0": {"status": "done"}}` |
| `completedSummary` | string[] | Running log of completed steps |
| `deviations` | string[] | Where implementation deviated from plan |
| `codexSession` | object | Codex CLI session state (threadId, phase, count) |

### Legacy fallback

If no `progress.json` exists, `plan_utils.py` reads mutable fields from
`plan.json` as a fallback. On first mutation, it auto-migrates existing
state from `plan.json` into a new `progress.json`.

---

## Field Reference (plan.json — immutable)

### Top-level fields

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | kebab-case plan name (matches directory name) |
| `title` | string | yes | Human-readable title |
| `context` | string | yes | What the user asked for — survives compaction |
| `status` | string | yes | `"active"` or `"completed"` |
| `requiredSkills` | string[] | yes | Exact skill identifiers (empty array if none) |
| `disciplines` | string[] | yes | Checklist filenames that apply |
| `discovery` | object | yes | All 8 exploration sections |
| `steps` | Step[] | yes | Ordered list of execution steps |
| `blocked` | string[] | yes | Blocked step descriptions (empty if none) |

**Note:** `completedSummary`, `deviations`, and `codexSession` are mutable
fields that live in `progress.json`. See the progress.json schema above.

### Step fields (immutable in plan.json, except where noted)

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | number | yes | Sequential step number (1-based) |
| `title` | string | yes | Step title |
| `status` | string | yes | **Mutable** — initial: `"pending"`. Runtime value in progress.json. |
| `owner` | string | no | Who implements this step: `"claude"` (default) or `"codex"`. Assigned by writing-plans skill based on routing matrix. Claude-owned steps are verified by Codex; Codex-owned steps are verified by Claude. |
| `mode` | string | no | Collaboration mode for this step. One of: `"claude-impl"` (default), `"codex-impl"`, `"collab-split"`, `"dual-pass"`. Determines how Claude and Codex interact. See collaboration modes below. |
| `skill` | string | yes | Skill to invoke, or `"none"` |
| `simplify` | boolean | yes | Whether to run simplification after step |
| `qa` | boolean | no | Whether to run fresh-eyes QA sub-agent after step (default false) |
| `codexVerify` | boolean | no | Always true — no exceptions, no mode-based exemptions. Codex verification is structural. Uses `run-codex-verify.sh` for claude-impl steps. For codex-impl steps, Claude verifies independently. |
| `files` | string[] | yes | Files involved in this step |
| `description` | string | yes | What to do — self-contained for fresh context |
| `acceptanceCriteria` | string | yes | How to know the step is done |
| `progress` | Progress[] | yes | Sub-task checklist (empty array for simple steps) |
| `subPlan` | SubPlan? | no | Inline sub-plan for large steps (null if none) |
| `result` | string? | no | **Mutable** — initial: null. Runtime value in progress.json. Uses `### Criterion:` template. See Result Field Format below. |
| `routingJustification` | string | no | Why this step was assigned to this owner/mode — routing matrix category and justification. Format: `"<category> → <mode> [override reason]"`. Required by writing-plans skill for auditability. Example: `"Refactor across many files → codex-impl"` |

### Progress item fields

| Field | Type | Required | Description |
|---|---|---|---|
| `task` | string | yes | Sub-task description |
| `status` | string | yes | **Mutable** — runtime value in progress.json. One of: `pending`, `in_progress`, `done` |
| `files` | string[] | yes | Files involved in this sub-task |

### SubPlan fields

| Field | Type | Required | Description |
|---|---|---|---|
| `groups` | Group[] | yes | Ordered list of file groups |

### Group fields

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Logical cluster name |
| `owner` | string | no | Who implements this group: `"claude"` or `"codex"`. Defaults to the parent step's `owner` if omitted. For `collab-split` steps, each group gets its own owner — the executor checks the effective owner (`group.owner ?? step.owner`) to dispatch to the correct agent. Assigned by writing-plans skill using the routing matrix. |
| `files` | string[] | yes | Files in this group |
| `status` | string | yes | **Mutable** — runtime value in progress.json. One of: `pending`, `in_progress`, `done` |
| `notes` | string? | no | **Mutable** — runtime value in progress.json. Execution notes (null before, filled during) |

## Result Field Format

When a step is completed, its `result` field must use this structured template.
The `### Criterion:` markers are stable tokens that hooks can count and match
against `acceptanceCriteria`. The `### Verdict` section contains the Codex/Claude
verdict.

### Template

```
### Criterion: "<quoted text from acceptanceCriteria>"
→ <what was done: file:line, function, behavior>
→ <how verified: command run, output observed>

### Criterion: "<next criterion>"
→ ...

### Verdict
Codex: PASS
```

### Good example

```
### Criterion: "python3 -m py_compile plan_utils.py succeeds"
→ Ran python3 -m py_compile plan_utils.py: exit 0, no output

### Criterion: "plan_utils.py exits non-zero when marking step done with empty result"
→ Added sys.exit(1) at plan_utils.py:152 in update_step()
→ Tested: python3 plan_utils.py update-step fixture.json 1 done → exit 1 with error message

### Verdict
Codex: PASS
```

### Bad examples

- `"Done."` — no evidence, no criterion mapping
- `"Created the files and updated imports."` — no criterion mapping, no verification evidence
- `"Codex: PASS"` — verdict without criterion evidence

Every acceptance criterion must appear as a `### Criterion:` entry. If the step
has 5 criteria, the result must have 5 `### Criterion:` markers. The
`verify-step-completion` hook will count these markers and warn on mismatches
once the enforcement is implemented.

## Status Values

Steps, progress items, and groups all use the same status values:

| Value | Meaning |
|---|---|
| `pending` | Not yet started |
| `in_progress` | Currently being worked on |
| `done` | Complete and verified |
| `blocked` | Cannot proceed (steps only) |

## Updating Progress

Claude updates progress via the Bash tool with `python3` one-liners that
call `plan_utils.py`. All mutation commands write to `progress.json`
automatically — the CLI takes the `plan.json` path and resolves
`progress.json` from the same directory:

```bash
# Mark step 3 as in_progress
python3 /path/to/plan_utils.py update-step /path/to/plan.json 3 in_progress

# Mark progress item 1 of step 3 as done
python3 /path/to/plan_utils.py update-progress /path/to/plan.json 3 0 done

# Add to completed summary
python3 /path/to/plan_utils.py add-summary /path/to/plan.json "Step 3: Migrated all hooks to JSON parsing"

# Get plan status overview
python3 /path/to/plan_utils.py status /path/to/plan.json

# Get next step to work on
python3 /path/to/plan_utils.py next-step /path/to/plan.json
```

## Collaboration Modes

Four distinct collaboration patterns determine how Claude and Codex interact
on each step. The `mode` field on each step selects the pattern:

| Mode | `owner` | Description |
|---|---|---|
| `claude-impl` | `claude` | Claude implements, Codex verifies afterward. The default mode — matches the existing codexVerify flow. |
| `codex-impl` | `codex` | Codex implements via `codex exec`, Claude verifies afterward independently. For backend, refactoring, debugging, CI. |
| `collab-split` | mixed | Both discuss approach first, then execution splits into sub-steps with mixed ownership. For complex features, migrations, integrations. |
| `dual-pass` | both | Both agents work independently, Claude synthesizes findings. For security review, PR review. |

The `owner` field is the primary dispatch signal during execution. The
`mode` field provides additional context about HOW the owner interacts
with the other agent. `codex-dispatch` skill reads both fields.

## masterPlan.md (companion file)

masterPlan.md is the human-facing proposal document. It lives alongside
plan.json in the same directory. **It is write-once** — frozen after Orbit
approval and never updated during execution.

Its purpose:

- Present the plan to the user for Orbit review
- Summarize what, why, critical decisions, warnings, risk areas
- Does NOT contain execution state (no `[x]`/`[ ]` checkboxes)
- Serves as a stable record of what was agreed upon

All runtime state (progress, results, completed summaries, deviations)
lives exclusively in progress.json (updated via plan_utils.py).
plan.json is immutable after approval.

See `references/master-plan-format.md` for the template.
