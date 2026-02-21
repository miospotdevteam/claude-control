# claude-control

Claude Code plugins that make Claude behave like a disciplined engineer instead of a fast-but-sloppy one.

## The Problem

Opus 4.6 is fast and pleasant to work with. It's also unreliable for serious engineering work. These failure modes aren't edge cases — they happen constantly in daily use:

| What Opus does | What actually happens |
|---|---|
| Silently drops scope | You ask for 5 things, get 3 done, and it declares victory |
| Doesn't check blast radius | Changes a shared utility and breaks every consumer |
| Leaves type safety holes | `as any`, nullable fields that should never be null, `v.any()` in schemas |
| Never verifies its own work | Doesn't run tsc, linter, or tests after changes |
| Doesn't explore the codebase | Fixes a file in isolation without checking patterns or conventions |
| Skips operational basics | Uses packages without installing them, reads env vars without checking they're loaded |
| Loses track after compaction | Forgets the plan, stops mid-task, or restarts work already done |
| Glazes instead of self-auditing | "You're absolutely right!" then fixes only the one thing you pointed out |
| Skips testing | Ships code without writing tests or running existing ones |
| Ignores design systems | Hardcodes colors and spacing instead of using project tokens |
| Introduces security holes | String-concatenated SQL, missing auth checks, hardcoded secrets |

If you've used Opus for real work, you've hit all of these.

## The Solution

Three plugins are available. Choose one installation option.

### Option A: software-discipline (recommended)

A single unified plugin that combines everything. Three-layer architecture:

- **Layer 1: The Conductor** (SKILL.md, always in context) — Controls the process: structured exploration, persistent plans, disciplined execution, verification. Routes to deeper guidance when needed.
- **Layer 2: Discipline Checklists** (~30-50 lines each, read during planning) — Quick-reference before/during/after checklists for testing, UI consistency, security, git, linting, dependencies, and API contracts.
- **Layer 3: Deep Guides** (~80-150 lines each, read on demand) — Comprehensive strategies for testing (TDD-lite, test theater detection), UI consistency (design tokens, drift detection), security (OWASP Top 10, slopsquatting prevention), and API contracts (shared schemas, Zod validation).

Additional features over the individual plugins:
- **Structured exploration protocol** — 8-question checklist that must be completed before planning (prevents shallow plans)
- **Skill discovery** — SessionStart hook scans for other installed plugins and lists them for routing
- **Enhanced plan templates** — Structured Discovery Summary with 8 sections, Required Skills, and Applicable Disciplines fields
- **Seven discipline checklists** — Testing, UI consistency, security, git, linting, dependencies, API contracts
- **Active enforcement via hooks** — Plans are mandatory (Edit/Write blocked without one), stopping mid-plan is blocked, API boundary edits trigger reminders, plan completion is auto-detected
- **Sub-agent discipline injection** — Every spawned sub-agent automatically receives engineering discipline rules tailored to its role (research, code-editing, review)
- **Cross-agent shared discovery** — Parallel sub-agents write findings to a shared `discovery.md` file for cross-pollination
- **Session lock** — Prevents multiple Claude sessions from claiming the same active plan

### Option B: Individual plugins (lightweight)

Two separate plugins that work together. Less comprehensive but lower overhead:

#### engineering-discipline

A behavioral override that forces Opus to be thorough. It shapes *how* work gets done:

- **Explore before editing** — read imports, consumers, sibling files, and project conventions before touching anything
- **No silent scope cuts** — do it or explicitly flag it. Silently trimming scope is the cardinal sin
- **No type safety shortcuts** — no `any`, no `as any`, no unnecessary nullables
- **Track blast radius** — grep for all consumers before modifying shared code
- **Run verification automatically** — tsc, lint, and tests after every task

#### persistent-plans

A workflow system that writes every plan to disk so nothing is lost to context compaction:

- **Every task starts with a plan** written to `.temp/plan-mode/active/<plan-name>/masterPlan.md`
- **Plans have steps with progress checklists** that get updated every 2-3 file edits
- **Auto-compaction survival** — a SessionStart hook detects the active plan and injects it into context
- **Helper scripts** — `plan-status.sh` and `resume.sh` for operational visibility

## Installation

### Option A: software-discipline (recommended)

```bash
git clone https://github.com/miospotdevteam/claude-control.git ~/claude-control
ln -s ~/claude-control/software-discipline ~/.claude/plugins/software-discipline
```

### Option B: Individual plugins

```bash
git clone https://github.com/miospotdevteam/claude-control.git ~/claude-control
ln -s ~/claude-control/engineering-discipline ~/.claude/plugins/engineering-discipline
ln -s ~/claude-control/persistent-plans ~/.claude/plugins/persistent-plans
```

**Do not install both options at once.** software-discipline includes everything from the individual plugins. Installing both would duplicate the context injection.

### Per-project config

On first session in a project, the plugin auto-detects the stack (language, frameworks, monorepo structure, etc.) and writes a config file to `.claude/software-discipline.local.md`. This makes hooks adapt to any project — no manual configuration needed.

To customize, edit the generated file. It's never overwritten after creation. Add it to `.gitignore` if you don't want it committed.

### Add the CLAUDE.md snippet (recommended)

Add this to your project's `CLAUDE.md` to reinforce the behavior:

```markdown
## Software Discipline

All tasks use the software-discipline plugin. This is the default operating
mode — not optional.

### Plan Mode
- **Before editing code**: write a plan to `.temp/plan-mode/active/<plan-name>/masterPlan.md`
- **After any compaction**: IMMEDIATELY read the active plan — do not wait for user prompt
- **Every 2-3 file edits**: checkpoint — update Progress checklist in the plan on disk
- **After each step**: update the plan file on disk immediately
- **Check plan status**: `bash .temp/plan-mode/scripts/plan-status.sh`
- **Find what to resume**: `bash .temp/plan-mode/scripts/resume.sh`
```

## Hooks

The unified plugin enforces discipline through hooks at every stage of the session lifecycle, not just instructions:

| Event | Hook | What it does |
|---|---|---|
| **SessionStart** | `session-start.sh` | Injects skill context, detects active plans, discovers installed plugins, acquires session lock |
| **PreToolUse** (Edit\|Write) | `enforce-plan.sh` | Blocks code edits if no active plan exists. Bypass with `.temp/plan-mode/.no-plan` for trivial changes |
| **PreToolUse** (Edit\|Write) | `check-api-contracts.sh` | Warns when editing API boundary files — reminds about shared schemas |
| **PreToolUse** (Task) | `inject-subagent-context.sh` | Injects tailored discipline rules into every sub-agent based on its role (research, code-editing, review). Creates shared `discovery.md` for cross-agent findings |
| **PostToolUse** (Edit\|Write) | `auto-complete-plan.sh` | Detects when all plan steps are marked complete and prompts finalization |
| **Stop** | `verify-plan-on-stop.sh` | Blocks stopping if the active plan has pending or in-progress steps |

## Repo Structure

