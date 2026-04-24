---
name: look-before-you-leap
description: "Unified engineering discipline for ALL coding tasks. Conductor-mode orchestrator: Claude is the conductor that dispatches every step (Codex implements by default, Claude verifies; or Claude implements via sub-agents and Codex verifies), and the main thread reads ONLY plan.json, progress.json, signed receipts, HMAC sidecars, and lbyl-digest outputs — never raw .codex-result-*.txt, .codex-stream-*.jsonl, codex-exploration.md, codex-consensus-*.md, or git diff. Drives discovery (Claude Explore + Codex co-exploration → lbyl-digest), planning (writing-plans + Codex consensus → lbyl-digest → Orbit), execution (runnable-steps DAG frontier dispatched in parallel), and verification (codex-receipt-step-N.json + lbyl-digest verification). Use for every task that writes, edits, fixes, refactors, ports, migrates, or debugs code — no exceptions, no shortcuts. Do NOT use when: answering questions about code without changing it, pure research or documentation queries, conversations with no file edits, or running commands that don't modify the codebase."
---

# Software Discipline (Conductor Mode)

This skill is the conductor. Conductor mode is the default and only
operating mode — it controls the process and routes every unit of
work to a specialized sub-agent or wrapper. The conductor itself
**writes no code**, **reads no raw artifacts**, and **runs no
verification by hand**. It dispatches; it consumes signed receipts and
bounded digests; it gates plan progress on those.

The actual rules live in companion skills that are always injected
alongside this one:

- **engineering-discipline** — The behavioral layer: explore before
  editing, track blast radius, no type shortcuts, verify work, no
  silent scope cuts.
- **persistent-plans** — The structural layer: plan files on disk, the
  execution loop, checkpoints, sub-plans, compaction survival.
- **codex-dispatch** — The Codex orchestration layer: receipt-first
  routing, direction-locked wrapper scripts, parallel DAG dispatch.
- **lbyl-digest** — The bounded-context reader. Every large or raw
  artifact (exploration MDs, consensus batch MDs, Codex receipts +
  modified files) is read by a `lbyl-digest` sub-agent in a fresh
  context and returns a bounded payload to the conductor.

**You must follow all four companion skills for every coding task.**

## What the Main Thread May Read

The main thread (the conductor) is allowed to read ONLY these on-disk
artifacts during execution:

- `plan.json` — immutable plan definition.
- `progress.json` — mutable execution state.
- `<plan-dir>/codex-receipt-step-<N>.json` — signed verification or
  implementation receipt (per `references/codex-receipt-schema.md`).
- `<plan-dir>/codex-receipt-step-<N>.claude-review.json` — sibling
  review receipt written by `lbyl-digest` (verification mode) for
  codex-impl steps.
- `~/.claude/look-before-you-leap/state/<projectId>/<planId>/codex_<kind>-step-<N>.json`
  — the HMAC sidecar that binds the receipt's bytes to the trust
  anchor.
- Digest outputs from `lbyl-digest`: `<plan-dir>/discovery-digest.md`,
  `<plan-dir>/consensus-round-<N>-digest.md`, and the bounded JSON
  payloads digesters return.
- The bounded payload returned directly by any dispatched sub-agent
  (Claude implementation Agents, `lbyl-digest` Skill calls).
- Project metadata: CLAUDE.md, README.md, `.claude/look-before-you-leap.local.md`,
  package.json / Cargo.toml / etc. Plain reference docs are fine.

The main thread MUST NOT read:

- `<plan-dir>/.codex-result-step-<N>.txt` (or `-group-G.txt`) — human
  trace only.
- `<plan-dir>/.codex-stream-step-<N>.jsonl` — raw streaming events.
- `<plan-dir>/codex-exploration.md`, `<plan-dir>/codex-convergence.md`,
  `<plan-dir>/codex-consensus-round*.md`,
  `<plan-dir>/codex-consensus-batch-*.md`,
  `<plan-dir>/codex-consensus-cross-cutting.md` — these are
  `lbyl-digest` inputs.
- `git diff` of step files — the digester sub-agent runs this
  internally if it needs to.
- The on-disk source files modified by a Codex-owned step — for
  verification, this is the digester's job. (Reading source files
  during exploration is fine; reading them to "double-check Codex"
  during execution is not.)

If you find yourself about to open one of the forbidden artifacts to
"see what really happened", **stop**. Either the receipt + digest are
sufficient, or you dispatch a fresh `lbyl-digest`. There is no third
path.

## Hard Interpretation Rules

**This plugin defines operational rules, not suggestions.** Treat the
capitalized words literally:

- **MUST / REQUIRED / ALWAYS** = binding requirement
- **NEVER / FORBIDDEN / DO NOT** = hard prohibition
- **SHOULD / PREFER** = default only when no hard rule applies

Do NOT silently downgrade a hard rule because:

- the task looks small
- you think you already understand the repo
- you believe your shortcut is faster
- you are under time pressure
- the user did not explicitly repeat the rule this turn

If a hard rule blocks progress, follow the documented fallback or stop
and state the exact blocker. Do NOT improvise a side path that
preserves your momentum while violating the rule.

---

## Step 0: Discover Available Skills

At the start of every session, note which skills are available (the
SessionStart hook provides a skill inventory). When a step calls for
specialized knowledge (testing, frontend design, security review),
check if an installed skill covers it before relying on general
knowledge.

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
| Codex interactions (step verification, Codex-owned implementation) | **Always** use `look-before-you-leap:codex-dispatch` — direction-locked wrappers, signed receipts, lbyl-digest verification |
| Bounded reading of raw conductor artifacts (exploration MDs, consensus batches, Codex receipt + diff cross-check) | **Always** use `look-before-you-leap:lbyl-digest` — conductor-internal sub-agent; never assigned as a plan-step skill |
| PR/commit workflow | "commit", "PR", "git" |

If no specialized skill exists, use the checklists and guides in
`references/`.

### First-run onboarding

When look-before-you-leap runs in a project for the first time, the
SessionStart hook auto-detects the stack and creates
`.claude/look-before-you-leap.local.md`. On that first session,
additional onboarding instructions are injected into the context
telling you to:

1. Tell the user what was detected
2. Offer to enrich the config by exploring the codebase
3. Offer to create a CLAUDE.md if the project has none
4. Suggest useful official plugins and offer to install them

