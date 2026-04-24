# look-before-you-leap

A Claude Code plugin that makes Claude behave like a disciplined engineer instead of a fast-but-sloppy one.

## The Problem

Claude is fast and pleasant to work with. It's also unreliable for serious engineering work. These failure modes aren't edge cases — they happen constantly:

| What Claude does | What actually happens |
|---|---|
| Silently drops scope | You ask for 5 things, get 3 done, and it declares victory |
| Doesn't check blast radius | Changes a shared utility and breaks every consumer |
| Leaves type safety holes | `as any`, nullable fields that should never be null, `v.any()` in schemas |
| Never verifies its own work | Doesn't run tsc, linter, or tests after changes |
| Doesn't explore the codebase | Fixes a file in isolation without checking patterns or conventions |
| Skips operational basics | Uses packages without installing them, reads env vars without checking they're loaded |
| Loses track after compaction | Forgets the plan, stops mid-task, or restarts work already done |
| Glazes instead of self-auditing | "You're absolutely right!" then fixes only the one thing you pointed out |

## How It Works

### Conductor mode

The main Claude thread is a **pure conductor**. It does not edit files, does
not run verification, does not read raw artifacts (no `.codex-result-*.txt`,
no `.codex-stream-*.jsonl`, no raw exploration / consensus markdown, no
`git diff`). It reads only:

- `plan.json` (immutable plan definition) and `progress.json` (mutable execution state)
- Signed HMAC sidecar receipts under `~/.claude/look-before-you-leap/state/<projectId>/<planId>/`
- Per-step evidence artifacts (`codex-receipt-step-N.json`)
- Bounded digests written by the `lbyl-digest` sub-agent

Implementation, verification, and large-artifact reading all happen in
sub-agents (Codex via `codex exec`, or Claude via the Agent/Skill tool).
The previous `collab-split` mode has been removed — every step has a single
owner and mixed-discipline work is expressed as multiple steps with
`dependsOn`. The remaining modes are `claude-impl`, `codex-impl`, and
`dual-pass`.

### Three-layer architecture

Context is expensive. Not every task needs every rule. The plugin loads knowledge progressively:

**Layer 1: The Conductor** (always in context, ~250 lines)
The main SKILL.md that controls the process. Enforces: explore before editing, write a plan before coding, checkpoint progress, verify before declaring done. Routes to deeper layers when needed.

**Layer 2: Discipline Checklists** (~30-50 lines each, loaded during planning)
Quick-reference checklists for testing, UI consistency, security, git, linting, dependencies, and API contracts. Read the relevant checklist before starting that kind of work.

**Layer 3: Deep Guides** (~80-150 lines each, loaded on demand)
Comprehensive strategies for testing (TDD-lite, test theater detection), UI consistency (design tokens, drift detection), and security (OWASP Top 10, slopsquatting prevention).

### Persistent plans

Every task gets a plan written to `.temp/plan-mode/active/<plan-name>/` before any code is edited. Plans consist of `plan.json` (immutable definition, frozen after approval), `progress.json` (mutable execution state, updated every 2-3 file edits via `plan_utils.py`), and `masterPlan.md` (user-facing proposal). When context compacts, both files survive on disk — Claude reads them and picks up exactly where it left off.

### Enforcement hooks

The plugin doesn't just give instructions — it enforces them:

| Event | Hook | What it does |
|---|---|---|
| **SessionStart** | `session-start.sh` | Injects all three skill layers, detects active plans, discovers other installed plugins, auto-detects project stack |
| **UserPromptSubmit** | `onboarding.sh` | First-run setup: walks user through config enrichment, CLAUDE.md creation, and plugin suggestions |
| **PreToolUse** (Codex MCP) | `block-codex-mcp.sh` | Blocks Codex MCP tool usage — enforces `codex exec` via Bash for all Codex interactions |
| **PreToolUse** (Edit\|Write) | `enforce-plan.sh` | Blocks code edits if no active plan exists |
| **PreToolUse** (Edit\|Write) | `check-api-contracts.sh` | Warns when editing API boundary files |
| **PreToolUse** (Bash) | `guard-filesystem-mutation.sh` | Blocks Bash file writes and destructive commands without an active plan or approval |
| **PreToolUse** (Bash) | `guard-plan-completion.sh` | Blocks moving a plan to completed/ if it has unchecked steps |
| **PreToolUse** (Grep) | `remind-deps-query.sh` | Blocks import/consumer greps when dependency maps are configured and redirects Claude to `deps-query.py` |
| **PreToolUse** (Task) | `inject-subagent-context.sh` | Injects discipline rules into every sub-agent, creates shared discovery file for cross-agent findings |
| **PostToolUse** (Edit\|Write) | `remind-plan-update.sh` | Reminds to checkpoint the plan after 3 code edits without a plan update |
| **PostToolUse** (Edit\|Write) | `auto-complete-plan.sh` | Detects when all plan steps are complete and prompts finalization |
| **PostToolUse** (Edit\|Write) | `mark-deps-stale.sh` | Marks configured TypeScript dependency maps stale after source edits so they can be regenerated lazily |
| **PostToolUse** (Edit\|Write) | `enforce-plan-handoff.sh` | Marks fresh plans for Orbit review handoff and injects the review workflow before execution begins |
| **PostToolUse** (`orbit_await_review`) | `clear-handoff-on-approval.sh` | Clears the pending handoff marker after Orbit approval |
| **PostToolUse** (Edit\|Write\|Bash) | `verify-step-completion.sh` | Blocks step-done transitions until the required Codex or Claude verification verdict is recorded |
| **PostToolUse** (Bash) | `log-script-errors.sh` | Logs plugin-script crashes and warnings to `usage-errors/script-errors/` for later debugging |
| **PostCompact** | `post-compact.sh` | Rehydrates the active plan and resumption context after Claude compacts |
| **Stop** | `verify-plan-on-stop.sh` | Blocks stopping if the active plan has unfinished steps |
| **Stop** | `refresh-deps-on-stop.sh` | Regenerates stale dependency maps before the session ends so the next session starts fresh |

### First-run onboarding

When you open a project for the first time with this plugin installed, it:

1. Auto-detects your stack (language, frameworks, package manager, monorepo structure)
2. Creates `.claude/look-before-you-leap.local.md` with the detected config
3. On your first message, walks you through setup:
   - Shows what was detected
   - Offers to enrich the config by exploring the codebase
   - Offers to create a `CLAUDE.md` if the project doesn't have one
   - Suggests useful official Anthropic plugins and offers to install them

This only happens once per project. The config file is never overwritten after creation.

### Project config

The auto-generated `.claude/look-before-you-leap.local.md` contains YAML frontmatter with your detected stack. Hooks use this to adapt behavior — for example, `check-api-contracts.sh` only fires if your stack includes a backend framework.

To customize, edit the file directly. Add it to `.gitignore` if you don't want it committed.

### Codex integration

Codex is the **default implementer**. Most steps are `codex-impl` (Codex
writes the code, Claude verifies via a sub-agent). Steps that require visual
taste, brand voice, or hands-on UI judgment are `claude-impl` (Claude
implements via the Agent tool, Codex verifies through a read-only review).
A small set of high-stakes steps run `dual-pass` — both agents work the same
step independently and the conductor compares verdicts.

The conductor dispatches Codex via `codex exec` through direction-locked
wrapper scripts (`run-codex-implement.sh`, `run-codex-verify.sh`). The
wrappers — not the conductor and not Codex — mint the trusted artifacts.

### Receipt protocol

Every Codex run produces two coupled artifacts:

- **Evidence artifact**: `<plan-dir>/codex-receipt-step-N.json` — rich
  per-criterion verdicts, file:line evidence, command exit codes, output
  hashes, and findings. Read by hooks and digest sub-agents.
- **HMAC sidecar**: `~/.claude/look-before-you-leap/state/<projectId>/<planId>/<type>-step-N.json`
  — short, signed payload (`receipt_utils.sign()`) that binds the
  evidence artifact's sha256. Hooks (`verify-step-completion.sh`,
  `guard-plan-completion.sh`, `verify-plan-on-stop.sh`) trust this sidecar
  as the authority. The legacy `.codex-result-step-N.txt` survives only as
  a human trace and is never read by the main thread.

Schema and authority rules live in
[`look-before-you-leap/references/codex-receipt-schema.md`](look-before-you-leap/references/codex-receipt-schema.md).

### Digest flow

