---
name: writing-plans
description: "Use after discovery to write implementation plans with TDD-granularity steps. Produces both plan.json (execution source of truth) and masterPlan.md (user-facing proposal for Orbit review). Every step is one component/feature; TDD rhythm (test, verify fail, implement, verify pass, commit) lives in its progress items. Consumes discovery.md from exploration phase. Make sure to use this skill whenever the user says discovery is done, exploration is finished, discovery.md is ready, or asks to write/create/draft the implementation plan — even if they don't mention plan.json or masterPlan.md by name. Also use when the user references completed exploration findings, blast radius analysis, or consumer mappings and wants them converted into actionable steps. Do NOT use when: the user says 'just do it' or 'no plan', resuming or executing an existing plan, during exploration or brainstorming (discovery not yet complete), debugging, or code review."
---

# Writing Plans

Turn discovery findings into bite-sized implementation plans. Assume the
implementing engineer has zero context for this codebase and questionable
taste. Document everything they need: which files to touch, precise
descriptions with file paths, exact commands, expected output. Give them
the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

**Announce at start:** "I'm using the writing-plans skill to create the
implementation plan."

**Prerequisite:** Discovery must be complete. If no `discovery.md` exists
in the plan directory, go back to Step 1 (Explore) first. If discovery.md
exists but is thin (missing blast radius counts, no consumer lists, vague
scope), warn the user that the plan quality will suffer and recommend going
back to enrich the discovery before continuing.

---

## The Steps

### 1. Read the discovery

Read `discovery.md` from `.temp/plan-mode/active/<plan-name>/`. This is the
raw exploration log — an append-only markdown file written during Step 1.

**Discovery flow** (each written once, never updated during execution):
1. **`discovery.md`** — raw exploration log (may have duplicates, rough notes)
2. **`plan.json.discovery`** — structured extraction: the 8 discovery fields
   distilled from the raw log into clean, self-contained summaries
3. **`masterPlan.md` Discovery Summary** — human-readable rendering of the
   same findings for Orbit review

Read discovery.md and extract what you need into plan.json's `discovery`
object. masterPlan.md's Discovery Summary is a human rendering of the same
data — both are written once during planning, then frozen.

If dep maps are configured (check `.claude/look-before-you-leap.local.md`
for a `dep_maps` section), the discovery MUST include `deps-query.py` output
for every file in scope. If the discovery lacks deps-query output for a
TypeScript project, go back to Step 1 (Explore) and run it before planning.
Dep maps are your most powerful planning tool — they give exact consumer
counts per file, which directly determines blast radius, step sizing, and
sub-plan needs. Never plan without them in a TypeScript project.

**design.md**: If the brainstorming skill produced a `design.md` in the same
plan directory, read it — it contains approved design decisions that must
inform the plan. Reference specific design decisions in step descriptions
where relevant (e.g., "Per design.md: use composition over inheritance for
the validator chain").

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

**Use dep maps to populate step `files` arrays.** If dep maps are
configured, run `deps-query.py` on each file you plan to modify. The
DEPENDENTS list tells you exactly which consumer files must be in the
step's `files` array — and which files to list in the blast radius
section of discovery. Without dep maps, you're guessing at consumers;
with them, you have the complete picture.

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/deps-query.py <project_root> <file_path>
```

#### masterPlan.md — user-facing proposal (write-once)

This is the document the user reviews via Orbit. It communicates **intent**,
not execution state. **It is frozen after Orbit approval** — never updated
during execution. All runtime state lives in plan.json.

Use the template from `references/master-plan-format.md`. No `[x]`/`[ ]`
checkboxes. No execution state. Just what, why, and what could go wrong.

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
    {"task": "Refactor and final verification", "status": "pending", "files": ["src/lib/validate-email.ts", "tests/lib/validate-email.test.ts"]}
  ],
  "subPlan": null,
  "result": null
}
```

Each progress item is one action (2-5 minutes). Notice the pattern:
alternating RED/GREEN items, each covering a slice of behavior. The
simplest case comes first. Aim for **3-5 cycles per step** — enough to
prove incrementalism without being tedious.

**Every progress item MUST have a `files` array — no exceptions.** Even
verification steps ("Run tsc --noEmit") and commit steps need `files`
listing the files being verified or committed. Use `[]` only if truly no
files are involved. This field is what makes resumption work after
compaction — without it, your next self has to re-discover which files
to check.

**Anti-pattern to avoid:** A single "Write all tests" item followed by a
single "Implement everything" item. That's test-first waterfall, not TDD.
The whole point of TDD is that each cycle's implementation informs what
the next cycle should test.

#### Which `skill` to assign each step

For each step, determine if a specialized skill should guide execution.
The `skill` field is read by the conductor at Step 3 — it dispatches the
skill before the step runs. Post-compaction, this is the ONLY way the
executor knows which guidance to follow.

| If the step involves... | Set `skill` to... |
|---|---|
| Writing new functions/components with tests, TDD cycles | `look-before-you-leap:test-driven-development` |
| Building/designing web UI, layouts, design systems, typography | `look-before-you-leap:frontend-design` |
| WebGL, Three.js, R3F, GSAP ScrollTrigger, 3D, scroll-driven | `look-before-you-leap:immersive-frontend` |
| React Native, mobile app, gestures, haptics, native feel | `look-before-you-leap:react-native-mobile` |
| Rename/move/extract across 3+ files | `look-before-you-leap:refactoring` |
| Bug investigation with root cause analysis | `look-before-you-leap:systematic-debugging` |
| E2E/browser testing, Playwright tests | `look-before-you-leap:webapp-testing` |
| Building an MCP server | `look-before-you-leap:mcp-builder` |
| Writing docs, specs, RFCs, proposals | `look-before-you-leap:doc-coauthoring` |
| All other steps (config, wiring, glue code) | `"none"` |

**When in doubt, prefer TDD over `"none"`** for any step that creates
testable behavior. TDD is the default for new logic — only use `"none"`
when the step has nothing to test (config files, wiring, migrations).

#### When to set `simplify: true`

Set `simplify: true` on a step when any of these apply:

- Step modifies **3 or more files**
- Step creates **new abstractions** (utilities, components, modules)
- Step involves **structural changes** (refactored APIs, new patterns)
- User **explicitly requests** simplification for the step

Default to `false` for simple steps.

#### When to set `qa: true`

Set `qa: true` on a step when any of these apply:

- Step produces **user-facing UI** (frontend components, pages, layouts)
- Step produces **user-facing documentation** (specs, RFCs, guides)
- Step involves **complex integration** across 5+ files where subtle
  breakage is likely
- User **explicitly requests** QA review for the step

The QA sub-agent reviews the step's output with fresh eyes (no
implementation context). It catches issues the implementer is too close
to see: inconsistencies, missing edge cases, unclear code, broken patterns.