Follow those instructions when they appear. On subsequent sessions
(config already exists), no onboarding is injected — proceed normally.

---

## Step 1: Discovery (mandatory before any task)

Shallow exploration is the #1 cause of failed plans — every minute
exploring saves five minutes fixing. Discovery is **co-exploration by
default** when Codex is available: Claude and Codex explore in
parallel, then `lbyl-digest` merges both into a bounded
`discovery-digest.md` that the conductor reads.

### Decision: brainstorm or explore directly?

Before exploring, classify the task:

- **Brainstorm first** if the task adds new user-facing behavior,
  introduces a new abstraction, or has more than one reasonable design
  approach. Invoke `look-before-you-leap:brainstorming` — it produces
  a `design.md` that feeds into Step 2. Examples: "add priority to
  tasks", "build a dashboard", "add team permissions". If
  classification is ambiguous, route to brainstorming.
  Ambiguity is not permission to explore directly.
- **Explore directly** if the task is a bug fix, a rename/refactor, a
  config change, or the implementation path is unambiguous (e.g.,
  "add field X to existing type Y and propagate").

### Obey the user's explicit instructions — no freelancing

**When the user tells you HOW to explore, you do it THAT way. Period.**

If the user says "explore with Codex", "use Codex to find X", or
"have Codex investigate" — you dispatch to Codex FIRST. You do NOT
explore on your own, form your own hypothesis, propose a fix, and
THEN belatedly ask Codex to rubber-stamp your conclusion. That is not
"exploring with Codex" — that is ignoring the user and using Codex as
a yes-man.

The same applies to any explicit tool routing instruction: "use grep",
"check with the linter", "ask the user", "look at git blame". If the
user specifies the tool or method, that is what you use. Your job is
to execute the instruction, not to substitute your preferred approach
and then retroactively involve the requested tool for validation
theater.

### Exploration protocol

Follow **engineering-discipline Phase 1** (Orient Before You Touch
Anything). Read `references/exploration-protocol.md` and answer all 8
questions. Exit criterion: confidence is Medium or higher. If Low,
keep exploring.

### Minimum exploration actions

<!-- deps-exploration-start -->
**Dep maps are the primary tool for finding consumers and blast
radius.** Check the project profile for a `dep_maps` section. If
configured, run `deps-query.py` on every file in scope BEFORE the
steps below — its output reveals consumers, cross-module dependencies,
and blast radius instantly. This is more thorough and reliable than
grep. A hook blocks import-pattern grep when dep maps exist — use
deps-query instead.

If dep maps are NOT configured and this is a TypeScript project,
suggest `/generate-deps` to the user before continuing.
<!-- deps-exploration-end -->

1. **Run deps-query** on files in scope (if dep maps configured) —
   record all consumers and blast radius counts.
2. Read the files in scope AND their imports.
3. Find consumers — use deps-query output (preferred) or `Grep` for
   import statements (fallback only when dep maps are not configured).
4. Read 2-3 sibling files to learn patterns.
5. Check CLAUDE.md/README for project conventions.
6. Search for existing solutions before implementing from scratch.

For complex or unfamiliar codebases, also read
`references/exploration-guide.md`.

### Refactoring tasks

If the task is a refactoring (rename across files, move files, extract
modules, restructure directories, split files, change naming
conventions), invoke `look-before-you-leap:refactoring` to structure
the exploration. Its Phase 1 (Inventory) replaces generic exploration
with a **refactoring contract** that catalogs every target, export,
consumer, and test. This contract becomes the verification checklist
for the plan.

If dep maps are configured, the refactoring skill uses
`deps-query.py` to find consumers instantly. After the refactoring,
it regenerates stale dep maps so future queries reflect the new
structure.

### Persist your findings

If the task requires exploration (anything beyond a trivial
single-file fix), create the plan directory and write findings to
disk **before** moving to Step 2:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-plan-dir.sh
mkdir -p .temp/plan-mode/active/<plan-name>
```

Write a `discovery.md` in that directory with what you found: file
paths, patterns, conventions, dependencies, blast radius, open
questions. Use the 8 questions from
`references/exploration-protocol.md` as structure.

This file survives compaction and feeds directly into the plan's
discovery section. If you skip this, your future compacted self
starts from zero.

### Co-exploration protocol (MANDATORY when Codex available)

Co-exploration is not optional. When Codex is available, both agents
MUST explore simultaneously. The actual `codex exec` invocations and
prompt templates live in `codex-dispatch` (Co-Exploration Dispatch).
This skill describes the conductor's role in that flow.

**Phase 0 — Codex preflight:**

Codex availability is checked at session start and injected into your
context. Look for `**Codex CLI: AVAILABLE**` or `**Codex CLI: NOT
AVAILABLE**` in your session context. If present, you do NOT need to
run `command -v codex` — it was already done.

If no session-start context is available (e.g., after compaction or
in a sub-agent), run the check as a fallback:

```bash
command -v codex && echo "Codex available" || echo "Codex unavailable"
```

If Codex is available → proceed with Phase 1.
If Codex is unavailable → explore solo, document the fallback reason
in discovery.md under `## Codex Availability`, and pass
`codexStatus=unavailable` to the discovery receipt.

**Phase 1 — Parallel exploration:**

Dispatch Codex co-exploration in the background via `codex-dispatch`
(it runs `codex exec ... -o <plan-dir>/codex-exploration.md` with
`run_in_background: true`). Claude explores simultaneously in the
main thread, writing notes to `discovery.md`. The conductor does NOT
open `codex-exploration.md` itself.

**Phase 2 — Convergence round:**

After both agents finish, dispatch Codex one more time (still via
`codex-dispatch`) for a focused convergence review with output to
`<plan-dir>/codex-convergence.md`. The prompt asks for **gaps and
disagreements only** — not a rehash of all findings.

**Phase 3 — Digest (mandatory):**

The conductor never reads `codex-exploration.md` or
`codex-convergence.md` directly. Dispatch `lbyl-digest`:

```
Skill(
  skill: "look-before-you-leap:lbyl-digest",
  args: "mode=co-exploration plan-dir=<plan-dir>"
)
```

The sub-agent reads `discovery.md`, `codex-exploration.md`, and
`codex-convergence.md`, writes
`<plan-dir>/discovery-digest.md`, and returns a bounded payload
`{ kind, digestPath, topicsCount, openQuestionsCount, summary }`.

