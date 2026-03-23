# Routing Matrix

Canonical task-type routing table for assigning `owner` and `mode` to each
plan step. Consumed by the `writing-plans` skill during plan creation and
by the `codex-dispatch` skill during execution.

---

## How to Use This Table

When creating a plan, classify each step by its **task category** (left
column). The table gives the default `owner`, `mode`, and conditions under
which the default should be overridden. Steps may span multiple categories
— use the category that best describes the step's *primary* work.

---

## Task-Type Routing Table

| Task Category | Default Owner | Default Mode | Override Conditions |
|---|---|---|---|
| **Frontend UI / visual design / UX polish** | `claude` | `claude-impl` | — |
| **Product copy / UX text / content** | `claude` | `claude-impl` | — |
| **Creative / landing page / marketing** | `claude` | `claude-impl` | — |
| **Brainstorming / requirements shaping** | `claude` | `claude-impl` | Codex co-explores codebase in parallel and reviews design.md before writing-plans |
| **Documentation / API docs / specs** | `claude` | `claude-impl` | Codex verifies technical accuracy |
| **MCP / DB / API / external integration** | `claude` | `claude-impl` | If internal service layer is separable, use `collab-split` (Claude: external-facing, Codex: internal services) |
| **Cross-domain integration** | varies | `collab-split` | Claude: external-facing / frontend. Codex: internal services / backend. |
| **Backend from clear spec (CRUD, services)** | `codex` | `codex-impl` | `claude` if external-tool reasoning needed |
| **API route / service implementation** | `codex` | `codex-impl` | `claude` if MCP/DB/external integration |
| **Refactor across many files** | `codex` | `codex-impl` | Claude reviews integration impact |
| **Framework / library migration** | varies | `collab-split` | Both discuss strategy first; Codex executes |
| **Dependency upgrade** | varies | `collab-split` | Both discuss breaking changes; Codex executes |
| **i18n string extraction sweep** | `codex` | `codex-impl` | Claude defines convention, Codex sweeps |
| **Bug investigation / root cause analysis** | `codex` | `codex-impl` | `claude` if external tools or product context needed |
| **Failing test / CI failure** | `codex` | `codex-impl` | — |
| **Performance optimization** | `codex` | `codex-impl` | Investigation step is `codex-impl`. Fix steps are assigned after: backend → `codex-impl`, frontend → `claude-impl`. See Dynamic Routing. |
| **Security review / audit** | both | `dual-pass` | Claude: design-level. Codex: implementation-level |
| **Security-sensitive design** | `claude` | `claude-impl` | Codex does adversarial challenge pass |
| **CI/CD pipeline setup** | `codex` | `codex-impl` | — |
| **Test writing** | `codex` | `codex-impl` | Gets TDD skill injected |
| **PR review** | both | `dual-pass` | Claude: design/architecture. Codex: correctness/security |
| **Post-step verification** | `codex` | `codex-impl` | This IS Codex's verification role |
| **Design system update (tokens)** | varies | `collab-split` | Claude designs + core primitives; Codex sweeps components |
| **Dark mode / theming** | varies | `collab-split` | Claude designs theme system; Codex sweeps components |
| **Dashboard with charts** | varies | `collab-split` | Claude: UI/layout. Codex: data hooks/API integration |
| **Real-time / collaborative features** | varies | `collab-split` | Both design architecture. Claude: frontend. Codex: backend |
| **Stripe / payment integration** | varies | `collab-split` | Claude: external API. Codex: internal services |
| **Plugin / MCP development** | varies | `collab-split` | Claude: skills + MCP. Codex: hooks + scripts + manifest |
| **Vague / ambiguous request** | `claude` | `claude-impl` | Clarification step is `claude-impl`. Once concrete, subsequent steps are assigned normally via the routing matrix. See Dynamic Routing. |

---

## Hard Boundaries

These rules override the table above:

1. **Claude owns ambiguity.** Codex does not interpret product intent,
   clarify vague requirements, or make UX decisions. If a step requires
   user interaction or creative judgment, it stays with Claude.

2. **One implementation slice gets one builder.** A single step is not
   split between Claude and Codex at execution time (except `collab-split`
   which explicitly creates sub-steps with mixed ownership).

3. **Claude-only skills are never injected into Codex.** These skills
   require visual taste or user interaction that Codex cannot provide:
   `frontend-design`, `svg-art`, `immersive-frontend`, `react-native-mobile`,
   `brainstorming`, `writing-plans`, `doc-coauthoring`.

4. **Default owner is `claude`.** When no category matches or the task is
   unclear, the step defaults to `owner: "claude"`, `mode: "claude-impl"`.
   Codex ownership is opt-in based on matching routing criteria.

5. **User can override any assignment.** During Orbit plan review, the user
   may change any step's `owner` and `mode`. The routing matrix provides
   defaults, not mandates.

---

## Dynamic Routing

Some steps cannot determine their owner at plan time:

| Pattern | How It Works |
|---|---|
| **Performance optimization** | Codex investigates bottlenecks first. Based on findings, fix steps are assigned: backend → Codex, frontend → Claude. |
| **Vague requests** | Claude clarifies with user first (`claude-impl`). Once requirements are concrete, steps are assigned normally. |
| **collab-split design phase** | Collaborative discussion may reveal the split should differ from initial assumption. |

For these, `writing-plans` creates an investigation step (owner determined
by the pattern above) followed by placeholder steps whose `owner` field
is set to `"claude"` (safe default) with a note that ownership will be
reassigned after investigation completes.

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

Skills that stay Claude-only (never injected):
- `frontend-design` — visual taste
- `svg-art` — creative direction
- `immersive-frontend` — experiential judgment
- `react-native-mobile` — native-feel taste
- `brainstorming` — Claude leads dialogue, Codex co-explores and reviews
- `writing-plans` — Claude leads, Codex participates in plan consensus
- `doc-coauthoring` — Claude writes, Codex verifies accuracy
