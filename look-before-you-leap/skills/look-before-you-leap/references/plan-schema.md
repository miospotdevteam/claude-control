# plan.json Schema

The execution source of truth for every plan. Hooks read this file to check
plan state. Claude updates it to track progress. masterPlan.md is the
human-facing presentation document — it does NOT contain execution state.

## Location

```
.temp/plan-mode/active/<plan-name>/plan.json
```

## Full Schema

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
      "skill": "none",
      "simplify": false,
      "files": ["src/foo.ts", "src/bar.ts"],
      "description": "What needs to happen. Specific enough for a fresh context window.",
      "acceptanceCriteria": "Concrete, verifiable conditions (e.g., 'tsc --noEmit passes').",
      "progress": [
        {"task": "Sub-task description", "status": "pending", "files": ["src/foo.ts"]},
        {"task": "Another sub-task", "status": "pending", "files": ["src/bar.ts"]}
      ],
      "subPlan": null,
      "result": null
    },
    {
      "id": 2,
      "title": "Large sweep step",
      "status": "pending",
      "skill": "none",
      "simplify": false,
      "files": ["a.tsx", "b.tsx", "c.tsx", "d.tsx"],
      "description": "A step large enough to warrant a sub-plan.",
      "acceptanceCriteria": "All files updated, tsc clean.",
      "progress": [
        {"task": "Group 1: Dashboard pages", "status": "pending", "files": ["a.tsx", "b.tsx"]},
        {"task": "Group 2: Modal components", "status": "pending", "files": ["c.tsx", "d.tsx"]}
      ],
      "subPlan": {
        "groups": [
          {"name": "Dashboard pages", "files": ["a.tsx", "b.tsx"], "status": "pending", "notes": null},
          {"name": "Modal components", "files": ["c.tsx", "d.tsx"], "status": "pending", "notes": null}
        ]
      },
      "result": null
    }
  ],
  "blocked": [],
  "completedSummary": [],
  "deviations": []
}
```

## Field Reference

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
| `completedSummary` | string[] | yes | Running log of completed steps |
| `deviations` | string[] | yes | Where implementation deviated from plan |

### Step fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | number | yes | Sequential step number (1-based) |
| `title` | string | yes | Step title |
| `status` | string | yes | One of: `pending`, `in_progress`, `done`, `blocked` |
| `skill` | string | yes | Skill to invoke, or `"none"` |
| `simplify` | boolean | yes | Whether to run simplification after step |
| `qa` | boolean | no | Whether to run fresh-eyes QA sub-agent after step (default false) |
| `files` | string[] | yes | Files involved in this step |
| `description` | string | yes | What to do — self-contained for fresh context |
| `acceptanceCriteria` | string | yes | How to know the step is done |
| `progress` | Progress[] | yes | Sub-task checklist (empty array for simple steps) |
| `subPlan` | SubPlan? | no | Inline sub-plan for large steps (null if none) |
| `result` | string? | no | Filled after completion (null before) |

### Progress item fields

| Field | Type | Required | Description |
|---|---|---|---|
| `task` | string | yes | Sub-task description |
| `status` | string | yes | One of: `pending`, `in_progress`, `done` |
| `files` | string[] | no | Files involved in this sub-task |

### SubPlan fields

| Field | Type | Required | Description |
|---|---|---|---|
| `groups` | Group[] | yes | Ordered list of file groups |

### Group fields

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Logical cluster name |
| `files` | string[] | yes | Files in this group |
| `status` | string | yes | One of: `pending`, `in_progress`, `done` |
| `notes` | string? | no | Execution notes (null before, filled during) |

## Status Values

Steps, progress items, and groups all use the same status values:

| Value | Meaning |
|---|---|
| `pending` | Not yet started |
| `in_progress` | Currently being worked on |
| `done` | Complete and verified |
| `blocked` | Cannot proceed (steps only) |

## Updating plan.json

Claude updates plan.json using the Bash tool with `python3` one-liners that
call `plan_utils.py`. This is more reliable than Edit-based markdown
checkbox toggling:

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
lives exclusively in plan.json.

See `references/master-plan-format.md` for the template.
