# plan.json Schema

The immutable plan definition. Frozen after Orbit approval — never edited
during execution. Hooks read this file for step structure, ownership, and
acceptance criteria.

Mutable execution state (step statuses, results, progress items,
completedSummary, deviations, codexSessions) lives in **progress.json**,
which is auto-created by `plan_utils.py` on first mutation.

masterPlan.md is the human-facing proposal document reviewed via Orbit.

## Location

```
.temp/plan-mode/active/<plan-name>/plan.json      # immutable definition
.temp/plan-mode/active/<plan-name>/progress.json   # mutable execution state
.temp/plan-mode/active/<plan-name>/masterPlan.md   # Orbit-reviewed proposal
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
  "conductorMode": true,
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
      "title": "Define shared types",
      "status": "pending",
      "owner": "codex",
      "mode": "codex-impl",
      "skill": "none",
      "simplify": false,
      "codexVerify": true,
      "files": ["src/types/user.ts"],
      "description": "Add the shared User type. Self-contained for fresh context.",
      "acceptanceCriteria": "tsc --noEmit passes; type exported from src/types/user.ts.",
      "progress": [
        {"task": "Add User type", "status": "pending", "files": ["src/types/user.ts"]}
      ],
      "result": null,
      "dependsOn": [],
      "routingJustification": "Backend from clear spec → codex-impl (codex default)"
    },
    {
      "id": 2,
      "title": "Implement user CRUD endpoints",
      "status": "pending",
      "owner": "codex",
      "mode": "codex-impl",
      "skill": "look-before-you-leap:test-driven-development",
      "simplify": false,
      "codexVerify": true,
      "files": ["src/routes/users.ts", "tests/routes/users.test.ts"],
      "description": "Implement GET/POST/PATCH/DELETE for /users. TDD per cycle.",
      "acceptanceCriteria": "All tests pass; tsc --noEmit clean; consumer count via deps-query unchanged.",
      "progress": [
        {"task": "Cycle 1 RED+GREEN: GET /users", "status": "pending", "files": ["src/routes/users.ts", "tests/routes/users.test.ts"]},
        {"task": "Cycle 2 RED+GREEN: POST /users", "status": "pending", "files": ["src/routes/users.ts", "tests/routes/users.test.ts"]}
      ],
      "result": null,
      "dependsOn": [1],
      "routingJustification": "Backend from clear spec → codex-impl (codex default)"
    },
    {
      "id": 3,
      "title": "User profile UI",
      "status": "pending",
      "owner": "claude",
      "mode": "claude-impl",
      "skill": "look-before-you-leap:frontend-design",
      "simplify": false,
      "codexVerify": true,
      "files": ["src/app/profile/page.tsx"],
      "description": "Profile page consuming /users endpoints from step 2.",
      "acceptanceCriteria": "Visual review passes; tsc --noEmit clean.",
      "progress": [
        {"task": "Build profile page", "status": "pending", "files": ["src/app/profile/page.tsx"]}
      ],
      "result": null,
      "dependsOn": [2],
      "routingJustification": "Frontend UI / visual design → claude-impl (skill in Claude-only list: frontend-design)"
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
      ]
    }
  },
  "completedSummary": ["Step 1: implemented auth flow"],
  "deviations": ["Used OAuth2 instead of SAML"],
  "codexSessions": {
    "1": {
      "threadId": "...",
      "phase": "verify",
      "interactionCount": 3,
      "lastInteraction": "2026-03-24T10:00:00Z"
    },
    "3": {
      "threadId": "...",
      "phase": "implement",
      "interactionCount": 1,
      "lastInteraction": "2026-03-24T10:05:00Z"
    }
  }
}
```

### Mutable fields (progress.json)

| Field | Type | Description |
|---|---|---|
| `steps.<id>.status` | string | `"pending"`, `"in_progress"`, `"done"`, `"blocked"` |
| `steps.<id>.result` | string | What was implemented (required before marking done) |
| `steps.<id>.progress` | object[] | Status of each progress item: `{"status": "..."}` |
| `completedSummary` | string[] | Running log of completed steps |
| `deviations` | string[] | Where implementation deviated from plan |
| `codexSessions` | object | Per-step Codex CLI session state, keyed by step ID. Each value: `{threadId, phase, interactionCount, lastInteraction}`. Legacy singleton `codexSession` is auto-migrated on first access. |