Whenever an artifact is too large or too unstructured for the conductor to
read directly — co-exploration markdown, multi-batch consensus outputs,
verification cross-checks of `codex-receipt-step-N.json` plus modified
files — the conductor dispatches the **`lbyl-digest`** sub-agent. The
digester reads raw bytes from disk and writes a bounded digest file
(`discovery-digest.md`, `consensus-round-N-digest.md`, or a
`claude-review-step-N.md`) that the conductor reads instead. `lbyl-digest`
is internal: it is dispatched only by the conductor skills and is never
assignable as a `step.skill` value in `plan.json`.

### Parallel DAG dispatch

Step dispatch is parallel by default. After each completion the conductor
calls `plan_utils.py runnable-steps` to compute the DAG frontier — every
pending step whose `blockedBy` is satisfied — and dispatches all of them in
the same message via multiple Skill / Agent tool calls. Serial dispatch of
independent steps is an anti-pattern. This means `blockedBy` must be
specified correctly in `plan.json` — under-specified deps race under
parallel execution.

### Machine defaults

The plugin runs on machine-level model defaults; dispatch scripts and
sub-agent prompts deliberately pass **no** `--model` / `--effort` flags so
every dispatch inherits the same configuration:

- Claude: `claude-opus-4-7` at `effortLevel: "high"` from `~/.claude/settings.json`
- Codex: `model = "gpt-5.5"`, `model_reasoning_effort = "high"`,
  `service_tier = "fast"` from `~/.codex/config.toml`

Verification commands and the rationale for the no-flag rule live in
[`look-before-you-leap/references/machine-defaults.md`](look-before-you-leap/references/machine-defaults.md).

### Dependency maps

If you configure `dep_maps`, the plugin builds per-module import graphs with
`deps-generate.py` and queries them with `deps-query.py`. Hooks mark maps
stale after TypeScript edits and refresh them lazily, so Claude can check
blast radius and consumers without grepping the codebase every time.

### Commands

The repo also ships four slash commands: `/bypass` writes a signed override
receipt when the user explicitly wants to skip the plan, `/commit-msg`
generates a 1-line commit message from the current diff, `/generate-deps`
sets up or refreshes dependency maps, and `/tangent` loads discovery context
from another active plan so a new session can explore a related thread
without starting from zero.

## Prerequisites

### Required

| Dependency | Why | Install |
|---|---|---|
| `python3` | All hooks use Python 3 for JSON parsing (stdlib only — no pip packages needed) | Pre-installed on macOS. Linux: `sudo apt install python3` |
| `bash` | All hooks and scripts use bash | Pre-installed on macOS and Linux |
| `git` | Used for project root detection | Pre-installed on macOS (Xcode tools). Linux: `sudo apt install git` |

Standard POSIX tools (`find`, `grep`, `sed`, `awk`, `stat`, `sort`, `head`, `cut`, `wc`) are also required but ship with all macOS and Linux distributions.

### Optional

