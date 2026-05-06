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

**Codex is the default implementer.** Under the conductor-mode
architecture (plan-level `conductorMode: true`), every step is presumed
`codex-impl` unless an explicit, justified override applies. Claude-impl
requires a written justification on the step, and that justification MUST
cite either:

- the step's `skill` is in the **Claude-only skill list** (see below), OR
- the step matches the conditional `react-native-mobile` Routing
  Directive (see "RN-mobile conditional routing" below), OR
- the routing matrix's documented overrides (security-sensitive design,
  external-tool reasoning, etc.) apply.

This step is the #1 defense against accidental all-claude-impl plans.
You MUST complete it before writing plan.json. If you skip it, the
default kicks in: every step gets `codex-impl` and only the Claude-only
skill list (and RN routing directive) can move a step back to Claude.
Treat an all-claude-impl first draft as a planning failure — every step
that could be Codex must be Codex unless the routing matrix exempts it.

Read `references/routing-matrix.md` now (you should have already read it
in Step 2). For each step you plan to create, classify it against the
routing matrix task categories.

#### Claude-only skill list (exact, exhaustive)

A step's `skill` field forces `owner: "claude"` if and only if the
skill is one of EXACTLY these six:

```
frontend-design, svg-art, immersive-frontend,
brainstorming, writing-plans, doc-coauthoring
```

Notes on this list:

- `react-native-mobile` is NOT in the Claude-only list — it is
  **conditional** (see RN routing rule below).
- `lbyl-digest` is **internal-only**: it is dispatched by the conductor
  for receipt and consensus digesting, and MUST NOT appear as a
  plan-step `skill` value. Do not assign it to any plan step.
- Any step whose `skill` is NOT in this list defaults to `codex-impl`
  unless a routing-matrix override applies and is documented in
  `routingJustification`.

#### RN-mobile conditional routing rule

If a step's `skill` would be `react-native-mobile`, do NOT auto-assign
ownership. Instead, read the **Routing Directive** section in
`look-before-you-leap/skills/react-native-mobile/SKILL.md` and pick:

- **UI/UX work** (visual layout, animation polish, gesture taste,
  haptic feel, native look-and-feel) → `owner: "claude"`,
  `mode: "claude-impl"`. Justification: "react-native-mobile UI/UX
  per Routing Directive → claude-impl".
- **Code-heavy work** (state-machine wiring, refactors, list
  virtualization plumbing, mechanical platform-API integration with no
  visual taste call) → `owner: "codex"`, `mode: "codex-impl"`.
  Justification: "react-native-mobile code-heavy per Routing Directive
  → codex-impl".

The Routing Directive in the RN skill is the source of truth. If the
step blends UI/UX and code-heavy work, split it into two sequential
steps with `dependsOn` rather than forcing a single owner.

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

#### Codex-default routing — the only valid stance

Codex owns implementation by default. Claude only owns a step when its
`skill` is in the Claude-only list above, when the RN-mobile Routing
Directive sends it to Claude, or when a routing-matrix override applies
(e.g., security-sensitive design, MCP/external-tool reasoning).
**Everything else — backend, refactoring, testing, debugging, CI/CD,
performance, i18n, migrations, dependency upgrades, sweeps — is
codex-impl.**

When classifying, start by asking: "Is this step's `skill` in the
Claude-only list, OR does the RN Routing Directive send it to Claude,
OR does a documented routing-matrix override apply?" If the answer to
all three is no, the step is `codex-impl`.

#### Anti-pattern: undefaulted claude-impl

**Any `claude-impl` step without an explicit `routingJustification`
citing one of the three allowed reasons is a planning bug.** If a
multi-step plan ends up with a majority of `claude-impl` steps and you
can't point each one at the Claude-only list, the RN directive, or a
named routing-matrix override, re-classify — Codex should be carrying
the mechanical work.

The only valid mostly-Claude plans are ones whose steps all touch
Claude-only skills (e.g., a multi-step `frontend-design` build). Even
those should split out test-writing into separate `codex-impl` steps
with `dependsOn`.

#### Classification rules

