---
name: persistent-plans
description: "Persistent planning system that writes every task plan to disk so it survives context compaction. Use this skill for ALL tasks — it is the default operating mode, not an optional add-on. Every coding task, feature, refactor, bug fix, migration, or multi-step operation starts with a plan written to `.temp/plan-mode/active/`. Even small tasks get a lightweight plan. The plan on disk is the source of truth, not context memory. Trigger this skill whenever you are about to do work. If you are starting a task, resuming after compaction, or the user says 'continue' — read the plan first. If no plan exists, create one. The only exception is truly trivial one-liner changes where the user explicitly says 'just do it' or 'no plan.' Do NOT use when: answering questions without code changes, pure research, documentation-only queries, or conversations that don't touch source files."
---

# Persistent Plans

Context is finite. Plans on disk are not. Every plan lives in
`.temp/plan-mode/` as structured files. When context compacts, the plan
survives. You read it, see where you left off, and continue. No work is
ever lost.

This skill adds **structure** (plan files, the execution loop)
on top of the **behavior** (thoroughness, blast radius checks, verification)
that engineering-discipline provides.

---

## Dual-File Architecture

Every plan consists of three files:

- **`plan.json`** — Immutable plan definition. Steps, acceptance criteria,
  files, ownership, mode, skill. Frozen after Orbit approval. **Never edited
  during execution.** Hooks read this for step structure.
- **`progress.json`** — Mutable execution state. Step statuses, results,
  progress item statuses, completedSummary, deviations, codexSessions.
  Updated constantly via `plan_utils.py` commands. This is what changes
  during execution.
- **`masterPlan.md`** — Proposal document for user review via Orbit.
  Summarizes what, why, critical decisions, warnings, risk areas.
  Human-facing. **Write-once**: frozen after Orbit approval, never updated
  during execution.

Hooks read both files. You update progress via `plan_utils.py` commands
(which write to `progress.json`). **Never Edit plan.json directly after
approval** — it is immutable. The user reviews `masterPlan.md` once during
planning.

---

## Auto-Compaction Survival

**This is the core reason this skill exists. Read this section first.**

Claude Code will auto-compact your context without warning. You cannot
prevent this. You cannot predict exactly when it will happen. Therefore,
your progress.json on disk must ALWAYS reflect your current progress.

**Treat every write to progress.json as a save point.** If auto-compaction
happens right now, would your plan files let you resume without
re-discovering anything? If the answer is no, update progress via
plan_utils.py immediately.

After ANY compaction (including auto-compaction), your FIRST action is to
read the active plan from disk. Do not wait for the user to say "continue".
If context was just compacted and there's an active plan, read it
immediately and state where you're resuming from.

---

## The Rule

**Every task gets a plan.json before any code is edited.**

The plan is your external memory. Write plan.json to disk, update progress
via plan_utils.py as you work, and trust the files over your recollection.
After compaction, plan.json + progress.json are all you have.

Exception: the user explicitly says "just do it" or "no plan" for a
single-line trivially obvious change. Everything else gets a plan.

---

## Boundaries

This skill must NOT:

- **Delete plan files** — only move completed plans from `active/` to
  `completed/`. Never `rm` a plan.
- **Create plans outside `.temp/plan-mode/`** — all plans live in the
  defined directory structure, nowhere else.
- **Proceed past a `blocked` step without user input** — blocked means
  blocked. Ask the user or skip to an independent step.
- **Mark a step `done` without running verification** — `done` means done
  AND verified, not "I wrote some code."
- **Move a plan to `completed/` with non-done items** — a hook enforces
  this, but the rule is the skill's, not just the hook's.

**Autonomy limits**: creating plans, writing to plan files, and updating
progress are autonomous. Deleting plans, skipping blocked steps, and
deviating from the plan require user confirmation.

Reinterpreting or narrowing an accepted step after verification has failed
also counts as a deviation. If Codex says a criterion was not met, you may
not redefine terms like "panel", "sync", or "complete" on your own. Ask
the user to approve the narrower scope and record it via `plan_utils.py add-deviation`
before proceeding.

**Prerequisites**: this skill is always invoked via the `look-before-you-leap`
conductor. `${CLAUDE_PLUGIN_ROOT}` must resolve for reference file paths. All
referenced templates live under `skills/look-before-you-leap/` relative to
the plugin root.

