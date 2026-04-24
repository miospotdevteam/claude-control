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

## Three-File Architecture

Every plan consists of three files:

- **`plan.json`** — Immutable plan definition. Steps, acceptance criteria,
  files, ownership, mode, skill. Frozen after Orbit approval. **Never edited
  during execution.** Hooks read this for step structure.
- **`progress.json`** — Mutable execution state. Step statuses, results,
  progress item statuses, completedSummary, deviations, codexSessions.
  Auto-created on first mutation and updated via `plan_utils.py` commands.
  This is what changes during execution.
- **`masterPlan.md`** — Proposal document for user review via Orbit.
  Summarizes what, why, critical decisions, warnings, and risk areas.
  Human-facing. **Write-once**: frozen after Orbit approval, never updated
  during execution.

Orbit reviews `masterPlan.md`. Once approved, `plan.json` and
`masterPlan.md` are treated as frozen records of the agreed work; all
runtime state moves to `progress.json`.

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
this directory, install the helper wrappers under `.temp/plan-mode/scripts/`,
and ensure `.temp/` is gitignored:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-plan-dir.sh
```

---

## Updating Progress

Use `plan_utils.py` via the Bash tool. Prefer the project-local helper copy
under `.temp/plan-mode/scripts/` because `init-plan-dir.sh` installs it in
every repo and it stays stable even if plugin cache or install paths change.
All commands write to `progress.json` automatically — pass the `plan.json`
path and mutations go to the right file. For strict plans, use
`complete-step` so receipt checks run before a step is marked done:

<!-- plan-utils-cmd-start -->
```bash
PLAN_UTILS=".temp/plan-mode/scripts/plan_utils.py"
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

# Get the runnable frontier (parallel-by-default execution loop uses this)
python3 "$PLAN_UTILS" runnable-steps "$PLAN_JSON"

# Get next single step (legacy — only useful when frontier is size 1)
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
- Whether a single proposed step should be decomposed into multiple
  steps wired with `dependsOn`

```bash
# Query blast radius for a file
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/deps-query.py . "<file_path>"

# JSON output for programmatic use
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/deps-query.py . "<file_path>" --json
```

Feed the dep-map output directly into your plan: use the DEPENDENTS list
to populate each step's `files` array, and use the BLAST RADIUS count
to decide whether a proposed step should be decomposed into multiple
steps wired with `dependsOn`. This replaces manual grep for consumer
discovery during planning and catches cross-module consumers that grep
would miss.

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

| Complexity | Characteristics | How to plan |
|---|---|---|
| Small | 1-3 files, straightforward change | One step with progress items |
| Medium | 4-5 files, some complexity | One step with detailed progress items |
| Large | Triggers any decomposition criterion below | Multiple steps wired with `dependsOn` |

### When to decompose into multiple steps

Decompose a single proposed step into multiple plan.json steps (each
with its own `dependsOn` edges) when ANY of these are true:

- Dep maps show the work touches **more than 5 files** (direct +
  consumers). This is the primary trigger — dep maps give you exact file
  counts, so use them.
