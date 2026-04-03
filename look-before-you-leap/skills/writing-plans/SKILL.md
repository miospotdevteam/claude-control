---
name: writing-plans
description: "Use after discovery to write implementation plans with TDD-granularity steps. Produces plan.json (immutable definition, frozen after approval), progress.json (mutable execution state), and masterPlan.md (user-facing proposal for Orbit review). Every step is one component/feature; TDD rhythm (test, verify fail, implement, verify pass, commit) lives in its progress items. Consumes discovery.md from exploration phase. Make sure to use this skill whenever the user says discovery is done, exploration is finished, discovery.md is ready, or asks to write/create/draft the implementation plan — even if they don't mention plan.json or masterPlan.md by name. Also use when the user references completed exploration findings, blast radius analysis, or consumer mappings and wants them converted into actionable steps. Do NOT use when: the user says 'just do it' or 'no plan', resuming or executing an existing plan, during exploration or brainstorming (discovery not yet complete), debugging, or code review."
---

# Writing Plans

Turn discovery findings into bite-sized implementation plans. Assume the
implementing engineer has zero context for this codebase and questionable
taste. Document everything they need: which files to touch, precise
descriptions with file paths, exact commands, expected output. Give them
the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

**Announce at start:** "I'm using the writing-plans skill to create the
implementation plan."

**Prerequisite:** Discovery must be complete with verified co-exploration.

