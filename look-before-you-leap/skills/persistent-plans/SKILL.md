---
name: persistent-plans
description: >
  Persistent planning system that writes every task plan to disk so it survives context compaction. Use this skill for ALL tasks — it is the default operating mode, not an optional add-on. Every coding task, feature, refactor, bug fix, migration, or multi-step operation starts with a plan written to `.temp/plan-mode/active/`. Even small tasks get a lightweight plan. The plan on disk is the source of truth, not context memory. Trigger this skill whenever you are about to do work. If you are starting a task, resuming after compaction, or the user says "continue" — read the plan first. If no plan exists, create one. The only exception is truly trivial one-liner changes where the user explicitly says "just do it" or "no plan."
---

# Persistent Plans

Context is finite. Plans on disk are not. Every plan lives in
`.temp/plan-mode/` as a markdown file. When context compacts, the plan
survives. You read it, see where you left off, and continue. No work is
ever lost.

This skill adds **structure** (plan files, sub-plans, the execution loop)
on top of the **behavior** (thoroughness, blast radius checks, verification)
that engineering-discipline provides.

---

## Auto-Compaction Survival

**This is the core reason this skill exists. Read this section first.**

Claude Code will auto-compact your context without warning. You cannot
prevent this. You cannot predict exactly when it will happen. Therefore,
your plan files on disk must ALWAYS reflect your current progress.

**Treat every write to the plan file as a save point.** If auto-compaction
happens right now, would your plan file let you resume without
re-discovering anything? If the answer is no, update the plan file
immediately.

After ANY compaction (including auto-compaction), your FIRST action is to
read the active plan from disk. Do not wait for the user to say "continue".
If context was just compacted and there's an active plan, read it
immediately and state where you're resuming from.

---

## The Rule

**Every task gets a plan file before any code is edited.**

The plan is your external memory. Write it to disk, update it as you work,
and trust it over your recollection. After compaction, the plan is all you
have.

Exception: the user explicitly says "just do it" or "no plan" for a
single-line trivially obvious change. Everything else gets a plan.

---

## Directory Structure

All plans live in `.temp/plan-mode/` relative to the project root. Active
plans go in `active/`; completed plans are automatically moved to
`completed/`.

```
.temp/plan-mode/
├── active/                       # Plans currently in progress
│   └── <plan-name>/              # kebab-case (e.g., "migrate-auth-to-v2")
│       ├── masterPlan.md         # Source of truth
│       ├── sub-plan-01-<name>.md # Optional: for steps too large for one window
│       ├── sub-plan-02-<name>.md
│       └── ...
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
bash ${CLAUDE_PLUGIN_ROOT}/skills/software-discipline/scripts/init-plan-dir.sh
```

---

## Phase 1: Create the Plan

When the user gives you a task:

1. **Do NOT start editing code.** Resist the urge.
2. **Explore** using engineering-discipline Phase 1 (read imports, consumers,
   sibling files, project conventions). Gather all the context you need.
3. **Write masterPlan.md** to disk at
   `.temp/plan-mode/active/<plan-name>/masterPlan.md`.

The masterPlan format is documented in
`${CLAUDE_PLUGIN_ROOT}/skills/software-discipline/references/master-plan-format.md`.
Read that file for the exact template. The critical sections are:

- **Context**: What the user asked for and key constraints
- **Required Skills**: Which installed skills to invoke at which steps
- **Applicable Disciplines**: Which checklists apply (testing, security, etc.)
- **Discovery Summary**: Everything you learned during exploration — this is
  your gift to your future compacted self. Complete ALL 8 sections (Scope,
  Entry Points, Consumers, Existing Patterns, Test Infrastructure,
  Conventions, Blast Radius, Confidence Rating). Include file paths,
  patterns found, dependencies, conventions.
- **Steps**: Numbered, each with status, files involved, description,
  acceptance criteria, a **Progress** checklist for sub-tasks within the
  step, and a Result field filled in after completion.
- **Completed Summary**: A running log updated as steps finish.

### Sizing steps

Each step should be completable within a single context window. Use these
heuristics:

| Complexity | Characteristics | Sub-plan? |
|---|---|---|
| Small | 1-3 files, straightforward change | No |
| Medium | 4-10 files, some complexity | No, but use Progress checklist |
| Large | Triggers any sub-plan criteria below | Yes |

### When to create sub-plans

A step MUST get its own sub-plan when ANY of these are true:

- It touches **more than 10 files**
- It involves a **repetitive sweep** across many files
- It has **more than 5 internal sub-tasks** that are independently
  completable
- It requires **reading more than 8 files** just to understand what to
  change
- The step description contains words like **"all", "every", "sweep",
  "migrate all", "across the codebase"**

See `${CLAUDE_PLUGIN_ROOT}/skills/software-discipline/references/sub-plan-format.md`
for the template.

---

## Phase 2: Execute the Plan

This is a loop. Follow it mechanically.