The conductor reads only the bounded payload — `summary` and
`openQuestionsCount` to decide whether to surface open questions to
the user before proceeding to Step 2. Open
`<plan-dir>/discovery-digest.md` only if the summary indicates it
must.

**Phase 4 — Discovery receipt:**

After co-exploration completes (or solo exploration with documented
fallback), write a signed discovery receipt:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-discovery-receipt.sh \
  <project_root> <plan_name> <codex_status>
```

Where `codex_status` is one of:

- `complete` — Codex participated in co-exploration
- `unavailable` — `command -v codex` failed (document in discovery.md)
- `skipped-user-override` — user explicitly said to skip Codex

The writing-plans skill gates on this receipt — it will refuse to
produce a plan without verified discovery.

---

## Step 2: Plan (write to disk before editing code)

**You MUST invoke `look-before-you-leap:writing-plans` via the Skill
tool to produce the plan. Do NOT write plan.json or masterPlan.md
directly.** The writing-plans skill applies rules you cannot replicate
by hand: it sets `codexVerify: true` on every step, evaluates
decomposition criteria, applies TDD rhythm to progress items, and
checks discipline checklists.

Call: `Skill(skill: "look-before-you-leap:writing-plans")`

The skill consumes your discovery digest, identifies applicable
discipline checklists, structures TDD-granularity steps, and writes
both files. When dep maps are configured, `dep_partition.py` can be
run on scoped files to build graph-informed step boundaries (see
writing-plans).

Outputs:

- `plan.json` — immutable plan definition (frozen after Orbit
  approval, never edited during execution).
- `progress.json` — mutable execution state (step statuses, results,
  updated via `plan_utils.py`).
- `masterPlan.md` — user-facing proposal for Orbit review (write-once,
  frozen after approval).

Follow **persistent-plans Phase 1** (Create the Plan) for the
structural rules — the writing-plans skill handles the content.

Initialize the plan directory if needed:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-plan-dir.sh
```

### conductorMode is the default

Plans default to `conductorMode: true` at the top level of plan.json.
This makes explicit what the entire plugin assumes: the main thread
is a conductor, every step dispatches to a sub-agent or wrapper, and
authority lives in receipts and digests. There is no
`conductorMode: false` execution path supported by the current
hooks — the field exists so future tooling can reject plans that
expect raw-read behavior. See `references/plan-schema.md` for the full
field documentation.

There is no `collab-split` mode. Step-level file isolation is
enforced by the DAG (`dependsOn` + disjoint `files[]` on the runnable
frontier); there is no in-step group ownership. Decomposition
happens at the step level — write multiple steps with explicit
ownership and let the frontier dispatch them in parallel.

### Mandatory plan.json fields

Every plan.json MUST include these fields — hooks parse them, and
compaction recovery depends on them. Do NOT invent your own schema:

- **Top level (plan.json)**: `name`, `title`, `context`, `status`,
  `conductorMode`, `requiredSkills`, `disciplines`, `discovery`,
  `steps`, `blocked`.
- **Top level (progress.json)**: `completedSummary`, `deviations`,
  `codexSessions`, step statuses/results — auto-managed by
  plan_utils.py.
- **`discovery` object** (required in plan.json): `scope`,
  `entryPoints`, `consumers`, `existingPatterns`, `testInfrastructure`,
  `conventions`, `blastRadius`, `confidence`. Your exploration
  findings go HERE, not just in discovery.md.
- **Each step (plan.json)**: `id`, `title`, `skill`, `simplify`,
  `files`, `description`, `acceptanceCriteria`, `progress`
  (task/files definitions), `dependsOn`. Optional: `owner`
  (`"codex"` is the default implementer; `"claude"` for steps that
  require Claude judgment such as design / brainstorm follow-up /
  doc authoring), `mode` (`"codex-impl"` or `"claude-impl"`,
  matching `owner`), `qa` (default false), `codexVerify` (always
  true — no exceptions), `subPlan` (always null; the field exists
  for legacy plans only), `result` (null until completion),
  `routingJustification` (why this owner/mode was assigned —
  required by writing-plans for auditability).
- **Each progress item**: `task`, `status`, `files` — all three
  fields, no exceptions. Progress arrays go INSIDE each step, never
  at the top level.

**Common mistakes to avoid:**

- Do NOT put a `progress` array at the top level — it belongs inside
  EACH step.
- Do NOT use `name` on steps — use `title`.
- Do NOT invent skill values like `"code-editing"` or
  `"verification"` — valid values are ONLY: `"none"`,
  `"look-before-you-leap:test-driven-development"`,
  `"look-before-you-leap:frontend-design"`,
  `"look-before-you-leap:svg-art"`,
  `"look-before-you-leap:immersive-frontend"`,
  `"look-before-you-leap:react-native-mobile"`,
  `"look-before-you-leap:systematic-debugging"`,
  `"look-before-you-leap:refactoring"`,
  `"look-before-you-leap:webapp-testing"`,
  `"look-before-you-leap:mcp-builder"`,
  `"look-before-you-leap:doc-coauthoring"`. If no skill applies, use
  `"none"`. **Never** put `"look-before-you-leap:lbyl-digest"` here —
  it is a conductor-internal sub-agent skill, not a plan-step skill.
- Do NOT omit `title`, `context`, `status`, or `conductorMode` at the
  top level — even for lightweight bug-fix plans.
- Do NOT default every step to `claude-impl`. Codex is the default
  implementer. Steps that route to `claude-impl` need a clear
  `routingJustification` (design judgment, doc authoring, brainstorm
  follow-up, frontend visual work). An all-claude-impl plan with 3+
  steps is almost certainly a routing failure.
- Do NOT set `mode: "collab-split"` — collab-split has been removed.
  If you see a legacy plan with collab-split, decompose its
  sub-plan groups into top-level steps with `dependsOn` edges.

See `references/plan-schema.md` for the complete schema with all
optional fields. The fields above are non-negotiable.

### Plan consensus protocol (multi-round debate before Orbit)

After writing-plans produces the plan, Claude and Codex reach
consensus through structured debate before presenting to the user.
Both agents must agree on the plan.

Consensus dispatch (the actual `codex exec` calls and batching) lives
in `codex-dispatch` (Plan Consensus Dispatch). This skill describes
the conductor's role.