1. For each step, identify its **primary task category** from the routing
   matrix table (e.g., "Backend from clear spec", "Frontend UI", "Refactor
   across many files")
2. Read the **Default Owner** and **Default Mode** columns; the
   conductor-mode default for unmatched/mechanical work is
   `codex-impl`
3. Check the **Override Conditions** — if any apply, use the override
   and cite it in `routingJustification`
4. Check **skill injection rules** — if the step's `skill` is in the
   Claude-only list (`frontend-design`, `svg-art`, `immersive-frontend`,
   `brainstorming`, `writing-plans`, `doc-coauthoring`), it MUST stay
   `owner: "claude"` regardless of routing matrix
5. If the step's `skill` is `react-native-mobile`, apply the RN
   conditional routing rule above instead of defaulting
6. Set `owner`, `mode`, and `routingJustification` on the step

**The `routingJustification` field is required on every step.** Format:
`"<category match> → <owner>-<mode> [reason if override]"`. Examples:
- `"Frontend UI / visual design → claude-impl (skill in Claude-only list: frontend-design)"`
- `"Refactor across many files → codex-impl (codex default)"`
- `"Backend from clear spec → claude-impl (override: needs MCP tool reasoning)"`
- `"react-native-mobile UI/UX per Routing Directive → claude-impl"`
- `"react-native-mobile code-heavy per Routing Directive → codex-impl"`

Valid `mode` values are exactly: `claude-impl`, `codex-impl`,
`dual-pass`. Mixed-ownership steps must be split into two sequential
single-owner steps linked by `dependsOn`. See "Mode reference" below.

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

These six skills stay **Claude-only** and MUST NOT have `owner: "codex"`:
- `frontend-design`, `svg-art`, `immersive-frontend`,
  `brainstorming`, `writing-plans`, `doc-coauthoring`

`react-native-mobile` is **conditional** (see RN routing rule above) —
it MAY be `owner: "codex"` for code-heavy work or `owner: "claude"` for
UI/UX work, per its Routing Directive.

`lbyl-digest` is **internal-only** and MUST NOT appear in any plan
step's `skill` field. The conductor dispatches it to digest receipts and
consensus output; it is not a plan-routable skill.

If a step needs a Claude-only skill (one of the six above), its owner
MUST be `"claude"` regardless of what the routing matrix says. This is a
hard constraint.

#### In-thread vs. dispatched execution (conductor mode)

Conductor mode is the default (`conductorMode: true` at plan level).
The main thread never writes code directly; everything dispatches to a
subagent. There is exactly one narrow exception:

**Threshold for in-thread `claude-impl`**: a `claude-impl` step MAY run
in the main thread iff BOTH conditions hold:

1. The step's `files` array has **≤1 file**, AND
2. The step's `skill` is one of `{brainstorming, writing-plans,
   doc-coauthoring}`.

Every other `claude-impl` step dispatches to an Opus subagent. All
`codex-impl` steps dispatch through `run-codex-implement.sh`.

#### Mode reference

Only three modes are valid: `claude-impl`, `codex-impl`, `dual-pass`.

- `claude-impl` — Opus subagent (or main thread under the threshold
  above) implements; Codex verifies via receipt.
- `codex-impl` — Codex implements via `run-codex-implement.sh`; emits a
  structured receipt; an Opus verification subagent reads the receipt
  (NOT the raw artifact).
- `dual-pass` — both agents review; used for security review and PR
  review where each angle (design vs. correctness) needs an
  independent pass.

Only the three modes above are valid. Do not emit any other mode
value. If a step needs mixed ownership across files, split it into two
sequential single-owner steps with `dependsOn`.

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
skipped gracefully (noted in the structured receipt).

Codex verification uses `run-codex-verify.sh` (direction-locked). See
the `codex-dispatch` skill for the full flow.

#### Receipt-first verification (codex-impl steps)

`codex-impl` steps emit a structured receipt:
`<plan-dir>/codex-receipt-step-N.json`. The receipt is produced from a
fenced ` ```codex-receipt-v1 ` block written by the wrapper script and
HMAC-signed via a sidecar in
`~/.claude/look-before-you-leap/state/<projectId>/<planId>/`. See
`look-before-you-leap/references/codex-receipt-schema.md` for the full
schema.

The verification subagent dispatched after a `codex-impl` step MUST
read the receipt JSON, NOT the raw `.codex-result-step-N.txt` trace.
The TXT file is preserved as a human-readable trace only — its sha256
is bound into the receipt so post-mint tampering is detectable, but the
main thread and verification subagent read the receipt.

