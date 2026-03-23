# Scenario Playbook

Concrete ownership decisions for every task type. Each scenario documents
the collaboration mode, what each agent does, and the verification rules.
Consumed by `writing-plans` (for step ownership assignment) and
`codex-dispatch` (for execution guidance).

---

## Collaboration Modes

Four distinct modes. Each plan step is assigned one mode (not just an owner).

| Mode | Code | Description |
|---|---|---|
| Claude implements, Codex verifies | `claude-impl` | Claude implements, Codex does verification pass. Default mode. |
| Codex implements, Claude verifies | `codex-impl` | Codex implements, Claude does full verification pass. |
| Collaborative design, split execution | `collab-split` | Both discuss the approach, then execution splits by domain/layer. |
| Dual-pass (independent) | `dual-pass` | Both agents work independently, then Claude synthesizes findings. |

The `owner` field in plan.json maps to these:
- `claude-impl` → `owner: "claude"`, Codex verifies after
- `codex-impl` → `owner: "codex"`, Claude verifies after
- `collab-split` → step is split into sub-steps with mixed ownership
- `dual-pass` → both agents run, Claude synthesizes (special dispatch)

---

## Scenario Matrix

### Backend / API

| # | Scenario | Mode | Claude Does | Codex Does |
|---|---|---|---|---|
| 1 | New API endpoint (CRUD) | `codex-impl` | Discovers, plans (clarifies fields/auth/validation with user) | Implements endpoint (route, handler, types, validation). Gets TDD skill if applicable. |
| 2 | API route with external integration | `collab-split` | Designs integration + implements external-facing parts | Implements internal service layer, types, DB models |

### Frontend / UI

| # | Scenario | Mode | Claude Does | Codex Does |
|---|---|---|---|---|
| 3 | Dashboard with charts | `collab-split` | Implements UI components, layout, visual design | Implements data-fetching hooks/utilities, API integration |
| 4 | Landing page (creative) | `claude-impl` | Brainstorms, designs, implements full page | Verifies code quality, accessibility, performance |
| 5 | Design system update (tokens) | `collab-split` | Designs token system, implements core primitives + reference components | Sweeps all remaining components to use new tokens |
| 6 | Dark mode | `collab-split` | Designs theme system, implements ThemeProvider + core components | Sweeps all components to use theme tokens |

### Refactoring / Migration

| # | Scenario | Mode | Claude Does | Codex Does |
|---|---|---|---|---|
| 7 | Large rename across codebase | `codex-impl` | Explores, builds refactoring contract (targets, consumers, tests) | Executes mechanical rename following the contract. Gets refactoring skill. |
| 8 | Framework migration (Express→Hono) | `collab-split` | Discusses migration strategy with Codex (collaborative design phase) | Executes migration steps. Gets relevant skill. |
| 9 | Dependency upgrade (React 18→19) | `collab-split` | Discusses breaking changes with Codex (collaborative design phase) | Executes migration. Claude verifies functionality/UX. |
| 10 | i18n string extraction sweep | `codex-impl` | Defines key naming convention and file structure | Finds all strings, extracts into translation keys across all files |

### Bug Fixing / Debugging

| # | Scenario | Mode | Claude Does | Codex Does |
|---|---|---|---|---|
| 11 | Failing test / CI failure | `codex-impl` | Verifies the fix, checks for same bug class elsewhere | Investigates root cause (systematic-debugging skill), implements fix |
| 12 | Performance optimization | `codex-impl` | Verifies fixes, handles frontend UX fixes if needed | Investigates bottlenecks (`codex-impl`). Fix steps assigned after: backend → `codex-impl`, frontend → `claude-impl`. See Dynamic Routing. |

### Security

| # | Scenario | Mode | Claude Does | Codex Does |
|---|---|---|---|---|
| 13 | Security review / audit | `dual-pass` | Reviews design-level issues (auth flow, permission model, data exposure) | Reviews implementation-level issues (OWASP, injection, validation, secrets) |
| 14 | Security-sensitive design | `claude-impl` | Designs auth architecture, permission model | Challenge pass: adversarial critique of Claude's design |

### Infrastructure / DevOps

| # | Scenario | Mode | Claude Does | Codex Does |
|---|---|---|---|---|
| 15 | CI/CD pipeline setup | `codex-impl` | Verifies pipeline works correctly | Designs and implements full pipeline (YAML, scripts, caching) |

### Review / Verification

