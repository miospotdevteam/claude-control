---
name: writing-plans
description: "Use after discovery to write implementation plans with TDD-granularity steps. Produces masterPlan.md that assumes the implementing engineer has zero codebase context and questionable taste. Every masterPlan step is one component/feature; TDD rhythm (test, verify fail, implement, verify pass, commit) lives in its Progress items. Consumes discovery.md from exploration phase. Invoke explicitly at Step 2 of the conductor. Do NOT use when: the user explicitly says 'just do it' or 'no plan', resuming an existing plan (use persistent-plans resumption protocol), executing a plan that already exists on disk, or doing pure research/exploration without code changes."
---

# Writing Plans

Turn discovery findings into bite-sized implementation plans. Assume the
implementing engineer has zero context for this codebase and questionable
taste. Document everything they need: which files to touch, complete code,
exact commands, expected output. Give them the whole plan as bite-sized
tasks. DRY. YAGNI. TDD. Frequent commits.

**Announce at start:** "I'm using the writing-plans skill to create the
implementation plan."

**Prerequisite:** Discovery must be complete. If no `discovery.md` exists
in the plan directory, go back to Step 1 (Explore) first.

---

## The Steps

### 1. Read the discovery

Read `discovery.md` from `.temp/plan-mode/active/<plan-name>/`. Understand
the scope, entry points, consumers, existing patterns, test infrastructure,
and blast radius. This feeds directly into the masterPlan.

If the brainstorming skill produced a `design.md` in the same plan
directory (`.temp/plan-mode/active/<plan-name>/design.md`), read that
too — it contains the approved design decisions.

### 2. Identify applicable disciplines

Scan the task and mark which checklists apply. Read each relevant checklist
now — they inform how you structure the steps.

| If the task involves... | Read before planning... |
|---|---|
| Writing or modifying tests | `references/testing-checklist.md` |
| Building or modifying UI | `references/frontend-design-checklist.md` + `references/ui-consistency-checklist.md` |
| Auth, input validation, secrets | `references/security-checklist.md` |
| Adding/removing packages | `references/dependency-checklist.md` |
| API route handlers or endpoints | `references/api-contracts-checklist.md` |

Also note these for the executing engineer (they apply during execution,
not planning):

- **git-checklist.md** — applies at every commit step
- **linting-checklist.md** — applies after any code changes

### 3. Write the masterPlan

Use the template from `references/master-plan-format.md`. Write to
`.temp/plan-mode/active/<plan-name>/masterPlan.md`.

The Discovery Summary in the masterPlan comes directly from your
discovery.md findings.

#### Plan document header

Every masterPlan MUST include this directive after the title so that a
fresh session knows how to execute it:

```markdown
# Plan: <Title>

> **For Claude:** REQUIRED SKILL: Use look-before-you-leap:engineering-discipline
> for all steps. Also invoke each step's `Skill` field when it is not `none`.
> See the Required Skills section for the full list.
```

#### Granularity: how steps map to TDD

One masterPlan Step = one component or feature unit. The TDD rhythm lives
in the **Progress** checklist within each step:

```markdown
### Step N: <Component Name>
- **Status**: [ ] pending
- **Skill**: `look-before-you-leap:test-driven-development` | none
- **Simplify**: true/false
- **Files involved**: `src/auth/validator.ts`, `tests/auth/validator.test.ts`
- **Description**: Add email validation to the auth module.
- **Acceptance criteria**: `npm test -- validator` passes, tsc clean.
- **Progress**:
  - [ ] Write failing test
  - [ ] Run test — verify it fails
  - [ ] Implement minimal code to pass
  - [ ] Run tests — verify they pass
  - [ ] Commit
- **Result**:
```

Each Progress item is one action (2-5 minutes).

#### When to set `Simplify: true`

Set `Simplify: true` on a step when any of these apply:

- Step modifies **3 or more files**
- Step creates **new abstractions** (utilities, components, modules)
- Step involves **structural changes** (refactored APIs, new patterns)
- User **explicitly requests** simplification for the step

Default to `false` for simple steps (1-2 files, straightforward changes).
When in doubt, leave it `false` — the user can always request a
simplification pass manually.

#### Key rules

- **Exact skill identifiers** — in Required Skills AND in each step's
  `Skill` field, use the full skill name (e.g., `look-before-you-leap:frontend-design`),
  never vague hints like "look for skills about testing". Post-compaction
  Claude has no memory — only exact names let it invoke the right skill.
  Use `none` for steps that don't need a specialized skill.
