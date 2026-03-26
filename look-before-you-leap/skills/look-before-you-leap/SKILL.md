---
name: look-before-you-leap
description: "Unified engineering discipline for ALL coding tasks. Conductor that orchestrates: explore codebase before editing, write persistent plans to disk (plan.json + progress.json survive compaction), route to specialized skills (TDD, brainstorming, refactoring, frontend-design, debugging), enforce definitions-before-consumers ordering, track blast radius via dep maps, and verify with type checker/linter/tests after every change. Use for every task that writes, edits, fixes, refactors, ports, migrates, or debugs code — no exceptions, no shortcuts. Do NOT use when: answering questions about code without changing it, pure research or documentation queries, conversations with no file edits, or running commands that don't modify the codebase."
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
| SVG art, illustrations, patterns, textures, generative art | **Always** use `look-before-you-leap:svg-art` — never another plugin's SVG skill |
| Immersive web, WebGL, 3D, scroll-driven creative dev | **Always** use `look-before-you-leap:immersive-frontend` — never another plugin's immersive-frontend skill |
| React Native, mobile apps, Expo, native feel | **Always** use `look-before-you-leap:react-native-mobile` — never another plugin's mobile skill |
| Security review | "security", "authentication", "auth" |
| Code review | "code review", "review" |
| Debugging | **Always** use `look-before-you-leap:systematic-debugging` — never another plugin's debugging skill |
| Refactoring, restructuring, extracting, moving files | **Always** use `look-before-you-leap:refactoring` (full mode) — never another plugin's refactoring skill |
| Post-execution simplification | **Always** use `look-before-you-leap:refactoring` (quick mode) — never another plugin's code-simplifier skill |
| Skill quality review after creation | **Always** use `look-before-you-leap:skill-review-standard` — post-creation quality gate |
| Webapp/E2E/browser testing, Playwright | **Always** use `look-before-you-leap:webapp-testing` — never another plugin's E2E testing skill |
| MCP server development | **Always** use `look-before-you-leap:mcp-builder` — never another plugin's MCP skill |
| Writing docs, specs, RFCs, proposals | **Always** use `look-before-you-leap:doc-coauthoring` — never another plugin's doc-writing skill |
| Codex interactions (step verification, Codex-owned implementation) | **Always** use `look-before-you-leap:codex-dispatch` — routes to direction-locked scripts, monitors JSONL, enforces independent verification |
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

### Obey the user's explicit instructions — no freelancing

**When the user tells you HOW to explore, you do it THAT way. Period.**

If the user says "explore with Codex", "use Codex to find X", or "have
Codex investigate" — you dispatch to Codex FIRST. You do NOT explore on
your own, form your own hypothesis, propose a fix, and THEN belatedly
ask Codex to rubber-stamp your conclusion. That is not "exploring with
Codex" — that is ignoring the user and using Codex as a yes-man.

The same applies to any explicit tool routing instruction: "use grep",
"check with the linter", "ask the user", "look at git blame". If the
user specifies the tool or method, that is what you use. Your job is to
execute the instruction, not to substitute your preferred approach and
then retroactively involve the requested tool for validation theater.

**Failure mode to watch for**: you read the user's instruction, mentally
classify it as "I can do this faster myself", do the work solo, and only
remember the instruction when the user complains. This is the #1 trust
destroyer. The user chose a tool for a reason — respect that choice even
if you think you can do it alone.

### Codex CLI only — NEVER use MCP tools for Codex

**All Codex interactions MUST go through `codex exec` via Bash.** NEVER
use `mcp__codex__codex` or any Codex MCP server tool. The MCP tool
bypasses the direction-locked scripts (`run-codex-verify.sh`,
`run-codex-implement.sh`), JSONL monitoring, structured result parsing,
sandbox enforcement, and error logging that the plugin provides.

The Codex MCP tool exists for other purposes. Within this plugin's
workflow, it is **forbidden**. If you catch yourself reaching for
`mcp__codex__codex`, stop — use `codex exec` via Bash instead.

```bash
# CORRECT — always use this:
codex exec -C <project-root> \
  --dangerously-bypass-approvals-and-sandbox --disable fast_mode "..."

# WRONG — never do this:
# mcp__codex__codex(prompt: "...", sandbox: "read-only")
```

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
bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-plan-dir.sh
mkdir -p .temp/plan-mode/active/<plan-name>
```

Write a `discovery.md` in that directory with what you found: file paths,
patterns, conventions, dependencies, blast radius, open questions. Use
the 8 questions from `references/exploration-protocol.md` as structure.

This file survives compaction and feeds directly into the plan's
discovery section. If you skip this, your future compacted self starts
from zero.

### Co-exploration protocol (MANDATORY when Codex available)

Co-exploration is not optional. When Codex is available, both agents
MUST explore simultaneously. This produces broader coverage and catches
blind spots neither agent would find solo.

**Phase 0 — Codex preflight:**

Codex availability is checked at session start and injected into your
context. Look for `**Codex CLI: AVAILABLE**` or `**Codex CLI: NOT
AVAILABLE**` in your session context. If present, you do NOT need to
run `command -v codex` — it was already done.

If no session-start context is available (e.g., after compaction or in
a sub-agent), run the check as a fallback:

```bash
command -v codex && echo "Codex available" || echo "Codex unavailable"
```

If Codex is available → proceed with Phase 1 (mandatory parallel exploration).
If Codex is unavailable → explore solo, document the fallback reason in
discovery.md under `## Codex Availability`, and pass `codexStatus=unavailable`
to the discovery receipt.