```
┌─ EXECUTION LOOP ────────────────────────────────────────┐
│                                                         │
│  1. Read masterPlan.md from disk                        │
│  2. Find the next [ ] pending or [~] in-progress step   │
│  3. Mark it [~] in-progress — write to disk NOW         │
│                                                         │
│  4. IF step has a sub-plan:                             │
│     a. Read the sub-plan file                           │
│     b. Find next pending group/sub-step                 │
│     c. Execute the group/sub-step                       │
│     d. Update the sub-plan on disk (mark it [x])        │
│     e. Checkpoint: update masterPlan Progress field     │
│     f. IF all groups/sub-steps complete:                │
│        - Mark sub-plan [x] complete                     │
│        - Mark master step [x] complete                  │
│        - Write Result to masterPlan                     │
│        - Update Completed Summary                       │
│        - Run verification (engineering-discipline P3)   │
│                                                         │
│  5. IF step has no sub-plan:                            │
│     a. Execute the step                                 │
│     b. CHECKPOINT after every 2-3 file edits:           │
│        - Update the Progress checklist in masterPlan    │
│        - Write partial notes to the Result field        │
│     c. When done: mark step [x] complete                │
│     d. Write final Result to masterPlan                 │
│     e. Update Completed Summary                         │
│                                                         │
│  6. IF all steps are now [x] complete:                  │
│     a. Move plan folder from active/ to completed/      │
│     b. Report completion to the user                    │
│                                                         │
│  7. ELSE: Loop back to step 1                           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### The checkpoint rule

**Save progress continuously, not just at step boundaries.**

After every 2-3 file edits or every significant action within a step,
update the masterPlan.md:
- Check off completed items in the **Progress** checklist
- Add partial notes to the **Result** field if useful for recovery

Think of it like autosave in a video game — save constantly so that when
the crash (auto-compaction) happens, you lose minimal progress.

**The question to always ask yourself**: "If auto-compaction fired RIGHT
NOW, would my plan file let me resume exactly where I left off?" If no,
update the plan file before doing anything else.

### Progress updates are NOT optional

**The Progress checklist is a live checkpoint, not a decoration.** If
auto-compaction fires mid-step, the checked items tell your next context
window exactly where to resume.

Rules:
- Mark each `- [ ]` item `- [x]` as soon as you finish it — before starting
  the next sub-task
- If a sub-task is partially done, mark it `- [~]` with a note about what
  remains
- **Never mark a step `[x] complete` if its Progress items are still `[ ]`**.
  That means you skipped tracking — go back and check them off first.
- After every 2-3 file edits, ask: "If compaction fired RIGHT NOW, would my
  plan file let me resume exactly where I left off?" If no, update it now.

### Result fields matter

When you complete a step, the Result field should capture what you actually
did:
- Files created/modified
- Decisions made and why
- Anything unexpected that the next context window needs to know

Bad: `"Done."`
Good: `"Created apiClient.ts in src/lib/ with typed wrappers for all 5
endpoints. Used the existing AuthContext for token injection rather than a
separate interceptor — matches the pattern in src/lib/analytics.ts. Updated
imports in 3 consumer files: Dashboard.tsx, Settings.tsx, Profile.tsx."`

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
2. Find the most recently modified masterPlan.md
3. Read it completely — especially the **Discovery Summary** and
   **Completed Summary**
4. Find the next step with status `[ ] pending` or `[~] in-progress`
5. If the step has a **Progress** checklist, check which items are done —
   that tells you exactly where within the step to resume
6. If that step has a sub-plan, read the sub-plan too
7. State to the user: *"Resuming plan '<title>'. Steps 1-N are complete.
   Picking up at Step N+1: <title>, starting from <specific progress
   point>."*
8. Continue the execution loop

**You MUST do this before touching any code.** The plan on disk is the
source of truth, not your memory of what you were doing.

### If an in-progress step exists

A step marked `[~] in-progress` means compaction happened mid-step. Read
the step's Progress checklist and any partial Result notes. The checked-off
Progress items tell you what's been done. Assess the state (check git
status, look at files) and continue from where the Progress checklist left
off.

---

## Plan Hygiene

- **Checkpoint constantly** — after every 2-3 file edits, update Progress
  on disk
- **Update immediately** — after every step completion, write to disk
- **Never delete a plan** — when all steps are complete, move the plan
  folder from `active/` to `completed/`
- **If requirements change** — update masterPlan FIRST, then continue
  execution
- **The Discovery Summary is sacred** — write it thoroughly during
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
| Orient | Plan file creation, discovery summary | Codebase exploration, reading neighborhoods |
| Execute | Execution loop, disk writes, checkpoints, sub-plans | Blast radius checks, type safety, no scope cuts |
| Verify | Plan completion tracking, result logging | Type checker, linter, tests |
| Resume | Read plan from disk, check Progress, continue | Self-audit for error patterns |

Both skills are always active. persistent-plans structures the work;
engineering-discipline ensures the work is done correctly.

---

## Quick Reference

| Situation | Action |
|---|---|
| New task from user | Explore -> write masterPlan.md in active/ -> execute |
| Every 2-3 file edits | Checkpoint: update Progress checklist on disk |
| Step completed | Update plan on disk immediately |
| Step touches >10 files or is a sweep | Create sub-plan with Groups |
| After any compaction | Read plan IMMEDIATELY -> state where you are -> continue |
| User says "continue" | Read plan -> find next step/progress point -> execute |
| Requirements changed | Update masterPlan -> continue execution |
| Stuck or blocked | Mark step [!] blocked -> write why -> move on or ask user |
| All steps complete | Final verification -> move plan to completed/ -> report to user |

---

## Reference Files

Read these when you need the detailed templates:

- `${CLAUDE_PLUGIN_ROOT}/skills/software-discipline/references/master-plan-format.md` — exact masterPlan.md template
- `${CLAUDE_PLUGIN_ROOT}/skills/software-discipline/references/sub-plan-format.md` — sub-plan template with Groups
- `${CLAUDE_PLUGIN_ROOT}/skills/software-discipline/references/claude-md-snippet.md` — recommended CLAUDE.md additions