**Round 1 — Codex reviews the plan:**

Dispatch Codex via `codex-dispatch` (foreground; consensus runs are
not backgrounded — background notifications during plan mode handoff
break the context clear). For plans with ≤5 steps, one call. For >5
steps, batch into groups of 5, with optional cross-cutting check at
the end.

Each call writes a separate `codex-consensus-*.md` file under
`<plan-dir>/`. The conductor does NOT read these files itself.

**Digest the round (mandatory):**

After all batches finish, dispatch `lbyl-digest`:

```
Skill(
  skill: "look-before-you-leap:lbyl-digest",
  args: "mode=consensus plan-dir=<plan-dir> round-N=1"
)
```

The sub-agent reads every `codex-consensus-round1.md` and/or
`codex-consensus-batch-*.md` (and the cross-cutting file if present),
writes `<plan-dir>/consensus-round-1-digest.md`, and returns
`{ kind, round, digestPath, counts, decisions, openDisagreements,
summary }`.

The conductor reads only the bounded payload:
- `counts` to decide whether the plan can advance.
- `decisions` to know which steps need plan edits.
- `openDisagreements` to know what to respond to in Round 2.

**Round 2 — Claude responds** to each `decision` from the digester
(ACCEPT / REJECT with reasoning / COUNTER-PROPOSE). Update plan files
with accepted changes.

**Round 3 (if needed) — Final resolution:**

If `openDisagreements` remain, dispatch Codex once more (≤5
disagreements per call; batch as in Round 1). Then re-dispatch
`lbyl-digest` (mode=consensus, round-N=3) and gate on its returned
`openDisagreements`.

**Max 3 rounds.** Unresolved items go to Orbit with both positions
stated clearly so the user can make the final call.

If `codex` CLI is not available, skip consensus and proceed directly
to Orbit review.

### Plan review via Orbit

After plan consensus (or directly after writing-plans if Codex is
unavailable), present masterPlan.md to the user for review using the
Orbit MCP. The `writing-plans` skill handles the details, but the
flow is:

1. Discover Orbit tools: `ToolSearch query: "+orbit await_review"`.
2. Call `orbit_await_review` on the masterPlan.md — opens in VS Code
   and blocks until the user approves or requests changes.
3. Handle the response (approved → proceed, changes_requested →
   iterate).
4. Once approved — proceed with plan mode handoff:

   a. Call `EnterPlanMode` — do NOT output any text in the same
      response.
   b. After entering plan mode, a system message tells you the
      scratch pad file path (under `~/.claude/plans/`). Write to
      THAT file — NOT to masterPlan.md or plan.json. Content must
      be minimal: plan title, path, step count, one-liner context,
      and "Read plan.json to begin execution." The only additional
      lines allowed are the hard reminders: respect step ownership
      exactly, do NOT implement Codex-owned steps yourself, and do
      NOT mark any step done before the verification receipt
      (and lbyl-digest verification for codex-impl) returns PASS.
      Nothing else — no step descriptions, no Codex consensus, no
      file lists.
   c. Call `ExitPlanMode` — do NOT output any text in the same
      response.

   The pending-review marker is cleared only when
   `orbit_await_review` returns approved. `EnterPlanMode` happens
   after approval; it does not clear a pending review marker.

   **IMPORTANT**: Do not output explanatory text alongside
   `EnterPlanMode` or `ExitPlanMode` calls. Extra text can interfere
   with the plan mode transition and cause the scratch pad to appear
   as a stashed message instead of the plan mode green box.

The plan mode handoff happens **after** Orbit approval, not before.
This ensures the user has reviewed and approved the plan before
context clears.

Exception: the user explicitly says "just do it" or "no plan" for a
trivially obvious single-line change.

---

## Step 3: Execute (the loop)

Follow **persistent-plans Phase 2** (Execute the Plan) for the
execution loop, checkpointing, and result tracking. Follow
**engineering-discipline Phase 2** (Make Changes Carefully) for the
rules applied during execution. Codex implementation and verification
flow through **codex-dispatch**.

Conductor mode means: the main thread NEVER edits source files
itself. It dispatches Codex (`codex-impl` steps) or a Claude
sub-agent (`claude-impl` steps), waits for completion, reads the
receipt + digest, and gates on the verdict.

### Visual progress tracking (mandatory)

At the **start of execution** (first time entering the loop, or after
compaction when resuming), create a task for each step using
`TaskCreate`. This gives the user a live visual progress display in
the terminal.

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
- When a step is `blocked` → keep as `pending` (no blocked status in
  tasks)

**After compaction**: if tasks don't exist (compaction clears them),
re-create them from plan.json + progress.json with correct statuses
(completed for done steps, pending for the rest).

This is not optional — the task list is how the user tracks progress
visually. Skip only if the plan has a single step.

### DAG-driven parallel dispatch (the default execution loop)

Steps declare dependencies via `dependsOn`. The executor uses
`runnable-steps` to compute the frontier — all pending steps whose
predecessors are done. Independent steps run in parallel; dependent
steps wait. **`runnable-steps` is the default; `next-step` is legacy
and only useful when the frontier is size 1.**

```bash
python3 .temp/plan-mode/scripts/plan_utils.py runnable-steps <plan.json>
```

**MUST parallelize.** When `runnable-steps` returns more than one
step, you MUST dispatch them all in a single message — one Bash tool
call per `codex-impl` step (background) and one Agent tool call per
`claude-impl` step (foreground sub-agent). Executing them one-by-one
defeats the DAG and wastes time. The only exceptions are the
stated-reason cases below.

```
LOOP:
  1. runnable = runnable-steps(plan)    # pending steps with all dependsOn done
  2. IF runnable is empty AND no in_progress steps → plan complete
  3. IF len(runnable) == 1 → execute sequentially (single-step flow)
  4. IF len(runnable) > 1 → dispatch ALL in ONE message:
     a. Mark every frontier step in_progress in progress.json NOW
        → TaskUpdate(in_progress) for each
     b. In ONE assistant message, emit:
        - For each codex-impl step: Bash run-codex-implement.sh
          (run_in_background=true)
        - For each claude-impl step: Agent (subagent_type
          "general-purpose"), one Agent call per step
     c. Wait for completions (refetch the frontier as soon as one
        finishes — do not block until all finish)
  5. For each completed step:
     - Read codex-receipt-step-N.json
     - For codex-impl: dispatch lbyl-digest (verification mode)
     - Apply receipt-first gate (PASS / FINDINGS / FAIL)
     - Fix findings (sequentially per step), re-verify until PASS
  6. complete-step for each verified step → new steps may now be
     runnable
  7. GOTO LOOP
```