**Phase 1 — Parallel exploration (mandatory when Codex available):**

At the START of exploration (before writing discovery.md), dispatch Codex
in the background to explore in parallel with Claude:

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox --disable fast_mode \
  "Explore the codebase for the task: <task-description>. Focus on: \
   1. All consumers of files in scope (trace import chains) \
   2. Blast radius — what breaks if these files change? \
   3. Test infrastructure — what tests cover this code? \
   4. Edge cases and error paths in the current implementation \
   5. Cross-module dependencies that might be missed \
   Write your findings to <plan-dir>/discovery.md using heredoc append: \
   cat <<'EOF' >> discovery.md \
   then your markdown content, then EOF on its own line. \
   Use the format: ## [Codex: <topic>] then bullet points with findings."
```

While Codex runs, Claude explores simultaneously — focusing on:
- Patterns, conventions, existing solutions
- UI architecture and component structure
- Project config, sibling files, CLAUDE.md
- State producers and message emitters

Both write to the shared `discovery.md` using append (`>>`).

**Phase 2 — Convergence round:**

After both agents finish, Claude reads all of discovery.md, then
dispatches Codex for a focused convergence review. The prompt must ask
for **gaps and disagreements only** — not a rehash of all findings.
Keep Codex output scoped to structured bullet points.

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox --disable fast_mode \
  "Read <plan-dir>/discovery.md. Focus ONLY on gaps and disagreements: \
   1. What did Claude's exploration miss? (bullet points, max 5) \
   2. Where do you disagree with Claude's findings? (cite specific lines) \
   3. What blast radius was underestimated? (file:consumer count) \
   4. Cross-cutting concerns connecting both sets of findings? (max 3) \
   Keep output to structured bullets — no prose summaries. \
   Append under ## [Codex: Convergence] in discovery.md"
```

If discovery.md exceeds ~100 lines, tell Codex which sections to read
(e.g., "Read ## [Codex: Consumers] and ## [Claude: Patterns] only")
rather than asking it to process the entire file.

Claude then reconciles: merge complementary findings, flag disagreements
as open questions for the user, and update the discovery object in
plan.json.

**Exit criterion:** Both agents' findings are merged into discovery.md,
disagreements are flagged, and the discovery object in plan.json reflects
the combined understanding.

**Phase 3 — Discovery receipt:**

After co-exploration completes (or solo exploration with documented
fallback), write a signed discovery receipt:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-discovery-receipt.sh <project_root> <plan_name> <codex_status>
```

Where `codex_status` is one of:
- `complete` — Codex participated in co-exploration
- `unavailable` — `command -v codex` failed (document in discovery.md)
- `skipped-user-override` — user explicitly said to skip Codex

The writing-plans skill gates on this receipt — it will refuse to produce
a plan without verified discovery.

**Codex fallback states** (all require documentation in discovery.md):
- `unavailable`: Codex CLI not installed. Note "Codex: unavailable —
  command -v codex returned non-zero" under `## Codex Availability`.
- `skipped-user-override`: User said "skip Codex" or "explore without
  Codex". Note the user's instruction verbatim.

---

## Step 2: Plan (write to disk before editing code)

**You MUST invoke `look-before-you-leap:writing-plans` via the Skill tool
to produce the plan. Do NOT write plan.json or masterPlan.md directly.**
The writing-plans skill applies rules you cannot replicate by hand: it sets
`codexVerify: true` on every step, evaluates sub-plan criteria, applies
TDD rhythm to progress items, and checks discipline checklists. Even if you
have the schema memorized, skipping the skill means skipping those rules.

Call: `Skill(skill: "look-before-you-leap:writing-plans")`

The skill consumes your discovery.md, identifies applicable discipline
checklists, structures TDD-granularity steps, and writes both.
When dep maps are configured, `dep_partition.py` can be run on scoped
files to build graph-informed groups (see writing-plans Step 6).

Outputs:
- `plan.json` — immutable plan definition (frozen after Orbit approval, never edited during execution)
- `progress.json` — mutable execution state (step statuses, results, updated via plan_utils.py)
- `masterPlan.md` — user-facing proposal for Orbit review (write-once, frozen after approval)

Follow **persistent-plans Phase 1** (Create the Plan) for the structural
rules — the writing-plans skill handles the content.

