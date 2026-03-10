# masterPlan.md Template

masterPlan.md is the **user-facing proposal document** reviewed via Orbit.
It communicates intent, critical decisions, warnings, and risk — NOT
execution state. Execution state lives in `plan.json` (see
`references/plan-schema.md`).

**Write-once**: masterPlan.md is frozen after Orbit approval. It is never
updated during execution. All runtime state (progress, results, deviations)
lives in `plan.json`. This keeps the proposal document as a stable record
of what was agreed upon.

No `[x]`/`[ ]` checkboxes. No progress tracking. No result fields.
Just what, why, and what could go wrong.

---

```markdown
# Plan: <Descriptive Title>

> **For Claude:** REQUIRED SKILL: Use look-before-you-leap:engineering-discipline
> for all steps. Also invoke each step's `Skill` field when it is not `none`.
> See the Required Skills section for the full list.

## Context

<2-3 sentences: what the user asked for, what project this is, key constraints.
Write this so a fresh context window understands the task without needing the
original conversation.>

## Required Skills

<List any installed skills that should be invoked at specific steps. Use exact
skill identifiers. Format:

- **Step N**: `look-before-you-leap:frontend-design` (full mode)
- **Step M**: `look-before-you-leap:writing-plans` (plan generation)

If no external skills are needed, write "None — all work covered by core
disciplines.">

## Applicable Disciplines

<Which discipline checklists apply to this task. Format:

- **testing-checklist.md** — applies at Steps N, M (writing/modifying tests)
- **security-checklist.md** — applies at Step K (auth/input handling)
- **git-checklist.md** — applies at all commit points>

## Discovery Summary

<Structured findings from exploration. Complete ALL 8 sections.>

### Scope
<What files/directories are in scope. Be explicit about boundaries.>

### Entry Points
<The primary files to modify.>

### Consumers
<Who imports/uses the files you're changing.>

### Existing Patterns
<How similar problems are already solved in this codebase.>

### Test Infrastructure
<Testing framework, test location, how to run tests.>

### Conventions
<Project-specific conventions.>

### Blast Radius
<What could break. Consumer counts, shared types, public API surfaces.>

### Confidence Rating
<Low / Medium / High with justification.>

## Steps

### Step 1: <Title>
- **Skill**: `look-before-you-leap:refactoring` | none
- **Simplify**: true/false
- **Sub-plan**: none
- **Files involved**: `src/foo.ts`, `src/bar.ts`
- **Description**: What needs to happen in this step.
- **Acceptance criteria**: How to know this step is done.

### Step 2: <Title>
...

## Blocked Items

<List anything that's blocked, why, and what's needed to unblock.
If nothing is blocked, write "None.">

## Risk Areas

<Highlight areas where things could go wrong — consumer breakage, security
implications, performance concerns, areas requiring manual verification.
If no notable risks, write "None.">
```

---

## Naming Convention

Plan directories use kebab-case under `.temp/plan-mode/active/`:

- `.temp/plan-mode/active/migrate-auth-to-v2/` (good)
- `.temp/plan-mode/active/fix-login-bug/` (good)
- `.temp/plan-mode/active/task-1/` (bad — not descriptive)

When all steps are complete, the plan folder moves to `completed/`.

## Small Task Plans

Even small tasks get plans, but masterPlan.md can be minimal:

```markdown
# Plan: Fix Login Button Alignment

## Context
The login button on /auth/login is misaligned on mobile viewports.

## Required Skills
None — all work covered by core disciplines.

## Applicable Disciplines
- **ui-consistency-checklist.md** — applies at Step 1

## Discovery Summary

### Scope
Only `src/app/(auth)/login/page.tsx`.

### Entry Points
- `src/app/(auth)/login/page.tsx` — login page with misaligned button wrapper

### Consumers
N/A — not changing any shared components.

### Existing Patterns
Other auth pages use `w-full` on mobile button wrappers.

### Test Infrastructure
N/A — visual change only.

### Conventions
Tailwind breakpoint is `md` (768px) per tailwind config.

### Blast Radius
None — single file, no shared code.

### Confidence Rating
High — issue is clear, fix is straightforward.

## Steps

### Step 1: Fix button alignment
- **Skill**: none
- **Simplify**: false
- **Sub-plan**: none
- **Files involved**: `src/app/(auth)/login/page.tsx`
- **Description**: Add `w-full` to the button wrapper div for mobile viewports
- **Acceptance criteria**: Button is full-width on mobile, unchanged on desktop

## Blocked Items
None.

## Risk Areas
None.
```

## Relationship to plan.json

masterPlan.md and plan.json are written together during the planning phase
(see `writing-plans` skill). They contain the same steps, but:

| Aspect | plan.json | masterPlan.md |
|---|---|---|
| **Audience** | Claude + hooks | User (via Orbit) |
| **Execution state** | Yes (status, progress, results) | No |
| **Updated during execution** | Yes (constantly) | Never (frozen after approval) |
| **Reviewed via Orbit** | No | Yes |
| **Parsed by hooks** | Yes | Legacy fallback only |

The plan.json schema is documented in `references/plan-schema.md`.
