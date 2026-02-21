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
| **PreToolUse** (Task) | `inject-subagent-context.sh` | Injects discipline rules into every sub-agent, creates shared discovery file for cross-agent findings |
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
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   ├── hooks.json                       # Hook lifecycle configuration
│   ├── session-start.sh                 # SessionStart: skill injection + plan detection + config
│   ├── onboarding.sh                    # UserPromptSubmit: first-run setup walkthrough
│   ├── enforce-plan.sh                  # PreToolUse: blocks edits without an active plan
│   ├── check-api-contracts.sh           # PreToolUse: API boundary warnings
│   ├── inject-subagent-context.sh       # PreToolUse: discipline injection for sub-agents
│   ├── auto-complete-plan.sh            # PostToolUse: detects plan completion
│   ├── verify-plan-on-stop.sh           # Stop: blocks stopping with unfinished plans
│   └── lib/
│       ├── read-config.py               # YAML frontmatter → JSON config reader
│       └── detect-stack.py              # Auto-detects project stack
└── skills/
    ├── look-before-you-leap/
    │   ├── SKILL.md                     # Layer 1: The conductor
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
    │   │   ├── security-checklist.md    # Layer 2: Auth, input, secrets
    │   │   ├── security-guide.md        # Layer 3: OWASP, slopsquatting
    │   │   ├── git-checklist.md         # Layer 2: Commits, branches
    │   │   ├── linting-checklist.md     # Layer 2: Linter discipline
    │   │   ├── dependency-checklist.md  # Layer 2: Package management
    │   │   ├── api-contracts-checklist.md   # Layer 2: Shared schemas
    │   │   └── verification-commands.md # tsc/lint/test commands by ecosystem
    │   └── scripts/
    │       ├── init-plan-dir.sh         # Sets up .temp/plan-mode/
    │       ├── plan-status.sh           # Shows all plan statuses
    │       └── resume.sh               # Finds what to resume
    ├── engineering-discipline/
    │   └── SKILL.md                     # Companion: behavioral rules
    ├── persistent-plans/
    │   └── SKILL.md                     # Companion: plan management rules
    └── brainstorming/
        └── SKILL.md                     # Collaborative design exploration
```

## Origin Story

This plugin was built iteratively through real-world testing on production codebases. Each rule exists because Claude actually made that specific mistake. The sub-plan triggers, checkpoint frequency, auto-compaction survival logic, and discipline checklists were all calibrated based on actual failures during real tasks.

## Acknowledgments

The **brainstorming** skill is adapted from [superpowers](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/superpowers) by Jesse Vincent. superpowers is an excellent agentic skills framework — if you want a broader set of development skills beyond engineering discipline, check it out.