Initialize the plan directory if needed:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-plan-dir.sh
```

### Mandatory plan.json fields

Every plan.json MUST include these fields — hooks parse them, and
compaction recovery depends on them. Do NOT invent your own schema:

- **Top level (plan.json)**: `name`, `title`, `context`, `status`,
  `requiredSkills`, `disciplines`, `discovery`, `steps`, `blocked`.
- **Top level (progress.json)**: `completedSummary`, `deviations`,
  `codexSessions`, step statuses/results — auto-managed by plan_utils.py.
- **`discovery` object** (required in plan.json): `scope`,
  `entryPoints`, `consumers`, `existingPatterns`, `testInfrastructure`,
  `conventions`, `blastRadius`, `confidence`. Your exploration findings
  go HERE, not just in discovery.md.
- **Each step (plan.json)**: `id`, `title`, `skill`, `simplify`, `files`,
  `description`, `acceptanceCriteria`, `progress` (task/files definitions).
  Optional: `owner` (`"claude"` default or `"codex"`), `mode`
  (collaboration mode, default `"claude-impl"`), `qa` (default false),
  `codexVerify` (always true —
  no exceptions, no mode-based exemptions), `subPlan`
  (null if none), `result` (null until completion),
  `routingJustification` (why this owner/mode was assigned — required by
  writing-plans for auditability)
- **Each progress item**: `task`, `status`, `files` — all three fields,
  no exceptions. Progress arrays go INSIDE each step, never at the top level.

**Common mistakes to avoid:**
- Do NOT put a `progress` array at the top level — it belongs inside EACH step
- Do NOT use `name` on steps — use `title`
- Do NOT invent skill values like `"code-editing"` or `"verification"` —
  valid values are ONLY: `"none"`, `"look-before-you-leap:test-driven-development"`,
  `"look-before-you-leap:frontend-design"`, `"look-before-you-leap:svg-art"`,
  `"look-before-you-leap:immersive-frontend"`,
  `"look-before-you-leap:react-native-mobile"`, `"look-before-you-leap:systematic-debugging"`,
  `"look-before-you-leap:refactoring"`, `"look-before-you-leap:webapp-testing"`,
  `"look-before-you-leap:mcp-builder"`, `"look-before-you-leap:doc-coauthoring"`.
  If no skill applies, use `"none"`.
- Do NOT omit `title`, `context`, or `status` at the top level — even for
  lightweight bug-fix plans
- Do NOT leave all steps as `claude-impl` without consulting the routing
  matrix — mechanical sweeps, refactoring across files, test writing, and
  verification steps should route to Codex (`codex-impl`). An all-claude-impl
  plan with 3+ steps is almost certainly wrong.

See `references/plan-schema.md` for the complete schema with all optional
fields. But the fields above are non-negotiable.

### Codex output batching principle

Large Codex dispatches stall when the prompt asks Codex to process
unbounded input (e.g., "For EACH of 15 steps..." or "Read ALL 200 lines
of findings..."). Apply this rule to every `codex exec` call:

- **Batch into groups of 5.** If the input has more than 5 items (steps,
  disagreements, findings sections), split into sequential `codex exec`
  calls of ≤5 items each. Merge results between batches.
- **Never retry an oversized prompt.** If a `codex exec` call times out
  or produces truncated output, split it — do not re-run the same prompt.
- **Cap output scope.** Ask for structured bullet points, not open-ended
  prose. Specify what to focus on (gaps, disagreements, missing items) —
  not "review everything."

This principle applies to consensus, convergence, verification, and any
other multi-item Codex dispatch.

### Plan consensus protocol (multi-round debate before Orbit)

After writing-plans produces the plan, Claude and Codex reach consensus
through structured debate before presenting to the user. This replaces
the one-shot attack pass — both agents must agree on the plan.

**Round 1 — Codex reviews the plan:**

If the plan has **≤5 steps**, dispatch a single call:

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox --disable fast_mode \
  "Read the plan at <plan-dir>/masterPlan.md and <plan.json>. \
   For steps 1-N, return a structured proposal per step: \
   - ACCEPT: step is well-sized, criteria are concrete, ownership is correct \
   - REJECT <reason>: step should be removed or fundamentally rethought \
   - MODIFY <changes>: step needs specific changes (sizing, criteria, ownership, ordering) \
   Also flag: missing steps, wrong ordering, vague acceptance criteria, \
   ownership assignments that contradict the routing matrix."
```

If the plan has **>5 steps**, batch into groups of 5:

```bash
# Batch 1: steps 1-5
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox --disable fast_mode \
  "Read the plan at <plan-dir>/masterPlan.md and <plan.json>. \
   Review ONLY steps 1-5. For each, return: \
   - ACCEPT: step is well-sized, criteria are concrete, ownership is correct \
   - REJECT <reason>: step should be removed or fundamentally rethought \
   - MODIFY <changes>: step needs specific changes (sizing, criteria, ownership, ordering) \
   Append results to <plan-dir>/consensus-round1.md under ## Steps 1-5"

# Batch 2: steps 6-10 (adjust range for actual step count)
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox --disable fast_mode \
  "Read the plan at <plan-dir>/masterPlan.md and <plan.json>. \
   Review ONLY steps 6-10. For each, return: \
   - ACCEPT / REJECT <reason> / MODIFY <changes> \
   Append results to <plan-dir>/consensus-round1.md under ## Steps 6-10"

# Continue batching until all steps are covered.
# After all batches, also dispatch a cross-cutting check:
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox --disable fast_mode \
  "Read <plan-dir>/consensus-round1.md (all batch results). \
   Flag: missing steps, wrong ordering across the full plan, \
   ownership assignments that contradict the routing matrix. \
   Append cross-cutting notes under ## Cross-Cutting."
```

Merge all batch results before proceeding to Round 2.

**Round 2 — Claude responds:**

For each Codex proposal:
- **ACCEPT**: incorporate the change into plan.json and masterPlan.md
- **REJECT with reasoning**: explain why the current plan is correct
  (cite specific evidence — code paths, patterns, constraints)
