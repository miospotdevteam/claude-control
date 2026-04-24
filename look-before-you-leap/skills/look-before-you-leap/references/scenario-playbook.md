# Scenario Playbook

Concrete ownership decisions for every task type. Each scenario documents
the collaboration mode(s), what each agent does, and the verification
rules. Consumed by `writing-plans` (for step ownership assignment) and
`codex-dispatch` (for execution guidance).

**Conductor-mode + parallel-dispatch context**: every plan runs with
`conductorMode: true`, the main thread dispatches everything to subagents,
and the execution loop fans out the entire DAG frontier on each tick.
**Codex is the default implementer.** Mixed-ownership work is split into
two sequential single-owner steps with `dependsOn` — there is no
single-step mixed-ownership mode in the schema.

---

## Collaboration Modes

**Three valid modes**. Each plan step is assigned exactly one.

| Mode | Code | Description |
|---|---|---|
| Codex implements, Claude verifies | `codex-impl` | **Default under conductor mode.** Codex implements via `run-codex-implement.sh`; emits a structured receipt; a Claude verification subagent reads the receipt JSON and reports a bounded digest to the conductor. |
| Claude implements, Codex verifies | `claude-impl` | Opus subagent implements (or, under the in-thread threshold, the main thread). Codex verifies via `run-codex-verify.sh`; produces signed sidecar + evidence artifact. Reserved for steps whose `skill` is in the Claude-only set or that the RN Routing Directive sends to Claude. |
| Dual-pass (independent) | `dual-pass` | Both agents work independently, then Claude synthesizes. Used for security review and PR review only. |

The `owner` field in plan.json maps to these:
- `codex-impl` → `owner: "codex"`, Claude verifies after via receipt-reading subagent
- `claude-impl` → `owner: "claude"`, Codex verifies after via signed receipt
- `dual-pass` → both agents run, Claude synthesizes (special dispatch)

**Mixed-ownership work is NOT a mode.** When a feature spans both
Claude-suitable and Codex-suitable work, split it into two (or more)
sequential single-owner steps linked by `dependsOn`. The "Multi-step
worked example" sections below show how.

---

## In-thread vs. dispatched execution

Under conductor mode, the main thread dispatches every step to a
subagent. There is exactly one narrow exception:

**A `claude-impl` step MAY run inside the main thread iff BOTH:**
1. the step's `files` array has **≤1 file**, AND
2. the step's `skill` is one of `{brainstorming, writing-plans,
   doc-coauthoring}`.

Examples:

- "Update README.md security section" — 1 file, `doc-coauthoring`,
  fits the threshold → may run in-thread.
- "Add API authentication docs (5 files)" — 5 files → must dispatch
  to an Opus subagent.
- "Build new dashboard component" — `frontend-design` skill (not in
  the in-thread skill set) → must dispatch to an Opus subagent.
- Any `codex-impl` step → always dispatched via
  `run-codex-implement.sh`.

The main thread reads only structured receipts/digests from subagents;
it never reads raw `.codex-result-step-N.txt`, raw consensus markdown,
or raw `git diff` output. Those reads are delegated to digest
subagents (`lbyl-digest`).

---

## Parallel-dispatch worked example

The conductor's execution loop calls `runnable-steps` (NOT `next-step`)
and dispatches the entire DAG frontier concurrently:

```
DAG:
  Step 1 (codex-impl, files [src/types/user.ts]):                  dependsOn []
  Step 2 (codex-impl, files [src/db/users.ts]):                    dependsOn [1]
  Step 3 (codex-impl, files [src/db/audit.ts]):                    dependsOn []
  Step 4 (codex-impl, files [tests/db/users.test.ts]):             dependsOn [2]
  Step 5 (claude-impl, files [src/app/profile/page.tsx]):          dependsOn [2]
  Step 6 (codex-impl, files [src/lib/audit.ts]):                   dependsOn [3]