**Planning gate:** Before producing a plan, verify that a signed discovery
receipt exists for this project+plan. Check via:
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/receipt_utils.py check discovery <projectId> <planId>
```
If the receipt is MISSING, refuse to produce the plan and instruct the
caller to complete discovery first (including Codex co-exploration or
documented fallback). This gate ensures Claude cannot skip exploration
and jump straight to planning.

If this gate is closed, STOP. Do NOT write:

- a "quick plan"
- a checklist as a substitute for plan.json
- a verbal outline "for now"
- a partial masterPlan.md to fill in later

Those are all plan-writing attempts. The gate blocks them too.

If no `discovery.md` exists in the plan directory, go back to Step 1
(Explore) first. If discovery.md exists but is thin (missing blast radius
counts, no consumer lists, vague scope), warn the user that the plan
quality will suffer and recommend going back to enrich the discovery
before continuing.

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
| **Every plan (mandatory)** | **`references/routing-matrix.md`** (step ownership — read BEFORE Step 3) |
| Every plan with 3+ steps | `references/scenario-playbook.md` (23-scenario ownership matrix) |
| Writing or modifying tests | `references/testing-checklist.md` |
| Building or modifying UI | `references/frontend-design-checklist.md` + `references/ui-consistency-checklist.md` |
| Auth, input validation, secrets | `references/security-checklist.md` |
| Adding/removing packages | `references/dependency-checklist.md` |
| API route handlers or endpoints | `references/api-contracts-checklist.md` |

Also note these for the executing engineer (they apply during execution,
not planning):

- **git-checklist.md** — applies at every commit step
- **linting-checklist.md** — applies after any code changes

### 3. Classify step ownership (mandatory — before writing JSON)

**This step is the #1 defense against all-claude-impl plans.** You MUST
complete this before writing plan.json. If you skip this, every step
defaults to `claude-impl` and Codex is reduced to a verification-only
role — wasting its implementation capacity on mechanical tasks it could
own.

Read `references/routing-matrix.md` now (you should have already read it
in Step 2). For each step you plan to create, classify it against the
routing matrix task categories.

#### Produce a routing classification table

Before writing any JSON, write out this table (in your response, not in
a file) for every step:

| Step | Title | Category Match | Owner | Mode | Justification |
|---|---|---|---|---|---|
| 1 | "Add user CRUD endpoints" | Backend from clear spec | codex | codex-impl | Straightforward CRUD, no external integration |
| 2 | "Build user profile UI" | Frontend UI / visual design | claude | claude-impl | Requires visual taste |
| 3 | "Rename UserRole across codebase" | Refactor across many files | codex | codex-impl | Mechanical rename, 15 files |
| 4 | "Write API integration tests" | Test writing | codex | codex-impl | Gets TDD skill injection |

This table is the auditable artifact that proves routing was considered.
Copy each row's justification into the step's `routingJustification`
field in plan.json.

#### Aggressive Codex routing — the default stance

The routing matrix defaults most task types to `codex-impl`. Claude keeps
only: frontend UI / visual design, creative / marketing, product copy,
documentation, and security-sensitive design. **Everything mechanical goes
to Codex**: backend, refactoring, testing, debugging, CI/CD, performance,
i18n, migrations, dependency upgrades.

When classifying steps, start by asking: "Does this step require visual
taste, creative judgment, or direct user interaction?" If no, it likely
belongs to Codex.

#### Anti-pattern: all-claude-impl plans

**If every step in a multi-step plan (3+ steps) ends up as `claude-impl`,
re-read the routing matrix — this is almost certainly wrong.** Mechanical
sweeps, file-wide refactoring, test writing, CI setup, and verification
steps should route to Codex. The only valid all-claude-impl plan is one
where every step requires visual taste, creative judgment, or user
interaction — and even then, test-writing sub-steps should still route
to Codex.

Treat an all-claude-impl first draft as a planning failure, not as an
acceptable outcome. Re-read the routing matrix and classify again until
you can justify each Claude-owned step against the matrix explicitly.

#### Classification rules

1. For each step, identify its **primary task category** from the routing
   matrix table (e.g., "Backend from clear spec", "Frontend UI", "Refactor
   across many files")
2. Read the **Default Owner** and **Default Mode** columns
3. Check the **Override Conditions** — if any apply, use the override
4. Check **skill injection rules** — if the step needs a Claude-only
   skill (`frontend-design`, `svg-art`, `immersive-frontend`,
   `react-native-mobile`, `brainstorming`, `doc-coauthoring`), it MUST
   stay `owner: "claude"` regardless of routing matrix
5. Set `owner`, `mode`, and `routingJustification` on the step

**The `routingJustification` field is required on every step.** Format:
`"<category match> → <owner>-<mode> [reason if override]"`. Examples:
- `"Frontend UI / visual design → claude-impl"`
- `"Refactor across many files → codex-impl"`
- `"Backend from clear spec → claude-impl (override: needs MCP tool reasoning)"`

#### Dynamic routing

Some steps can't determine ownership at plan time:

- **Performance optimization**: Investigation step is `owner: "codex"`,
  `mode: "codex-impl"`. Fix steps default to `owner: "claude"` with a
  note that ownership will be reassigned after investigation.
- **Vague requests**: Clarification step is `owner: "claude"`,
  `mode: "claude-impl"`. Subsequent steps assigned normally after
  requirements are concrete.

See `references/scenario-playbook.md` for the complete 23-scenario
ownership matrix with collaboration modes and verification rules.

### 4. Write the plan (dual output)

Produce **both** files in `.temp/plan-mode/active/<plan-name>/`:

#### plan.json — immutable plan definition

Use the schema from `references/plan-schema.md`. This file is frozen after
Orbit approval. Hooks read it for step structure; mutable state (statuses,
results) lives in `progress.json` (auto-created by plan_utils.py). Include:

- All discovery findings in the `discovery` object
- Steps with TDD-granularity progress items
- Inline sub-plans for large steps (see Step 6 below)
- Exact skill identifiers in `skill` fields

**Use dep maps to populate step `files` arrays.** If dep maps are
configured, run `deps-query.py` on each file you plan to modify. The
DEPENDENTS list tells you exactly which consumer files must be in the
step's `files` array — and which files to list in the blast radius
section of discovery. Without dep maps, you're guessing at consumers;
with them, you have the complete picture.

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/deps-query.py <project_root> "<file_path>"
```

#### masterPlan.md — user-facing proposal (write-once)

This is the document the user reviews via Orbit. It communicates **intent**,
not execution state. **It is frozen after Orbit approval** — never updated
during execution. All runtime state lives in progress.json (updated
via plan_utils.py). plan.json is also immutable after approval.