| Dependency | Why | Install |
|---|---|---|
| `madge` | Dependency graph analysis for blast-radius tracking. Only needed if you configure `dep_maps` in `.claude/look-before-you-leap.local.md` | `npm install -g madge` or use on-demand via `npx` (no install needed) |
| Node.js | Required only if using `madge` | [nodejs.org](https://nodejs.org) |

### Recommended

| Dependency | Why | Install |
|---|---|---|
| `typescript-language-server` | TypeScript/JavaScript LSP for editor intelligence. Useful if your projects use TypeScript | `npm install -g typescript typescript-language-server` |

### Recommended Packages

The plugin's skills (frontend-design, immersive-frontend) reference specific
npm packages for color palettes, animation, and WebGL. See
[`PACKAGES.md`](look-before-you-leap/PACKAGES.md) for the full list with
install commands.

## Installation

### From the plugin marketplace

```bash
claude plugin install look-before-you-leap@claude-code-setup
```

### From source

```bash
git clone https://github.com/miospotdevteam/claude-control.git ~/claude-code-setup
claude plugin install --source ~/claude-code-setup/look-before-you-leap
```

## Repo Structure

```
look-before-you-leap/
├── PACKAGES.md                            # Recommended npm packages for skills
├── .claude-plugin/
│   ├── plugin.json                        # Claude plugin manifest
│   └── settings.json                      # Plugin-local UI/settings toggles
├── codex-skills/
│   ├── lbyl-implement/
│   │   └── SKILL.md                       # Codex protocol for codex-owned plan steps (emits codex-receipt-step-N.json)
│   ├── lbyl-verify/
│   │   └── SKILL.md                       # Codex protocol for verifying Claude's work (emits codex-receipt-step-N.json)
│   └── react-native-mobile/
│       └── SKILL.md                       # Codex-installable React Native skill for code-heavy RN/Expo steps (UI/UX stays Claude-owned)
├── commands/
│   ├── bypass.md                           # Slash command: write a signed override receipt
│   ├── commit-msg.md                      # Slash command: generate a 1-line commit message
│   ├── generate-deps.md                   # Slash command: configure and build dep maps
│   └── tangent.md                         # Slash command: load discovery from another session
├── hooks/
│   ├── auto-complete-plan.sh              # PostToolUse: migrates discovery + detects plan completion
│   ├── check-api-contracts.sh             # PreToolUse: API boundary warnings
│   ├── clear-handoff-on-approval.sh       # PostToolUse: clears pending handoff after approval
│   ├── guard-filesystem-mutation.sh       # PreToolUse: blocks unsafe Bash file writes
│   ├── enforce-plan-handoff.sh            # PostToolUse: requires Orbit review for fresh plans
│   ├── enforce-plan.sh                    # PreToolUse: blocks edits without an active plan
│   ├── guard-plan-completion.sh           # PreToolUse: blocks moving incomplete plans
│   ├── hooks.json                         # Hook lifecycle configuration
│   ├── inject-subagent-context.sh         # PreToolUse: discipline injection for sub-agents
│   ├── log-script-errors.sh               # PostToolUse: logs plugin-script errors and warnings
│   ├── mark-deps-stale.sh                 # PostToolUse: marks dep maps stale after TS edits
│   ├── onboarding.sh                      # UserPromptSubmit: first-run setup walkthrough
│   ├── post-compact.sh                    # PostCompact: restores active-plan context after compaction
│   ├── refresh-deps-on-stop.sh            # Stop: refreshes stale dep maps before exit
│   ├── remind-deps-query.sh               # PreToolUse: blocks grep-based import discovery
│   ├── remind-plan-update.sh              # PostToolUse: checkpoint reminder after 3 edits
│   ├── session-start.sh                   # SessionStart: skill injection + plan detection + config
│   ├── track-codex-exploration.sh         # PostToolUse: tracks Codex preflight and co-exploration markers
│   ├── verify-plan-on-stop.sh             # Stop: blocks stopping with unfinished plans
│   ├── verify-step-completion.sh          # PostToolUse: verification gate for step completion
│   └── lib/
│       ├── detect-stack.py                # Auto-detects project stack
│       ├── find-root.sh                   # Finds project root directory
│       └── read-config.py                 # YAML frontmatter -> JSON config reader
├── references/
│   ├── codex-receipt-schema.md            # Schema + dual-authority model for codex-receipt-step-N.json + HMAC sidecars
│   └── machine-defaults.md                # Required Claude/Codex machine-level model + effort defaults (no flags)
├── scripts/
│   ├── dep_partition.py                   # Partitions target files into planning groups using dep maps
│   ├── deps-generate.py                   # Builds normalized dep maps with madge
│   ├── deps-query.py                      # Queries dep maps for dependencies and dependents
│   ├── deps_utils.py                      # Shared dep-map helpers
│   ├── grant-bypass.sh                    # Mints a signed plan-bypass receipt (used by /bypass)
│   ├── init-plan-dir.sh                   # Sets up .temp/plan-mode/
│   ├── install-codex-skills.sh            # Keeps ~/.codex/skills/ synced on session start
│   ├── plan-status.sh                     # Shows all plan statuses
│   ├── plan_utils.py                      # Plan state management (incl. runnable-steps DAG frontier + receipt commands)
│   ├── receipt_utils.py                   # HMAC sidecar mint/verify (binds codex-receipt-step-N.json sha256)
│   ├── resume.sh                          # Finds what to resume
│   ├── run-codex-implement.sh             # Direction-locked Codex implementation entrypoint (mints codex-receipt-step-N.json + sidecar)
│   ├── run-codex-verify.sh                # Direction-locked Codex verification entrypoint (mints codex-receipt-step-N.json + sidecar)
│   ├── validate_step_ownership.py         # Step-level ownership enforcement (no group dispatch)
│   └── write-discovery-receipt.sh         # Mints signed discovery receipt before planning
├── skills/
│   ├── brainstorming/
│   │   └── SKILL.md                       # Collaborative design exploration
│   ├── codex-dispatch/
│   │   └── SKILL.md                       # Codex CLI orchestration via codex exec: receipt-first, parallel DAG dispatch, no collab-split
│   ├── doc-coauthoring/
│   │   └── SKILL.md                       # 3-stage document co-authoring
│   ├── engineering-discipline/
│   │   └── SKILL.md                       # Companion: behavioral rules
│   ├── frontend-design/
│   │   └── SKILL.md                       # Frontend UI design with aesthetic axes
│   ├── immersive-frontend/
│   │   ├── SKILL.md                       # WebGL, Three.js, GSAP, scroll-driven 3D
│   │   └── references/
│   │       ├── architecture.md            # Preloader, canvas+DOM layering, perf budgets
│   │       ├── effects-cookbook.md        # 8 complete implementations (preloader, marquee, etc.)
│   │       ├── gsap-common-mistakes.md    # Gotchas, debugging, FOUC prevention
│   │       ├── gsap-core-patterns.md      # context, matchMedia, quickTo, utils, CSS vars
│   │       ├── gsap-easing-advanced.md    # CustomEase, CustomBounce, CustomWiggle, EasePack
│   │       ├── gsap-helpers-cheatsheet.md # Dense all-in-one GSAP quick reference
│   │       ├── gsap-layout-plugins.md     # Flip, Draggable, Observer
│   │       ├── gsap-motion-physics.md     # MotionPath, Physics2D, PhysicsProps
│   │       ├── gsap-scroll-advanced.md    # ScrollSmoother, Observer patterns
│   │       ├── gsap-scroll-patterns.md    # Core tweens, timelines, ScrollTrigger, Lenis
│   │       ├── gsap-scroll-to-plugin.md   # Animated scroll-to navigation
│   │       ├── gsap-svg-plugins.md        # MorphSVG, DrawSVG, SVG transforms
│   │       ├── gsap-text-plugins.md       # SplitText, ScrambleText, TextPlugin
│   │       ├── gsap-value-plugins.md      # InertiaPlugin, Modifiers, Snap, roundProps
│   │       ├── shader-recipes.md          # GLSL: noise, chromatic aberration, distortion
│   │       └── three-js-patterns.md       # Scene setup, cameras, materials, R3F, disposal
│   ├── lbyl-digest/
│   │   └── SKILL.md                       # INTERNAL conductor-dispatched digester: collapses raw artifacts into bounded digests (co-exploration, consensus, verification)
│   ├── look-before-you-leap/
│   │   ├── SKILL.md                       # Layer 1: The conductor
│   │   ├── references/
│   │   │   ├── anti-slop.md               # Shared anti-AI-slop banlist for creative skills
│   │   │   ├── api-contracts-checklist.md # Layer 2: Shared schemas
│   │   │   ├── api-contracts-guide.md     # Layer 3: API boundary discipline
│   │   │   ├── claude-md-snippet.md       # Recommended CLAUDE.md addition
│   │   │   ├── color-palettes.md          # Curated palette systems for frontend skills
│   │   │   ├── debugging-condition-based-waiting.md # Layer 3: Replace timeouts with polling
│   │   │   ├── debugging-defense-in-depth.md # Layer 3: Multi-layer validation
│   │   │   ├── debugging-root-cause-tracing.md # Layer 3: Trace bugs to source
│   │   │   ├── dependency-checklist.md    # Layer 2: Package management
│   │   │   ├── dependency-mapping.md      # Dep-map workflow: generate, stale marking, query
│   │   │   ├── exploration-guide.md       # Deep exploration techniques
│   │   │   ├── exploration-protocol.md    # 8-question exploration checklist
│   │   │   ├── frontend-design-checklist.md # Layer 2: Accessibility, responsive, performance
│   │   │   ├── frontend-design-guide.md   # Layer 3: Aesthetic axes, fonts, animation
│   │   │   ├── git-checklist.md           # Layer 2: Commits, branches
│   │   │   ├── linting-checklist.md       # Layer 2: Linter discipline
│   │   │   ├── master-plan-format.md      # Plan template with structured discovery
│   │   │   ├── plan-schema.md             # plan.json (immutable) + progress.json (mutable) schemas
│   │   │   ├── recommended-plugins.md     # Official plugin suggestions for onboarding
│   │   │   ├── routing-matrix.md          # Task-type routing table for step ownership
│   │   │   ├── scenario-playbook.md       # 23-scenario ownership matrix
│   │   │   ├── security-checklist.md      # Layer 2: Auth, input, secrets
│   │   │   ├── security-guide.md          # Layer 3: OWASP, slopsquatting
│   │   │   ├── sub-plan-format.md         # Sub-plan and sweep templates
│   │   │   ├── testing-checklist.md       # Layer 2: Testing discipline
│   │   │   ├── testing-strategy.md        # Layer 3: TDD-lite, test pyramid
│   │   │   ├── ui-consistency-checklist.md # Layer 2: Design tokens, components
│   │   │   ├── ui-consistency-guide.md    # Layer 3: Drift detection
│   │   │   └── verification-commands.md   # tsc/lint/test commands by ecosystem
│   │   └── (scripts live at look-before-you-leap/scripts/ — see top-level scripts/ tree above)
│   ├── mcp-builder/
│   │   ├── SKILL.md                       # 4-phase MCP server development
│   │   └── references/
│   │       ├── mcp-best-practices.md      # Tool design, responses, security
│   │       ├── mcp-python.md              # FastMCP, Pydantic, async
│   │       └── mcp-typescript.md          # McpServer, Zod, transports
│   ├── persistent-plans/
│   │   └── SKILL.md                       # Companion: plan management rules
│   ├── react-native-mobile/
│   │   ├── SKILL.md                       # React Native mobile app implementation guide
│   │   └── references/
│   │       ├── animation-patterns.md      # Reanimated transitions and motion patterns
│   │       ├── architecture.md            # Feature slices, data flow, navigation boundaries
│   │       ├── component-recipes.md       # Lists, forms, empty states, and async UI recipes
│   │       ├── gesture-cookbook.md        # Gesture Handler + Reanimated interaction patterns
│   │       ├── performance-patterns.md    # FlatList, rendering, and profiling guidance
│   │       └── platform-patterns.md       # iOS/Android divergence and native capability patterns
│   ├── refactoring/
│   │   └── SKILL.md                       # Post-execution code simplification
│   ├── skill-review-standard/
│   │   ├── SKILL.md                       # Post-creation quality gate
│   │   └── scripts/
│   │       ├── aggregate_benchmark.py     # Stats from grading results
│   │       ├── generate_report.py         # HTML report with pass/fail
│   │       ├── improve_description.py     # LLM-based description optimizer
│   │       ├── run_eval.py                # Trigger skill evaluation runs
│   │       ├── utils.py                   # Skill frontmatter parser
│   │       └── validate-structure.sh      # Structural validation
│   ├── svg-art/
│   │   ├── SKILL.md                       # SVG illustration and graphics generation
│   │   └── references/
│   │       ├── decorative-backgrounds.md  # Blobs, meshes, waves, and layered scenes
│   │       ├── filter-recipes.md          # Blur, noise, displacement, and lighting filters
│   │       ├── generative-patterns.md     # Tiling, grids, noise, and algorithmic motifs
│   │       ├── illustration-techniques.md # Shape language, masks, and depth tricks
│   │       ├── micro-animations.md        # Lightweight SVG motion patterns
│   │       └── svg-gotchas.md             # ViewBox, IDs, transforms, and perf pitfalls
│   ├── systematic-debugging/
│   │   └── SKILL.md                       # Root cause investigation before fixes
│   ├── test-driven-development/
│   │   └── SKILL.md                       # Red-green-refactor testing discipline
│   ├── webapp-testing/
│   │   ├── SKILL.md                       # E2E/browser testing with Playwright
│   │   ├── references/
│   │   │   ├── playwright-patterns.md     # Selectors, assertions, waits, POM
│   │   │   └── server-recipes.md          # Dev server configs by framework
│   │   └── scripts/
│   │       └── with_server.py             # Dev server lifecycle for E2E tests
│   └── writing-plans/
│       └── SKILL.md                       # Plan generation with TDD-granularity steps
└── usage-errors/
    └── .gitkeep                           # Keeps the log directory committed
```

## Origin Story

This plugin was built iteratively through real-world testing on production codebases. Each rule exists because Claude actually made that specific mistake. The sub-plan triggers, checkpoint frequency, auto-compaction survival logic, and discipline checklists were all calibrated based on actual failures during real tasks.