There is NO `groups` sub-object in progress.json. The schema no longer
supports per-group execution state — all step ownership is uniform.

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
| `conductorMode` | boolean | no | Defaults to `true`. When `true`, the main Claude thread does not write code directly — it dispatches every step to a subagent (Opus for `claude-impl`, Codex for `codex-impl`) and reads only structured receipts/digests. The only in-thread exception is the threshold described under "In-thread `claude-impl` threshold" below. Plans omitting this field are treated as `conductorMode: true`. Set to `false` only with explicit, documented reason — almost never. |
| `requiredSkills` | string[] | yes | Exact skill identifiers (empty array if none) |
| `disciplines` | string[] | yes | Checklist filenames that apply |
| `discovery` | object | yes | All 8 exploration sections |
| `steps` | Step[] | yes | Ordered list of execution steps |
| `blocked` | string[] | yes | Blocked step descriptions (empty if none) |

**Note:** `completedSummary`, `deviations`, and `codexSessions` are mutable
fields that live in `progress.json`. See the progress.json schema above.

### Step fields (immutable in plan.json, except where noted)

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | number | yes | Sequential step number (1-based) |
| `title` | string | yes | Step title |
| `status` | string | yes | **Mutable** — initial: `"pending"`. Runtime value in progress.json. |
| `owner` | string | no | Who implements this step: `"codex"` (default under conductor mode) or `"claude"`. Assigned by `writing-plans` based on the routing matrix. Claude-owned steps are verified by Codex; Codex-owned steps are verified by Claude (independently, via a verification subagent reading the receipt). |
| `mode` | string | no | Collaboration mode for this step. **Exactly three valid values**: `"codex-impl"` (default — Codex implements, Claude verifies via receipt), `"claude-impl"` (Opus subagent implements, Codex verifies via receipt), `"dual-pass"` (both agents work independently — used for security review and PR review only). No other mode value is accepted. Mixed-ownership work is split into two sequential single-owner steps with `dependsOn`. |
| `skill` | string | yes | Skill to invoke, or `"none"`. Use `"none"` or `look-before-you-leap:<name>` form. The internal `lbyl-digest` skill is dispatched only by the conductor and MUST NOT appear here. |
| `simplify` | boolean | yes | Whether to run simplification after step |
| `qa` | boolean | no | Whether to run fresh-eyes QA sub-agent after step (default false) |
| `codexVerify` | boolean | no | Always true — no exceptions, no mode-based exemptions. Codex verification is structural. Uses `run-codex-verify.sh` for `claude-impl` steps; for `codex-impl` steps, an Opus verification subagent reads the structured receipt independently. |
| `files` | string[] | yes | Files involved in this step |
| `description` | string | yes | What to do — self-contained for fresh context |
| `acceptanceCriteria` | string | yes | How to know the step is done |
| `progress` | Progress[] | yes | Sub-task checklist (empty array for simple steps) |
| `result` | string? | no | **Mutable** — initial: null. Runtime value in progress.json. Uses `### Criterion:` template. See Result Field Format below. |
| `dependsOn` | number[] | no | Step IDs that must complete before this step can start. Computed by writing-plans from file overlap + dep-map enrichment. Steps with empty `dependsOn` (or all predecessors done) are immediately runnable. Defaults to `[]`. **This is the sole DAG signal** under parallel-dispatch — under-specified `dependsOn` causes races. |
| `routingJustification` | string | yes | Why this step was assigned to this owner/mode — routing matrix category and justification. Required for auditability. Examples: `"Backend from clear spec → codex-impl (codex default)"`, `"Frontend UI / visual design → claude-impl (skill in Claude-only list: frontend-design)"`, `"react-native-mobile UI/UX per Routing Directive → claude-impl"`. |

### Disallowed step fields (do not emit)

`writing-plans` MUST NOT emit any per-step inline grouping object
(historically named `subPlan`) and MUST NOT emit any `mode` value
outside the three listed above. Validators reject both. Decompose
oversized or mixed-ownership work into multiple smaller single-owner
steps linked by `dependsOn` — each has its own `id`, `owner`, `mode`,
and `files`. There is no inline per-step grouping mechanism.

### Progress item fields

| Field | Type | Required | Description |
|---|---|---|---|
| `task` | string | yes | Sub-task description |
| `status` | string | yes | **Mutable** — runtime value in progress.json. One of: `pending`, `in_progress`, `done` |
| `files` | string[] | yes | Files involved in this sub-task |

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

Steps and progress items use the same status values:

| Value | Meaning |
|---|---|
| `pending` | Not yet started |
| `in_progress` | Currently being worked on |
| `done` | Complete and verified |
| `blocked` | Cannot proceed (steps only) |

