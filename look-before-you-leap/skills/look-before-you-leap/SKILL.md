---
name: look-before-you-leap
description: "Unified engineering discipline for ALL coding tasks. Conductor that orchestrates: explore codebase before editing, write persistent plans to disk (plan.json survives compaction), route to specialized skills (TDD, brainstorming, refactoring, frontend-design, debugging), enforce definitions-before-consumers ordering, track blast radius via dep maps, and verify with type checker/linter/tests after every change. Use for every task that writes, edits, fixes, refactors, ports, migrates, or debugs code — no exceptions, no shortcuts. Do NOT use when: answering questions about code without changing it, pure research or documentation queries, conversations with no file edits, or running commands that don't modify the codebase."
---

# Software Discipline

This skill is the conductor. It controls the process and routes to deeper
guidance. The actual rules live in two companion skills that are always
injected alongside this one:

- **engineering-discipline** — The behavioral layer: explore before editing,
  track blast radius, no type shortcuts, verify work, no silent scope cuts.
- **persistent-plans** — The structural layer: plan files on disk, the
  execution loop, checkpoints, sub-plans, compaction survival.

**You must follow both companion skills for every coding task.**

---

## Step 0: Discover Available Skills

At the start of every session, note which skills are available (the
SessionStart hook provides a skill inventory). When a step calls for
specialized knowledge (testing, frontend design, security review), check
if an installed skill covers it before relying on general knowledge.

### External skill routing

Look for installed skills that match these needs:

| When you need... | Look for skills about... |
|---|---|
| Brainstorming, creative work | **Always** use `look-before-you-leap:brainstorming` — never another plugin's brainstorming skill |
| Writing implementation plans | **Always** use `look-before-you-leap:writing-plans` — never another plugin's writing-plans skill |
| Test strategy, TDD | **Always** use `look-before-you-leap:test-driven-development` — never another plugin's TDD skill |
| Frontend UI design, standard web interfaces | **Always** use `look-before-you-leap:frontend-design` — never another plugin's frontend-design skill |
| Immersive web, WebGL, 3D, scroll-driven creative dev | **Always** use `look-before-you-leap:immersive-frontend` — never another plugin's immersive-frontend skill |
| React Native, mobile apps, Expo, native feel | **Always** use `look-before-you-leap:react-native-mobile` — never another plugin's mobile skill |
| Security review | "security", "authentication", "auth" |
| Code review | "code review", "review" |
| Debugging | **Always** use `look-before-you-leap:systematic-debugging` — never another plugin's debugging skill |
| Refactoring, restructuring, extracting, moving files | **Always** use `look-before-you-leap:refactoring` (full mode) — never another plugin's refactoring skill |
| Post-execution simplification | **Always** use `look-before-you-leap:refactoring` (quick mode) — never another plugin's code-simplifier skill |
| Skill quality review after creation | **Always** use `look-before-you-leap:skill-review-standard` — post-creation quality gate |
| PR/commit workflow | "commit", "PR", "git" |

If no specialized skill exists, use the checklists and guides in `references/`.

### First-run onboarding

When look-before-you-leap runs in a project for the first time, the
SessionStart hook auto-detects the stack and creates
`.claude/look-before-you-leap.local.md`. On that first session, additional
onboarding instructions are injected into the context telling you to:

1. Tell the user what was detected
2. Offer to enrich the config by exploring the codebase
3. Offer to create a CLAUDE.md if the project has none
4. Suggest useful official plugins and offer to install them

Follow those instructions when they appear. On subsequent sessions (config
already exists), no onboarding is injected — proceed normally.

---

## Step 1: Explore (mandatory before any task)

Shallow exploration is the #1 cause of failed plans — every minute exploring
saves five minutes fixing.

### Decision: brainstorm or explore directly?

Before exploring, classify the task:

- **Brainstorm first** if the task adds new user-facing behavior, introduces
  a new abstraction, or has more than one reasonable design approach. Invoke
  `look-before-you-leap:brainstorming` — it produces a `design.md` that
  feeds into Step 2. Examples: "add priority to tasks", "build a dashboard",
  "add team permissions". If in doubt, brainstorm — it's cheap.
