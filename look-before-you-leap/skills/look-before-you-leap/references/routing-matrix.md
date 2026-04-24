# Routing Matrix

Canonical task-type routing table for assigning `owner` and `mode` to each
plan step. Consumed by the `writing-plans` skill during plan creation and
by the `codex-dispatch` skill during execution.

**Conductor-mode default**: every plan runs with `conductorMode: true` at
the plan level. The main Claude thread does not write code directly — it
dispatches every step to a subagent (Opus for `claude-impl`, Codex for
`codex-impl`) and reads only structured receipts/digests. **Codex is the
default implementer.** Claude-impl is the narrow exception, gated on the
Claude-only skill list (or the RN-mobile Routing Directive).

---

## How to Use This Table

When creating a plan, classify each step by its **task category** (left
column). The table gives the default `owner`, `mode`, and conditions under
which the default should be overridden. Steps may span multiple categories
— use the category that best describes the step's *primary* work.

If a step would naturally span both Claude-suitable and Codex-suitable
work (mixed ownership), **split it into two sequential steps with
`dependsOn`**. The plan schema does not support per-step mixed
ownership: every step has exactly one `owner` and one `mode`.

---

## Task-Type Routing Table

| Task Category | Default Owner | Default Mode | Override Conditions |
|---|---|---|---|
| **Frontend UI / visual design / UX polish** | `claude` | `claude-impl` | Skill must be in Claude-only set (`frontend-design`, `svg-art`, `immersive-frontend`). |
| **Product copy / UX text / content** | `claude` | `claude-impl` | Skill `doc-coauthoring`. |
| **Creative / landing page / marketing** | `claude` | `claude-impl` | Skill `frontend-design` / `immersive-frontend` / `svg-art`. |
| **Brainstorming / requirements shaping** | `claude` | `claude-impl` | Skill `brainstorming`. Codex co-explores in parallel and reviews `design.md` before `writing-plans`. |
| **Plan writing** | `claude` | `claude-impl` | Skill `writing-plans`. Codex participates in plan consensus. |
| **Documentation / API docs / specs** | `claude` | `claude-impl` | Skill `doc-coauthoring`. Codex verifies technical accuracy via receipt. |
| **MCP / DB / API / external integration** | `codex` | `codex-impl` | If the step is purely external-facing design (no code), it may be `claude-impl` with explicit justification. Otherwise split into design step (`claude-impl`, `doc-coauthoring`) and impl step (`codex-impl`) with `dependsOn`. |
| **Cross-domain integration** | `codex` | `codex-impl` | Split mixed work into sequential steps: design (`claude-impl`) → backend impl (`codex-impl`) → frontend impl (`claude-impl`) with `dependsOn`. |
| **Backend from clear spec (CRUD, services)** | `codex` | `codex-impl` | — |
| **API route / service implementation** | `codex` | `codex-impl` | — |
| **Refactor across many files** | `codex` | `codex-impl` | Claude reviews integration impact via verification subagent. |
| **Framework / library migration** | `codex` | `codex-impl` | Add a leading design step (`claude-impl`, `doc-coauthoring`) with `dependsOn` if strategy needs human framing. |
| **Dependency upgrade** | `codex` | `codex-impl` | Same as migration: optional leading design step for breaking-change discussion. |
| **i18n string extraction sweep** | `codex` | `codex-impl` | Add a leading convention-defining step (`claude-impl`) with `dependsOn` if convention is ambiguous. |
| **Bug investigation / root cause analysis** | `codex` | `codex-impl` | Skill `systematic-debugging`. |
| **Failing test / CI failure** | `codex` | `codex-impl` | Skill `systematic-debugging`. |
| **Performance optimization** | `codex` | `codex-impl` | Investigation step is `codex-impl`. Fix steps assigned after via Dynamic Routing: backend → `codex-impl`, frontend → `claude-impl`. |
| **Security review / audit** | both | `dual-pass` | Claude: design-level. Codex: implementation-level. Both passes independent. |
| **Security-sensitive design** | `claude` | `claude-impl` | Skill `brainstorming` / `doc-coauthoring`. Codex does adversarial challenge pass via verification receipt. |
| **CI/CD pipeline setup** | `codex` | `codex-impl` | — |
| **Test writing** | `codex` | `codex-impl` | Gets TDD skill injected. |
| **PR review** | both | `dual-pass` | Claude: design/architecture. Codex: correctness/security. |
| **Post-step verification** | `codex` | (verification dispatch — not a step mode) | Codex's verification of `claude-impl` runs via `run-codex-verify.sh` and emits a signed receipt. Verification is structural, not a step. |
| **Design system update (tokens)** | varies | sequential | Step A: design tokens + core primitives (`claude-impl`, `frontend-design`). Step B: sweep components to use tokens (`codex-impl`, `dependsOn: [A]`). |
| **Dark mode / theming** | varies | sequential | Step A: theme system + ThemeProvider (`claude-impl`, `frontend-design`). Step B: sweep components (`codex-impl`, `dependsOn: [A]`). |
| **Dashboard with charts** | varies | sequential | Step A: layout shell (`claude-impl`, `frontend-design`). Step B: data hooks (`codex-impl`, TDD). Step C: wire charts (`claude-impl`, `dependsOn: [A, B]`). |
| **Real-time / collaborative features** | varies | sequential | Step A: architecture decision (`claude-impl`, `brainstorming`). Step B: backend (`codex-impl`). Step C: frontend (`claude-impl`, `frontend-design`). `dependsOn` chain or fan-in as appropriate. |
| **Stripe / payment integration** | varies | sequential | Step A: external API surface design (`claude-impl`, `doc-coauthoring`). Step B: internal services + DB models (`codex-impl`, `dependsOn: [A]`). Step C: webhooks/checkout UI (`claude-impl`, `dependsOn: [B]`). |
| **Plugin / MCP development** | varies | sequential | Step A: skills + MCP surface (`claude-impl`, `mcp-builder` or `doc-coauthoring`). Step B: hooks + scripts + manifest (`codex-impl`, `dependsOn: [A]`). |
| **React Native (mobile) UI/UX** | `claude` | `claude-impl` | Skill `react-native-mobile`, **conditional** per the RN Routing Directive (see RN section below). |
| **React Native (mobile) code-heavy** | `codex` | `codex-impl` | Skill `react-native-mobile`, **conditional** per the RN Routing Directive (see RN section below). |
| **Vague / ambiguous request** | `claude` | `claude-impl` | Clarification step is `claude-impl`. Once concrete, subsequent steps assigned normally via this table — most will land on `codex-impl`. |
| **Anything not above (config, glue, wiring, mechanical work)** | `codex` | `codex-impl` | Codex default. |