Use the template from `references/master-plan-format.md`. No `[x]`/`[ ]`
checkboxes. No execution state. Just what, why, and what could go wrong.

#### progress.json — initialize after plan creation

After writing plan.json, create progress.json with all steps in `pending`
state:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/plan_utils.py init-progress <plan.json>
```

This creates the mutable state file that tracks execution progress.
plan.json becomes immutable after Orbit approval; all runtime updates
go to progress.json via plan_utils.py commands.

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
  "owner": "claude",
  "mode": "claude-impl",
  "skill": "look-before-you-leap:test-driven-development",
  "simplify": false,
  "codexVerify": true,
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
  "result": null,
  "routingJustification": "Frontend UI / visual design → claude-impl"
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

#### Apply step ownership from routing classification

Use the routing classification table you produced in Step 3. For each
step, set `owner`, `mode`, and `routingJustification` from that table.
If you haven't done Step 3 yet, go back — do NOT assign ownership while
writing JSON.

**Skill injection rules for Codex-owned steps:**

When `owner: "codex"`, the step's `skill` field determines what guidance
Codex receives in its prompt (via `{step.skill.content}` in the implement
template). These skills CAN be injected into Codex:
- `test-driven-development`, `refactoring`, `systematic-debugging`,
  `webapp-testing`, `mcp-builder`

These skills stay Claude-only and MUST NOT have `owner: "codex"`:
- `frontend-design`, `svg-art`, `immersive-frontend`, `react-native-mobile`,
  `brainstorming`, `writing-plans`, `doc-coauthoring`

If a step needs a Claude-only skill, its owner MUST be `"claude"` regardless
of what the routing matrix says. This is a hard constraint.

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

#### `codexVerify` — always `true`, no exceptions

**Set `codexVerify: true` on every step. No exceptions. No mode-based
exemptions.** Codex verification is structural — every step gets verified
by the other agent, regardless of mode. Codex runs as an independent agent
with its own engineering discipline plugin that independently verifies the
diff against the step's acceptance criteria, runs the project's type
checker and tests, and checks consumer integrity via dep maps. It catches
issues Claude might miss due to compaction or tunnel vision.

If the `codex` CLI is unavailable at runtime, Codex verification is
skipped gracefully (noted under `### Verdict` in the structured result).

Codex verification uses `run-codex-verify.sh` (direction-locked). See
the `codex-dispatch` skill for the full flow.

#### Key rules

- **Exact skill identifiers** — in each step's `skill` field, use the full
  skill name (e.g., `look-before-you-leap:frontend-design`), never vague
  hints. Post-compaction Claude has no memory — only exact names work.
  Use `"none"` for steps that don't need a specialized skill.
- **Precise descriptions with file paths** — not vague "add validation" but
  specific what-to-do with exact file paths and acceptance criteria. Plans
  describe *what* to build; the executing engineer writes the code.
- **Exact file paths** — every step lists files in the `files` array
- **Companion files** — every step that adds behavior must list its
  companion artifacts in the `files` array: test files (for new logic),
  locale files (for new user-visible strings), migration files (for new DB
  columns), consumer files (for changed exports). A step that adds an API
  endpoint without listing its test file is incomplete. A step that adds UI
  copy without listing locale files is incomplete. If companion artifacts do
  not exist yet and must be created, note that in the description.
- **Exact commands with expected outcome** — in description or acceptance
  criteria, include the command and expected result
- **Self-contained** — the plan.json is the ONLY thing the executing
  engineer reads. If it's not in the plan, it doesn't exist for them
- **DRY / YAGNI** — cut anything not clearly needed right now
- **Frequent commits** — after every green test or logical unit of work

**Anti-pattern to avoid:** A step that lists only the "main" implementation
files and omits required tests, locale files, migrations, or consumer
updates. Treat the step as incomplete and expand the `files` array first.

### 5. Compute step dependency DAG