## Strict Receipt Mode

Some plans set `_receiptMode` to `"strict"`. In strict mode, completed
steps must have the required verification receipts before the plan can move
to `completed/`. Under conductor mode, both `codex-impl` and `claude-impl`
steps emit signed sidecar receipts (paired with in-tree evidence
artifacts). See `look-before-you-leap/references/codex-receipt-schema.md`
for the dual-authority binding (HMAC-signed sidecar + sha256-bound
evidence artifact). If a plan is intended to use strict mode, call that
out in the proposal so the reviewer knows the completion gate is stricter
than the default legacy flow.

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

# Get next single step (legacy)
python3 /path/to/plan_utils.py next-step /path/to/plan.json

# Get the full DAG frontier (preferred under parallel-dispatch conductor mode)
python3 /path/to/plan_utils.py runnable-steps /path/to/plan.json
```

## Collaboration Modes

**Exactly three valid modes.** Mixed ownership is expressed as two
sequential single-owner steps with `dependsOn` rather than as a single
mixed-mode step.

| Mode | `owner` | Description |
|---|---|---|
| `codex-impl` | `codex` | **Default under conductor mode.** Codex implements via `run-codex-implement.sh`; emits a structured receipt. A Claude verification subagent reads the receipt JSON (NOT raw `.codex-result-step-N.txt`) and reports a bounded digest to the conductor. For backend, refactoring, debugging, CI, performance, i18n, migrations, sweeps. |
| `claude-impl` | `claude` | An Opus subagent implements (or, under the in-thread threshold below, the main thread implements). Codex verifies afterward via `run-codex-verify.sh`; the verification produces a signed sidecar + evidence artifact. Used for steps whose `skill` is in the Claude-only set or that the RN Routing Directive sends to Claude. |
| `dual-pass` | both | Both agents work independently, Claude synthesizes. Used for security review and PR review only. |

The `owner` field is the primary dispatch signal during execution. The
`mode` field provides additional context about HOW the owner interacts
with the other agent. `codex-dispatch` reads both fields.

### In-thread `claude-impl` threshold

Conductor mode is the default. The main thread never writes code
directly — every step dispatches to a subagent — with one narrow
exception:

A `claude-impl` step MAY run inside the main thread iff BOTH:
1. the step's `files` array has **≤1 file**, AND
2. the step's `skill` is one of `{brainstorming, writing-plans,
   doc-coauthoring}`.

Every other `claude-impl` step dispatches to an Opus subagent. Every
`codex-impl` step dispatches via `run-codex-implement.sh`.

## Receipt-first verification

Under conductor mode, both directions of verification produce structured
artifacts the main thread reads via digest subagents — never raw text:

- **`codex-impl` step**: `run-codex-implement.sh` writes
  `<plan-dir>/codex-receipt-step-N.json` (evidence artifact) plus an
  HMAC-signed sidecar receipt under
  `~/.claude/look-before-you-leap/state/<projectId>/<planId>/`. The
  Claude verification subagent reads the receipt; the
  `.codex-result-step-N.txt` trace is preserved for human debugging
  only and its sha256 is bound into the sidecar.
- **`claude-impl` step**: `run-codex-verify.sh` writes the verify
  evidence artifact + signed sidecar with the same dual-authority
  binding.

See `look-before-you-leap/references/codex-receipt-schema.md` for the
authoritative schema and the strict verifier contract enforced by
`verify-step-completion.sh`.

## Machine defaults — never downgrade

Default models are configured at the machine level — Claude Code = Opus
4.7 high; Codex = gpt-5.5 high fast. Dispatch scripts and skill prompts
MUST NOT pass `--model` flags that downgrade these defaults. Plan steps
MUST NOT include such flags in their descriptions or acceptance
criteria. See `look-before-you-leap/references/machine-defaults.md`.

## masterPlan.md (companion file)

masterPlan.md is the human-facing proposal document reviewed via Orbit. It
lives alongside plan.json in the same directory. **It is write-once** —
frozen after Orbit approval and never updated during execution.

Its purpose:

- Present the plan to the user for Orbit review
- Summarize what, why, critical decisions, warnings, risk areas
- Does NOT contain execution state (no `[x]`/`[ ]` checkboxes)
- Serves as a stable record of what was agreed upon

All runtime state (progress, results, completed summaries, deviations)
lives exclusively in progress.json (updated via plan_utils.py).
plan.json is immutable after approval.

See `references/master-plan-format.md` for the template.