| # | Scenario | Mode | Claude Does | Codex Does |
|---|---|---|---|---|
| 16 | PR review | `dual-pass` | Reviews design/architecture/UX, synthesizes and presents findings | Adversarial review: correctness, security, edge cases, test coverage |
| 17 | Post-step verification | `codex-impl` | N/A (this IS Codex's verification role) | Verifies acceptance criteria, runs tests, checks consumers |

### Documentation

| # | Scenario | Mode | Claude Does | Codex Does |
|---|---|---|---|---|
| 18 | API documentation | `claude-impl` | Writes docs (doc-coauthoring skill: audience, structure, tone) | Verifies technical accuracy (code examples work, signatures match) |

### Complex / Mixed-Domain

| # | Scenario | Mode | Claude Does | Codex Does |
|---|---|---|---|---|
| 19 | Real-time collaborative editing | `collab-split` | Collaborative architecture design with Codex. Implements frontend (cursor UI, presence). | Collaborative architecture design with Claude. Implements backend (WebSocket, CRDT, Redis). |
| 20 | Stripe integration | `collab-split` | Collaborative design with Codex. Implements Stripe API-facing code (webhooks, checkout). | Collaborative design with Claude. Implements internal service layer, DB models, types. |

### Additional Mixed-Domain

| # | Scenario | Mode | Claude Does | Codex Does |
|---|---|---|---|---|
| 21 | Plugin/MCP development | `collab-split` | Collaborative design with Codex. Implements skills + MCP server. | Collaborative design with Claude. Implements hooks, scripts, manifest. |
| 22 | Test writing | `codex-impl` | Verifies tests are meaningful and cover all cases | Writes tests. Gets TDD skill injected into prompt. |
| 23 | Vague request ("make it better") | `claude-impl` | Clarifies requirements with user, shapes into concrete task. Once concrete, subsequent steps are assigned normally via routing matrix. | After Claude has concrete requirements: audits codebase for relevant improvements |

---

## Phase-Level Ownership

These apply regardless of step-level ownership:

| Phase | Owner | Codex Role | Notes |
|---|---|---|---|
| Intent capture (vague ask) | Claude | Codex verifies after | Codex enters only after requirements are concrete |
| Brainstorming | Claude | Co-explores codebase, reviews design.md | Codex explores consumers/blast-radius in parallel, reviews design before planning |
| Discovery | Claude + Codex | Co-exploration partner | Both explore in parallel (Phase 1), then converge (Phase 2) |
| Plan writing | Claude | Consensus partner | Multi-round debate (max 3 rounds) until both agree or escalate to user |
| Plan review (Orbit) | User | N/A | User approves via Orbit |
| Execution | Per-step | Per-step | Based on step.owner and step.mode |
| Final summary | Claude | None | Claude always owns user communication |

---

## Dynamic Routing

Some scenarios don't know the correct owner at plan time:

- **Performance optimization** (scenario 12): Codex investigates first.
  Based on findings, fix steps are assigned to Claude (frontend) or Codex
  (backend). The plan may need mid-execution adjustment.
- **Vague requests** (scenario 23): Claude clarifies first (`claude-impl`).
  Once concrete, steps are assigned normally.
- **collab-split design phase**: The collaborative design discussion may
  reveal that the split should be different from what was initially assumed.

For these, the `writing-plans` skill creates an investigation step (always
`owner: codex` for performance, `owner: claude` for vague) followed by
placeholder steps that get their `owner` assigned after investigation
completes.

---

## Skill Injection Rules

When `owner: "codex"`, the step's `skill` field determines what guidance
Codex receives in its `developer-instructions`:

| Step skill | Codex gets |
|---|---|
| `look-before-you-leap:test-driven-development` | TDD guidance: RED-GREEN-REFACTOR cycles |
| `look-before-you-leap:refactoring` | Refactoring contract + execution order |
| `look-before-you-leap:systematic-debugging` | Four-phase investigation guidance |
| `look-before-you-leap:webapp-testing` | Playwright/E2E testing guidance |
| `look-before-you-leap:mcp-builder` | MCP server development guidance |
| `"none"` | Engineering-discipline only |

Skills that stay Claude-only (never injected into Codex):
- `frontend-design` — requires visual taste
- `svg-art` — requires creative direction
- `immersive-frontend` — requires experiential judgment
- `react-native-mobile` — requires native-feel taste
- `brainstorming` — Claude leads dialogue, Codex co-explores and reviews design
- `writing-plans` — Claude leads, Codex participates in plan consensus
- `doc-coauthoring` — Claude writes, Codex verifies accuracy

---

## Verification Rules

| Step owner | Who verifies | Verification depth |
|---|---|---|
| `claude` | Codex | Reads files, runs tsc/lint/tests, checks consumers, reports findings |
| `codex` | Claude | Reads modified files, runs tsc/lint/tests, checks consumers via deps-query |
| `dual-pass` | Both independently | Claude: design/UX. Codex: correctness/security. Claude synthesizes. |

**Symmetric verification**: same rigor in both directions. Neither agent's
work ships without the other's review.

**Symmetric error logging**:
- Codex logs Claude's mistakes → `usage-errors/codex-findings/`
- Claude logs Codex's mistakes → `usage-errors/claude-findings/`
- Same JSON schema for both directions