**Stated-reason exceptions to parallel dispatch.** Serial execution is
allowed only when one of these is true, AND you record the reason in
the step's result or via `add-deviation`:

- Frontier size is 1.
- A step in the frontier modifies the dispatch wrapper itself
  (`run-codex-implement.sh`, `run-codex-verify.sh`, or hooks the
  wrappers source) — see codex-dispatch's wrapper-modification race
  rule. These steps must be dispatched ALONE.
- A previous step's failure forced a "fix one, re-verify, then
  continue" recovery loop.
- The user explicitly requested serial execution.

#### Concrete example: dispatching 3 parallel steps

When the DAG frontier contains steps 1 (codex-impl), 2 (codex-impl),
and 3 (claude-impl), all `dependsOn: []`, your response MUST contain
all three tool calls in a single message:

```
Bash(command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-implement.sh
              <plan.json> 1",
     run_in_background: true,
     description: "Step 1: ...")

Bash(command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-implement.sh
              <plan.json> 2",
     run_in_background: true,
     description: "Step 2: ...")

Agent(description="Step 3: doc rewrite",
      prompt="You are implementing Step 3 of plan <path>/plan.json. ...
              Only edit files: [docs/foo.md].
              Acceptance criteria: ...",
      subagent_type="general-purpose")
```

All three appear in the SAME message → Claude Code dispatches them
concurrently. Do NOT send one, wait for it, then send the next.

### Owner-based dispatch (per-step)

For each step (whether dispatched sequentially or as part of a
parallel batch), the execution flow is determined entirely by
`owner`:

```
IF step.owner == "codex":               # codex-impl (default)
  → Bash run-codex-implement.sh (background)
  → On completion: read codex-receipt-step-N.json
  → Dispatch Skill lbyl-digest (mode=verification)
  → Read digester payload: claudeVerified ∈ {PASS, FINDINGS}
  → If FINDINGS: read claude-review.json + receipt findings, fix
    (re-dispatch Codex or patch via Claude Agent), re-run digester
  → On PASS: write ### Criterion: result, ### Verdict\nClaude: verified
  → complete-step

ELSE IF step.owner == "claude":         # claude-impl
  → Agent (foreground sub-agent) implements per step.files / criteria
  → On completion: Bash run-codex-verify.sh (background)
  → On completion: read codex-receipt-step-N.json
  → finalVerdict ∈ {PASS, FINDINGS, FAIL}
  → If FINDINGS/FAIL: dispatch a Claude Agent to fix, then re-run
    run-codex-verify.sh; repeat until PASS
  → On PASS: write ### Criterion: result, ### Verdict\nCodex: PASS
  → complete-step

IF step has dual-pass flag:
  → Run the owner's path above (typically claude-impl) to a PASS
    verify receipt.
  → Then dispatch a second run-codex-verify.sh focused on the
    aspects the first pass did not target. Both receipts must reach
    PASS.
  → Synthesize both receipts' findings[] into the step result.
```

**`owner: "codex"` (default — Codex implements, Claude verifies):**

The conductor dispatches `run-codex-implement.sh` in the background
via `codex-dispatch`. After the wrapper exits, the conductor reads
`codex-receipt-step-<N>.json` to confirm Codex emitted it, then
dispatches `lbyl-digest` (mode=verification). The digester reads
the receipt + the cited file ranges + runs the diff-vs-receipt and
sha256 cross-checks, writes
`<plan-dir>/codex-receipt-step-<N>.claude-review.json`, and returns
a bounded payload `{ kind, stepId, claudeVerified, findingCount,
reviewPath, criteria, summary }`.

The conductor gates on `claudeVerified`:
- `PASS` → write the step result, mark done.
- `FINDINGS` → identify failing criteria, decide whether to
  re-dispatch Codex or patch via a Claude Agent, then re-run the
  digester on the new receipt.

**Do NOT implement codex-impl steps yourself.** Even if the change
seems trivial (adding a value to a union type, updating a switch
statement), dispatch Codex via the wrapper. The ownership model
exists for independent verification — when you implement a
codex-impl step, you lose that independence. Do NOT call `codex
exec` directly to work around the wrapper; the direction-locked
script enforces the receipt + sidecar contract that the
`verify-step-completion` hook validates.

**`owner: "claude"` (Claude implements, Codex verifies):**

For multi-step plans, claude-impl steps are dispatched to a
**foreground Agent sub-agent** (one per step in the parallel
frontier). The sub-agent implements within the step's `files[]`,
runs its own tsc/lint/tests, and reports back. The conductor then
runs `run-codex-verify.sh` in the background; on completion, it
reads `codex-receipt-step-<N>.json` and gates on `finalVerdict`.

For findings, the conductor dispatches another Claude Agent to
patch (NEVER edits source files inline), then re-runs the verify
wrapper. Repeat until the receipt comes back PASS.

The `verify-step-completion` hook enforces the gate with direction
awareness:

- For `owner: "claude"` steps: result must contain "Codex: PASS"
  (or FAIL or skipped) AND a matching signed verify receipt must
  exist.
- For `owner: "codex"` steps: result must contain "Claude: verified"
  AND must NOT contain "Codex: PASS" (prevents Codex
  self-verification) AND a sibling `claude-review.json` with
  `claudeVerified == "PASS"` and matching `receiptSha256` must
  exist.

### Symmetric verification

Neither agent's work ships unreviewed. The verification direction
depends on the step owner:

| Step owner | Who verifies | How |
|---|---|---|
| `codex` | Claude (via lbyl-digest sub-agent) | Read receipt + dispatch `lbyl-digest` (verification mode); read claude-review.json receipt only |
| `claude` | Codex (via run-codex-verify.sh) | Read `codex-receipt-step-N.json` only |
| `dual-pass` | Both (sequential Codex passes) | Two verify receipts, synthesized |

### Symmetric error logging

Findings flow in both directions, logged to separate directories.
Both flows are receipt-driven — the conductor never hand-extracts
findings from raw text traces.

