# Sub-plan Template

Use this template when a master step is too large for a single context window.
Sub-plans break one master step into smaller pieces, each completable within a single context window.

## When to create a sub-plan

A step MUST get a sub-plan when ANY of these are true:

- It touches **more than 10 files**
- It involves a **repetitive sweep** across many files (e.g., "replace all
  silent catches", "update all API calls", "add i18n keys everywhere")
- It has **more than 5 internal sub-tasks** that are independently completable
- It requires **reading more than 8 files** just to understand what to change
- The step description contains words like **"all", "every", "sweep", "migrate
  all", "across the codebase"**

These are objective, countable criteria. Count files and sub-tasks — do not try to estimate tokens.

---

## Template: Standard sub-plan

For steps with a clear sequence of distinct sub-tasks:

```markdown
# Sub-plan: <Title>

**Parent**: masterPlan.md -> Step <N>
**Status**: [ ] pending

## Objective

<What this sub-plan accomplishes. This should map exactly to the parent step's
description. A fresh context window reading this should understand the goal
without needing the master plan.>

## Pre-conditions

<What must be true before starting this sub-plan. Be specific:
- Which files must exist (created by earlier steps)
- Which steps must be complete
- What state the codebase should be in
- Any environment or config requirements

A fresh context window uses this to verify the codebase is in the expected state
before continuing.>

## Sub-steps

### 1. <Title>
- **Status**: [ ] pending
- **Files involved**: `src/foo.ts`
- **Description**: What to do in this sub-step. Detailed enough for a fresh
  context window.
- **Result**: <leave empty — filled after completion>

### 2. <Title>
- **Status**: [ ] pending
- **Files involved**: `src/bar.ts`, `src/baz.ts`
- **Description**: ...
- **Result**:

### 3. <Title>
...

## Post-conditions

<What must be true after this sub-plan is complete. Used to verify success when
the next context window picks up. Be concrete:
- "All files in src/models/ have updated imports"
- "The /api/users endpoint returns the new response shape"
- "tsc --noEmit passes with zero errors"
- "The migration has been applied and rollback tested"

The next context window checks these before moving to the next master step.>

## Verification

<Specific commands to run to verify this sub-plan's work is correct:>

```bash
# Type check
bun run typecheck

# Run related tests
bun test src/models/

# Verify API response shape
curl -s localhost:3000/api/users | jq '.data[0] | keys'
```

<These commands should be copy-pasteable.>
```

---

## Template: Sweep sub-plan (with Groups)

For repetitive work across many files (replacing patterns, migrating calls, adding consistent changes). Organize by **file groups**, not individual files. This gives recovery granularity at the group level — if compaction happens between groups, the sub-plan shows exactly which groups are done.

```markdown
# Sub-plan: <Sweep Title>

**Parent**: masterPlan.md -> Step <N>
**Status**: [ ] pending

## Objective

<What this sweep accomplishes. Be specific about the pattern being changed and
the replacement. A fresh context window should be able to continue the sweep
without seeing the original conversation.>

## Pattern

<The exact thing being found and replaced/changed. Include:
- What to search for (grep pattern, code pattern, etc.)
- What to replace it with
- Any exceptions or special cases to watch for>

## Groups

### Group 1: <Logical cluster name>
- **Files**: `services/page.tsx`, `bookings/page.tsx`, `clients/page.tsx`, `floor-plan/page.tsx`
- **Status**: [ ] pending
- **Changes found**: <filled during execution — count of changes made>
- **Notes**: <filled during execution — special cases, decisions made>

### Group 2: <Logical cluster name>
- **Files**: `ServiceModal.tsx`, `ClientModal.tsx`, `BookingDetailModal.tsx`, `NewBookingModal.tsx`
- **Status**: [ ] pending
- **Changes found**:
- **Notes**:

### Group 3: <Logical cluster name>
- **Files**: `login/page.tsx`, `onboarding/page.tsx`, `reset-password/page.tsx`
- **Status**: [ ] pending
- **Changes found**:
- **Notes**:

## Post-conditions

<Concrete verification that the sweep is complete:
- "grep -r '<old pattern>' <path> returns 0 results"
- "All files use the new pattern"
- "Type checker passes">

## Verification

```bash
# Verify old pattern is gone
grep -r '<old pattern>' <path>
# Should return 0 results

# Type check
bunx tsc --noEmit

# Lint
bun run lint
```
```

### How to organize Groups

Group files by logical cluster — files that are related in purpose or location:

- **By directory**: "Dashboard pages", "Modal components", "Auth pages"
- **By feature**: "Booking flow", "Settings", "Onboarding"
- **By type**: "Page components", "Utility modules", "API routes"

Each group should have 3-8 files. If a group has more than 8 files, split it
into sub-groups. If a group has only 1 file, merge it with a related group.

### Checkpoint behavior for sweep sub-plans

After completing each Group:
1. Mark the Group `[x] complete` in the sub-plan
2. Fill in "Changes found" and "Notes"
3. Update the parent masterPlan.md Progress checklist
4. This is your save point — if compaction fires now, nothing is lost

---

## Status Markers

Same as masterPlan.md:

| Marker | Meaning |
|--------|---------|
| `[ ] pending` | Not yet started |
| `[~] in-progress` | Currently being worked on |
| `[x] complete` | Done and verified |
| `[!] blocked` | Cannot proceed |

## Naming Convention

Sub-plan files are named with a sequential number and descriptive kebab-case:

- `sub-plan-01-database-schema.md`
- `sub-plan-02-api-endpoints.md`
- `sub-plan-03-sweep-merchant-catches.md`

The number should match the order they appear in the master plan, not the order
of execution (which may differ if some are parallelizable).

## Linking to Master Plan

The master step that owns this sub-plan should reference it:

```markdown
### Step 3: Migrate database schema
- **Status**: [~] in-progress
- **Sub-plan**: `sub-plan-01-database-schema.md`
- **Files involved**: `drizzle/schema.ts`, `src/db/migrations/`, `src/models/`
...
```

When the sub-plan is fully complete:
1. Mark the sub-plan's top-level **Status** as `[x] complete`
2. Mark the master step as `[x] complete`
3. Write the Result in the master step summarizing what the sub-plan accomplished
4. Update the master plan's Completed Summary