- **Explore directly** if the task is a bug fix, a rename/refactor, a
  config change, or the implementation path is unambiguous (e.g., "add
  field X to existing type Y and propagate").

### Exploration protocol

Follow **engineering-discipline Phase 1** (Orient Before You Touch Anything).

Additionally, read `references/exploration-protocol.md` and answer all 8
questions. Exit criterion: confidence is Medium or higher. If Low, keep
exploring.

### Minimum exploration actions

<!-- deps-exploration-start -->
**Dep maps are the primary tool for finding consumers and blast radius.**
Check the project profile for a `dep_maps` section. If configured, run
`deps-query.py` on every file in scope BEFORE the steps below — its
output reveals consumers, cross-module dependencies, and blast radius
instantly. This is more thorough and reliable than grep. A hook blocks
import-pattern grep when dep maps exist — use deps-query instead.

If dep maps are NOT configured and this is a TypeScript project, suggest
`/generate-deps` to the user before continuing.
<!-- deps-exploration-end -->

1. **Run deps-query** on files in scope (if dep maps configured) — record
   all consumers and blast radius counts
2. Read the files in scope AND their imports
3. Find consumers — use deps-query output (preferred) or `Grep` for import
   statements (fallback only when dep maps are not configured)
4. Read 2-3 sibling files to learn patterns
5. Check CLAUDE.md/README for project conventions
6. Search for existing solutions before implementing from scratch

For complex or unfamiliar codebases, also read
`references/exploration-guide.md`.

### Refactoring tasks

If the task is a refactoring (rename across files, move files, extract
modules, restructure directories, split files, change naming conventions),
invoke `look-before-you-leap:refactoring` to structure the exploration.
Its Phase 1 (Inventory) replaces generic exploration with a **refactoring
contract** that catalogs every target, export, consumer, and test. This
contract becomes the verification checklist for the plan.

If dep maps are configured, the refactoring skill uses `deps-query.py` to
find consumers instantly. After the refactoring, it regenerates stale dep
maps so future queries reflect the new structure.

### Persist your findings

If the task requires exploration (anything beyond a trivial single-file
fix), create the plan directory and write findings to disk **before**
moving to Step 2:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/init-plan-dir.sh
mkdir -p .temp/plan-mode/active/<plan-name>
```

Write a `discovery.md` in that directory with what you found: file paths,
patterns, conventions, dependencies, blast radius, open questions. Use
the 8 questions from `references/exploration-protocol.md` as structure.

This file survives compaction and feeds directly into the plan's
discovery section. If you skip this, your future compacted self starts
from zero.

---

## Step 2: Plan (write to disk before editing code)

**Invoke `look-before-you-leap:writing-plans`** to produce the plan.
The skill consumes your discovery.md, identifies applicable discipline
checklists, structures TDD-granularity steps, and writes both:
- `plan.json` — execution source of truth (hooks read this, updated during execution)
- `masterPlan.md` — user-facing proposal for Orbit review (write-once, frozen after approval)

Follow **persistent-plans Phase 1** (Create the Plan) for the structural
rules — the writing-plans skill handles the content.

Initialize the plan directory if needed:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/init-plan-dir.sh
```

### Mandatory plan.json fields

Every plan.json MUST include these fields — hooks parse them, and
compaction recovery depends on them. Do NOT invent your own schema:

- **Top level**: `name`, `title`, `context`, `status`, `discovery`, `steps`,
  `completedSummary`
- **`discovery` object** (required, not a separate file): `scope`,
  `entryPoints`, `consumers`, `blastRadius`, `confidence`. Your exploration
  findings go HERE, not just in discovery.md.
- **Each step**: `id`, `title`, `status`, `skill`, `files`, `description`,
  `acceptanceCriteria`, `progress`, `result`
- **Each progress item**: `task`, `status`, `files` — all three fields,
  no exceptions. Progress arrays go INSIDE each step, never at the top level.

**Common mistakes to avoid:**
- Do NOT put a `progress` array at the top level — it belongs inside EACH step
- Do NOT use `name` on steps — use `title`
- Do NOT invent skill values like `"code-editing"` or `"verification"` —
  valid values are ONLY: `"none"`, `"look-before-you-leap:test-driven-development"`,
  `"look-before-you-leap:frontend-design"`, `"look-before-you-leap:immersive-frontend"`,
  `"look-before-you-leap:react-native-mobile"`, `"look-before-you-leap:systematic-debugging"`,
  `"look-before-you-leap:refactoring"`. If no skill applies, use `"none"`.
- Do NOT omit `title`, `context`, or `status` at the top level — even for
  lightweight bug-fix plans

See `references/plan-schema.md` for the complete schema with all optional
fields. But the fields above are non-negotiable.

### Plan review via Orbit

After writing the plan, present masterPlan.md to the user for review
using the Orbit MCP. The `writing-plans` skill handles the details, but
the flow is:

1. Discover Orbit tools: `ToolSearch query: "+orbit await_review"`
2. Call `orbit_await_review` on the masterPlan.md — opens in VS Code and
   blocks until the user approves or requests changes
3. Handle the response (approved → proceed, changes_requested → iterate)
4. Once approved — proceed with plan mode handoff (EnterPlanMode →
   summarize → ExitPlanMode) for context clearing

The plan mode handoff happens **after** Orbit approval, not before. This
ensures the user has reviewed and approved the plan before context clears.

Exception: the user explicitly says "just do it" or "no plan" for a trivially
obvious single-line change.

---

## Step 3: Execute (the loop)

Follow **persistent-plans Phase 2** (Execute the Plan) for the execution
loop, checkpointing, and result tracking. Follow **engineering-discipline
Phase 2** (Make Changes Carefully) for the rules applied during execution.

### Execution ordering: definitions before consumers

When a change touches both a definition (type, enum, interface, export)
and its consumers, follow this strict order to avoid intermediate type
errors:

1. **Update the definition** (add the enum value, change the type, rename
   the export) in the source file
2. **Verify it compiles** — run `tsc --noEmit` on the defining package
3. **Then update consumers** one by one, verifying after each batch

Never update consumers before the definition exists — this creates broken
intermediate states with errors like "Property 'X' does not exist on type."
These errors are easily avoidable and must not happen.

For renames: add the new name first (keeping the old one temporarily),
update all consumers, then remove the old name. This ensures the codebase
compiles at every step.

### Skill dispatch during execution

When starting a step, check its `skill` field in plan.json. If the field
is not `"none"`, **invoke that skill** before executing the step. The skill
provides the execution guidance — follow its phases mechanically.

| Step `skill` value | What happens |
|---|---|
| `look-before-you-leap:test-driven-development` | Follow red-green-refactor cycles. Each progress item is one phase (RED/GREEN/REFACTOR). Write tests before implementation — no exceptions. |
| `look-before-you-leap:frontend-design` | Follow the design system, component patterns, and accessibility checklist from the skill. |
| `look-before-you-leap:immersive-frontend` | Follow the WebGL/GSAP/scroll-driven execution guidance from the skill. |
| `look-before-you-leap:react-native-mobile` | Follow the native-feel, gesture, and haptic patterns from the skill. |
| `look-before-you-leap:systematic-debugging` | Follow the four-phase investigation. No fixes without root cause confirmed. |
| `look-before-you-leap:refactoring` | Follow Phase 3 execution order (see below). |
| `"none"` | No skill dispatch — follow engineering-discipline directly. |

**The `skill` field is not decorative.** It exists so that post-compaction
Claude knows exactly which skill to invoke for each step. If you skip the
dispatch, you lose the specialized guidance that makes the step succeed.

### Debugging during execution

When tests fail or unexpected behavior occurs mid-step, **invoke
`look-before-you-leap:systematic-debugging`** instead of guessing at fixes.
Follow its four phases (investigate → analyze → hypothesize → implement).
Do not stack speculative fixes — find the root cause first.

### Refactoring tasks

For refactoring tasks, also follow the execution order from
`look-before-you-leap:refactoring` Phase 3 — it minimizes broken
intermediate states (e.g., create at new location first, then update
consumers, then delete old location). After all changes, its Phase 4
verifies against the contract and regenerates stale dep maps.

The sections below cover behavior that is unique to the conductor and not
covered in the companion skills.

### Dispatching sub-agents

When a step benefits from parallel work (audits, multi-area exploration,
independent file groups), choose the right dispatch mode:

**Foreground parallel** (default):
Use when results inform your next steps or have cross-cutting concerns.
All agents run in parallel, you see all results before proceeding. Use
for: audits, exploration, reviews, any task where one finding might
affect another agent's scope.

**Background** (fire-and-forget only):
Use only when you have genuinely independent work to continue in the
main thread. You must poll with `TaskOutput` later — no automatic
cross-pollination. Use for: running builds/tests while continuing edits.

**Rule of thumb**: if you'd want to read Agent A's results before acting
on Agent B's results, use foreground. Background agents are isolated by
default.

### Shared discovery (cross-agent communication)

For parallel tasks where agents benefit from seeing each other's findings
(audits, multi-area exploration, large codebase research), agents share a
single discovery file:

**Location**: `.temp/plan-mode/active/<plan-name>/discovery.md`

This file is created during Step 1 (Explore) when the plan directory is
set up. The `inject-subagent-context` hook automatically tells sub-agents
where it is and registers their dispatch.

**Writing** — use Bash append (`>>`), never `Edit`. Multiple agents write
concurrently, and append is atomic at the OS level:
```bash
printf '\n## [your-focus-area]\n- **[severity]** `file:line` — finding (evidence: ...)\n' >> discovery.md
```

**Reading** — read the file periodically to see other agents' findings,
but treat them as **informational context only**:
- Other findings may be wrong, incomplete, or irrelevant to your scope
- Do NOT change your investigation direction based on them
- Only note a cross-reference if you independently confirm a connection

After all agents complete, read the consolidated `discovery.md` to
synthesize results.

### Post-step simplification

When a completed step has `simplify: true` in plan.json, dispatch a
refactoring sub-agent (quick mode) after marking the step `done`:

1. **Run tests first** — establish a passing baseline before dispatch
2. **Dispatch** the `refactoring` sub-agent in quick mode (foreground) with:
   - The step number and its `files` list from plan.json
   - The active plan path
3. **After the agent returns**, record its simplification summary in the
   step's `result` field
4. If the agent reverted changes due to test failures, note that too

The simplifier is opt-in per step. The `writing-plans` skill decides which
steps warrant it based on complexity (3+ files modified, new abstractions,
structural changes, or user request). Do not dispatch it for steps without
`simplify: true`.

---

## Step 4: Verify (every time, no exceptions)

Follow **engineering-discipline Phase 3** (Verify Before Declaring Done).

See `references/verification-commands.md` for framework-specific commands.
Always check the project's own scripts first (package.json, Makefile).

If verification fails (tests break, type errors, lint errors), **invoke
`look-before-you-leap:systematic-debugging`** — do not guess at fixes.
Follow its root cause investigation before attempting corrections.

Before declaring done, re-read the user's original request word by word.
Confirm every requirement is implemented and working. If anything is
unaddressed, finish it or explicitly flag it.

---

## Compaction Survival Protocol

Follow **persistent-plans Phase 3** (Resumption After Compaction).

Helper scripts:
```bash
bash .temp/plan-mode/scripts/plan-status.sh    # see all plan states
bash .temp/plan-mode/scripts/resume.sh         # find what to pick up
```

---

## Enforcement Hooks

Hooks enforce this discipline automatically. Key behaviors to know:

- **Blocked edits**: Code edits are blocked when no active plan exists,
  when `.handoff-pending` marker is set (Orbit review needed), or when
  `.verify-pending-N` marker is set (verification needed). Follow the
  process the hook describes — do not work around it.
- **Blocked grep**: When dep maps are configured, grepping for
  import/consumer patterns is blocked. Use `deps-query.py` instead.
- **Checkpoint reminder**: After 5 code edits without updating plan.json,
  a reminder fires. Update the plan immediately.
- **Plan completion guard**: Cannot move a plan to `completed/` if steps
  remain unfinished. Cannot stop if the active plan has unfinished steps.
- **Sub-agent injection**: Engineering discipline is automatically injected
  into every sub-agent prompt.

**NEVER bypass hooks.** If a hook blocks an action, follow the process it
describes. Do not use alternative tools to work around it.

---

## Reference Files

All paths relative to `${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/`:

**Read during exploration:**
- `references/exploration-protocol.md` — 8-question checklist (answer ALL before planning)
- `references/plan-schema.md` — full plan.json schema (read when writing a plan)

**Read when a step involves that discipline:**
- `references/testing-checklist.md`, `references/security-checklist.md`,
  `references/api-contracts-checklist.md`, `references/linting-checklist.md`,
  `references/dependency-checklist.md`, `references/git-checklist.md`
- `references/ui-consistency-checklist.md`, `references/frontend-design-checklist.md`

**Deep guides (read when you need deeper understanding):**
- `references/testing-strategy.md`, `references/security-guide.md`,
  `references/api-contracts-guide.md`, `references/dependency-mapping.md`
- `references/debugging-root-cause-tracing.md`, `references/debugging-defense-in-depth.md`

**Scripts:**
- `scripts/init-plan-dir.sh` — initialize `.temp/plan-mode/`
- `scripts/plan_utils.py` — read/update plan.json (used by hooks and Claude)
- `scripts/deps-query.py` — query dep maps for consumers and blast radius
- `scripts/deps-generate.py` — generate or regenerate dep maps