- **Codex verifies Claude** → `usage-errors/codex-findings/`. The
  `lbyl-verify` Codex skill embeds `findings[]` in the receipt and
  the wrapper auto-archives them, keyed by `{plan, step, retry}`.
- **Claude verifies Codex** → `usage-errors/claude-findings/`. When
  the verification digester returns `claudeVerified == "FINDINGS"`,
  the conductor archives the bounded payload's findings (via the
  digester's `reviewPath` sibling file), keyed by `{plan, step,
  retry}`. The sub-agent does not write into `usage-errors/`
  itself; the conductor does, after consuming the payload.

Both directories use the same JSON schema and failure categories
(`INCOMPLETE_WORK`, `MISSED_CONSUMER`, `TYPE_SAFETY`,
`SILENT_SCOPE_CUT`, `WRONG_PATTERN`, `MISSING_TEST`, `MISSING_I18N`,
`OTHER`). The `reviewer` field (`"codex"` or `"claude"`)
distinguishes direction. See `codex-dispatch` for the exact schema.

### Skill dispatch during execution

**Skills MUST be invoked via the Skill tool — not approximated from
memory.** When starting a step, check its `skill` field in plan.json.
If the field is not `"none"`, **call `Skill(skill: "<value>")` before
executing the step.** The skill provides execution guidance you cannot
replicate by hand.

| Step `skill` value | What happens |
|---|---|
| `look-before-you-leap:test-driven-development` | Follow red-green-refactor cycles. Each progress item is one phase (RED/GREEN/REFACTOR). |
| `look-before-you-leap:frontend-design` | Follow the design system, component patterns, and accessibility checklist. |
| `look-before-you-leap:svg-art` | Follow the composition principles, decision tree, and reference file routing. |
| `look-before-you-leap:immersive-frontend` | Follow the WebGL/GSAP/scroll-driven execution guidance. |
| `look-before-you-leap:react-native-mobile` | Follow the native-feel, gesture, and haptic patterns. |
| `look-before-you-leap:systematic-debugging` | Follow the four-phase investigation. No fixes without root cause confirmed. |
| `look-before-you-leap:refactoring` | Follow Phase 3 execution order. |
| `look-before-you-leap:webapp-testing` | Follow the decision tree, reconnaissance-then-action, Playwright MCP integration, and server lifecycle. |
| `look-before-you-leap:mcp-builder` | Follow the 4-phase MCP workflow (research, implement, review/test, evaluate). |
| `look-before-you-leap:doc-coauthoring` | Follow the 3-stage authoring workflow (context gathering, refinement, reader testing). |
| `"none"` | No skill dispatch — follow engineering-discipline directly. |

**The `skill` field is not decorative.** It exists so that
post-compaction Claude knows exactly which skill to invoke for each
step. If you skip the dispatch, you lose the specialized guidance
that makes the step succeed.

### Pre-step deliverables checklist

Before dispatching any step, extract every deliverable from its
`description` and `acceptanceCriteria` fields into a numbered
checklist. This is separate from progress items (which track
sub-tasks) — the deliverables checklist tracks *what the step must
produce*, not *how*.

The process:

1. Re-read the step's `description` word by word.
2. Re-read its `acceptanceCriteria` word by word.
3. List every concrete deliverable as a numbered item.
4. Write this checklist somewhere persistent (plan notes,
   discovery.md, or inline as you work).
5. **Before marking the step done**, walk through every item and
   verify it was implemented (using the receipt's per-criterion
   verdicts and the digester's bounded payload — NOT by re-reading
   the source files).

This prevents the failure mode where you focus on the primary
feature and forget secondary deliverables. The checklist is
mandatory for every step.

### Debugging during execution

When tests fail or unexpected behavior occurs mid-step, **invoke
`look-before-you-leap:systematic-debugging`** instead of guessing at
fixes. Follow its four phases (investigate → analyze → hypothesize
→ implement). Do not stack speculative fixes — find the root cause
first.

For Codex-owned steps, "investigation" means dispatching Codex to
debug (with a focused prompt), not opening source files inline.

### Refactoring tasks

For refactoring tasks, also follow the execution order from
`look-before-you-leap:refactoring` Phase 3 — it minimizes broken
intermediate states (e.g., create at new location first, then update
consumers, then delete old location). After all changes, its Phase 4
verifies against the contract and regenerates stale dep maps.

### Dispatching sub-agents

**The key mechanic**: to run N agents in parallel, emit all N tool
calls in a SINGLE message. Claude Code dispatches them concurrently.
If you send them one at a time across separate messages, they run
sequentially — defeating the purpose.

**Foreground parallel** (Claude Agent sub-agents):
Use for `claude-impl` steps in the parallel frontier. Each sub-agent
implements one step inside its own files; the conductor sees the
sub-agent's bounded summary and the verify receipt.

**Background** (`run_in_background: true`):
Use for Codex wrapper invocations (`run-codex-implement.sh`,
`run-codex-verify.sh`) and for `codex exec` calls during
discovery / consensus. The wrapper writes the receipt + sidecar to
disk; the conductor reads them after the wrapper exits.

#### Implementation sub-agents (parallel claude-impl execution)

When dispatching a claude-impl step to a sub-agent, the sub-agent
receives:

- The step definition from plan.json (id, description,
  acceptanceCriteria, files, skill, owner).
- The plan.json path for progress updates.
- The project root for running commands.

Each sub-agent must:

- Only edit files listed in its step's `files` array.
- Update its step's progress items via plan_utils.py.
- Run its step's skill if `skill` is not `"none"`.
- Run its own verification (tsc, lint, tests) before reporting.
- Report a bounded summary — do NOT mark the step done (the
  conductor does that after the verify receipt comes back PASS).

Each sub-agent must NOT:

- Edit files belonging to other steps.
- Mark the step as `done` (verification gate is the conductor's
  job).
- Read or modify other steps' progress items.
- Run Codex verification (the conductor handles this).

### Shared discovery (cross-agent communication)

For parallel tasks where agents benefit from seeing each other's
findings (audits, multi-area exploration), agents share a single
discovery file:

**Location**: `.temp/plan-mode/active/<plan-name>/discovery.md`

This file is created during Step 1 (Discovery). The
`inject-subagent-context` hook automatically tells sub-agents where
it is and registers their dispatch.

**Writing** — use heredoc append (`>>`), never `Edit`. Multiple
agents write concurrently, and append is atomic at the OS level. Use
a single-quoted heredoc delimiter (`'EOF'`) to prevent zsh glob
expansion of `**bold**` markdown patterns:

```bash
cat <<'EOF' >> discovery.md