```
claude-control/
├── software-discipline/                     # Unified plugin (recommended)
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── hooks/
│   │   ├── hooks.json                       # Hook lifecycle configuration
│   │   ├── session-start.sh                 # SessionStart: skill injection + plan detection + config auto-detect
│   │   ├── enforce-plan.sh                  # PreToolUse: blocks edits without an active plan
│   │   ├── check-api-contracts.sh           # PreToolUse: config-driven API boundary warnings
│   │   ├── inject-subagent-context.sh       # PreToolUse: injects discipline + stack info into sub-agents
│   │   ├── auto-complete-plan.sh            # PostToolUse: detects plan completion
│   │   ├── verify-plan-on-stop.sh           # Stop: blocks stopping with unfinished plans
│   │   └── lib/
│   │       ├── read-config.py               # Shared config reader (YAML frontmatter → JSON)
│   │       └── detect-stack.py              # Auto-detects project stack from package.json, etc.
│   └── skills/
│       ├── brainstorming/
│       │   └── SKILL.md                     # Collaborative design exploration before implementation
│       ├── software-discipline/
│       │   ├── SKILL.md                     # Layer 1: The conductor (always in context)
│       │   ├── evals/
│       │   │   └── evals.json               # Eval scenarios
│       │   ├── references/
│       │   │   ├── exploration-protocol.md   # Layer 2: 8-question exploration checklist
│       │   │   ├── exploration-guide.md      # Layer 3: Deep exploration techniques
│       │   │   ├── master-plan-format.md     # Enhanced plan template
│       │   │   ├── sub-plan-format.md        # Sub-plan and sweep templates
│       │   │   ├── claude-md-snippet.md      # Recommended CLAUDE.md addition
│       │   │   ├── testing-checklist.md      # Layer 2: Testing discipline
│       │   │   ├── testing-strategy.md       # Layer 3: TDD-lite, test pyramid, test theater
│       │   │   ├── ui-consistency-checklist.md   # Layer 2: Design tokens, components
│       │   │   ├── ui-consistency-guide.md   # Layer 3: Drift detection, visual regression
│       │   │   ├── security-checklist.md     # Layer 2: Auth, input, secrets
│       │   │   ├── security-guide.md         # Layer 3: OWASP, S.E.C.U.R.E., slopsquatting
│       │   │   ├── git-checklist.md          # Layer 2: Commits, branches
│       │   │   ├── linting-checklist.md      # Layer 2: Linter discipline
│       │   │   ├── dependency-checklist.md   # Layer 2: Package management
│       │   │   ├── api-contracts-checklist.md    # Layer 2: Shared schemas, API boundaries
│       │   │   ├── api-contracts-guide.md    # Layer 3: Hono + Zod patterns, migration strategies
│       │   │   └── verification-commands.md  # tsc/lint/test commands by ecosystem
│       │   └── scripts/
│       │       ├── init-plan-dir.sh          # Sets up .temp/plan-mode/
│       │       ├── plan-status.sh            # Shows all plan statuses
│       │       └── resume.sh                 # Finds what to resume
│       ├── engineering-discipline/
│       │   └── SKILL.md                      # Sub-skill: behavioral rules
│       └── persistent-plans/
│           └── SKILL.md                      # Sub-skill: plan management rules
│
├── engineering-discipline/                   # Standalone behavioral plugin
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── hooks/
│   │   ├── hooks.json
│   │   └── session-start.sh
│   └── skills/
│       └── engineering-discipline/
│           ├── SKILL.md
│           ├── evals/
│           │   └── evals.json
│           └── references/
│               └── verification-commands.md
│
└── persistent-plans/                         # Standalone workflow plugin
    ├── .claude-plugin/
    │   └── plugin.json
    ├── hooks/
    │   ├── hooks.json
    │   └── session-start.sh
    └── skills/
        └── persistent-plans/
            ├── SKILL.md
            ├── references/
            │   ├── master-plan-format.md
            │   ├── sub-plan-format.md
            │   └── claude-md-snippet.md
            └── scripts/
                ├── init-plan-dir.sh
                ├── plan-status.sh
                └── resume.sh
```

## Origin Story

These plugins were built iteratively through real-world testing on production codebases. Each rule exists because Claude actually made that specific mistake. The sub-plan triggers, checkpoint frequency, auto-compaction survival logic, and discipline checklists were all calibrated based on actual failures during real tasks.

## Acknowledgments

- The **brainstorming** skill is adapted from [superpowers](https://github.com/obra/superpowers) by Jesse Vincent, licensed under MIT. superpowers is an excellent agentic skills framework — if you want a broader set of development skills beyond engineering discipline, check it out.