#### Model pinning — rely on machine defaults

NEVER pass `--model` flags that downgrade the configured machine
defaults. Claude Code = Opus 4.7 high; Codex = gpt-5.5 high fast. See
`look-before-you-leap/references/machine-defaults.md` for the full
no-downgrade rule and verification commands. Do not write step
descriptions, acceptance criteria, or wrapper invocations that override
these settings.

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

### 5. Design for maximum parallelism, then compute the DAG

Parallel dispatch is the **default**: the conductor's execution loop
dispatches the entire DAG frontier — all currently runnable steps —
concurrently on every tick. Every unnecessary `dependsOn` edge
serializes work and wastes a parallel slot. **Design steps to minimize
dependencies first, then compute edges on the result.**

#### Design principles (apply BEFORE computing edges)

1. **Bias toward small, independent steps.** Prefer many 1-3-file
   steps with `dependsOn: []` over a few large steps. Small
   independent steps fan out across the parallel-dispatch frontier;
   large ones serialize work behind themselves.
2. **Isolate file sets.** If two steps both need `shared.ts`, consider
   whether one step can own the shared file and the other can consume
   it read-only (no edit). Only steps that *write* to the same file
   need a `dependsOn` edge.
3. **Split shared-file steps.** If step A creates a utility and step B
   uses it, put the utility file in step A's `files` only. Step B
   lists only its own files and gets an explicit `dependsOn: [A]`.
   Don't dump the utility file into both steps — that forces serial
   execution even when step B only reads it.
4. **Front-load foundations.** Definitions (types, schemas, interfaces)
   go in early low-ID steps. Consumer steps depend on them. All
   consumer steps that don't share files with each other can then run
   in parallel once the foundation step finishes.
5. **Avoid monolith steps.** A single step touching 10+ files often
   blocks everything behind it. Split it into smaller, file-disjoint
   steps that can run in parallel.
6. **Audit the result.** After computing edges, count steps with empty
   `dependsOn`. If fewer than half the steps are parallelizable in a
   plan with 4+ steps, revisit the step design — you may be able to
   split or restructure to unlock more parallelism.

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

### 6. Decompose large steps into independent small steps (mandatory checkpoint)

Under the conductor-mode + parallel-dispatch architecture,
**decomposition happens at the step level**, not inside a step.
Split one large step into multiple small steps, each with 1-3 files
and explicit `dependsOn` edges. The execution loop will fan them out
across the DAG frontier. Inline `subPlan.groups` are no longer
emitted by this skill.

#### Graph-informed splitting (when dep maps are configured)