## [your-focus-area]
- **[severity]** `file:line` — finding (evidence: ...)
EOF
```

**Reading** — read the file periodically to see other agents'
findings, but treat them as **informational context only**. Do NOT
change your investigation direction based on them. Only note a
cross-reference if you independently confirm a connection.

After all agents complete, the consolidated `discovery.md` is fed
into `lbyl-digest` (mode=co-exploration) — the conductor does not
read the raw consolidated file itself.

### Post-step simplification

When a completed step has `simplify: true` in plan.json, dispatch a
refactoring sub-agent (quick mode) after marking the step `done`:

1. **Run tests first** — establish a passing baseline.
2. **Dispatch** the `refactoring` sub-agent in quick mode (foreground
   Agent) with the step number and its `files` list and the active
   plan path.
3. **After the agent returns**, record its bounded simplification
   summary in the step's `result` field.
4. If the agent reverted changes due to test failures, note that.

The simplifier is opt-in per step. The `writing-plans` skill decides
which steps warrant it based on complexity (3+ files modified, new
abstractions, structural changes, or user request). Do not dispatch
it for steps without `simplify: true`.

### Post-step QA review

When a completed step has `qa: true` in plan.json, dispatch a
fresh-eyes QA sub-agent (Agent, foreground) after marking the step
`done`:

1. **Spawn a foreground sub-agent** with:
   - The step's `files` list and `acceptanceCriteria`.
   - NO prior context from the implementation.
   - Prompt: "Review these files against the acceptance criteria.
     Report any issues: missing functionality, inconsistencies,
     unclear code, broken patterns, accessibility problems."
2. **Read the agent's bounded report.** If it found issues, dispatch
   another sub-agent to fix them and re-verify.
3. **Record the QA outcome** in the step's `result` field — append
   QA findings to each relevant criterion's evidence.

QA dispatch is opt-in per step. Do not dispatch for steps without
`qa: true`.

### Codex verification gate (every step, no exceptions)

When a step has `codexVerify: true` (which writing-plans sets on
every step), the verification receipt is a **gate**. You MUST get a
PASS receipt **before** marking the step `done`. Codex runs on a
different model with its own `lbyl-verify` skill, providing truly
independent verification with fresh context.

**The receipt is the contract — not freeform text in the result
field.** The conductor reads `codex-receipt-step-N.json`'s
`finalVerdict` and per-criterion `criteria[].verdict`. For
codex-impl steps, the conductor also reads the digester's bounded
payload (which the digester wrote to
`codex-receipt-step-N.claude-review.json`). The conductor does NOT
read raw `.codex-result-step-N.txt`, JSONL streams, or `git diff`.

**No pre-existing exemptions.** If acceptance criteria say "tsc
passes" and tsc does not pass, fix the issue — regardless of whether
this step introduced the failure. "Pre-existing" is not a valid
dismissal.

**One step at a time.** Each step gets its own receipt. NEVER batch
multiple steps into a single Codex call.

**You MUST run `command -v codex` before claiming Codex is
unavailable.** The default assumption is that Codex IS installed. If
the check fails, THEN and only then may you skip verification and
note the skip in the result field's `### Verdict` section.

**Findings handling:**

When `finalVerdict == "FINDINGS"` or `claudeVerified == "FINDINGS"`:

1. Read the receipt's `findings[]` (and the
   `claude-review.json`'s findings, for codex-impl steps).
2. Codex's findings auto-log to `usage-errors/codex-findings/`. The
   conductor archives Claude's findings to
   `usage-errors/claude-findings/` after consuming the digester
   payload.
3. Do NOT dismiss a finding as "pre-existing," "out of scope," or
   "my interpretation is different." If you believe a finding is
   wrong, you have exactly two options:
   1. Quote the exact code path or plan text that proves it is
      wrong.
   2. Ask the user to approve a plan / acceptance-criteria change
      before continuing.
4. **Investigate before fixing.** Use the receipt's cited file
   ranges and the digester's payload — do NOT re-read source files
   inline. If patching, dispatch a Claude Agent (claude-impl steps)
   or re-dispatch Codex (codex-impl steps).
5. **Re-run verification after fixing.** Tsc passing is not the
   same as Codex confirming your fixes are correct.
6. **Test-parity rule**: When the receipt flags both code issues
   and MISSING_TEST in the same round, fix BOTH before re-verifying.
7. **Type-error escalation**: If the same finding CATEGORY appears
   in 2 consecutive reverify receipts (e.g., TYPE_SAFETY in both
   `step-N.json` and `step-N-reverify-1.json`), STOP ad-hoc
   fixing — invoke `look-before-you-leap:systematic-debugging`.

**THEN mark the step done** with a structured result using the
`### Criterion:` template. Map each acceptance criterion to evidence
(receipt's `criteria[].evidence`, file:line cited in the receipt,
command output reported by the digester), then add a `### Verdict`
section with the receipt-backed verdict (`Codex: PASS` for
claude-impl, `Claude: verified` for codex-impl). The verdict comes
from the receipt, not from your own assessment. See
`references/plan-schema.md` for the full template.

---

## Step 4: Verify (every time, no exceptions)

Step 4 is gated by Step 3's verification receipts — there is no
separate Verify phase that the conductor performs by hand.

For `claude-impl` steps: the verify receipt
(`codex-receipt-step-N.json`) is the contract. Read it. Gate on it.

For `codex-impl` steps: the digester's `claude-review.json` (sibling
receipt) plus its bounded payload is the contract. Read the payload.
Gate on it.

If a verification receipt fails (FAIL or persistent FINDINGS),
**invoke `look-before-you-leap:systematic-debugging`** — do not
guess at fixes. Follow its root cause investigation before
attempting corrections, and route any source-file reads through the
digester or a debug sub-agent.

Before declaring the plan done, re-read the user's original request
word by word. Confirm every requirement is implemented and working
(per the receipts). If anything is unaddressed, finish it or
explicitly flag it.

