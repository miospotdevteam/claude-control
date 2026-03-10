---
name: look-before-you-leap
description: "Unified engineering discipline for ALL coding tasks. Three layers: this file (the conductor), quick-reference checklists, and deep guides. Enforces structured exploration before planning, persistent plans that survive compaction, TDD red-green-refactor cycles that prevent implementation-first coding, disciplined execution with blast radius tracking and type safety, and multi-discipline coverage (testing, UI consistency, security, git, linting, dependencies). Use for every task that touches source files — no exceptions, no shortcuts. Do NOT use when: answering questions about code without changing it, pure research or documentation queries, conversations with no file edits, or running commands that don't modify the codebase."
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

Follow **engineering-discipline Phase 1** (Orient Before You Touch Anything).

Additionally, read `references/exploration-protocol.md` and answer all 8
questions. Exit criterion: confidence is Medium or higher. If Low, keep
exploring.

### Minimum exploration actions

<!-- deps-exploration-start -->
**If dep maps are configured** (check the project profile for the resolved
command): run `deps-query.py` on every file in scope BEFORE the steps below.
The output reveals consumers, cross-module dependencies, and blast radius
upfront — it shapes the entire exploration. For audits/reviews, run on key
entry points per module. If dep maps are NOT configured, skip this preamble.
<!-- deps-exploration-end -->

If dep maps are NOT configured and this is a TypeScript project (check the
project profile), suggest `/generate-deps` to the user before continuing.
Dep maps make consumer finding and blast-radius analysis instant and complete.

1. Read the files in scope AND their imports
2. Find consumers of files in scope — use deps-query output if available,
   otherwise `Grep` for import statements
3. Read 2-3 sibling files to learn patterns
4. Check CLAUDE.md/README for project conventions
5. Search for existing solutions before implementing from scratch

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

This plugin enforces discipline through hooks, not just instructions:

- **SessionStart**: Injects the full conductor, engineering-discipline, and
  persistent-plans skills into every session. Detects active plans (via
  plan.json) and shows resumption instructions. Discovers other installed
  plugins. On first run, auto-detects the project stack and creates the
  local config.
- **UserPromptSubmit**: On first run (when `.claude/.onboarding-pending`
  marker exists), injects onboarding instructions to walk the user through
  setup: stack summary, config enrichment, CLAUDE.md creation, plugin
  suggestions. Fires once, then removes the marker.
- **PreToolUse(Edit|Write)**: Blocks code edits if no active plan exists
  in `.temp/plan-mode/active/` (checks plan.json, falls back to
  masterPlan.md). Allows edits to `.temp/` (plan files). Bypass for
  trivial changes: `echo $PPID > .temp/plan-mode/.no-plan`.
- **PreToolUse(Edit|Write)**: **Hard deny** when `.handoff-pending` marker
  exists and plan is still fresh. Blocks all code edits until Orbit review
  + plan mode handoff is complete. Includes ToolSearch guidance for
  orbit_await_review. Bypass: `rm .temp/plan-mode/.handoff-pending`.
- **PreToolUse(Edit|Write)**: Soft warning when editing API boundary files.
  Reminds Claude to check for shared types and schemas.
- **PreToolUse(Bash)**: Blocks Bash file-writing commands when no active
  plan exists. Also blocks `mv` of plan directories from `active/` to
  `completed/` if the plan has unfinished steps (checked via plan.json).
- **PreToolUse(Grep)**: **Hard deny** when grepping for import/consumer
  patterns and dep maps are configured. Forces use of `deps-query.py`.
- **PostToolUse(Edit|Write)**: Counts code file edits. After 5 edits
  without updating plan files, injects a checkpoint reminder. Resets when
  any plan file (plan.json or masterPlan.md) is edited.
- **PostToolUse(Edit|Write)**: When plan.json or masterPlan.md is edited,
  migrates any fallback discovery file and checks if all steps are done
  (via plan.json). If all complete, injects a reminder to verify and
  finalize before moving to `completed/`.
- **PostToolUse(Edit|Write)**: When a fresh plan is written (all steps
  pending in plan.json), creates `.handoff-pending` marker and injects
  directive for Orbit review + plan mode handoff.
- **PostToolUse(Edit|Write)**: When a step transitions to done, creates
  `.verify-pending-N` marker and injects directive to dispatch a
  verification sub-agent. Code edits are blocked until verification passes.
- **PostToolUse(Edit|Write)**: When `.ts`/`.tsx` files are edited, marks
  the corresponding dep map module as stale. Silent — no output.
- **PreToolUse(Task)**: Automatically injects engineering discipline into
  every sub-agent prompt.
- **Stop**: Blocks Claude from stopping if the active plan has unfinished
  steps (checked via plan.json). Forces explicit completion or status update.

**NEVER bypass hooks.** If a hook blocks an action, follow the process it
describes. Do not use alternative tools to work around it. Do not call it
a "false positive." The hooks exist to enforce the discipline that makes
your work survive compaction and remain correct.

---

## Reference Files

All paths relative to `${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/`:

### Process & Templates
- `references/exploration-protocol.md` — 8-question exploration checklist
- `references/exploration-guide.md` — deep exploration techniques
- `references/plan-schema.md` — plan.json schema (execution source of truth)
- `references/master-plan-format.md` — masterPlan.md template (user-facing proposal)
- `references/claude-md-snippet.md` — recommended CLAUDE.md addition

### Discipline Checklists (Layer 2)
- `references/testing-checklist.md` — before/during/after testing
- `references/ui-consistency-checklist.md` — design tokens, components, visual consistency
- `references/frontend-design-checklist.md` — accessibility, responsive, performance, coherence for frontend design
- `references/security-checklist.md` — auth, input validation, secrets
- `references/git-checklist.md` — commits, branches, messages
- `references/linting-checklist.md` — linter and formatter discipline
- `references/dependency-checklist.md` — package management and verification
- `references/api-contracts-checklist.md` — API boundary discipline

### Deep Guides (Layer 3)
- `references/testing-strategy.md` — TDD-lite, test pyramid, edge cases, test theater
- `references/ui-consistency-guide.md` — design tokens, component discipline, drift detection
- `references/frontend-design-guide.md` — aesthetic axes, font sourcing, animation, color, anti-slop blacklist
- `references/security-guide.md` — OWASP Top 10, S.E.C.U.R.E. framework, slopsquatting
- `references/api-contracts-guide.md` — API boundary discipline, shared schema enforcement
- `references/debugging-root-cause-tracing.md` — trace bugs backward through call stack to source
- `references/debugging-defense-in-depth.md` — multi-layer validation after fixing root cause
- `references/debugging-condition-based-waiting.md` — replace arbitrary timeouts with condition polling
- `references/dependency-mapping.md` — dep map configuration, module setup, query usage

### Operational
- `references/verification-commands.md` — type checker/linter/test commands by ecosystem
- `references/recommended-plugins.md` — suggested official plugins for onboarding
- `scripts/init-plan-dir.sh` — initialize `.temp/plan-mode/` directory
- `scripts/plan-status.sh` — show status of all active plans
- `scripts/resume.sh` — find what to resume after compaction
- `scripts/plan_utils.py` — read/update plan.json (used by hooks and Claude)
- `scripts/deps-query.py` — query dependency maps for consumers and dependencies
- `scripts/deps-generate.py` — generate or regenerate dependency maps