Before saving the plan, compute `dependsOn` edges so the executor can
dispatch independent steps in parallel.

#### Algorithm

For each pair of steps (A, B) where A.id < B.id:

1. Collect step A's file set and step B's file set from their `files` arrays
2. **When dep maps are configured**: expand each file set with its
   dependents from `deps-query.py` before checking intersection. This
   catches transitive dependencies — step B might not directly list a file
   from step A, but one of B's files may depend on one of A's files.
3. If step B's (expanded) file set intersects step A's (expanded) file set,
   add A.id to B's `dependsOn` array
4. You may also add **manual** `dependsOn` edges when you know step B
   consumes step A's output even without file overlap (e.g., step A creates
   a type that step B uses, but they have no shared files because the type
   file isn't listed in step A)

Steps with empty `dependsOn` are roots of the DAG — they can all start
in parallel. The executor uses `runnable_steps()` in plan_utils.py to
compute the frontier at runtime.

#### Example

```
Step 1: files [a.ts, b.ts]        → dependsOn: []
Step 2: files [c.ts, d.ts]        → dependsOn: []
Step 3: files [e.ts, f.ts]        → dependsOn: []
Step 4: files [b.ts, g.ts]        → dependsOn: [1]  (shares b.ts with step 1)
Step 5: files [h.ts]              → dependsOn: []
Step 6: files [a.ts, c.ts, e.ts]  → dependsOn: [1, 2, 3]
```

Execution: Steps 1, 2, 3, 5 start in parallel. Step 4 starts when 1
finishes. Step 6 starts when 1, 2, 3 all finish. Step 5 is independent
and can run alongside anything.

#### Validation

After computing all edges, verify the DAG is valid:
- No cycles (step A depends on B, B depends on A)
- No self-references (step depends on itself)
- All referenced IDs exist in the step list

If the plan has no file overlaps and no manual edges, every step gets
`dependsOn: []` — the plan is fully parallel. This is valid and common
for plans with well-isolated steps.

### 6. Evaluate sub-plan needs (mandatory checkpoint)

#### Graph-informed grouping (when dep maps are configured)

Before evaluating thresholds, run `dep_partition.py` on the scoped
entry-point files to get graph-informed groups:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/dep_partition.py <project_root> <file_path> [<file_path> ...]
```

The partition output tells you:
- Which files belong in the same group (connected components via shared deps)
- Which groups are safe to parallelize (`safeParallel` hint)
- Suggested execution order (`suggestedOrder` — cross-module boundaries first)

Use these groups to shape `subPlan.groups` directly when the thresholds
below are met. The partition output feeds group structure inline — do NOT
create a separate `dep-partition.json` artifact. When dep maps are **not**
configured, skip `dep_partition.py` and use existing threshold-based
grouping unchanged.

#### Threshold criteria

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
      {"name": "Dashboard pages", "owner": "claude", "files": ["a.tsx", "b.tsx", "c.tsx"]},
      {"name": "Modal components", "owner": "codex", "files": ["d.tsx", "e.tsx"]}
    ]
  }
}
```

Groups should have 3-8 files each. If a group exceeds 8, split it.

#### Group ownership for collab-split steps

When the step's `mode` is `"collab-split"`, each group MUST have an
`owner` field. Classify each group against the routing matrix the same
way you classified steps in Step 3:

1. For each group, identify its primary task category from the routing
   matrix (e.g., "Frontend UI", "Backend from clear spec", "Refactor")
2. Set `owner` to `"claude"` or `"codex"` based on the routing matrix
3. The executor dispatches each group to the correct agent based on
   `group.owner` — Claude-owned groups get Codex verification,
   Codex-owned groups get Claude verification

For non-collab-split steps, `group.owner` is optional and defaults to
the parent step's `owner`. But for collab-split steps, making ownership
explicit on every group prevents the failure mode where Claude implements
all groups (including Codex-owned ones) because ownership was only hinted
in group names, not enforced by schema.

**Progress item naming**: include the owner designation for readability:
`"Group 3 (Codex): Account hooks"`. But the formal `owner` field on
the group object is what the executor reads — the name is informational.

