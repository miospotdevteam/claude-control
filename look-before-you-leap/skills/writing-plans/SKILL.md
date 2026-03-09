---
name: writing-plans
description: "Use after discovery to write implementation plans with TDD-granularity steps. Produces both plan.json (execution source of truth) and masterPlan.md (user-facing proposal for Orbit review). Every step is one component/feature; TDD rhythm (test, verify fail, implement, verify pass, commit) lives in its progress items. Consumes discovery.md from exploration phase. Invoke explicitly at Step 2 of the conductor. Do NOT use when: the user explicitly says 'just do it' or 'no plan', resuming an existing plan (use persistent-plans resumption protocol), executing a plan that already exists on disk, or doing pure research/exploration without code changes."
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
and blast radius. This feeds directly into both plan.json and masterPlan.md.

If dep maps are configured, the discovery MUST include `deps-query.py` output
for every file in scope. If the discovery lacks deps-query output for a
TypeScript project, go back to Step 1 (Explore) and run it before planning.

If the brainstorming skill produced a `design.md` in the same plan
directory, read that too — it contains the approved design decisions.

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

### 3. Write the plan (dual output)

Produce **both** files in `.temp/plan-mode/active/<plan-name>/`:

#### plan.json — execution source of truth

Use the schema from `references/plan-schema.md`. This file is what hooks
read and what Claude updates during execution. Include:

- All discovery findings in the `discovery` object
- Steps with TDD-granularity progress items
- Inline sub-plans for large steps (see Step 4 below)
- Exact skill identifiers in `skill` fields

#### masterPlan.md — user-facing proposal

This is the document the user reviews via Orbit. It should communicate
**intent**, not execution state. Format:

```markdown
# Plan: <Title>

## What I Want To Do
[2-3 paragraph summary — the "elevator pitch" for the user]

## Critical Decisions
- Decision 1 and its implications
- Decision 2 and its implications

## Warnings
- Risk 1 and mitigation
- Risk 2 and mitigation

## Steps Overview
1. Step title → key files
2. Step title → key files
...

## Risk Areas
- High blast radius areas
- Integration points that could break
```

No `[x]`/`[ ]` checkboxes. No execution state. Just what, why, and what
could go wrong.

#### Step granularity: how steps map to TDD

One plan.json step = one component or feature unit. The TDD rhythm lives
in the **progress** array within each step.

**The key insight: each step must have MULTIPLE red-green cycles.** Don't
write all tests at once — that's speculative testing, not TDD. Instead,
break the behavior into slices and iterate: simplest case first, then add
complexity one behavior at a time. Each cycle adds 1-3 tests for one
specific behavior, then implements just enough to pass.

```json
{
  "id": 1,
  "title": "Email validation utility",
  "status": "pending",
  "skill": "look-before-you-leap:test-driven-development",
  "simplify": false,
  "files": ["src/lib/validate-email.ts", "tests/lib/validate-email.test.ts"],
  "description": "Add email validation function. Rejects empty strings, missing @, missing domain.",
  "acceptanceCriteria": "npx vitest run validate-email passes, tsc --noEmit clean.",
  "progress": [
    {"task": "Cycle 1 RED: test for simplest valid email", "status": "pending", "files": ["tests/lib/validate-email.test.ts"]},
    {"task": "Cycle 1 GREEN: implement basic validation", "status": "pending", "files": ["src/lib/validate-email.ts"]},
    {"task": "Cycle 2 RED: tests for empty string and missing @", "status": "pending", "files": ["tests/lib/validate-email.test.ts"]},
    {"task": "Cycle 2 GREEN: add rejection logic", "status": "pending", "files": ["src/lib/validate-email.ts"]},
    {"task": "Cycle 3 RED: tests for missing domain and edge cases", "status": "pending", "files": ["tests/lib/validate-email.test.ts"]},
    {"task": "Cycle 3 GREEN: handle remaining cases", "status": "pending", "files": ["src/lib/validate-email.ts"]},
    {"task": "Refactor and final verification", "status": "pending"}
  ],
  "subPlan": null,
  "result": null
}
```

Each progress item is one action (2-5 minutes). Notice the pattern:
alternating RED/GREEN items, each covering a slice of behavior. The
simplest case comes first. Aim for **3-5 cycles per step** — enough to
prove incrementalism without being tedious.

**Anti-pattern to avoid:** A single "Write all tests" item followed by a
single "Implement everything" item. That's test-first waterfall, not TDD.
The whole point of TDD is that each cycle's implementation informs what
the next cycle should test.

#### When to set `simplify: true`

Set `simplify: true` on a step when any of these apply:

- Step modifies **3 or more files**
- Step creates **new abstractions** (utilities, components, modules)
- Step involves **structural changes** (refactored APIs, new patterns)
- User **explicitly requests** simplification for the step

Default to `false` for simple steps.

#### Key rules

- **Exact skill identifiers** — in each step's `skill` field, use the full
  skill name (e.g., `look-before-you-leap:frontend-design`), never vague
  hints. Post-compaction Claude has no memory — only exact names work.
  Use `"none"` for steps that don't need a specialized skill.