---

## Hard Boundaries

These rules override the table above:

1. **Codex is the default implementer.** Under conductor mode, every step
   is presumed `codex-impl` unless one of three conditions holds: (a) the
   step's `skill` is in the Claude-only set below, (b) the RN-mobile
   Routing Directive sends it to Claude, or (c) a documented routing-matrix
   override applies (e.g., security-sensitive design, MCP/external-tool
   reasoning). Claude-impl steps without a written `routingJustification`
   citing one of these reasons are a planning bug.

2. **Claude-only skill set (exact, exhaustive — six skills).** A step's
   `skill` field forces `owner: "claude"` if and only if the skill is one
   of EXACTLY:

   ```
   frontend-design, svg-art, immersive-frontend,
   brainstorming, writing-plans, doc-coauthoring
   ```

   `react-native-mobile` is NOT in this set — it is conditional (see RN
   section). `lbyl-digest` is internal-only and MUST NOT appear as a
   step `skill`.

3. **One step has one owner.** Mixed-ownership work is split into two
   sequential single-owner steps linked by `dependsOn`. The plan schema
   does not support per-file or per-group ownership; each step carries
   exactly one `owner` and one `mode`.

4. **Conductor mode is the default.** The main thread dispatches every
   step to a subagent and reads only structured receipts/digests. No
   raw artifact reads from the main thread.