Tick 1: runnable = [1, 3]            → dispatch BOTH in parallel
Tick 2: 1 done, 3 done → runnable = [2, 6]   → dispatch BOTH in parallel
Tick 3: 2 done → runnable = [4, 5]   → dispatch BOTH in parallel
Tick 4: all done.
```

On each tick the conductor sends ONE message containing multiple
dispatches (multiple Bash calls + multiple Skill calls). Sequential
"dispatch step N, wait, dispatch step N+1" is an anti-pattern that
serializes work the DAG already declared independent.

**Wrapper-modification serialization** is the only exception. A step
that edits `run-codex-implement.sh` / `run-codex-verify.sh` (or any hook
lib those wrappers source) MUST be dispatched ALONE — never alongside
other dispatches that use those scripts. See the `codex-dispatch` skill
("Parallel Step Execution") for the full rule.

---

## Scenario Matrix

### Backend / API

| # | Scenario | Mode(s) | Claude Does | Codex Does |
|---|---|---|---|---|
| 1 | New API endpoint (CRUD) | `codex-impl` | Verifies via receipt-reading subagent | Implements endpoint (route, handler, types, validation). Gets TDD skill if applicable. |
| 2 | API route with external integration | `claude-impl` (design) → `codex-impl` (impl), with `dependsOn` | Step A: design external API surface (`doc-coauthoring`). | Step B: implement internal services + DB models + types (depends on Step A). |

### Frontend / UI

| # | Scenario | Mode(s) | Claude Does | Codex Does |
|---|---|---|---|---|
| 3 | Dashboard with charts | sequential: `claude-impl` (shell) + `codex-impl` (hooks) + `claude-impl` (wire) | Step A: layout shell (`frontend-design`). Step C: wire charts to hooks (depends on A and B). | Step B: data hooks (TDD). |
| 4 | Landing page (creative) | `claude-impl` | Brainstorms, designs, implements full page (`frontend-design`). Dispatched to Opus subagent. | Verifies via signed receipt — code quality, accessibility, performance. |
| 5 | Design system update (tokens) | sequential: `claude-impl` (tokens + primitives) + `codex-impl` (sweep) | Step A: design tokens, implement core primitives + reference components (`frontend-design`). | Step B: sweep all remaining components to use new tokens (depends on A). |
| 6 | Dark mode | sequential: `claude-impl` (theme) + `codex-impl` (sweep) | Step A: design theme system, implement ThemeProvider + core components (`frontend-design`). | Step B: sweep all components to use theme tokens (depends on A). |

### Refactoring / Migration

| # | Scenario | Mode(s) | Claude Does | Codex Does |
|---|---|---|---|---|
| 7 | Large rename across codebase | `codex-impl` | Verifies via receipt-reading subagent | Explores, builds refactoring contract (targets, consumers, tests), executes mechanical rename. Gets `refactoring` skill. |
| 8 | Framework migration (Express→Hono) | optional `claude-impl` (strategy doc) → `codex-impl` (execution) | Step A (optional): strategy doc (`doc-coauthoring`). | Step B: executes migration steps (depends on A if present). |
| 9 | Dependency upgrade (React 18→19) | optional `claude-impl` (breaking-changes doc) → `codex-impl` (migration) | Step A (optional): breaking-changes notes (`doc-coauthoring`). | Step B: executes migration. |
| 10 | i18n string extraction sweep | optional `claude-impl` (convention) → `codex-impl` (sweep) | Step A (optional): define key naming convention (`doc-coauthoring`). | Step B: extract all strings into translation keys across all files (depends on A if present). |

### Bug Fixing / Debugging

| # | Scenario | Mode(s) | Claude Does | Codex Does |
|---|---|---|---|---|
| 11 | Failing test / CI failure | `codex-impl` | Verifies via receipt-reading subagent | Investigates root cause (`systematic-debugging`), implements fix. |
| 12 | Performance optimization | `codex-impl` (investigation), then dynamic routing for fix steps | Verifies fixes; for frontend fix steps reassigned post-investigation, an Opus subagent (`frontend-design`) implements. | Investigation step is `codex-impl`. Backend fix steps remain `codex-impl`; frontend fix steps reassigned to `claude-impl` per Dynamic Routing. |

### Security

| # | Scenario | Mode(s) | Claude Does | Codex Does |
|---|---|---|---|---|
| 13 | Security review / audit | `dual-pass` | Reviews design-level issues (auth flow, permission model, data exposure) | Reviews implementation-level issues (OWASP, injection, validation, secrets) |
| 14 | Security-sensitive design | `claude-impl` (design) → `codex-impl` (impl) | Step A: design auth architecture, permission model (`brainstorming` or `doc-coauthoring`). | Step B: implement (depends on A); challenge pass = adversarial verification via signed receipt. |

### Infrastructure / DevOps

| # | Scenario | Mode(s) | Claude Does | Codex Does |
|---|---|---|---|---|
| 15 | CI/CD pipeline setup | `codex-impl` | Verifies via receipt-reading subagent | Designs and implements full pipeline (YAML, scripts, caching). |

### Review / Verification

| # | Scenario | Mode(s) | Claude Does | Codex Does |
|---|---|---|---|---|
| 16 | PR review | `dual-pass` | Reviews design/architecture/UX, synthesizes findings | Adversarial review: correctness, security, edge cases, test coverage |
| 17 | Post-step verification | (not a step mode) | Reads structured receipts via `lbyl-digest` subagent | `run-codex-verify.sh` for `claude-impl` steps; `run-codex-implement.sh` emits implement receipts that a Claude verification subagent reads |

### Documentation

| # | Scenario | Mode(s) | Claude Does | Codex Does |
|---|---|---|---|---|
| 18 | API documentation | `claude-impl` | Writes docs (`doc-coauthoring`). May run in-thread if ≤1 file; otherwise dispatched to Opus subagent. | Verifies technical accuracy via signed receipt (code examples work, signatures match). |

### Complex / Mixed-Domain (always sequential, never single-step)

| # | Scenario | Mode(s) | Claude Does | Codex Does |
|---|---|---|---|---|
| 19 | Real-time collaborative editing | `claude-impl` (architecture) → `codex-impl` (backend) → `claude-impl` (frontend) | Step A: architecture (`brainstorming`). Step C: cursor UI, presence (`frontend-design`). | Step B: WebSocket, CRDT, Redis (depends on A). Step C depends on B. |
| 20 | Stripe integration | `claude-impl` (API surface) → `codex-impl` (services) → `claude-impl` (UI) | Step A: external API surface design (`doc-coauthoring`). Step C: webhooks/checkout UI (`frontend-design`). | Step B: internal service layer, DB models, types (depends on A). Step C depends on B. |

### Additional Mixed-Domain

| # | Scenario | Mode(s) | Claude Does | Codex Does |
|---|---|---|---|---|
| 21 | Plugin / MCP development | `claude-impl` (skills/MCP design) → `codex-impl` (hooks/scripts/manifest) | Step A: skills + MCP server (`mcp-builder` or `doc-coauthoring`). | Step B: hooks, scripts, manifest (depends on A). |
| 22 | Test writing | `codex-impl` | Verifies tests are meaningful and cover all cases via receipt-reading subagent | Writes tests. Gets TDD skill injected into prompt. |
| 23 | Vague request ("make it better") | `claude-impl` (clarify) → normal routing | Step A: clarifies requirements with user, shapes into concrete task (`brainstorming`/`doc-coauthoring`). | Subsequent steps assigned normally — most will land on `codex-impl`. |

### React Native (mobile)

`react-native-mobile` is the only skill that is conditional. The
**Routing Directive** in
`look-before-you-leap/skills/react-native-mobile/SKILL.md` (and the
parallel directive in
`look-before-you-leap/codex-skills/react-native-mobile/SKILL.md`) is the
source of truth:

- **UI/UX (animations, haptics, gestures, visual polish) → claude.**
- **Code-heavy (data flow, networking, native modules, non-visual logic) → codex.**

| # | Scenario | Mode | Owner | Notes |
|---|---|---|---|---|
| 24 | RN bottom-sheet animation polish | `claude-impl` | claude | UI/UX per RN Routing Directive |
| 25 | RN list virtualization (FlashList) | `codex-impl` | codex | Code-heavy per RN Routing Directive |
| 26 | RN haptic feedback integration | `claude-impl` | claude | UI/UX per RN Routing Directive |
| 27 | RN networking layer + retry logic | `codex-impl` | codex | Code-heavy per RN Routing Directive |
| 28 | RN gesture taste + native module wiring | sequential: `claude-impl` (gesture) → `codex-impl` (wiring), `dependsOn` | both | Split per RN Routing Directive — never one mixed step |

---

## Phase-Level Ownership

These apply regardless of step-level ownership:

| Phase | Owner | Codex Role | Notes |
|---|---|---|---|
| Intent capture (vague ask) | Claude | Codex verifies after | Codex enters only after requirements are concrete |
| Brainstorming | Claude | Co-explores codebase, reviews `design.md` | Codex explores consumers/blast-radius in parallel, reviews design before planning |
| Discovery | Claude + Codex | Co-exploration partner | Both explore in parallel (Phase 1), then converge (Phase 2). Main thread reads only digested results from `lbyl-digest`. |
| Plan writing | Claude | Consensus partner | Multi-round debate (max 3 rounds) until both agree or escalate to user. Main thread reads only digested consensus output. |
| Plan review (Orbit) | User | N/A | User approves via Orbit |
| Execution | Per-step (dispatched) | Per-step | Based on `step.owner` and `step.mode`; main thread is the conductor and reads only receipts/digests. |
| Final summary | Claude | None | Claude always owns user communication |

---

## Dynamic Routing

Some scenarios don't know the correct owner at plan time:

- **Performance optimization** (scenario 12): Codex investigates first
  (`codex-impl`). Based on findings, fix steps are assigned: backend →
  `codex-impl`, frontend → `claude-impl`. The plan may need
  mid-execution adjustment.
- **Vague requests** (scenario 23): Claude clarifies first
  (`claude-impl`). Once concrete, steps are assigned normally — most
  will land on `codex-impl`.

For these, the `writing-plans` skill creates an investigation /
clarification step (always `owner: codex` for performance, `owner:
claude` for vague) followed by placeholder steps that get their `owner`
assigned after investigation completes. The placeholders carry
`dependsOn` edges back to the investigation step so the parallel
dispatcher correctly waits.

---

## Skill Injection Rules

When `owner: "codex"`, the step's `skill` field determines what guidance
Codex receives in its `developer-instructions`:

| Step skill | Codex gets |
|---|---|
| `look-before-you-leap:test-driven-development` | TDD: RED-GREEN-REFACTOR cycles |
| `look-before-you-leap:refactoring` | Refactoring contract + execution order |
| `look-before-you-leap:systematic-debugging` | Four-phase investigation |
| `look-before-you-leap:webapp-testing` | Playwright/E2E testing guidance |
| `look-before-you-leap:mcp-builder` | MCP server development |
| `"none"` | Engineering-discipline only |

Skills that stay Claude-only (never injected into Codex):
- `frontend-design` — visual taste
- `svg-art` — creative direction
- `immersive-frontend` — experiential judgment
- `brainstorming` — Claude leads dialogue, Codex co-explores and reviews
- `writing-plans` — Claude leads, Codex participates in plan consensus
- `doc-coauthoring` — Claude writes, Codex verifies accuracy

`react-native-mobile` is dual-installable — both Claude and Codex have
their own copies, and routing per step follows the RN Routing
Directive above.

`lbyl-digest` is internal-only — dispatched by the conductor for
digesting raw Codex output, consensus rounds, and verification
receipts. It MUST NOT appear as a step `skill` value.

---

## Verification Rules

| Step owner | Who verifies | Verification depth |
|---|---|---|
| `claude` | Codex (signed receipt via `run-codex-verify.sh`) | Reads files, runs tsc/lint/tests, checks consumers, emits structured evidence artifact + HMAC sidecar |
| `codex` | Claude verification subagent (reads structured receipt from `run-codex-implement.sh`) | Subagent reads `<plan-dir>/codex-receipt-step-N.json`, runs tsc/lint/tests, checks consumers via `deps-query`, returns bounded digest |
| `dual-pass` | Both independently | Claude: design/UX. Codex: correctness/security. Claude synthesizes from digested outputs. |

**Receipt-first verification**: under conductor mode, the main thread
NEVER reads raw `.codex-result-step-N.txt`, raw `git diff` output, or
raw consensus markdown. All raw artifacts are digested by subagents
(`lbyl-digest`); only the bounded digest reaches the main thread.

**Symmetric verification**: same rigor in both directions. Neither
agent's work ships without the other's review.

**Symmetric error logging**:
- Codex logs Claude's mistakes → `usage-errors/codex-findings/`
- Claude logs Codex's mistakes → `usage-errors/claude-findings/`
- Same JSON schema for both directions

---

## Receipt-first verification (full pipeline)

Both directions of verification produce structured artifacts the main
thread reads via digest subagents:

- **`codex-impl` step**: `run-codex-implement.sh` writes the implement
  evidence artifact at `<plan-dir>/codex-receipt-step-N.json` plus an
  HMAC-signed sidecar receipt under
  `~/.claude/look-before-you-leap/state/<projectId>/<planId>/`. A Claude
  verification subagent reads the receipt JSON (NOT the raw
  `.codex-result-step-N.txt`) and reports a bounded digest to the
  conductor.
- **`claude-impl` step**: `run-codex-verify.sh` writes the verify
  evidence artifact + signed sidecar with the same dual-authority
  binding. The conductor reads the receipt; raw Codex prose is not
  read by the main thread.

See `look-before-you-leap/references/codex-receipt-schema.md` for the
authoritative receipt format.

---

## Machine defaults — never downgrade

Default models are configured at the machine level — Claude Code = Opus
4.7 high; Codex = gpt-5.5 high fast. Dispatch scripts and skill prompts
MUST NOT pass `--model` flags that downgrade these defaults. Plan steps
MUST NOT include such flags. See
`look-before-you-leap/references/machine-defaults.md` for the full
no-downgrade rule and verification commands.