- **COUNTER-PROPOSE**: offer an alternative that addresses Codex's
  concern differently

Update the plan files with accepted changes.

**Round 3 (if needed) — Final resolution:**

If disagreements remain after Round 2, dispatch Codex one more time.
If **≤5 disagreements**, use a single call. If **>5**, batch into groups
of 5 disagreements per call, merging results between batches.

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox --disable fast_mode \
  "Read the updated plan at <plan-dir>/plan.json and Claude's responses \
   to your proposals. For these remaining disagreements: [list ≤5 items] \
   - ACCEPT Claude's reasoning, or \
   - ESCALATE with both positions stated (for the user to decide in Orbit)"
```

**Max 3 rounds.** Unresolved items go to Orbit review with both
positions clearly stated so the user can make the final call.

If `codex` CLI is not available, skip consensus and proceed directly to
Orbit review.

### Plan review via Orbit

After plan consensus (or directly after writing-plans if Codex is
unavailable), present masterPlan.md to the user for review using the
Orbit MCP. The `writing-plans` skill handles the details, but the flow is:

1. Discover Orbit tools: `ToolSearch query: "+orbit await_review"`
2. Call `orbit_await_review` on the masterPlan.md — opens in VS Code and
   blocks until the user approves or requests changes
3. Handle the response (approved → proceed, changes_requested → iterate)
4. Once approved — proceed with plan mode handoff:
   **Pre-flight**: Kill ALL running background tasks before starting
   the handoff (background Bash commands, background Agents, pending
   Codex exec). They are no longer needed after plan approval. If any
   survive, their results leak into the new session after context
   clears and corrupt the fresh start.
   a. Call `EnterPlanMode` — do NOT output any text in the same response.
   b. After entering plan mode, a system message tells you the scratch pad
      file path (under `~/.claude/plans/`). Write to THAT file — NOT to
      masterPlan.md or plan.json. Content must be minimal: plan title,
      path, step count, one-liner context, and "Read plan.json to begin
      execution." Nothing else — no step descriptions, no Codex consensus,
      no file lists.
   c. Call `ExitPlanMode` — do NOT output any text in the same response.
   The handoff marker is auto-cleared by a hook when `EnterPlanMode` is
   called or when `orbit_await_review` returns approved.

   **IMPORTANT**: Do not output explanatory text alongside `EnterPlanMode`
   or `ExitPlanMode` calls. Extra text can interfere with the plan mode
   transition and cause the scratch pad to appear as a stashed message
   instead of the plan mode green box.

The plan mode handoff happens **after** Orbit approval, not before. This
ensures the user has reviewed and approved the plan before context clears.

Exception: the user explicitly says "just do it" or "no plan" for a trivially
obvious single-line change.

---

## Step 3: Execute (the loop)

Follow **persistent-plans Phase 2** (Execute the Plan) for the execution
loop, checkpointing, and result tracking. Follow **engineering-discipline
Phase 2** (Make Changes Carefully) for the rules applied during execution.

### Visual progress tracking (mandatory)

At the **start of execution** (first time entering the loop, or after
compaction when resuming), create a task for each step using `TaskCreate`.
This gives the user a live visual progress display in the terminal.

**Format**: `[Step N/total: owner] step title`

```
TaskCreate for each step in plan.steps:
  subject: "[Step {id}/{total}: {owner}] {title}"
  description: step.description (truncated to 200 chars)
  activeForm: "[Step {id}/{total}] {title}"