5. **Parallel dispatch is the default.** The conductor's execution loop
   uses `runnable-steps` and dispatches the entire DAG frontier
   concurrently on every tick. Sequencing is expressed via `dependsOn`,
   not via main-thread serialization.

6. **In-thread `claude-impl` threshold (the only exception to dispatch).**
   A `claude-impl` step MAY run inside the main thread iff BOTH:
   - the step's `files` array has **≤1 file**, AND
   - the step's `skill` is one of `{brainstorming, writing-plans,
     doc-coauthoring}`.

   Every other `claude-impl` step dispatches to an Opus subagent.
   Every `codex-impl` step dispatches via `run-codex-implement.sh`.

7. **User can override any assignment.** During Orbit plan review, the
   user may change any step's `owner` and `mode`. The routing matrix
   provides defaults, not mandates.

8. **Wrapper-modification serialization.** A step that edits
   `run-codex-implement.sh`, `run-codex-verify.sh`, or any other
   actively-used dispatch script (or a hook lib those wrappers source)
   MUST be dispatched ALONE — never in a parallel batch alongside other
   dispatches that use those scripts. This rule is enforced by the
   `codex-dispatch` skill ("Parallel Step Execution" section).

---

## RN-mobile conditional routing

`react-native-mobile` is the only skill that is neither Claude-only nor
Codex-default. Apply this rule whenever a step's `skill` is
`react-native-mobile`:

- **UI/UX (animations, haptics, gestures, visual polish) → claude.**
- **Code-heavy (data flow, networking, native modules, non-visual logic) → codex.**

The Routing Directive section in
`look-before-you-leap/skills/react-native-mobile/SKILL.md` is the source
of truth for the Claude-side breakdown; the same wording lives in
`look-before-you-leap/codex-skills/react-native-mobile/SKILL.md` so Codex
sees the same routing rule. If a step blends both kinds of work, split
it into two sequential steps with `dependsOn` rather than forcing a
single owner.

`routingJustification` examples:
- `"react-native-mobile UI/UX per Routing Directive → claude-impl"`
- `"react-native-mobile code-heavy per Routing Directive → codex-impl"`

---

## Dynamic Routing

Some steps cannot determine their owner at plan time:

| Pattern | How It Works |
|---|---|
| **Performance optimization** | Codex investigates bottlenecks first (`codex-impl`). Based on findings, fix steps are assigned: backend → `codex-impl`, frontend → `claude-impl`. |
| **Vague requests** | Claude clarifies with user first (`claude-impl`, `brainstorming` or `doc-coauthoring`). Once requirements are concrete, subsequent steps are assigned normally — most will land on `codex-impl`. |

For these, `writing-plans` creates an investigation/clarification step
and follows it with placeholder steps whose `owner` is reassigned after
that step completes. The placeholders carry `dependsOn` edges back to
the investigation step.

---

## Skill Injection Rules

When `owner: "codex"`, the step's `skill` field determines what guidance
Codex receives in its developer-instructions:

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
their own copies, and routing per step follows the Routing Directive
above.

`lbyl-digest` is internal to the conductor (used for digesting raw
Codex output and consensus rounds for the main thread); it is not a
plan-routable skill and must not appear in any step's `skill` field.

---

## Receipt-first verification

Verification is no longer a free-form text exchange. Both directions of
verification produce structured artifacts the main thread reads via
digest subagents:

- **`codex-impl` step**: `run-codex-implement.sh` writes the implement
  evidence artifact at `<plan-dir>/codex-receipt-step-N.json` and an
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
authoritative receipt format and dual-authority verification semantics.

---

## Machine defaults — never downgrade

Default models are configured at the machine level — Claude Code = Opus
4.7 high; Codex = gpt-5.5 high fast. Dispatch scripts and skill prompts
MUST NOT pass `--model` flags that downgrade these defaults.
`run-codex-implement.sh` and `run-codex-verify.sh` already invoke
`codex exec` without a `-m`/`--model` flag; do not add one. See
`look-before-you-leap/references/machine-defaults.md` for the full
no-downgrade rule and verification commands.
