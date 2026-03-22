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
  "codexSession": {
    "threadId": "abc-123",
    "phase": "discovery",
    "interactionCount": 1,
    "lastInteraction": "2026-03-22T10:30:00Z"
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
      "result": null
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
| `codexSession` | object | no | Persistent Codex MCP thread state (null/absent if no Codex involvement). See Codex Session fields below. |
| `steps` | Step[] | yes | Ordered list of execution steps |
| `blocked` | string[] | yes | Blocked step descriptions (empty if none) |
| `completedSummary` | string[] | yes | Running log of completed steps |
| `deviations` | string[] | yes | Where implementation deviated from plan |

### Codex Session fields

| Field | Type | Required | Description |
|---|---|---|---|
| `threadId` | string | yes | Codex MCP thread ID. Set after first `mcp__codex__codex` call. Used for all subsequent `mcp__codex__codex-reply` calls. |
| `phase` | string | yes | Current lifecycle phase: `"discovery"`, `"plan-review"`, `"execution"`, `"completed"` |
| `interactionCount` | number | yes | Number of Codex interactions on this thread. When >= 10, trigger overflow: start a fresh thread via the initialization protocol in `codex-dispatch`. Threshold is conservative — timeouts observed at ~15. |
| `lastInteraction` | string | yes | ISO 8601 timestamp of the last Codex interaction. Used for staleness detection. |

The `codexSession` object is absent or `null` for plans with no Codex involvement (backward compatible). Created during discovery when the first Codex call is made. Updated after every Codex interaction via `plan_utils.py update-codex-session`.

### Step fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | number | yes | Sequential step number (1-based) |
| `title` | string | yes | Step title |
| `status` | string | yes | One of: `pending`, `in_progress`, `done`, `blocked` |
| `owner` | string | no | Who implements this step: `"claude"` (default) or `"codex"`. Assigned by writing-plans skill based on routing matrix. Claude-owned steps are verified by Codex; Codex-owned steps are verified by Claude. |
| `mode` | string | no | Collaboration mode for this step. One of: `"claude-solo"`, `"claude-impl"` (default), `"codex-impl"`, `"collab-split"`, `"dual-pass"`. Determines how Claude and Codex interact. See collaboration modes below. |
| `skill` | string | yes | Skill to invoke, or `"none"` |
| `simplify` | boolean | yes | Whether to run simplification after step |
| `qa` | boolean | no | Whether to run fresh-eyes QA sub-agent after step (default false) |
| `codexVerify` | boolean | no | Whether to run Codex MCP verification after step (default true — set on every step unless user opts out). Requires Codex MCP server configured globally. See `references/codex-verify-template.md` for prompt templates. |
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
| `files` | string[] | yes | Files involved in this sub-task |

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

## Codex Session Management

```bash
# Set/update codex session (all fields at once)
python3 /path/to/plan_utils.py update-codex-session /path/to/plan.json <threadId> <phase>

# Read current codex session state
python3 /path/to/plan_utils.py get-codex-session /path/to/plan.json

# Clear codex session (thread lost, plan complete, etc.)
python3 /path/to/plan_utils.py clear-codex-session /path/to/plan.json
```

## Collaboration Modes

Five distinct collaboration patterns determine how Claude and Codex interact
on each step. The `mode` field on each step selects the pattern:

| Mode | `owner` | Description |
|---|---|---|
| `claude-solo` | `claude` | Claude handles everything. No Codex involvement for this step. Use for vague/ambiguous tasks requiring user interaction. |
| `claude-impl` | `claude` | Claude implements, Codex verifies afterward. The default mode — matches the existing codexVerify flow. |
| `codex-impl` | `codex` | Codex implements via MCP, Claude verifies afterward. For backend, refactoring, debugging, CI. |
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
lives exclusively in plan.json.

See `references/master-plan-format.md` for the template.