```

**During execution**, update tasks to match progress state:
- When marking a step `in_progress` → `TaskUpdate(status: "in_progress")`
- When marking a step `done` → `TaskUpdate(status: "completed")`
- When a step is `blocked` → keep as `pending` (no blocked status in tasks)

**After compaction**: if tasks don't exist (compaction clears them), re-create
them from plan.json + progress.json with correct statuses (completed for done steps, pending
for the rest).

This is not optional — the task list is how the user tracks progress visually.
Skip only if the plan has a single step.

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

### Pre-step deliverables checklist

Before writing any code for a step, extract every deliverable from its
`description` and `acceptanceCriteria` fields into a numbered checklist.
This is separate from progress items (which track sub-tasks) — the
deliverables checklist tracks *what the step must produce*, not *how*.

**The process:**

1. Re-read the step's `description` word by word
2. Re-read its `acceptanceCriteria` word by word
3. List every concrete deliverable as a numbered item — primary features,
   secondary behaviors, adapted labels, i18n keys, documentation updates,
   precondition checks, validation rules
4. Write this checklist somewhere persistent (plan notes, discovery.md,
   or inline as you work)
5. **Before marking the step done**, walk through every item and verify
   it was implemented

This prevents the failure mode where you focus on the primary feature
and forget secondary deliverables mid-implementation. Example: a step
says "Tab label adapts to vertical (Menu vs Lookbook)" — you build the
tab content but forget the label because you focused on the harder part.
Or a step lists "Translation progress section" and "Retranslate button"
among other features — you implement the novel parts and silently drop
the ones that seemed straightforward.

**The checklist is mandatory for every step.** Even simple steps benefit
from it — the cost is 30 seconds of reading, and the payoff is catching
scope cuts before they ship.

### Skill dispatch during execution

**Skills MUST be invoked via the Skill tool — not approximated from memory.**
When starting a step, check its `skill` field in plan.json. If the field
is not `"none"`, **call `Skill(skill: "<value>")` before executing the
step.** The skill provides execution guidance you cannot replicate by hand.
Do NOT read a skill's SKILL.md and follow it manually — invoke it so the
full skill context (references, checklists, hooks) loads properly.

| Step `skill` value | What happens |
|---|---|
| `look-before-you-leap:test-driven-development` | Follow red-green-refactor cycles. Each progress item is one phase (RED/GREEN/REFACTOR). Write tests before implementation — no exceptions. |
| `look-before-you-leap:frontend-design` | Follow the design system, component patterns, and accessibility checklist from the skill. |
| `look-before-you-leap:svg-art` | Follow the composition principles, decision tree, and reference file routing from the skill. |
| `look-before-you-leap:immersive-frontend` | Follow the WebGL/GSAP/scroll-driven execution guidance from the skill. |
| `look-before-you-leap:react-native-mobile` | Follow the native-feel, gesture, and haptic patterns from the skill. |
| `look-before-you-leap:systematic-debugging` | Follow the four-phase investigation. No fixes without root cause confirmed. |
| `look-before-you-leap:refactoring` | Follow Phase 3 execution order (see below). |
| `look-before-you-leap:webapp-testing` | Follow the decision tree, reconnaissance-then-action, Playwright MCP integration, and server lifecycle from the skill. |
| `look-before-you-leap:mcp-builder` | Follow the 4-phase MCP workflow (research, implement, review/test, evaluate). |
| `look-before-you-leap:doc-coauthoring` | Follow the 3-stage authoring workflow (context gathering, refinement, reader testing). |
| `"none"` | No skill dispatch — follow engineering-discipline directly. |

**The `skill` field is not decorative.** It exists so that post-compaction
Claude knows exactly which skill to invoke for each step. If you skip the
dispatch, you lose the specialized guidance that makes the step succeed.

### DAG-driven parallel dispatch

Steps declare dependencies via `dependsOn`. The executor uses
`runnable_steps()` from plan_utils.py to compute the frontier — all
pending steps whose predecessors are done. Independent steps run in
parallel; dependent steps wait.

```
LOOP:
  1. runnable = runnable_steps(plan)    # pending steps with all dependsOn done
  2. IF runnable is empty AND no in_progress steps → plan complete
  3. IF len(runnable) == 1 → execute sequentially (current single-step flow)
  4. IF len(runnable) > 1 → dispatch all in parallel:
     FOR each step in runnable:
       Mark step in_progress
       IF step.owner == "claude":
         Dispatch as foreground sub-agent via Agent tool
       ELSE IF step.owner == "codex":
         Dispatch via run-codex-implement.sh in background
     Wait for all to complete
  5. Verify all completed steps (Codex verify for claude-impl, Claude verify for codex-impl)
  6. Fix findings sequentially, re-verify as needed
  7. Mark verified steps done → new steps may now be runnable
  8. GOTO LOOP
```

### Owner-based dispatch (per-step)

For each step (whether dispatched sequentially or as part of a parallel
batch), the execution flow depends on `owner` and `mode`:

```
IF step.mode == "collab-split":
  REQUIRE step.subPlan with groups
  FOR each group in step.subPlan.groups:
    effective_owner = group.owner ?? step.owner
    IF effective_owner == "claude":
      Claude implements the group's files
      → run-codex-verify.sh scoped to group files
      → If findings: Claude fixes → re-run verify → repeat until PASS
      → Record "Group N (Claude): Codex: PASS" in group.notes
    ELSE IF effective_owner == "codex":
      → run-codex-implement.sh scoped to group files
      → Claude verifies INDEPENDENTLY: read files, tsc/lint/tests, deps-query
      → If issues: Claude fixes directly, log to usage-errors/claude-findings/
      → Record "Group N (Codex): Claude: verified" in group.notes
  Step result accumulates per-group verdicts

ELSE IF step.mode == "dual-pass":
  Claude does design/UX/architecture pass
  Codex does correctness/security pass via run-codex-verify.sh
  Claude synthesizes both sets of findings

ELSE IF step.owner == "claude":           # claude-impl
  Claude implements
  → run-codex-verify.sh
  → If findings: Claude fixes → re-run verify → repeat until PASS
  → Write ### Criterion: result, add ### Verdict with Codex: PASS

ELSE IF step.owner == "codex":            # codex-impl
  → run-codex-implement.sh
  → Codex implements via codex exec
  → Claude verifies INDEPENDENTLY: read files, tsc/lint/tests, deps-query
  → If issues: Claude fixes directly
  → Log findings to usage-errors/claude-findings/
  → Write ### Criterion: result, add ### Verdict with Claude: verified
```

**`owner: "claude"` (default — Claude implements, Codex verifies):**

Claude implements the step, then Codex verifies via `run-codex-verify.sh`.
Standard flow — implement, then run Codex verification.

**`owner: "codex"` (Codex implements, Claude verifies):**

1. Invoke `Skill(skill: "look-before-you-leap:codex-dispatch")` —
   the skill runs `run-codex-implement.sh` in the background
2. Codex implements the step via `codex exec`
3. After Codex reports completion, Claude does a full verification pass:
   - Read all files Codex modified (`git diff --name-only`)
   - Read EVERY modified file
   - Run tsc/lint/tests
   - Check consumers via deps-query on any modified shared files
   - Verify against the step's acceptance criteria
4. If issues found:
   - Fix directly
   - Log Claude's findings to `usage-errors/claude-findings/` (see
     Symmetric Error Logging below)
5. Update progress items via plan_utils.py based on Codex's report
6. Write step result using the `### Criterion:` template, add `### Verdict\nClaude: verified`

