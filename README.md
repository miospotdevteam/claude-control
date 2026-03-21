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

### Three-layer architecture

Context is expensive. Not every task needs every rule. The plugin loads knowledge progressively:

**Layer 1: The Conductor** (always in context, ~250 lines)
The main SKILL.md that controls the process. Enforces: explore before editing, write a plan before coding, checkpoint progress, verify before declaring done. Routes to deeper layers when needed.

**Layer 2: Discipline Checklists** (~30-50 lines each, loaded during planning)
Quick-reference checklists for testing, UI consistency, security, git, linting, dependencies, and API contracts. Read the relevant checklist before starting that kind of work.

**Layer 3: Deep Guides** (~80-150 lines each, loaded on demand)
Comprehensive strategies for testing (TDD-lite, test theater detection), UI consistency (design tokens, drift detection), and security (OWASP Top 10, slopsquatting prevention).

### Persistent plans

Every task gets a plan written to `.temp/plan-mode/active/<plan-name>/masterPlan.md` before any code is edited. Plans have numbered steps with progress checklists that get updated every 2-3 file edits. When context compacts, the plan survives on disk — Claude reads it and picks up exactly where it left off.

### Enforcement hooks

The plugin doesn't just give instructions — it enforces them:

| Event | Hook | What it does |
|---|---|---|
| **SessionStart** | `session-start.sh` | Injects all three skill layers, detects active plans, discovers other installed plugins, auto-detects project stack |
| **UserPromptSubmit** | `onboarding.sh` | First-run setup: walks user through config enrichment, CLAUDE.md creation, and plugin suggestions |
| **PreToolUse** (Edit\|Write) | `enforce-plan.sh` | Blocks code edits if no active plan exists |
| **PreToolUse** (Edit\|Write) | `check-api-contracts.sh` | Warns when editing API boundary files |
| **PreToolUse** (Bash) | `enforce-plan-bash.sh` | Blocks Bash file-write bypasses (redirects, sed -i, tee) without an active plan |
| **PreToolUse** (Bash) | `guard-plan-completion.sh` | Blocks moving a plan to completed/ if it has unchecked steps |
| **PreToolUse** (Task) | `inject-subagent-context.sh` | Injects discipline rules into every sub-agent, creates shared discovery file for cross-agent findings |
| **PostToolUse** (Edit\|Write) | `remind-plan-update.sh` | Reminds to checkpoint the plan after 3 code edits without a plan update |
| **PostToolUse** (Edit\|Write) | `auto-complete-plan.sh` | Detects when all plan steps are complete and prompts finalization |
| **Stop** | `verify-plan-on-stop.sh` | Blocks stopping if the active plan has unfinished steps |

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
git clone https://github.com/anthropics/claude-code-setup.git ~/claude-code-setup
claude plugin install --source ~/claude-code-setup/look-before-you-leap
```

## Repo Structure

```
look-before-you-leap/
├── PACKAGES.md                            # Recommended npm packages for skills
├── usage-errors/                          # Plugin error logs (auto-documented by Claude)
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   ├── hooks.json                       # Hook lifecycle configuration
│   ├── session-start.sh                 # SessionStart: skill injection + plan detection + config
│   ├── onboarding.sh                    # UserPromptSubmit: first-run setup walkthrough
│   ├── enforce-plan.sh                  # PreToolUse: blocks edits without an active plan
│   ├── enforce-plan-bash.sh             # PreToolUse: blocks Bash file-write bypasses
│   ├── check-api-contracts.sh           # PreToolUse: API boundary warnings
│   ├── guard-plan-completion.sh         # PreToolUse: blocks moving incomplete plans
│   ├── inject-subagent-context.sh       # PreToolUse: discipline injection for sub-agents
│   ├── remind-plan-update.sh            # PostToolUse: checkpoint reminder after 3 edits
│   ├── auto-complete-plan.sh            # PostToolUse: detects plan completion
│   ├── verify-plan-on-stop.sh           # Stop: blocks stopping with unfinished plans
│   └── lib/
│       ├── read-config.py               # YAML frontmatter → JSON config reader
│       ├── detect-stack.py              # Auto-detects project stack
│       └── find-root.sh                 # Finds project root directory
└── skills/
    ├── look-before-you-leap/
    │   ├── SKILL.md                     # Layer 1: The conductor
    │   ├── evals/
    │   │   └── evals.json               # Skill evaluation definitions
    │   ├── references/
    │   │   ├── exploration-protocol.md  # 8-question exploration checklist
    │   │   ├── exploration-guide.md     # Deep exploration techniques
    │   │   ├── master-plan-format.md    # Plan template with structured discovery
    │   │   ├── sub-plan-format.md       # Sub-plan and sweep templates
    │   │   ├── claude-md-snippet.md     # Recommended CLAUDE.md addition
    │   │   ├── recommended-plugins.md   # Official plugin suggestions for onboarding
    │   │   ├── testing-checklist.md     # Layer 2: Testing discipline
    │   │   ├── testing-strategy.md      # Layer 3: TDD-lite, test pyramid
    │   │   ├── ui-consistency-checklist.md  # Layer 2: Design tokens, components
    │   │   ├── ui-consistency-guide.md  # Layer 3: Drift detection
    │   │   ├── frontend-design-checklist.md # Layer 2: Accessibility, responsive, performance
    │   │   ├── frontend-design-guide.md # Layer 3: Aesthetic axes, fonts, animation
    │   │   ├── security-checklist.md    # Layer 2: Auth, input, secrets
    │   │   ├── security-guide.md        # Layer 3: OWASP, slopsquatting
    │   │   ├── git-checklist.md         # Layer 2: Commits, branches
    │   │   ├── linting-checklist.md     # Layer 2: Linter discipline
    │   │   ├── dependency-checklist.md  # Layer 2: Package management
    │   │   ├── api-contracts-checklist.md   # Layer 2: Shared schemas
    │   │   ├── api-contracts-guide.md   # Layer 3: API boundary discipline
    │   │   ├── debugging-root-cause-tracing.md      # Layer 3: Trace bugs to source
    │   │   ├── debugging-defense-in-depth.md        # Layer 3: Multi-layer validation
    │   │   ├── debugging-condition-based-waiting.md  # Layer 3: Replace timeouts with polling
    │   │   ├── verification-commands.md # tsc/lint/test commands by ecosystem
    │   │   ├── codex-verify-template.md # Prompt templates for Codex MCP verification
    │   │   └── anti-slop.md             # Shared anti-AI-slop banlist for creative skills
    │   └── scripts/
    │       ├── init-plan-dir.sh         # Sets up .temp/plan-mode/
    │       ├── plan-status.sh           # Shows all plan statuses
    │       └── resume.sh               # Finds what to resume
    ├── engineering-discipline/
    │   └── SKILL.md                     # Companion: behavioral rules
    ├── persistent-plans/
    │   └── SKILL.md                     # Companion: plan management rules
    ├── brainstorming/
    │   └── SKILL.md                     # Collaborative design exploration
    ├── writing-plans/
    │   └── SKILL.md                     # Plan generation with TDD-granularity steps
    ├── frontend-design/
    │   └── SKILL.md                     # Frontend UI design with aesthetic axes
    ├── immersive-frontend/
    │   ├── SKILL.md                     # WebGL, Three.js, GSAP, scroll-driven 3D
    │   └── references/
    │       ├── architecture.md          # Preloader, canvas+DOM layering, perf budgets
    │       ├── three-js-patterns.md     # Scene setup, cameras, materials, R3F, disposal
    │       ├── shader-recipes.md        # GLSL: noise, chromatic aberration, distortion
    │       ├── effects-cookbook.md       # 8 complete implementations (preloader, marquee, etc.)
    │       ├── gsap-core-patterns.md    # context, matchMedia, quickTo, utils, CSS vars
    │       ├── gsap-scroll-patterns.md  # Core tweens, timelines, ScrollTrigger, Lenis
    │       ├── gsap-scroll-advanced.md  # ScrollSmoother, Observer patterns
    │       ├── gsap-scroll-to-plugin.md # Animated scroll-to navigation
    │       ├── gsap-layout-plugins.md   # Flip, Draggable, Observer
    │       ├── gsap-text-plugins.md     # SplitText, ScrambleText, TextPlugin
    │       ├── gsap-svg-plugins.md      # MorphSVG, DrawSVG, SVG transforms
    │       ├── gsap-motion-physics.md   # MotionPath, Physics2D, PhysicsProps
    │       ├── gsap-easing-advanced.md  # CustomEase, CustomBounce, CustomWiggle, EasePack
    │       ├── gsap-value-plugins.md    # InertiaPlugin, Modifiers, Snap, roundProps
    │       ├── gsap-helpers-cheatsheet.md # Dense all-in-one GSAP quick reference
    │       └── gsap-common-mistakes.md  # Gotchas, debugging, FOUC prevention
    ├── refactoring/
    │   └── SKILL.md                     # Post-execution code simplification
    ├── systematic-debugging/
    │   └── SKILL.md                     # Root cause investigation before fixes
    ├── skill-review-standard/
    │   ├── SKILL.md                     # Post-creation quality gate
    │   └── scripts/
    │       ├── validate-structure.sh    # Structural validation
    │       ├── utils.py                 # Skill frontmatter parser
    │       ├── run_eval.py              # Trigger skill evaluation runs
    │       ├── aggregate_benchmark.py   # Stats from grading results
    │       ├── improve_description.py   # LLM-based description optimizer
    │       └── generate_report.py       # HTML report with pass/fail
    ├── webapp-testing/
    │   ├── SKILL.md                     # E2E/browser testing with Playwright
    │   ├── scripts/
    │   │   └── with_server.py           # Dev server lifecycle for E2E tests
    │   └── references/
    │       ├── playwright-patterns.md   # Selectors, assertions, waits, POM
    │       └── server-recipes.md        # Dev server configs by framework
    ├── mcp-builder/
    │   ├── SKILL.md                     # 4-phase MCP server development
    │   └── references/
    │       ├── mcp-best-practices.md    # Tool design, responses, security
    │       ├── mcp-typescript.md        # McpServer, Zod, transports
    │       └── mcp-python.md            # FastMCP, Pydantic, async
    └── doc-coauthoring/
        └── SKILL.md                     # 3-stage document co-authoring
```

## Origin Story

This plugin was built iteratively through real-world testing on production codebases. Each rule exists because Claude actually made that specific mistake. The sub-plan triggers, checkpoint frequency, auto-compaction survival logic, and discipline checklists were all calibrated based on actual failures during real tasks.

