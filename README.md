# claude-control

Two Claude Code plugins that make Opus 4.6 behave like a disciplined engineer instead of a fast-but-sloppy one.

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

If you've used Opus for real work, you've hit all of these.

## The Solution

Two plugins that close the gap. Install both — they're designed to work together.

### engineering-discipline

A behavioral override that forces Opus to be thorough. It shapes *how* work gets done:

- **Explore before editing** — read imports, consumers, sibling files, and project conventions before touching anything
- **Check for existing patterns** — search the codebase before implementing from scratch
- **No silent scope cuts** — do it or explicitly flag it. Silently trimming scope is the cardinal sin
- **No type safety shortcuts** — no `any`, no `as any`, no unnecessary nullables, no `v.any()` in schemas
- **Track blast radius** — grep for all consumers before modifying shared code, types, or dependencies
- **Install before import** — verify packages exist in package.json before using them
- **Run verification automatically** — tsc, lint, and tests after every task, every time
- **Self-audit after corrections** — when the user points out a mistake, search for the same class of mistake elsewhere. Fix the pattern, not one instance

### persistent-plans

A workflow system that writes every plan to disk so nothing is lost to context compaction:

- **Every task starts with a plan** written to `.temp/plan-mode/active/<plan-name>/masterPlan.md`
- **Plans have steps with progress checklists** that get updated every 2-3 file edits
- **Large steps get sub-plans** — triggered by objective criteria: >10 files, sweep keywords, >5 independent sub-tasks
- **Auto-compaction survival** — a SessionStart hook detects the active plan and injects it into context automatically
- **Seamless resumption** — Opus reads the plan, sees exactly where it left off (down to which files within a step), and continues
- **Active/completed organization** — active plans live in `active/`, completed plans are automatically moved to `completed/`
- **Helper scripts included** — `plan-status.sh` to see all plan states (use `--all` for completed), `resume.sh` to find what to pick up

### How They Complement Each Other

| Phase | persistent-plans | engineering-discipline |
|---|---|---|
| Orient | Plan file creation, discovery summary | Codebase exploration, reading neighborhoods |
| Execute | Execution loop, disk writes, checkpoints, sub-plans | Blast radius checks, type safety, no scope cuts |
| Verify | Plan completion tracking, result logging | Type checker, linter, tests |
| Resume | Read plan from disk, check Progress, continue | Self-audit for error patterns |

persistent-plans structures the **work**. engineering-discipline ensures the work is done **correctly**. Both are always active.

## Origin Story

These plugins were built iteratively through real-world testing on production codebases. Each rule exists because Opus actually made that specific mistake. The sub-plan triggers, checkpoint frequency, and auto-compaction survival logic were all calibrated based on actual failures during real tasks.

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/miospotdevteam/claude-control.git ~/claude-control
```

### 2. Symlink both plugins to your Claude Code plugins directory

```bash
ln -s ~/claude-control/engineering-discipline ~/.claude/plugins/engineering-discipline
ln -s ~/claude-control/persistent-plans ~/.claude/plugins/persistent-plans
```

Both plugins should be installed together for the full effect. They're designed to complement each other — engineering-discipline without persistent-plans loses work on compaction; persistent-plans without engineering-discipline structures sloppy work.

### 3. Add the CLAUDE.md snippet (recommended)

Add this to your project's `CLAUDE.md` to reinforce plan-mode behavior:

```markdown
## Plan Mode

All tasks use persistent plans in `.temp/plan-mode/`. This is the default
operating mode — not optional.

- **Before editing code**: write a plan to `.temp/plan-mode/active/<plan-name>/masterPlan.md`
- **After any compaction**: IMMEDIATELY read the active plan — do not wait for user prompt
- **Every 2-3 file edits**: checkpoint — update Progress checklist in the plan on disk
- **After each step**: update the plan file on disk immediately
- **Check plan status**: `bash .temp/plan-mode/scripts/plan-status.sh`
- **Find what to resume**: `bash .temp/plan-mode/scripts/resume.sh`
- **Steps with >10 files or sweep keywords**: MUST get a sub-plan with Groups
- **Always ask**: "If compaction fired right now, could I resume from the plan file?"
```

## Repo Structure

```
claude-control/
├── engineering-discipline/
│   ├── .claude-plugin/
│   │   └── plugin.json                  # Plugin manifest
│   ├── hooks/
│   │   ├── hooks.json                   # SessionStart hook config
│   │   └── session-start.sh             # Injects skill into every session
│   └── skills/
│       └── engineering-discipline/
│           ├── SKILL.md                  # The core behavioral rules
│           ├── evals/
│           │   └── evals.json            # Test scenarios for the skill
│           └── references/
│               └── verification-commands.md  # tsc/lint/test commands by ecosystem
│
└── persistent-plans/
    ├── .claude-plugin/
    │   └── plugin.json                  # Plugin manifest
    ├── hooks/
    │   ├── hooks.json                   # SessionStart hook config
    │   └── session-start.sh             # Detects active plans, injects into context
    └── skills/
        └── persistent-plans/
            ├── SKILL.md                  # Plan system rules and execution loop
            ├── references/
            │   ├── master-plan-format.md  # masterPlan.md template
            │   ├── sub-plan-format.md     # Sub-plan and sweep templates
            │   └── claude-md-snippet.md   # Recommended CLAUDE.md addition
            └── scripts/
                ├── init-plan-dir.sh       # Sets up .temp/plan-mode/ with .gitignore
                ├── plan-status.sh         # Shows status of all active plans
                └── resume.sh              # Finds what to resume after compaction
```

### What each piece does

**Plugin manifests** (`plugin.json`) — Register each plugin with Claude Code.

**SessionStart hooks** — Run on every session start, resume, compact, and clear. The engineering-discipline hook injects the full skill content into context. The persistent-plans hook does the same *and* checks for active plans on disk — if one exists, it injects the plan status so Opus knows to resume immediately.

**SKILL.md files** — The core instructions. engineering-discipline defines the behavioral rules (explore, verify, no shortcuts). persistent-plans defines the workflow system (plan files, execution loop, checkpoints, resumption protocol).

**References** — Templates and lookup tables. The master plan and sub-plan format files are exact templates Opus copies when creating plans. The verification commands reference covers tsc/lint/test commands across Node.js, Python, Rust, and Go ecosystems.

**Scripts** — Operational helpers that get copied into each project's `.temp/plan-mode/scripts/` directory. `plan-status.sh` shows a dashboard of all plans and their step statuses (use `--all` to include completed plans). `resume.sh` finds the most recently active plan and shows exactly where to pick up. Both work on macOS and Linux. Plans are organized into `active/` and `completed/` subdirectories under `.temp/plan-mode/`.

**Evals** (`evals.json`) — Test scenarios for verifying the engineering-discipline skill works correctly. Covers blast radius checking, scope tracking, and type safety enforcement.