- **Complete code in every step** — not "add validation" but the actual code
- **Exact file paths** — every step lists files in the `files` array
- **Exact commands with expected outcome** — in description or acceptance
  criteria, include the command and expected result
- **Self-contained** — the plan.json is the ONLY thing the executing
  engineer reads. If it's not in the plan, it doesn't exist for them
- **DRY / YAGNI** — cut anything not clearly needed right now
- **Frequent commits** — after every green test or logical unit of work

### 4. Evaluate sub-plan needs (mandatory checkpoint)

**Before saving the plan, evaluate EVERY step against these criteria:**

For each step, count the files in its `files` array. If ANY of these are
true, the step MUST have an inline `subPlan` with groups:

1. **More than 10 files** in the `files` array
2. **Repetitive sweep** — the description contains words like "all", "every",
   "sweep", "migrate all", "across the codebase"
3. **More than 5 progress items** that are independently completable
4. **More than 8 files to read** just to understand what to change
5. **The step is a migration** that touches the same pattern in many files

If ANY criterion is met, restructure the step NOW:

```json
{
  "subPlan": {
    "groups": [
      {"name": "Dashboard pages", "files": ["a.tsx", "b.tsx", "c.tsx"], "status": "pending", "notes": null},
      {"name": "Modal components", "files": ["d.tsx", "e.tsx"], "status": "pending", "notes": null}
    ]
  }
}
```

Groups should have 3-8 files each. If a group exceeds 8, split it.

**This is a hard checkpoint.** Do not proceed to Step 5 until every step
has been evaluated. If you skip this, large steps will fail mid-execution
when context runs out.

### 5. Present for review via Orbit

After saving both files to disk, present masterPlan.md to the user for
interactive review using the Orbit MCP:

1. Discover the Orbit tool: `ToolSearch query: "+orbit await_review"`
2. Tell the user: *"The plan is open in VS Code for review. Add inline
   comments on any section, then click Approve or Request Changes."*
3. Call `orbit_await_review` with the masterPlan.md path. This generates
   the artifact, opens it in VS Code, and **blocks** until the user clicks
   Approve or Request Changes.

#### Handle the response

`orbit_await_review` returns JSON with `status` and `threads`.

- **`approved`, no threads** → proceed to step 6 (plan mode handoff).
- **`approved`, with threads** → read each thread, reply as `agent`
  acknowledging the feedback, resolve threads, then proceed to step 6.
- **`changes_requested`** → read all threads. Update both masterPlan.md
  and plan.json to address the feedback. Reply to each thread explaining
  what changed. Resolve threads. Call `orbit_await_review` again for
  re-review. Loop back to handle the new response.
- **`timeout`** → tell the user the review timed out and ask them to
  review when ready.

### 6. Plan mode handoff (post-approval)

After the plan is approved via Orbit:

1. **If not already in plan mode**, call `EnterPlanMode` to enter it.
2. Read the plan.json you just wrote from disk.
3. Write a summary to the **plan mode scratch pad** (the file specified in
   the plan mode system message — NOT the masterPlan.md). Include: the key
   steps, files involved, and acceptance criteria — enough for the user to
   approve or reject.
4. Call `ExitPlanMode` to present the plan to the user.

This gives the user the built-in **"autoaccept edits and clear context?"**
prompt. If they accept, context clears and the persistent-plans resumption
protocol picks up the plan.json automatically — execution follows the
conductor's Step 3 with engineering-discipline.

---

## Boundaries

This skill must NOT:

- **Create plans outside `.temp/plan-mode/`** — all plans live in the
  defined directory structure, nowhere else.
- **Modify discovery.md during planning** — discovery is read-only input.
  If you find gaps, go back to Step 1 (Explore) first.
- **Overwrite an existing plan without user consent** — if a plan already
  exists in the target directory, ask before replacing it.
- **Skip the Orbit review** — every plan must be presented to the user
  for review via Orbit MCP before execution.
- **Skip the plan mode handoff** — after Orbit approval, every plan must
  go through plan mode handoff before execution begins.
- **Write implementation code** — this skill produces plans, not code files.
- **Skip the sub-plan evaluation** — Step 4 is mandatory for every plan.

**Autonomy limits**: reading discovery, reading checklists, writing plan
files, and writing sub-plans are autonomous. Overwriting an existing plan
and skipping the user-approval handoff require user confirmation.

**Prerequisites**: this skill is always invoked via the `look-before-you-leap`
conductor at Step 2. `${CLAUDE_PLUGIN_ROOT}` must resolve for reference file
paths. Discovery must be complete (`discovery.md` must exist in the plan
directory).

---

## Principles

- **Zero-context, questionable taste** — spell everything out; don't trust
  the engineer to make good test design or naming decisions
- **One component per step** — TDD rhythm in progress items, not separate steps
- **TDD by default** — test first, then implement, always
- **Complete code** — never write "add error handling", write the actual code
- **DRY / YAGNI** — only what's needed now, nothing speculative
- **Sub-plans are mandatory** — if a step meets the criteria, it gets one