---

## Directory Structure

All plans live in `.temp/plan-mode/` relative to the project root. Active
plans go in `active/`; completed plans are automatically moved to
`completed/`.

```
.temp/plan-mode/
├── active/                       # Plans currently in progress
│   └── <plan-name>/              # kebab-case (e.g., "migrate-auth-to-v2")
│       ├── plan.json             # Immutable plan definition (frozen after approval)
│       ├── progress.json         # Mutable execution state (updated via plan_utils.py)
│       ├── masterPlan.md         # User-facing proposal document
│       └── discovery.md          # Exploration findings (optional)
├── completed/                    # Finished plans (moved here automatically)
│   └── <plan-name>/
│       └── ...
└── scripts/                      # Shared helper scripts
    ├── plan-status.sh
    └── resume.sh
```

Before creating your first plan, run the initialization script to set up
this directory and ensure `.temp/` is gitignored:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-plan-dir.sh
```

---

## Updating Progress

Use `plan_utils.py` via the Bash tool. All commands write to progress.json
automatically — pass the plan.json path and mutations go to the right file:

<!-- plan-utils-cmd-start -->
```bash
PLAN_UTILS="${CLAUDE_PLUGIN_ROOT}/scripts/plan_utils.py"
PLAN_JSON=".temp/plan-mode/active/<plan-name>/plan.json"

# Mark step 3 as in_progress
python3 "$PLAN_UTILS" update-step "$PLAN_JSON" 3 in_progress

# Mark progress item 0 of step 3 as done
python3 "$PLAN_UTILS" update-progress "$PLAN_JSON" 3 0 done

# Set the result field on step 3
python3 "$PLAN_UTILS" set-result "$PLAN_JSON" 3 "Migrated all hooks to new format"

# Mark step 3 as done (legacy plans)
python3 "$PLAN_UTILS" update-step "$PLAN_JSON" 3 done

# Mark step 3 as done (strict plans — gates on verification receipts)
# python3 "$PLAN_UTILS" complete-step "$PLAN_JSON" 3 "result text" "$PROJECT_ROOT"

# Add to completed summary
python3 "$PLAN_UTILS" add-summary "$PLAN_JSON" "Step 3: Migrated all hooks"

# Get status overview
python3 "$PLAN_UTILS" status "$PLAN_JSON"

# Get next step
python3 "$PLAN_UTILS" next-step "$PLAN_JSON"
```
<!-- plan-utils-cmd-end -->

---

## Phase 1: Create the Plan

When the user gives you a task:

1. **Do NOT start editing code.** Resist the urge.
2. **Explore** using engineering-discipline Phase 1 (read imports, consumers,
   sibling files, project conventions). Gather all the context you need.
3. **Use dep maps to size the blast radius** (see below).
4. **Write both files** to disk at
   `.temp/plan-mode/active/<plan-name>/`:
   - `plan.json` — structured execution plan using the **exact schema below**.
     Your exploration findings go into the `discovery` object. Every progress
     item gets `task`, `status`, AND `files` fields. No exceptions.
   - `masterPlan.md` — user-facing proposal for Orbit review (write-once,
     frozen after approval)

### Use dependency maps during planning

If dep maps are configured (check `.claude/look-before-you-leap.local.md`
for a `dep_maps` section), run `deps-query.py` on every file you plan to
modify BEFORE writing the plan. This tells you:

- How many consumers each file has (blast radius)
- Which modules will be affected
- Whether a step needs a sub-plan

```bash
# Query blast radius for a file
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/deps-query.py . "<file_path>"