Before evaluating thresholds, run `dep_partition.py` on the scoped
entry-point files to get graph-informed groups:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/dep_partition.py <project_root> <file_path> [<file_path> ...]
```

The partition output tells you:
- Which files belong in the same connected component (shared deps)
- Which components are safe to parallelize (`safeParallel` hint)
- Suggested execution order (`suggestedOrder` — cross-module boundaries first)

**Use the partition output to shape multiple plan-level steps**, not
inline groups. Each connected component becomes one or more small
steps; the `safeParallel` hint tells you which steps can have
`dependsOn: []` and run concurrently. The `suggestedOrder` informs the
`dependsOn` edges between sequential components. When dep maps are
**not** configured, skip `dep_partition.py` and apply the threshold
criteria below using just the `files` array.

#### Threshold criteria — when to split

**Before saving the plan, evaluate EVERY step against these criteria.**

For each step, count the files in its `files` array. If dep maps are
configured, also count the DEPENDENTS from `deps-query.py` — a file with
6 direct dependents means the step actually touches 7 files, not 1.

If ANY of these are true, the step MUST be split into multiple smaller
steps with `dependsOn` edges:

1. **More than 10 files** in the `files` array (including consumers from dep maps)
2. **Repetitive sweep** — description contains words like "all", "every",
   "sweep", "migrate all", "across the codebase"
3. **More than 5 progress items** that are independently completable
4. **More than 8 files to read** just to understand what to change
5. **The step is a migration** that touches the same pattern in many files
6. **Mixed ownership** — the step would naturally need both Claude and
   Codex work (e.g., a UI component plus its data hook). Split into
   one Claude step and one Codex step linked by `dependsOn`.

#### How to split: many small steps with explicit `dependsOn`

Aim for 1-3 files per step. Each step has a single `owner`. Cross-step
dependencies live in `dependsOn`. Independent steps have
`dependsOn: []` and run in parallel under conductor-mode dispatch.

Example — replacing what was previously a single mixed-ownership step
("Build dashboard with charts: Claude UI / Codex hooks") with three
single-owner steps:

```json
[
  {"id": 7,  "title": "Dashboard layout shell",     "owner": "claude", "mode": "claude-impl",
   "skill": "look-before-you-leap:frontend-design",
   "files": ["src/app/dashboard/page.tsx", "src/app/dashboard/Layout.tsx"],
   "dependsOn": [],
   "routingJustification": "Frontend UI / visual design → claude-impl (skill in Claude-only list)"},

  {"id": 8,  "title": "Dashboard data hooks",       "owner": "codex",  "mode": "codex-impl",
   "skill": "look-before-you-leap:test-driven-development",
   "files": ["src/app/dashboard/hooks/useMetrics.ts", "src/app/dashboard/hooks/useMetrics.test.ts"],
   "dependsOn": [],
   "routingJustification": "Backend from clear spec → codex-impl (codex default)"},

  {"id": 9,  "title": "Wire charts to hooks",       "owner": "claude", "mode": "claude-impl",
   "skill": "look-before-you-leap:frontend-design",
   "files": ["src/app/dashboard/Chart.tsx"],
   "dependsOn": [7, 8],
   "routingJustification": "Frontend UI / visual design → claude-impl (skill in Claude-only list)"}
]
```

Steps 7 and 8 fan out in parallel; step 9 waits for both. No
`subPlan`, no `groups`, no mixed-mode steps. Each step has one owner
and a small file set.

**This is a hard checkpoint.** Do not proceed to Step 7 until every
large step has been split. If you skip it, oversized steps will fail
mid-execution when context runs out, and you will have lost the
parallel-dispatch wins by serializing work behind monoliths.

### 7. Plan consensus with Codex (before Orbit)

After saving both files to disk, run the plan consensus protocol with
Codex before presenting to the user. Both agents must agree on the plan.

**Receipt-first principle**: the main thread MUST NOT read raw Codex
consensus output (`codex-consensus-*.md`, batch files, cross-cutting
files). Under conductor mode, every raw artifact is digested by an
`lbyl-digest` subagent dispatch and the main thread reads only the
bounded digest the subagent returns. This keeps the main thread context
small and predictable, preventing consensus prose from polluting the
plan-mode handoff.

**Apply the Codex output batching principle** (see conductor SKILL.md):
batch into groups of 5 items, never retry oversized prompts, cap output
scope to structured bullets per batch.

**IMPORTANT: Run all consensus `codex exec` calls in foreground (no
`run_in_background`).** Background Codex notifications arriving during
`EnterPlanMode`/`ExitPlanMode` break the plan mode handoff. Wait for each
call to complete before proceeding. Also close stdin on every `codex exec`
call with `</dev/null>`; otherwise Codex can hang waiting for additional
stdin from the Bash tool.

Do NOT pass `--model` flags to `codex exec` — rely on machine defaults
(`look-before-you-leap/references/machine-defaults.md`).

**Round 1 — Codex reviews:**

If the plan has **≤5 steps**, dispatch a single Codex consensus call:

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

Then dispatch an `lbyl-digest` Agent to read
`codex-consensus-round1.md` and return ONLY a bounded digest:

```
Agent(
  description: "lbyl-digest consensus",
  subagent_type: "general-purpose",
  prompt: "Load <project-root>/look-before-you-leap/skills/lbyl-digest/SKILL.md as primary guidance. Run mode=consensus with plan-dir=<plan-dir>, round-N=1. Return ONLY the bounded consensus payload shape defined by that skill: { kind, round, digestPath, counts, decisions, openDisagreements, summary }. Do not include prose, markdown fences, or follow-up text."
)
```

- per step: ACCEPT / REJECT / MODIFY plus a one-line summary of the
  proposed change
- cross-cutting flags (missing steps, wrong ordering, ownership
  contradictions)
- nothing else (no quoted prose, no reasoning paragraphs)

The main thread reads the digest, NOT the raw `.md`.

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
# After all batches, dispatch a cross-cutting Codex check:
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-cross-cutting.md \
  </dev/null \
  "Read <plan-dir>/codex-consensus-batch-*.md. \
   Flag: missing steps, wrong ordering across the full plan, \
   ownership assignments that contradict the routing matrix."
```