See `references/verification-commands.md` for framework-specific
commands. Always check the project's own scripts first (package.json,
Makefile). When dispatching sub-agents to run verification commands,
the sub-agent reports the command output as a bounded payload —
the conductor never tails build logs.

---

## Compaction Survival Protocol

Follow **persistent-plans Phase 3** (Resumption After Compaction).

After compaction, your FIRST action is to read the active plan from
disk. The conductor's allowed-reads list still applies: `plan.json`,
`progress.json`, signed receipts, HMAC sidecars, and digest outputs.
If you need a forbidden artifact's content, dispatch a
sub-agent — never read it inline.

Helper scripts:

```bash
bash .temp/plan-mode/scripts/plan-status.sh    # see all plan states
bash .temp/plan-mode/scripts/resume.sh         # find what to pick up
```

---

## Enforcement Hooks

Hooks enforce this discipline automatically. Key behaviors to know:

- **Blocked edits**: Code edits are blocked when no active plan
  exists, when `.handoff-pending` marker is set (Orbit review
  needed), or when `.verify-pending-N` marker is set (verification
  needed). Follow the process the hook describes — do not work
  around it.
- **Blocked grep**: When dep maps are configured, grepping for
  import/consumer patterns is blocked. Use `deps-query.py` instead.
- **Receipt enforcement**: The `verify-step-completion` hook
  validates the HMAC sidecar, the receipt's `artifactSha256`, and
  (for codex-impl) the sibling `claude-review.json`'s
  `receiptSha256` and `claudeVerified == "PASS"`. "Codex verifies
  Codex" is structurally impossible.
- **Checkpoint reminder**: After 5 code edits without updating
  progress, a reminder fires. Update via plan_utils.py immediately.
- **Plan completion guard**: Cannot move a plan to `completed/` if
  steps remain unfinished. Cannot stop if the active plan has
  unfinished steps.
- **Script warnings**: When `plan_utils.py` emits a warning (e.g.,
  "step marked done with no result"), treat it as an error. Stop and
  fix the issue before continuing.
- **Sub-agent injection**: Engineering discipline is automatically
  injected into every sub-agent prompt.
- **PostCompact resumption**: After context compaction, a dedicated
  hook detects the active plan and injects resumption context. Do
  NOT re-plan or re-explore — just read the plan and continue.

**NEVER bypass hooks.** If a hook blocks an action, follow the
process it describes. Do not use alternative tools to work around it.

---

## Plugin Error Logging

When you encounter an error **caused by this plugin** — a hook script
failing, `plan_utils.py` crashing, a schema validation error, a
script not found, or any unexpected behavior from plugin hooks or
scripts — document it immediately:

1. **Create a `.md` file** in `usage-errors/` at the **project root**
   with the naming convention `YYYY-MM-DD-<short-description>.md`.
2. **Include**:
   - What you were doing when the error occurred.
   - The hook/script/skill that errored.
   - The full error output.
   - Your best guess at the root cause.
3. **Then fix the issue before continuing.** If the error is in your
   command arguments (wrong step number, missing file), fix and
   retry. If the error is a genuine plugin bug (script crash on
   valid input), log it and continue — the bug is not yours to fix
   mid-task.
4. **When the error is fixed**, move the `.md` file to
   `usage-errors/resolved/`.

This applies only to errors originating from the plugin itself
(hooks, scripts, skills, plan infrastructure). Do NOT log errors
from the user's project code, build tools, or unrelated tooling.

Example filename: `2026-03-19-plan-utils-key-error.md`.

---

## Codex Lessons Pipeline

When Codex catches a behavioral pattern that the existing rules
should have prevented (e.g., "guessed API response shape" maps to
"Read API handlers before typing responses"), the lesson belongs in
the centralized pipeline — not in memory.

**Location**: `codex-lessons/` at the plugin repo root.

**Workflow**: After a session where Codex found genuine bugs,
analyze the root causes. If a bug reveals a gap in
engineering-discipline rules (a habit that would have prevented it),
write a proposal to `codex-lessons/proposals/`. During periodic
review, proposals are either promoted to plugin rules or discarded.

This is distinct from error logging (which tracks plugin bugs) and
memory (which tracks procedural preferences). The lessons pipeline
tracks **behavioral rule gaps** — patterns Codex keeps catching that
the rules should make impossible.

---

## Reference Files

All paths relative to `${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/`:

**Read during exploration:**

- `references/exploration-protocol.md` — 8-question checklist
  (answer ALL before planning).
- `references/plan-schema.md` — full plan.json schema (read when
  writing a plan).
- `references/codex-receipt-schema.md` — schema and trust chain for
  `codex-receipt-step-N.json` and the HMAC sidecar.

**Read when a step involves that discipline:**

- `references/testing-checklist.md`,
  `references/security-checklist.md`,
  `references/api-contracts-checklist.md`,
  `references/linting-checklist.md`,
  `references/dependency-checklist.md`,
  `references/git-checklist.md`.
- `references/ui-consistency-checklist.md`,
  `references/frontend-design-checklist.md`.

**Deep guides (read when you need deeper understanding):**

- `references/testing-strategy.md`, `references/security-guide.md`,
  `references/api-contracts-guide.md`,
  `references/dependency-mapping.md`.
- `references/debugging-root-cause-tracing.md`,
  `references/debugging-defense-in-depth.md`.

**Codex integration:**

- `references/routing-matrix.md` — task-type routing table for step
  ownership assignment.
- `references/scenario-playbook.md` — scenario ownership matrix
  (collab-split entries are legacy; treat them as decomposed
  step-level ownership).

**Scripts:**

- `scripts/init-plan-dir.sh` — initialize `.temp/plan-mode/`.
- `scripts/plan_utils.py` — read plan.json + progress.json, update
  progress, fetch the runnable frontier, complete steps with
  receipt validation.
- `scripts/deps-query.py` — query dep maps for consumers and blast
  radius.
- `scripts/deps-generate.py` — generate or regenerate dep maps.
- `scripts/run-codex-verify.sh` — direction-locked Codex
  verification (claude-impl steps).
- `scripts/run-codex-implement.sh` — direction-locked Codex
  implementation (codex-impl steps).
- `scripts/dep_partition.py` — partition target files into planning
  groups using dep maps.
- `scripts/write-discovery-receipt.sh` — sign the discovery receipt
  after Step 1.