# JSON output for programmatic use
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/deps-query.py . "<file_path>" --json
```

Feed the dep-map output directly into your plan: use the DEPENDENTS list
to populate each step's `files` array, and use the BLAST RADIUS count
to decide whether a step needs a sub-plan. This replaces manual grep
for consumer discovery during planning and catches cross-module consumers
that grep would miss.

### plan.json — the exact schema you MUST use

Do NOT invent your own plan format. Every plan.json must follow this
structure exactly. Hooks parse this schema — deviations break tooling.

```json
{
  "name": "plan-name-kebab-case",
  "title": "Descriptive Title",
  "context": "What the user asked for — enough for a fresh context to understand.",
  "status": "active",
  "requiredSkills": [],
  "disciplines": ["testing-checklist.md"],
  "discovery": {
    "scope": "Files/directories in scope",
    "entryPoints": "Primary files to modify",
    "consumers": "Who imports the files you're changing (from dep maps or grep)",
    "existingPatterns": "How similar problems are already solved",
    "testInfrastructure": "Test framework, where tests live, how to run them",
    "conventions": "Project-specific conventions",
    "blastRadius": "What could break — dep-map consumer counts go here",
    "confidence": "high"
  },
  "steps": [
    {
      "id": 1,
      "title": "Step title",
      "status": "pending",
      "skill": "none",
      "simplify": false,
      "codexVerify": true,
      "files": ["src/foo.ts", "src/bar.ts"],
      "description": "What needs to happen. Self-contained for a fresh context.",
      "acceptanceCriteria": "Concrete conditions (e.g., 'tsc --noEmit passes').",
      "progress": [
        {"task": "Add FooType to types.ts", "status": "pending", "files": ["src/foo.ts"]},
        {"task": "Update bar to use FooType", "status": "pending", "files": ["src/bar.ts"]}
      ],
      "subPlan": null,
      "result": null
    }
  ],
  "blocked": []
}
```

**Note:** `completedSummary`, `deviations`, and `codexSessions` are mutable
fields stored in `progress.json` (created by `plan_utils.py init-progress`).
Step `status`, `result`, and progress item statuses are also tracked in
`progress.json` during execution — the values in plan.json are initial only.

**Every step MUST have a `progress` array** — even simple steps get at
least 2 items. Progress items are your compaction insurance: if context
is lost mid-step, the done/pending items tell your next self exactly
where to resume. A step without progress items is a step that cannot be
resumed.

**Each progress item has exactly three required fields:**
- `task` — what to do (human-readable description)
- `status` — `"pending"`, `"in_progress"`, or `"done"`
- `files` — which files this sub-task touches (array of paths)

The `files` field is what makes resumption work — without it, your
compacted self has to re-discover which files to check. Do not replace
`files` with `result` or any other field. The step-level `result` field
is for the step's final summary; the progress-level `files` field is for
per-sub-task file tracking. They serve different purposes.

**The `discovery` object is required, not optional.** Your exploration
findings (blast radius, consumers, entry points, patterns) must be
captured in plan.json's `discovery` object — not just in your context
memory. After compaction, context is gone; the discovery object is how
your next self knows what you learned about the codebase. Write it when
you create the plan, even for small tasks. A plan without discovery is a
plan that forces re-exploration after compaction.

For full field reference, see
`${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/references/plan-schema.md`.

### Sizing steps

Each step should be completable within a single context window. Use these
heuristics:

| Complexity | Characteristics | Sub-plan? |
|---|---|---|
| Small | 1-3 files, straightforward change | No |
| Medium | 4-5 files, some complexity | No, but use progress items |
| Large | Triggers any sub-plan criteria below | Yes (inline in plan.json) |

### When to create sub-plans

A step MUST get an inline sub-plan (in the step's `subPlan` field) when
ANY of these are true:

- Dep maps show the step touches **more than 5 files** (direct +
  consumers). This is the primary trigger — dep maps give you exact file
  counts, so use them.
- It touches **more than 10 files** (when dep maps aren't available)
- It involves a **repetitive sweep** across many files
- It has **more than 5 internal sub-tasks** that are independently
  completable
- The step description contains words like **"all", "every", "sweep",
  "migrate all", "across the codebase"**

Sub-plans live **inside a step's `subPlan` field** — not at the top level,
not as separate files. Each group clusters related files:

```json
{
  "id": 2,
  "title": "Add archivedAt to all entity types and schemas",
  "status": "pending",
  "skill": "none",
  "simplify": false,
  "files": ["types.ts", "schemas.ts", "filtering.ts", "client.ts", "seed.ts"],
  "description": "Sweep archivedAt across shared, business-logic, api-client, api.",
  "acceptanceCriteria": "All types have archivedAt, schemas validate it, tests pass.",
  "progress": [
    {"task": "Group 1: Core types and schemas", "status": "pending", "files": ["types.ts", "schemas.ts"]},
    {"task": "Group 2: Business logic filtering", "status": "pending", "files": ["filtering.ts"]},
    {"task": "Group 3: API client methods", "status": "pending", "files": ["client.ts"]},
    {"task": "Group 4: API seed data and routes", "status": "pending", "files": ["seed.ts"]}
  ],
  "subPlan": {
    "groups": [
      {"name": "Core types and schemas", "files": ["types.ts", "schemas.ts"]},
      {"name": "Business logic filtering", "files": ["filtering.ts"]},
      {"name": "API client methods", "files": ["client.ts"]},
      {"name": "API seed data and routes", "files": ["seed.ts"]}
    ]
  },
  "result": null
}
```

Note how `progress` items mirror the `subPlan.groups` — both exist because
they serve different purposes. Progress items are the checkpoint mechanism
(updated via `plan_utils.py`). Groups are the organizational structure
(what files belong together and why).

---

## Phase 2: Execute the Plan

### The Checkpoint Rule (THE #1 RULE OF EXECUTION)

**After every 2-3 code file edits, you MUST update progress via plan_utils.py.**
This is a hard requirement enforced by a hook that will remind you if you
forget. All mutations write to `progress.json` — never edit `plan.json`
directly after approval.

What "update progress" means:
1. Use `plan_utils.py update-progress` to mark completed sub-tasks
2. Use `plan_utils.py update-step` to change step status
3. Use `plan_utils.py add-summary` when a step finishes

**Why this matters**: Auto-compaction can fire at any moment. If your
progress is stale, your next context window starts from scratch. Every
progress update is insurance against lost work.

**The Compaction Test**: *"If compaction fired RIGHT NOW, could someone
resume from the plan files alone?"* Ask this after every code edit. If the
answer is no, update progress BEFORE your next edit.

This is a loop. Follow it mechanically.

```
┌─ EXECUTION LOOP (DAG-DRIVEN) ───────────────────────────┐
│                                                         │
│  0. IF first loop entry (or after compaction):          │
│     Create/recreate tasks from plan.json steps:         │
│     TaskCreate for each step:                           │
│       subject: "[Step N/total: owner] title"            │
│       Set completed steps to status: "completed"        │
│       Set in_progress steps to status: "in_progress"    │
│                                                         │
│  1. Read plan.json + progress.json from disk            │
│  2. Compute runnable steps:                             │
│     runnable = runnable_steps(plan)                     │
│     (pending steps whose dependsOn predecessors are done)│
│                                                         │
│  3. IF no runnable AND no in_progress → plan complete   │
│                                                         │
│  4. IF 1 runnable step → execute sequentially:          │
│     a. Mark it in_progress — write to disk NOW          │
│        → TaskUpdate(status: "in_progress")              │
│     b. EXTRACT DELIVERABLES CHECKLIST                   │
│     c. Execute per owner-based dispatch (see conductor) │
│     d. CHECKPOINT after every 2-3 file edits            │
│     e. Verify deliverables checklist (every item)       │
│     f. Run own verification (tsc, lint, tests)          │
│     g. CODEX GATE (see below)                           │
│     h. Mark step done, TaskUpdate(completed),           │
│        add to completedSummary                          │
│                                                         │
│  5. IF multiple runnable steps → dispatch in parallel:  │
│     a. Mark ALL runnable steps as in_progress           │
│        → TaskUpdate(in_progress) for each               │
│     b. FOR each step:                                   │
│        - claude-impl: dispatch as foreground sub-agent  │
│          via Agent tool (implements + own verification)  │
│        - codex-impl: dispatch via run-codex-implement.sh│
│          (background — continue with other work)         │
│     c. Wait for all to complete                         │
│     d. Verify all (Codex verify for claude-impl,        │
│        Claude verify for codex-impl)                    │
│     e. Fix findings sequentially, re-verify as needed   │
│     f. Mark verified steps done, TaskUpdate(completed), │
│        add to completedSummary                          │
│                                                         │
│  CODEX GATE (for steps with codexVerify: true):         │
│     a. Run run-codex-verify.sh (claude-impl steps)      │
│        or Claude verifies independently (codex-impl)    │
│     b. If issues found: fix → re-run verify → repeat    │
│     c. Only proceed to "mark done" after PASS           │
│                                                         │
│  6. GOTO step 1 — new steps may now be runnable         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Never mark done without verified work

A step is NOT complete just because you wrote some code. Before marking
any step `done`:

1. The code you wrote actually works (you verified it, not just assumed)
2. The step's acceptance criteria are met
3. Every item on the deliverables checklist (extracted in step 3b of the
   loop) has been verified — if any deliverable is missing, implement it
   before marking done
4. If `codexVerify: true`: Codex has reported PASS via `run-codex-verify.sh`
   (for claude-impl steps) or Claude has independently verified (for
   codex-impl steps)
5. You've written a structured result using the `### Criterion:` template,
   mapping each acceptance criterion to evidence, with the Codex/Claude
   verdict in a `### Verdict` section

**A plan with all steps `done` but unverified work is a lie on disk.** A
hook guards the `mv` command — you cannot move an incomplete plan to
`completed/`. The `verify-step-completion` hook also enforces the Codex
gate: if a codexVerify step is marked done without a Codex verdict in
the result field, it reverts to `in_progress`. Don't mark steps done
until they ARE done. If you're unsure, leave it `in_progress` with
notes about what remains.

### Progress updates are NOT optional

**The progress array is a live checkpoint, not a decoration.** If
auto-compaction fires mid-step, the done items tell your next context
window exactly where to resume.

Rules:
- Mark each progress item `done` as soon as you finish it — before starting
  the next sub-task
- If a sub-task is partially done, mark it `in_progress` with a note
- **Never mark a step `done` if its progress items are still `pending`**.
  That means you skipped tracking — go back and update them first.
- Apply the Compaction Test after every 2-3 file edits.

### Result fields matter

When you complete a step, write the result using the **structured template**
that maps each acceptance criterion to evidence. This is not optional prose —
the `verify-step-completion` hook will count `### Criterion:` markers and
warn if they don't match the number of acceptance criteria.

**Template:**
```
### Criterion: "<quoted text from acceptanceCriteria>"
→ <what was done: file:line, function, behavior>
→ <how verified: command run, output observed>

### Criterion: "<next criterion>"
→ ...

### Verdict
Codex: PASS
```

Every acceptance criterion gets its own `### Criterion:` entry with 1-2
evidence lines. The `### Verdict` section contains the Codex/Claude verdict.

Bad: `"Done."` — no evidence, no criterion mapping
Bad: `"Created apiClient.ts with typed wrappers."` — no criterion mapping
Good: The structured template above — each criterion mapped to file:line evidence

---

## Phase 3: Resumption After Compaction

This is the FIRST thing you do when:
- You suspect context was compacted (including auto-compaction)
- The user says "continue" or "keep going"
- The SessionStart hook injected an active plan notice
- You find yourself in a fresh context with no memory of prior work

**Do NOT wait for the user to tell you to resume.** If there's an active
plan, read it immediately.

### Resumption protocol

1. Look for `.temp/plan-mode/active/` directory
2. Find the most recent plan (use `plan_utils.py find-active`)
3. Read plan.json (discovery, step definitions) and progress.json
   (completedSummary, step statuses, progress items)
4. Find ALL steps with status `in_progress` and all `pending` steps
5. For each `in_progress` step, check which progress items are done —
   that tells you exactly where within the step to resume
6. State to the user: *"Resuming plan '<title>'. Steps [done list] are
   complete. Steps [in_progress list] were in flight. Picking up from
   [specific progress points]."*
7. Continue the execution loop (DAG-driven — see below)

**You MUST do this before touching any code.** The plan files on disk are
the source of truth, not your memory of what you were doing.

### If multiple in-progress steps exist

Multiple `in_progress` steps means compaction happened during parallel
execution. For each in_progress step:

1. Check its `dependsOn` — if ALL predecessors are `done`, the step was
   legitimately running in parallel and can be re-dispatched
2. If a predecessor is also `in_progress`, the step may be stale from a
   crash — wait for the predecessor to complete first
3. Determine the step's phase (implementation vs verification):
   - Check `codexSessions[step_id].phase` in progress.json — if `"verify"`,
     the step was mid-verification (Claude had finished implementing,
     Codex was reviewing). Resume by re-running verification.
   - If `codexSessions[step_id].phase` is `"implement"` (codex-impl step),
     Codex was mid-implementation. Check result/stream files below.
   - If no codexSessions entry exists for this step, it was mid-
     implementation by Claude. Resume from progress items.
4. Check for existing result/stream files in the plan directory:
   - `.codex-result-step-N.txt` exists → Codex finished, parse the result
   - `.codex-stream-step-N.jsonl` exists but no result → Codex may still
     be running (check process) or may have crashed
   - Neither exists → step was mid-implementation, resume from
     progress items

Re-dispatch legitimate parallel steps using the DAG-driven execution
loop below.

### If a single in-progress step exists

A step with status `in_progress` means compaction happened mid-step. Read
the step's progress array. The `done` items tell you what's been done.
Assess the state (check git status, look at files) and continue from where
the progress left off.

### Plan vs filesystem conflicts

After compaction, you may find that the plan says a progress item is `done`
but the expected file doesn't exist on disk — or the file exists but looks
different from what you'd expect. This happens when compaction fired between
a file write and the next checkpoint.

**Resolution rules:**

1. **Plan says `done`, file exists** — trust the plan. The work was done.
   Move on to the next pending item.
2. **Plan says `done`, file is missing** — check git status and git log.
   If the file was committed, it was done. If it was never written (no
   trace in git or on disk), the progress item was marked prematurely —
   treat it as `pending` and redo it.
3. **Plan says `pending`, file exists** — the work was done but the plan
   wasn't checkpointed. Verify the file is correct, then mark the item
   `done` and continue.
4. **Plan says `in_progress` with partial notes** — read the notes, verify
   what's on disk matches, and continue from where the notes indicate.

**The key principle**: verify against disk state, then align the plan. Do
NOT blindly redo work the plan says is complete — check first. And do NOT
assume unchecked work is missing — the file might already be there from
before compaction.

---

## Plan Hygiene

- **Checkpoint constantly** — follow the Checkpoint Rule (Phase 2)
- **Update immediately** — after every step completion, write to disk
- **Never delete a plan** — when all steps are complete, move the plan
  folder from `active/` to `completed/`
- **If requirements change** — update progress via plan_utils.py FIRST,
  then continue execution. plan.json is immutable after approval.
- **The discovery section is sacred** — write it thoroughly during
  exploration; your compacted future self will thank you
- **Use the scripts** — run `plan-status.sh` to see all plan states, run
  `resume.sh` to find what to pick up next

### Script usage

```bash
bash .temp/plan-mode/scripts/plan-status.sh    # see all plan states
bash .temp/plan-mode/scripts/resume.sh         # find what to resume
```

---

## Integration with engineering-discipline

| Phase | persistent-plans adds | engineering-discipline provides |
|---|---|---|
| Orient | Plan file creation, discovery | Codebase exploration, reading neighborhoods |
| Execute | Execution loop, JSON updates, checkpoints | Blast radius checks, type safety, no scope cuts |
| Verify | Plan completion tracking, result logging | Type checker, linter, tests |
| Resume | Read plan.json from disk, check progress, continue | Self-audit for error patterns |

Both skills are always active. persistent-plans structures the work;
engineering-discipline ensures the work is done correctly.

---

## Quick Reference

| Situation | Action |
|---|---|
| New task from user | Explore -> write plan.json + masterPlan.md + init-progress in active/ -> execute |
| Every 2-3 file edits | Checkpoint via plan_utils.py |
| Step completed | complete-step (strict) or update-step done (legacy) + add-summary immediately |
| Dep maps show >5 files for a step | Use inline subPlan with groups |
| Step touches >10 files or is a sweep | Use inline subPlan with groups |
| After any compaction | Read plan.json + progress.json IMMEDIATELY -> state where you are -> continue |
| User says "continue" | Read plan.json + progress.json -> find next step -> execute |
| Requirements changed | Update progress via plan_utils.py -> continue execution |
| Stuck or blocked | update-step blocked -> ask user |
| All steps complete | Final verification -> move plan to completed/ -> report to user |

---

## Reference Files

Read these when you need the detailed templates:

- `${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/references/plan-schema.md` — exact plan.json schema
- `${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/references/claude-md-snippet.md` — recommended CLAUDE.md additions