Then dispatch a single `lbyl-digest` Agent that reads ALL of
`codex-consensus-batch-*.md` AND `codex-consensus-cross-cutting.md`
and returns one merged, bounded digest in the same format as the
≤5-step case (per-step verdicts + cross-cutting flags). The main
thread reads only that digest. Do NOT have the main thread merge batch
files itself — that re-introduces raw-prose pollution.

```
Agent(
  description: "lbyl-digest consensus",
  subagent_type: "general-purpose",
  prompt: "Load <project-root>/look-before-you-leap/skills/lbyl-digest/SKILL.md as primary guidance. Run mode=consensus with plan-dir=<plan-dir>, round-N=1. Read all codex-consensus-batch-*.md files and codex-consensus-cross-cutting.md if present. Return ONLY the bounded consensus payload shape defined by that skill: { kind, round, digestPath, counts, decisions, openDisagreements, summary }. Do not include prose, markdown fences, or follow-up text."
)
```

**Round 2 — Claude responds** to each digest entry (ACCEPT / REJECT
with reasoning / COUNTER-PROPOSE). Update plan files with accepted
changes via `plan_utils.py` (deviations to progress.json after
approval; direct plan.json edits before approval).

**Round 3 (if needed)** — Final resolution. If disagreements remain
after Round 2, dispatch Codex one more time. If **≤5 disagreements**,
use a single call. If **>5**, batch into groups of 5 disagreements per
call:

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-round3.md \
  </dev/null \
  "Read the updated plan at <plan-dir>/plan.json and Claude's responses \
   to your proposals. For these remaining disagreements: [list ≤5 items] \
   - ACCEPT Claude's reasoning, or \
   - ESCALATE with both positions stated (for the user to decide in Orbit)"
```

Then dispatch `lbyl-digest` once more to read the round-3 output(s)
and return only the per-disagreement verdict plus any escalations.
Main thread reads the digest only.

```
Agent(
  description: "lbyl-digest consensus",
  subagent_type: "general-purpose",
  prompt: "Load <project-root>/look-before-you-leap/skills/lbyl-digest/SKILL.md as primary guidance. Run mode=consensus with plan-dir=<plan-dir>, round-N=3. Return ONLY the bounded consensus payload shape defined by that skill: { kind, round, digestPath, counts, decisions, openDisagreements, summary }. Do not include prose, markdown fences, or follow-up text."
)
```

**Max 3 rounds.** Unresolved items go to Orbit with both positions clearly
stated so the user can decide.

If `codex` CLI is not available, skip consensus and proceed to Orbit.

### 8. Present for review via Orbit

**Mandatory Orbit review rule:** Orbit review is MANDATORY for every plan.
Claude MUST NOT skip Orbit review based on its own assessment of task size,
complexity, or interactivity. The ONLY valid skip path is when the user has
typed one of these exact override phrases verbatim in this turn: "no orbit",
"skip orbit", "no review", "skip review". Phrases like "small fix", "this is
simple", "user is interactive", or any inference Claude makes from context are
NOT valid override phrases. If Claude believes Orbit should be skipped, it MUST
ask the user explicitly with the exact phrase "Should I skip the Orbit review
for this plan? Please type 'skip orbit' to confirm." and wait for the literal
answer.

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
   Respect step ownership exactly.
   Do NOT implement Codex-owned steps yourself.
   Do NOT mark any step done before independent verification passes.
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
- **Skip the Orbit review** — Orbit review is MANDATORY for every plan.
  Claude MUST NOT skip Orbit review based on its own assessment of task size,
  complexity, or interactivity. The ONLY valid skip path is when the user has
  typed one of these exact override phrases verbatim in this turn: "no orbit",
  "skip orbit", "no review", "skip review". Phrases like "small fix", "this is
  simple", "user is interactive", or any inference Claude makes from context are
  NOT valid override phrases. If Claude believes Orbit should be skipped, it
  MUST ask the user explicitly with the exact phrase "Should I skip the Orbit
  review for this plan? Please type 'skip orbit' to confirm." and wait for the
  literal answer.
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