- It touches **more than 10 files** (when dep maps aren't available)
- It involves a **repetitive sweep** across many files
- It has **more than 5 internal sub-tasks** that are independently
  completable
- The description contains words like **"all", "every", "sweep",
  "migrate all", "across the codebase"**

There is no `subPlan.groups` mechanism — group-based sub-plan execution
has been removed. Decomposition happens at the step level via the DAG:
write multiple steps, give each one a clear ownership / scope, and use
`dependsOn` to express ordering constraints. Steps without ordering
constraints become parallel frontier candidates automatically.

Example decomposition (sweep across four file clusters):

```json
{ "id": 2, "title": "Add archivedAt to core types and schemas",
  "files": ["types.ts", "schemas.ts"], "dependsOn": [],
  "owner": "codex", "mode": "codex-impl", ... },
{ "id": 3, "title": "Update business-logic filtering for archivedAt",
  "files": ["filtering.ts"], "dependsOn": [2],
  "owner": "codex", "mode": "codex-impl", ... },
{ "id": 4, "title": "Add archivedAt to API client methods",
  "files": ["client.ts"], "dependsOn": [2],
  "owner": "codex", "mode": "codex-impl", ... },
{ "id": 5, "title": "Update API seed data and routes",
  "files": ["seed.ts"], "dependsOn": [2],
  "owner": "codex", "mode": "codex-impl", ... }
```

Steps 3, 4, and 5 all depend only on step 2 — so once step 2 is done,
they form a parallel frontier of size 3 and dispatch in a single message.

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

This is a loop. Follow it mechanically. **Parallel frontier dispatch is the
default.** Serial execution is the exception, used only when the DAG genuinely
yields a frontier of size 1 (or when a stated reason — see below — forces it).

```
┌─ EXECUTION LOOP (DAG-DRIVEN, PARALLEL BY DEFAULT) ──────┐
│                                                         │
│  0. IF first loop entry (or after compaction):          │
│     Create/recreate tasks from plan.json steps:         │
│     TaskCreate for each step:                           │
│       subject: "[Step N/total: owner] title"            │
│       Set completed steps to status: "completed"        │
│       Set in_progress steps to status: "in_progress"    │
│                                                         │
│  1. Read plan.json + progress.json from disk            │
│  2. Compute the runnable frontier via the CLI:          │
│     python3 .temp/plan-mode/scripts/plan_utils.py \\     │
│         runnable-steps <plan.json>                      │
│     (returns ALL pending steps whose dependsOn          │
│      predecessors are done — this is the frontier)      │
│                                                         │
│  3. IF frontier is empty AND no in_progress → done      │
│                                                         │
│  4. DISPATCH THE ENTIRE FRONTIER IN A SINGLE MESSAGE.   │
│     a. Mark every frontier step in_progress — write to  │
│        progress.json NOW (one update-step per step)     │
│        → TaskUpdate(in_progress) for each               │
│     b. In ONE assistant message, emit one tool call per │
│        step so Claude Code runs them concurrently:      │
│        - claude-impl: Agent (foreground sub-agent),     │
│          one Agent call per step, all in the same       │
│          message                                        │
│        - codex-impl: Bash run-codex-implement.sh        │
│          (run_in_background: true), one per step        │
│     c. Wait for ANY completion (do not block until      │
│        all finish — refetch as soon as one PASSes so    │
│        newly-unblocked steps join the next frontier)    │
│     d. For each completed step, run the verification    │
│        gate (Codex verify for claude-impl, Claude       │
│        verify for codex-impl) and read the SIGNED       │
│        receipt artifact (codex-receipt-step-N.json or   │
│        the equivalent claude verify digest). NEVER      │
│        read raw `.codex-result-step-N.txt` or           │
│        `.codex-stream-step-N.jsonl` from the main       │
│        thread — those are inputs to a digest subagent,  │
│        not to the conductor.                            │
│     e. Fix any findings (sequentially per step), then   │
│        re-verify until PASS                             │
│     f. complete-step for each verified step,            │
│        TaskUpdate(completed), add-summary               │
│                                                         │
│  5. REFETCH THE FRONTIER (GOTO step 1).                 │
│     Completing steps unblocks new ones — recompute      │
│     immediately rather than guessing.                   │
│                                                         │
│  CODEX GATE (for steps with codexVerify: true):         │
│     a. Verifier runs (Codex for claude-impl, Claude     │
│        for codex-impl) and writes a signed receipt      │
│     b. Conductor reads the receipt's finalVerdict +     │
│        per-criterion pass/fail (NOT raw output)         │
│     c. If FAIL: fix → re-run verify → repeat            │
│     d. Only proceed to complete-step after PASS         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### The runnable-steps pattern

The pattern is mechanical and identical every iteration:

1. **Fetch the frontier** — `runnable-steps` returns the set of pending
   steps whose `dependsOn` predecessors are all done.
2. **Dispatch all in parallel** — one assistant message containing one
   Agent/Bash tool call per frontier step. The tool calls run concurrently
   because they share a single message.
3. **Mark complete** — once a step's verification receipt is PASS, call
   `complete-step` (which writes to progress.json and updates summaries).
4. **Refetch** — go back to step 1. Completed steps unblock new ones; the
   next frontier may be larger, smaller, or differently shaped.

Do not try to plan the schedule ahead. The DAG decides — you just keep
asking for the frontier and dispatching it.

### Anti-pattern: sequential dispatch of independent steps

**NEVER execute frontier steps one-at-a-time.** If `runnable-steps`
returns steps [1, 2, 3], dispatching step 1, waiting for it to finish,
then dispatching step 2, etc. is wrong — it ignores the DAG and makes
execution 3x slower than necessary.

The correct behavior: emit all three Agent/Bash tool calls in a single
message so Claude Code runs them concurrently. See the conductor skill's
"DAG-driven parallel dispatch" section for a concrete example.

**Stated-reason exceptions to parallel dispatch.** Serial execution is
allowed only when one of these is true, AND you record the reason in the
step's result or via `add-deviation`:

- Frontier size is 1 (only one step is runnable right now)
- Steps share a write target that cannot be safely interleaved
- A previous step's failure forced a "fix one, re-verify, then continue"
  recovery loop
- The user explicitly requested serial execution

Without one of these, parallel dispatch is the default.

### Never mark done without verified work

A step is NOT complete just because you wrote some code. Before marking
any step `done`:

1. The code you wrote actually works (you verified it, not just assumed)
2. The step's acceptance criteria are met
3. Every item on the deliverables checklist (extracted in step 3b of the
   loop) has been verified — if any deliverable is missing, implement it
   before marking done
4. If `codexVerify: true`: a SIGNED verification receipt
   (`codex-receipt-step-N.json` for claude-impl steps, the equivalent
   claude-verify digest receipt for codex-impl steps) exists with
   `finalVerdict: PASS` and per-criterion `verdict: pass`. The receipt
   is the contract — not freeform text in the result field.
5. You've written a structured result using the `### Criterion:` template,
   mapping each acceptance criterion to evidence, with the receipt-backed
   Codex/Claude verdict surfaced in a `### Verdict` section. The
   structured result is a human-readable rendering of the receipt; the
   receipt is the machine-readable source of truth that hooks gate on.

**A plan with all steps `done` but unverified work is a lie on disk.** A
hook guards the `mv` command — you cannot move an incomplete plan to
`completed/`. The `verify-step-completion` hook also enforces the Codex
gate: if a codexVerify step is marked done without a corresponding signed
receipt (and a verdict surfaced in the result field), it reverts to
`in_progress`. Don't mark steps done until they ARE done. If you're
unsure, leave it `in_progress` with notes about what remains.

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
7. Continue the execution loop above — refetch the runnable frontier and
   dispatch all of it in a single message (parallel by default).

**You MUST do this before touching any code.** The plan files on disk are
the source of truth, not your memory of what you were doing.

### If multiple in-progress steps exist

Multiple `in_progress` steps means compaction happened during parallel
frontier dispatch. For each in_progress step:

1. Check its `dependsOn` — if ALL predecessors are `done`, the step was
   legitimately running in parallel and can be re-dispatched as part of
   the next frontier
2. If a predecessor is also `in_progress`, the step may be stale from a
   crash — wait for the predecessor to complete first
3. Determine the step's phase via signed receipts (NOT raw files):
   - Check `codexSessions[step_id].phase` in progress.json — if `"verify"`,
     the step was mid-verification. Look for the verification receipt
     (`codex-receipt-step-N.json` for claude-impl, the claude-verify
     digest receipt for codex-impl). If a PASS receipt exists, the step
     finished verification and can be marked done; otherwise re-run
     verification.
   - If `codexSessions[step_id].phase` is `"implement"` (codex-impl step),
     Codex was mid-implementation. Check the implement receipt
     (`codex-receipt-step-N.json` with `kind: implement`). If present
     and PASS, advance to verification; otherwise re-dispatch implement.
   - If no codexSessions entry exists for this step, it was mid-
     implementation by Claude. Resume from progress items.
4. The conductor reads RECEIPTS, not raw artifacts. `.codex-result-*.txt`
   and `.codex-stream-*.jsonl` are inputs to the digest subagent — if you
   need their content, dispatch a digest subagent and read its bounded
   output, never the raw file from the main thread.

Re-dispatch legitimate parallel steps via the runnable-steps pattern
above (refetch the frontier, dispatch in one message).

### If a single in-progress step exists

A step with status `in_progress` means compaction happened mid-step. Read
the step's progress array — the `done` items tell you what's been done.
Check `git status` for committed/staged work. If the step had reached
verification, look for the signed receipt (`codex-receipt-step-N.json`
or the claude-verify digest). Continue from where the progress left
off — do NOT re-read raw `.codex-result-*.txt` or `.codex-stream-*.jsonl`
from the main thread; dispatch a digest subagent if you need their
content.

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
| Dep maps show >5 files for a step | Decompose into multiple steps wired with `dependsOn` |
| Step touches >10 files or is a sweep | Decompose into multiple steps wired with `dependsOn` |
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