**This is a hard checkpoint.** Do not proceed to Step 7 until every step
has been evaluated. If you skip this, large steps will fail mid-execution
when context runs out.

### 7. Plan consensus with Codex (before Orbit)

After saving both files to disk, run the plan consensus protocol with
Codex before presenting to the user. Both agents must agree on the plan.

**Apply the Codex output batching principle** (see conductor SKILL.md):
batch into groups of 5 items, never retry oversized prompts, cap output
scope to structured bullets.

**IMPORTANT: Run all consensus `codex exec` calls in foreground (no
`run_in_background`).** Background Codex notifications arriving during
`EnterPlanMode`/`ExitPlanMode` break the plan mode handoff. Wait for each
call to complete before proceeding. Also close stdin on every `codex exec`
call with `</dev/null>`; otherwise Codex can hang waiting for additional
stdin from the Bash tool.

**Round 1 — Codex reviews:**

If the plan has **≤5 steps**, dispatch a single call:

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-round1.md \
  </dev/null \
  "Read the plan at <plan-dir>/masterPlan.md and <plan.json>. \
   For steps 1-N, return a structured proposal per step: \
   - ACCEPT: step is well-sized, criteria are concrete, ownership is correct \
   - REJECT <reason>: step should be removed or fundamentally rethought \
   - MODIFY <changes>: step needs specific changes (sizing, criteria, ownership, ordering) \
   Also flag: missing steps, wrong ordering, vague acceptance criteria, \
   ownership assignments that contradict the routing matrix."
```

Claude reads `codex-consensus-round1.md` after the call completes.

If the plan has **>5 steps**, batch into groups of 5:

```bash
# Batch 1: steps 1-5
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-batch-1.md \
  </dev/null \
  "Read the plan at <plan-dir>/masterPlan.md and <plan.json>. \
   Review ONLY steps 1-5. For each, return: \
   - ACCEPT: step is well-sized, criteria are concrete, ownership is correct \
   - REJECT <reason>: step should be removed or fundamentally rethought \
   - MODIFY <changes>: step needs specific changes (sizing, criteria, ownership, ordering)"

# Batch 2: steps 6-10 (adjust range for actual step count)
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-batch-2.md \
  </dev/null \
  "Read the plan at <plan-dir>/masterPlan.md and <plan.json>. \
   Review ONLY steps 6-10. For each, return: \
   - ACCEPT / REJECT <reason> / MODIFY <changes>"

# Continue batching until all steps are covered.
# After all batches, Claude merges batch files into consensus-round1.md,
# then dispatches a cross-cutting check:
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-cross-cutting.md \
  </dev/null \
  "Read <plan-dir>/consensus-round1.md (merged batch results). \
   Flag: missing steps, wrong ordering across the full plan, \
   ownership assignments that contradict the routing matrix."
```

Claude reads each `-o` output file after the call completes and merges
batch results into `consensus-round1.md`. Append cross-cutting notes.

**Round 2 — Claude responds** to each proposal (ACCEPT / REJECT with
reasoning / COUNTER-PROPOSE). Update plan files with accepted changes.

**Round 3 (if needed)** — Final resolution. If disagreements remain
after Round 2, dispatch Codex one more time. If **≤5 disagreements**,
use a single call. If **>5**, batch into groups of 5 disagreements per
call, merging results between batches.

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-round3.md \
  </dev/null \
  "Read the updated plan at <plan-dir>/plan.json and Claude's responses \
   to your proposals. For these remaining disagreements: [list ≤5 items] \
   - ACCEPT Claude's reasoning, or \
   - ESCALATE with both positions stated (for the user to decide in Orbit)"
```

**Max 3 rounds.** Unresolved items go to Orbit with both positions clearly
stated so the user can decide.

If `codex` CLI is not available, skip consensus and proceed to Orbit.

### 8. Present for review via Orbit

After plan consensus (or directly after saving if Codex is unavailable),
present masterPlan.md to the user for interactive review using the Orbit
MCP:

1. Discover the Orbit tool: `ToolSearch query: "+orbit await_review"`
2. Tell the user: *"The plan is open in VS Code for review. Add inline
   comments on any section, then click Approve or Request Changes."*
3. Call `orbit_await_review` with the masterPlan.md path. This generates
   the artifact, opens it in VS Code, and **blocks** until the user clicks
   Approve or Request Changes.

#### Handle the response

`orbit_await_review` returns JSON with `status` and `threads`.

- **`approved`, no threads** → proceed to step 8 (plan mode handoff).
- **`approved`, with threads** → read each thread, reply as `agent`
  acknowledging the feedback, resolve threads, then proceed to step 8.
- **`changes_requested`** → read all threads. Update both masterPlan.md
  and plan.json to address the feedback. Reply to each thread explaining
  what changed. Resolve threads. Call `orbit_await_review` again for
  re-review. Loop back to handle the new response.
- **`timeout`** → tell the user the review timed out and ask them to
  review when ready.

### 9. Plan mode handoff (post-approval)

After the plan is approved via Orbit:

**Pre-flight**: The `guard-handoff-background.sh` hook auto-kills any
running codex processes and cleans markers on `EnterPlanMode`. If
non-codex background work exists, kill it before handoff.

1. **Call `EnterPlanMode`** — do NOT output any text in the same response.
   Call the tool and nothing else. The pending-review marker
   (`.handoff-pending`) is cleared only when `orbit_await_review`
   returns approved. `EnterPlanMode` happens after approval; it does not
   clear a pending review marker.
2. **Read the scratch pad path** from the plan mode system message that
   appears after EnterPlanMode succeeds. The path is under `~/.claude/plans/`
   — it is NOT masterPlan.md and NOT plan.json.
3. **Write a minimal summary** to that scratch pad file. Use this exact format:

   ```
   # Plan: <title from plan.json>
   Path: <absolute path to plan.json>
   Steps: <N> total
   Context: <plan.json.context — one or two sentences>

   Read plan.json at the path above to begin execution.
   ```

   **Do NOT include**: step descriptions, acceptance criteria, file lists,
   Codex consensus results, exploration findings, implementation details,
   transcript references, or any other content. All of that lives on disk
   already. The session-start hook and resumption protocol handle
   everything — the scratch pad is a pointer, not a copy.

   **Why this matters**: the scratch pad becomes the initial prompt in the
   new session. If it's too large or contains mixed instructions (implement
   + handle consensus + read transcript), Claude gets confused and acts
   erratically — editing code while simultaneously outputting stale Codex
   feedback. Keep it minimal.

4. **Call `ExitPlanMode`** — do NOT output any text in the same response.
   Just call the tool.

**IMPORTANT**: Do not output explanatory text alongside `EnterPlanMode` or
`ExitPlanMode` calls. Extra text in the same response can interfere with
the plan mode transition and cause the scratch pad to appear as a stashed
message instead of the plan mode green box.

This gives the user the built-in **"autoaccept edits and clear context?"**
prompt. If they accept, context clears and the persistent-plans resumption
protocol picks up the plan.json automatically — execution follows the
conductor's Step 3 with engineering-discipline.

---

## Updating an existing plan

If the user changes requirements during planning (before Orbit approval),
update BOTH plan.json and masterPlan.md to reflect the new scope. If the
user changes requirements AFTER Orbit approval (during execution),
masterPlan.md is frozen and plan.json is immutable. Record the deviation
via `plan_utils.py add-deviation` (writes to progress.json) so the
change is visible after compaction.

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
- **Skip the routing classification** — Step 3 is mandatory for every plan.
- **Skip the sub-plan evaluation** — Step 6 is mandatory for every plan.

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
- **masterPlan.md is write-once** — frozen after Orbit approval. plan.json
  is also immutable. All runtime state lives in progress.json
- **DRY / YAGNI** — only what's needed now, nothing speculative
- **Sub-plans are mandatory** — if a step meets the criteria, it gets one