- **Complete code in every step** — not "add validation" but the actual
  code the engineer should write
- **Exact file paths** — every step lists Create/Modify/Test files
- **Exact commands with expected outcome** — include the command to run and
  the expected outcome (pass/fail, exit code, key output lines), not
  necessarily full verbatim output
- **Self-contained** — the masterPlan is the ONLY thing the executing
  engineer reads. If it's not in the plan, it doesn't exist for them
- **DRY / YAGNI** — cut anything not clearly needed right now
- **Frequent commits** — after every green test or logical unit of work

#### Concrete example

````markdown
### Step 1: Email validation utility

- **Status**: [ ] pending
- **Skill**: none
- **Simplify**: false
- **Files involved**:
  - Create: `src/lib/validate-email.ts`
  - Create: `tests/lib/validate-email.test.ts`
- **Description**: Add an email validation function. Rejects empty strings,
  missing @, missing domain. Returns `{ valid: boolean; error?: string }`.
- **Acceptance criteria**: `npx vitest run validate-email` passes, `tsc --noEmit` clean.
- **Progress**:
  - [ ] Write failing test
  - [ ] Run: `npx vitest run validate-email` — expect FAIL (module not found)
  - [ ] Implement minimal code
  - [ ] Run: `npx vitest run validate-email` — expect PASS
  - [ ] Commit: `git add src/lib/validate-email.ts tests/lib/validate-email.test.ts && git commit -m "feat: add email validation utility"`

**Test code:**
```typescript
import { validateEmail } from '../src/lib/validate-email'

test('rejects empty string', () => {
  expect(validateEmail('')).toEqual({ valid: false, error: 'Email is required' })
})

test('rejects missing @', () => {
  expect(validateEmail('foo')).toEqual({ valid: false, error: 'Invalid email format' })
})

test('accepts valid email', () => {
  expect(validateEmail('user@example.com')).toEqual({ valid: true })
})
```

**Implementation code:**
```typescript
export function validateEmail(email: string): { valid: boolean; error?: string } {
  if (!email) return { valid: false, error: 'Email is required' }
  if (!email.includes('@') || !email.split('@')[1]?.includes('.')) {
    return { valid: false, error: 'Invalid email format' }
  }
  return { valid: true }
}
```
````

### 4. Hand off to execution

After saving the masterPlan to disk:

1. **If not already in plan mode**, call `EnterPlanMode` to enter it.
   If already in plan mode (e.g., the conductor entered it earlier), skip
   this step.
2. Read the masterPlan you just wrote from disk.
3. Write a summary to the **plan mode scratch pad** (the file specified in
   the plan mode system message — NOT the masterPlan.md). Include: the key
   steps, files involved, and acceptance criteria — enough for the user to
   approve or reject.
4. Call `ExitPlanMode` to present the plan to the user.

This gives the user the built-in **"autoaccept edits and clear context?"**
prompt. If they accept, context clears and the persistent-plans resumption
protocol picks up the masterPlan automatically — execution follows the
conductor's Step 3 with engineering-discipline.

---

## Boundaries

This skill must NOT:

- **Create plans outside `.temp/plan-mode/`** — all plans live in the
  defined directory structure, nowhere else.
- **Modify discovery.md during planning** — discovery is read-only input.
  If you find gaps, go back to Step 1 (Explore) first.
- **Overwrite an existing masterPlan.md without user consent** — if a plan
  already exists in the target directory, ask before replacing it.
- **Skip the plan mode handoff** — every plan must be presented to the user
  for approval via ExitPlanMode before execution begins.
- **Write implementation code** — this skill produces plans, not code files.
  Code belongs in the plan's code blocks, not in the project source tree.

**Autonomy limits**: reading discovery, reading checklists, writing
masterPlan.md, and writing sub-plans are autonomous. Overwriting an existing
plan and skipping the user-approval handoff require user confirmation.

**Prerequisites**: this skill is always invoked via the `look-before-you-leap`
conductor at Step 2. `${CLAUDE_PLUGIN_ROOT}` must resolve for reference file
paths. Discovery must be complete (`discovery.md` must exist in the plan
directory).

---

## Principles

- **Zero-context, questionable taste** — spell everything out; don't trust
  the engineer to make good test design or naming decisions
- **One component per step** — TDD rhythm in Progress items, not separate steps
- **TDD by default** — test first, then implement, always
- **Complete code** — never write "add error handling", write the actual code
- **DRY / YAGNI** — only what's needed now, nothing speculative