Default to `false` for backend logic, config changes, and steps already
covered by automated tests.

#### Key rules

- **Exact skill identifiers** — in each step's `skill` field, use the full
  skill name (e.g., `look-before-you-leap:frontend-design`), never vague
  hints. Post-compaction Claude has no memory — only exact names work.
  Use `"none"` for steps that don't need a specialized skill.
- **Precise descriptions with file paths** — not vague "add validation" but
  specific what-to-do with exact file paths and acceptance criteria. Plans
  describe *what* to build; the executing engineer writes the code.
- **Exact file paths** — every step lists files in the `files` array
- **Exact commands with expected outcome** — in description or acceptance
  criteria, include the command and expected result
- **Self-contained** — the plan.json is the ONLY thing the executing
  engineer reads. If it's not in the plan, it doesn't exist for them
- **DRY / YAGNI** — cut anything not clearly needed right now
- **Frequent commits** — after every green test or logical unit of work

### 4. Evaluate sub-plan needs (mandatory checkpoint)

**Before saving the plan, evaluate EVERY step against these criteria:**

For each step, count the files in its `files` array. If dep maps are
configured, also count the DEPENDENTS from `deps-query.py` — a file with
6 direct dependents means the step actually touches 7 files, not 1. This
is the primary input for sub-plan decisions.

If ANY of these are true, the step MUST have an inline `subPlan` with groups:

1. **More than 10 files** in the `files` array (including consumers from dep maps)
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
3. Write a summary to the **plan mode scratch pad** (the file path is
   specified in the plan mode system message — it is NOT masterPlan.md and
   NOT plan.json). Include: the key steps, files involved, and acceptance
   criteria — enough for the user to approve or reject.
4. Call `ExitPlanMode` to present the plan to the user.

This gives the user the built-in **"autoaccept edits and clear context?"**
prompt. If they accept, context clears and the persistent-plans resumption
protocol picks up the plan.json automatically — execution follows the
conductor's Step 3 with engineering-discipline.

---

## Updating an existing plan

If the user changes requirements during planning (before Orbit approval),
update BOTH plan.json and masterPlan.md to reflect the new scope. If the
user changes requirements AFTER Orbit approval (during execution), update
only plan.json — masterPlan.md is frozen. Record the deviation in
plan.json's `deviations` array so the change is visible after compaction.

If a plan already exists in the target directory and you're asked to
rewrite it, read the existing plan first to understand what changed. Do
not silently overwrite — confirm with the user what should change.

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
- **Precise descriptions** — never write vague "add error handling"; specify
  exactly what to do, which files, and how to verify. Plans describe intent;
  the executing engineer writes the code.
- **masterPlan.md is write-once** — frozen after Orbit approval. All runtime
  state lives in plan.json
- **DRY / YAGNI** — only what's needed now, nothing speculative
- **Sub-plans are mandatory** — if a step meets the criteria, it gets one