**Do NOT run `run-codex-verify.sh` on codex-impl steps.** The script
rejects them — and even if it didn't, having Codex verify its own work
defeats the purpose. The `verify-step-completion` hook enforces this:
it rejects "Codex: PASS" on codex-impl steps.

**Do NOT implement codex-impl steps yourself.** Even if the change seems
"trivially small" (adding a value to a union type, updating a switch
statement), dispatch Codex via `run-codex-implement.sh`. The ownership
model exists for independent verification — when you implement a codex-impl
step, you lose that independence. Do not work around the verification
rejection by calling `codex exec` directly; the direction-locked scripts
exist for a reason.

**`mode: "collab-split"` (collaborative design, per-group ownership execution):**

Collab-split steps use sub-plan groups as the unit of ownership. Each group
has an `owner` field (`"claude"` or `"codex"`) assigned by writing-plans
using the routing matrix. The executor dispatches each group to the correct
agent — **never implement a codex-owned group yourself**.

1. Read the step's `subPlan.groups` — each group has `owner`, `files`,
   `status`, `notes`
2. For each pending group, check `group.owner`:
   - **Claude-owned group**: Claude implements the group's files, then runs
     `run-codex-verify.sh <plan.json> <step> <group-idx>` (the third arg
     scopes verification to the group's files). Fix findings → re-verify
     → repeat until PASS. Record `"Group N (Claude): Codex: PASS"` in
     `group.notes`.
   - **Codex-owned group**: Dispatch via
     `run-codex-implement.sh <plan.json> <step> <group-idx>` (third arg
     scopes implementation to the group's files). After Codex completes,
     Claude verifies independently (read files, tsc/lint/tests, deps-query).
     Record `"Group N (Codex): Claude: verified"` in `group.notes`.
3. After all groups complete, write the step's `result` field using the
   `### Criterion:` template — map each acceptance criterion to evidence
   from the accumulated group verdicts, then add the `### Verdict` section
   (e.g., `### Verdict\nGroups 1-4 (Claude): Codex: PASS. Groups 5,7
   (Codex): Claude: verified.`)

**`mode: "dual-pass"` (both agents work independently):**

1. Claude does its pass first (design/UX/architecture focus)
2. Run `run-codex-verify.sh` — Codex focuses on correctness/security
3. Claude synthesizes both sets of findings
4. Record combined findings in step result

### Symmetric verification

Neither agent's work ships unreviewed. The verification direction depends
on the step owner:

| Step owner | Who verifies | How |
|---|---|---|
| `claude` | Codex | Via `run-codex-verify.sh` |
| `codex` | Claude | Read files, run tsc/lint/tests, check consumers |
| `dual-pass` | Both | Each focuses on different aspects, Claude synthesizes |

### Symmetric error logging

Findings flow in both directions:

- **Codex → Claude**: Codex logs Claude's mistakes to
  `usage-errors/codex-findings/` (auto-logged by the `lbyl-verify` Codex
  skill installed at `~/.codex/skills/`)
- **Claude → Codex**: When Claude verifies Codex-owned steps and finds
  issues, write findings to `usage-errors/claude-findings/` using the same
  JSON schema. See `codex-dispatch` skill for the exact schema and naming
  convention.

Both directories use the same core JSON structure (severity, category,
file, line, summary, detail, preventable). Claude-review logs add a
`reviewer: "claude"` field; Codex logs do not include a reviewer field
(they are implicitly from Codex). This enables cross-agent pattern
analysis to identify which rules need strengthening.

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
affect another agent's scope. **Also use for parallel claude-impl steps**
— each sub-agent implements one step.

**Background** (fire-and-forget only):
Use only when you have genuinely independent work to continue in the
main thread. You must poll with `TaskOutput` later — no automatic
cross-pollination. Use for: running builds/tests while continuing edits,
**and for codex-impl steps dispatched via run-codex-implement.sh**.

**Rule of thumb**: if you'd want to read Agent A's results before acting
on Agent B's results, use foreground. Background agents are isolated by
default.

#### Implementation sub-agents (parallel step execution)

When the DAG frontier has multiple runnable steps, Claude dispatches
parallel sub-agents. Each sub-agent receives:

- The step definition from plan.json (id, description, acceptanceCriteria,
  files, skill, owner)
- The plan.json path for progress updates
- The project root for running commands

Each sub-agent must:
- Only edit files listed in its step's `files` array
- Update its step's progress items via plan_utils.py
- Run its step's skill if `skill` is not `"none"`
- Run own verification (tsc, lint, tests) before reporting
- Report results — do NOT mark the step done (main thread does that
  after Codex/Claude verification)

Each sub-agent must NOT:
- Edit files belonging to other steps
- Mark the step as `done` (verification gate is main thread's job)
- Read or modify other steps' progress items
- Run Codex verification (main thread handles this after all sub-agents
  complete)

### Shared discovery (cross-agent communication)

For parallel tasks where agents benefit from seeing each other's findings
(audits, multi-area exploration, large codebase research), agents share a
single discovery file:

**Location**: `.temp/plan-mode/active/<plan-name>/discovery.md`

This file is created during Step 1 (Explore) when the plan directory is
set up. The `inject-subagent-context` hook automatically tells sub-agents
where it is and registers their dispatch.

**Writing** — use heredoc append (`>>`), never `Edit`. Multiple agents
write concurrently, and append is atomic at the OS level. Use a
single-quoted heredoc delimiter (`'EOF'`) to prevent zsh glob expansion
of `**bold**` markdown patterns:
```bash
cat <<'EOF' >> discovery.md

## [your-focus-area]
- **[severity]** `file:line` — finding (evidence: ...)
EOF
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

### Post-step QA review

When a completed step has `qa: true` in plan.json, dispatch a fresh-eyes
QA sub-agent after marking the step `done`:

1. **Spawn a foreground sub-agent** with:
   - The step's `files` list and `acceptanceCriteria` from plan.json
   - NO prior context from the implementation — the agent reads the files
     cold, exactly as a reviewer would
   - Prompt: "Review these files against the acceptance criteria. Report
     any issues: missing functionality, inconsistencies, unclear code,
     broken patterns, accessibility problems."
2. **Read the agent's report.** If it found issues:
   - Fix them (follow engineering-discipline, not quick patches)
   - Re-verify after fixes
3. **Record the QA outcome** in the step's `result` field using the
   `### Criterion:` template — append QA findings to each relevant
   criterion's evidence, note what was fixed and what was accepted as-is

QA dispatch is opt-in per step. The `writing-plans` skill decides which
steps warrant it. Do not dispatch for steps without `qa: true`.

### Codex verification (gate before marking done)

When a step has `codexVerify: true` in plan.json, Codex verification
is a **gate** — you MUST get a Codex PASS **before** marking the step
`done`. Codex runs on a different model with its own engineering-discipline
plugin, providing truly independent verification with fresh context.

**Codex runs BEFORE done, not after.** The correct flow is: complete all
progress items → run your own verification (tsc, lint, tests) → run
`run-codex-verify.sh` → fix any findings → re-run until PASS → THEN
mark the step done with the Codex verdict in the result field.

**No pre-existing exemptions.** If the acceptance criteria say "tsc
passes" and tsc does not pass, fix the issue — regardless of whether
this step introduced the failure. "Pre-existing" is not a valid
dismissal. Either fix the failure or get the acceptance criteria changed
before the plan was approved.

**One step at a time.** Each step gets its own Codex call. NEVER batch
multiple steps into a single call.

**Prerequisites**: The Codex CLI must be installed (`npm install -g
@openai/codex`). Codex skills must be installed at `~/.codex/skills/`
(done automatically by the SessionStart hook).

**You MUST run `command -v codex` before claiming Codex is unavailable.**
Do NOT write "Codex: skipped — codex CLI not installed" without proof.
The default assumption is that Codex IS installed. If `command -v codex`
fails, THEN and only then may you skip verification and note the skip
in the result field.

**Flow:**

1. **Complete the step's work** — all progress items done, your own
   verification passing (tsc, lint, tests).
2. **Run Codex verification** via `run-codex-verify.sh`:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh <plan.json> <step-number>
   ```
   Run this in the background (`Bash run_in_background: true`). While
   Codex runs, you can begin exploring the next step (read files, check
   consumers) — but do NOT start editing code.
3. **Read the result** from `.codex-result-step-N.txt`. If findings:
   - Codex auto-logs findings to `usage-errors/codex-findings/`
   - Do NOT dismiss a Codex finding as "pre-existing," "out of scope,"
     or "my interpretation is different." If you believe the finding is
     wrong, you have exactly two options:
     1. Quote the exact code path or plan text that proves it is wrong.
     2. Ask the user to approve a plan / acceptance-criteria change
        before continuing.
   - **Investigate before fixing.** Before editing any code:
     1. Read the file(s) and line(s) Codex cited
     2. State the root cause in one sentence
     3. If the finding has multiple parts, address ALL of them
   - Fix each issue (follow engineering-discipline, not quick patches)
   - **Re-run verification after fixing.** Run `run-codex-verify.sh`
     again. Do NOT skip this — `tsc --noEmit` passing is not the same
     as Codex confirming your fixes are correct.
   - **Test-parity rule**: When Codex flags both code issues and
     MISSING_TEST in the same reverify round, you MUST fix BOTH before
     re-verifying. Do not cherry-pick code fixes while ignoring test gaps.
   - **Type-error escalation**: If the same finding CATEGORY appears in
     2 consecutive reverify log files (e.g., TYPE_SAFETY in both
     `step-N.json` and `step-N-reverify-1.json` in
     `usage-errors/codex-findings/`), STOP ad-hoc fixing. Invoke
     `look-before-you-leap:systematic-debugging` to find the root cause.
   - Repeat the fix → re-verify loop until Codex reports PASS
4. **THEN mark the step done** with a structured result using the
   `### Criterion:` template. Map each acceptance criterion to evidence
   (file:line, command output), then add a `### Verdict` section with the
   Codex verdict. The verdict must come from Codex, not from your own
   assessment. See `references/plan-schema.md` for the full template.

Codex verification is **on for every step — no exceptions.** The
`writing-plans` skill sets `codexVerify: true` on all steps. There are
no mode-based exemptions. The field is structural, not opt-in.

The `verify-step-completion` hook enforces this gate with direction
awareness:
- For `owner: "claude"` steps: result must contain "Codex: PASS" (or
  FAIL or skipped)
- For `owner: "codex"` steps: result must contain "Claude: verified"
  AND must NOT contain "Codex: PASS" (prevents Codex self-verification)

### Codex Findings Log (both directions)

Findings flow in both directions, logged to separate directories:

**Codex verifies Claude** → `usage-errors/codex-findings/`
Codex auto-logs its findings via the `lbyl-verify` skill installed at
`~/.codex/skills/`. You do not need to log these manually.
- Initial: `YYYY-MM-DD-{plan}-step-{N}.json`
- Re-verify: `YYYY-MM-DD-{plan}-step-{N}-reverify-{M}.json`

**Claude verifies Codex** → `usage-errors/claude-findings/`
When Claude verifies Codex-owned steps and finds issues, Claude writes
findings manually using the same JSON schema.
- Review: `YYYY-MM-DD-{plan}-step-{N}-claude-review.json`
- Re-review: `YYYY-MM-DD-{plan}-step-{N}-claude-review-{M}.json`

Both use the same JSON structure and failure categories: `INCOMPLETE_WORK`,
`MISSED_CONSUMER`, `TYPE_SAFETY`, `SILENT_SCOPE_CUT`, `WRONG_PATTERN`,
`MISSING_TEST`, `MISSING_I18N`, `OTHER`. The `reviewer` field (`"codex"`
or `"claude"`) distinguishes direction. See `codex-dispatch` skill for
the exact schema.

This ensures the full verification history is auditable in both directions
and enables cross-agent pattern analysis.

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
- **Checkpoint reminder**: After 5 code edits without updating progress,
  a reminder fires. Update via plan_utils.py immediately.
- **Plan completion guard**: Cannot move a plan to `completed/` if steps
  remain unfinished. Cannot stop if the active plan has unfinished steps.
- **Script warnings**: When `plan_utils.py` emits a warning (e.g., "step
  marked done with no result"), treat it as an error. Stop and fix the
  issue before continuing. Warnings exist because something is wrong —
  they are not informational noise to ignore.
- **Sub-agent injection**: Engineering discipline is automatically injected
  into every sub-agent prompt.
- **PostCompact resumption**: After context compaction, a dedicated hook
  detects the active plan and injects resumption context. Do NOT re-plan
  or re-explore — just read the plan and continue.

**NEVER bypass hooks.** If a hook blocks an action, follow the process it
describes. Do not use alternative tools to work around it.

---

## Plugin Error Logging

When you encounter an error **caused by this plugin** — a hook script
failing, `plan_utils.py` crashing, a schema validation error, a script
not found, or any unexpected behavior from plugin hooks or scripts —
document it immediately:

1. **Create a `.md` file** in `usage-errors/` at the **project root** with
   the naming convention `YYYY-MM-DD-<short-description>.md`.
2. **Include**:
   - What you were doing when the error occurred
   - The hook/script/skill that errored
   - The full error output
   - Your best guess at the root cause
3. **Then fix the issue before continuing.** If the error is in your
   command arguments (wrong step number, missing file), fix and retry.
   If the error is a genuine plugin bug (script crash on valid input),
   log it and continue — the bug is not yours to fix mid-task
4. **When the error is fixed**, move the `.md` file to `usage-errors/resolved/`

This applies only to errors originating from the plugin itself (hooks,
scripts, skills, plan infrastructure). Do NOT log errors from the user's
project code, build tools, or unrelated tooling.

Example filename: `2026-03-19-plan-utils-key-error.md`

---

## Codex Lessons Pipeline

When Codex catches a behavioral pattern that the existing rules should
have prevented (e.g., "guessed API response shape" maps to "Read API
handlers before typing responses"), the lesson belongs in the centralized
pipeline — not in memory.

**Location**: `codex-lessons/` at the plugin repo root.

**Workflow**: After a session where Codex found genuine bugs, analyze the
root causes. If a bug reveals a gap in engineering-discipline rules (a
habit that would have prevented it), write a proposal to
`codex-lessons/proposals/`. During periodic review, proposals
are either promoted to plugin rules or discarded.

This is distinct from error logging (which tracks plugin bugs) and memory
(which tracks procedural preferences). The lessons pipeline tracks
**behavioral rule gaps** — patterns Codex keeps catching that the rules
should make impossible.

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

**Codex integration:**
- `references/routing-matrix.md` — task-type routing table for step ownership assignment
- `references/scenario-playbook.md` — 23-scenario ownership matrix with collaboration modes

**Scripts:**
- `scripts/init-plan-dir.sh` — initialize `.temp/plan-mode/`
- `scripts/plan_utils.py` — read plan.json + progress.json, update progress (used by hooks and Claude)
- `scripts/deps-query.py` — query dep maps for consumers and blast radius
- `scripts/deps-generate.py` — generate or regenerate dep maps
- `scripts/run-codex-verify.sh` — direction-locked Codex verification
- `scripts/run-codex-implement.sh` — direction-locked Codex implementation
- `scripts/dep_partition.py` — partition target files into planning groups using dep maps
