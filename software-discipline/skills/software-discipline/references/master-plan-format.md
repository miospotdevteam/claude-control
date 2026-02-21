# masterPlan.md Template

Copy this template exactly when creating a new plan. The Discovery Summary and
Completed Summary enable seamless resumption after compaction. The Progress field
within each step enables resumption mid-step when auto-compaction fires.

---

```markdown
# Plan: <Descriptive Title>

## Context

<2-3 sentences: what the user asked for, what project this is, key constraints.
Write this so a fresh context window understands the task without needing the
original conversation.>

## Required Skills

<List any installed skills that should be invoked at specific steps. Format:

- **Step N**: look for skills about <topic> (e.g., "testing", "frontend design")
- **Step M**: look for skills about <topic>

If no external skills are needed, write "None — all work covered by core
disciplines.">

## Applicable Disciplines

<Which discipline checklists apply to this task. Read the relevant checklist
before starting the associated step. Format:

- **testing-checklist.md** — applies at Steps N, M (writing/modifying tests)
- **security-checklist.md** — applies at Step K (auth/input handling)
- **git-checklist.md** — applies at all commit points

If unsure, list all that might apply — it's better to check an unnecessary
checklist than to miss a relevant one.>

## Discovery Summary

<Structured findings from the exploration phase. This section is your gift to
your future compacted self. Complete ALL 8 sections — if a section doesn't apply,
write "N/A" rather than omitting it.>

### Scope
<What files/directories are in scope for this change. Be explicit about
boundaries: "Only files in src/auth/ and src/middleware/. NOT touching
src/api/ even though it imports from auth.">

### Entry Points
<The primary files to modify and their current state. Include file paths
and brief descriptions of what they contain.>

### Consumers
<Who imports/uses the files you're changing. Include file paths found via
grep. If many consumers, list count and representative examples.>

### Existing Patterns
<How similar problems are already solved in this codebase. Naming
conventions, error handling patterns, data flow patterns, etc.>

### Test Infrastructure
<What testing framework is used, where tests live, how to run them,
any test utilities or fixtures already available.>

### Conventions
<Project-specific conventions from CLAUDE.md, README.md, or observed
patterns. Include coding style, file organization, naming rules.>

### Blast Radius
<What could break if you get this wrong. Shared utilities, types, APIs
that downstream consumers depend on.>

### Confidence Rating
<Low / Medium / High. Low = need more exploration before planning.
Medium = have enough to proceed but some unknowns. High = fully mapped.
You are NOT ready to plan until confidence is Medium or higher.>

## Steps

### Step 1: <Title>
- **Status**: [ ] pending
- **Sub-plan**: none
- **Files involved**: `src/foo.ts`, `src/bar.ts`
- **Description**: What needs to happen in this step. Be specific enough that
  a fresh context window can execute this without guessing.
- **Acceptance criteria**: How to know this step is done — concrete, verifiable
  conditions (e.g., "tsc --noEmit passes", "new route returns 200", "test X
  passes").
- **Progress**:
  - [ ] <sub-task description> (files: `foo.ts`, `bar.ts`)
  - [ ] <sub-task description> (files: `baz.ts`)
- **Result**: <leave empty — filled in after completion>

### Step 2: <Title>
- **Status**: [ ] pending
- **Sub-plan**: `sub-plan-01-schema-migration.md`
- **Files involved**: `drizzle/schema.ts`, `src/db/migrations/`, `src/models/`
- **Description**: ...
- **Acceptance criteria**: ...
- **Progress**:
  - [ ] <sub-task or file group description>
  - [ ] <sub-task or file group description>
- **Result**: <leave empty>

### Step 3: <Title>
...

## Blocked Items

<List anything that's blocked, why, and what's needed to unblock. Format:

- **Step N: <title>** — Blocked because <reason>. Needs: <what would unblock>.

If nothing is blocked, write "None.">

## Completed Summary

<Updated as steps complete. This is a running log so the next context window
doesn't have to re-discover what's been done. Format:

- **Step 1** (complete): Created apiClient.ts with typed wrappers. Used existing
  AuthContext pattern. Updated 3 consumer files.
- **Step 2** (complete): Migrated schema, ran drizzle push, verified all queries.

Start with "No steps completed yet." and update as you go.>

## Deviations

<Any places where the implementation deviated from the original plan and why.
This helps the next context window understand why reality differs from the plan.

Start with "None yet." and update as needed.>
```

---

## The Progress Field

The **Progress** field is a checklist of sub-tasks within a step. It serves as
a fine-grained save point — when auto-compaction fires mid-step, the checked
items tell your next context window exactly where to resume.

**Update the Progress checklist after every 2-3 file edits.** This is the
autosave mechanism that prevents lost work.

### Example: Progress during execution

Before starting:
```markdown
- **Progress**:
  - [ ] Update auth middleware (files: `middleware.ts`)
  - [ ] Update API client (files: `api.ts`, `types.ts`)
  - [ ] Update consumer pages (files: `login.tsx`, `signup.tsx`, `profile.tsx`)
```

After the first sub-task and partway through the second:
```markdown
- **Progress**:
  - [x] Update auth middleware (files: `middleware.ts`)
  - [~] Update API client — api.ts done, types.ts remaining
  - [ ] Update consumer pages (files: `login.tsx`, `signup.tsx`, `profile.tsx`)
- **Result**: (partial) middleware.ts updated to use new token format. Using
  existing refreshToken() utility from src/lib/auth.ts.
```

### When to add Progress items

- **Always** for steps with 3+ files
- **Always** for steps with multiple distinct sub-tasks
- For simple 1-2 file steps, Progress can be omitted or a single item

### Progress markers

| Marker | Meaning |
|--------|---------|
| `[ ]` | Not started |
| `[~]` | Partially done (add a note about what remains) |
| `[x]` | Complete |

## Status Markers

Use these exact markers — the helper scripts parse them:

| Marker | Meaning |
|--------|---------|
| `[ ] pending` | Not yet started |
| `[~] in-progress` | Currently being worked on |
| `[x] complete` | Done and verified |
| `[!] blocked` | Cannot proceed — see Blocked Items |

## Naming Convention

Plan directories live under `.temp/plan-mode/active/` and use kebab-case:

- `.temp/plan-mode/active/migrate-auth-to-v2/` (good)
- `.temp/plan-mode/active/fix-login-bug/` (good)
- `.temp/plan-mode/active/task-1/` (bad — not descriptive)
- `.temp/plan-mode/active/update/` (bad — too vague)

When all steps are complete, the plan folder is moved from `active/` to `completed/`.

## Small Task Plans

Even small tasks get plans, but they can be minimal:

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
Only `src/app/(auth)/login/page.tsx`. Button component itself is NOT modified.

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
- **Status**: [ ] pending
- **Sub-plan**: none
- **Files involved**: `src/app/(auth)/login/page.tsx`
- **Description**: Add `w-full` to the button wrapper div for mobile viewports
- **Acceptance criteria**: Button is full-width on mobile, unchanged on desktop
- **Result**:

## Blocked Items
None.

## Completed Summary
No steps completed yet.

## Deviations
None yet.
```
