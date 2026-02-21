---
name: software-discipline
description: >
  Unified engineering discipline for ALL coding tasks. Three layers: this file (the conductor), quick-reference checklists, and deep guides. Enforces structured exploration before planning, persistent plans that survive compaction, disciplined execution with blast radius tracking and type safety, and multi-discipline coverage (testing, UI consistency, security, git, linting, dependencies). Use for every task that touches source files — no exceptions, no shortcuts.
---

# Software Discipline

This skill is the conductor. It controls the process and routes to deeper
guidance. The actual rules live in two companion skills that are always
injected alongside this one:

- **engineering-discipline** — The behavioral layer: explore before editing,
  track blast radius, no type shortcuts, verify work, no silent scope cuts.
- **persistent-plans** — The structural layer: plan files on disk, the
  execution loop, checkpoints, sub-plans, compaction survival.

**You must follow both companion skills for every coding task.**

---

## Step 0: Discover Available Skills

At the start of every session, note which skills are available (the
SessionStart hook provides a skill inventory). When a step calls for
specialized knowledge (testing, frontend design, security review), check
if an installed skill covers it before relying on general knowledge.

### External skill routing

Look for installed skills that match these needs:

| When you need... | Look for skills about... |
|---|---|
| Test strategy, TDD | "testing", "TDD", "test-driven" |
| Frontend UI work | "frontend design", "UI", "components" |
| Security review | "security", "authentication", "auth" |
| Code review | "code review", "review" |
| Debugging | "debugging", "systematic debugging" |
| PR/commit workflow | "commit", "PR", "git" |

If no specialized skill exists, use the checklists and guides in `references/`.

---

## Step 1: Explore (mandatory before any edit)

Shallow exploration is the #1 cause of failed plans — every minute exploring
saves five minutes fixing.

Follow **engineering-discipline Phase 1** (Orient Before You Touch Anything).

Additionally, read `references/exploration-protocol.md` and answer all 8
questions. Exit criterion: confidence is Medium or higher. If Low, keep
exploring.

### Minimum exploration actions

1. Read the files you plan to modify AND their imports
2. `Grep` for consumers of any file you'll change
3. Read 2-3 sibling files to learn patterns
4. Check CLAUDE.md/README for project conventions
5. Search for existing solutions before implementing from scratch

For complex or unfamiliar codebases, also read
`references/exploration-guide.md`.

---

## Step 2: Plan (write to disk before editing code)

Follow **persistent-plans Phase 1** (Create the Plan).

Use the template in `references/master-plan-format.md`. Plans live in
`.temp/plan-mode/active/<plan-name>/masterPlan.md`.

Initialize the plan directory if needed:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/software-discipline/scripts/init-plan-dir.sh
```

### Discipline checklists

Read the relevant checklist BEFORE starting the associated step:

| Discipline | Read when... | File |
|---|---|---|
| Testing | Writing or modifying tests | `references/testing-checklist.md` |
| UI Consistency | Building or modifying UI | `references/ui-consistency-checklist.md` |
| Security | Handling auth, input, secrets | `references/security-checklist.md` |
| Git | Committing or branching | `references/git-checklist.md` |
| Linting | After any code changes | `references/linting-checklist.md` |
| Dependencies | Adding, removing, or updating packages | `references/dependency-checklist.md` |
| API Contracts | Touching Hono route handlers, API endpoints, or client API calls | `references/api-contracts-checklist.md` |
| Exploration | Before planning any task | `references/exploration-protocol.md` |

Each checklist points to a deep guide for comprehensive coverage.

Exception: the user explicitly says "just do it" or "no plan" for a trivially
obvious single-line change.

---

## Step 3: Execute (the loop)

Follow **persistent-plans Phase 2** (Execute the Plan) for the execution
loop, checkpointing, and result tracking.

Follow **engineering-discipline Phase 2** (Make Changes Carefully) for the
rules applied during execution.

### Dispatching sub-agents

When a step benefits from parallel work (audits, multi-area exploration,
independent file groups), choose the right dispatch mode:

**Foreground parallel** (default):
Use when results inform your next steps or have cross-cutting concerns.
All agents run in parallel, you see all results before proceeding. Use
for: audits, exploration, reviews, any task where one finding might
affect another agent's scope.

**Background** (fire-and-forget only):
Use only when you have genuinely independent work to continue in the
main thread. You must poll with `TaskOutput` later — no automatic
cross-pollination. Use for: running builds/tests while continuing edits.

**Rule of thumb**: if you'd want to read Agent A's results before acting
on Agent B's results, use foreground. Background agents are isolated by
default.

### Shared discovery (cross-agent communication)

For parallel tasks where agents benefit from seeing each other's findings
(audits, multi-area exploration, large codebase research), agents share a
single discovery file:

**Location**: `.temp/plan-mode/active/<plan-name>/discovery.md`

The file is **auto-created** by the `inject-subagent-context` hook when
a sub-agent is dispatched and an active plan exists. No manual setup needed.

**Writing** — use Bash append (`>>`), never `Edit`. Multiple agents write
concurrently, and append is atomic at the OS level:
```bash
printf '\n## [your-focus-area]\n- **[severity]** `file:line` — finding (evidence: ...)\n' >> discovery.md
```

**Reading** — read the file periodically to see other agents' findings,
but treat them as **informational context only**:
- Other findings may be wrong, incomplete, or irrelevant to your scope
- Do NOT change your investigation direction based on them
- Only note a cross-reference if you independently confirm a connection
- Be thorough and precise in your own findings — include file:line and
  evidence

After all agents complete, read the consolidated `discovery.md` to
synthesize results.

---

## Step 4: Verify (every time, no exceptions)

Follow **engineering-discipline Phase 3** (Verify Before Declaring Done).

See `references/verification-commands.md` for framework-specific commands.
Always check the project's own scripts first (package.json, Makefile).

Before declaring done, re-read the user's original request word by word.
Confirm every requirement is implemented and working. If anything is
unaddressed, finish it or explicitly flag it.

---

## Compaction Survival Protocol

Follow **persistent-plans Phase 3** (Resumption After Compaction).

Helper scripts:
```bash
bash .temp/plan-mode/scripts/plan-status.sh    # see all plan states
bash .temp/plan-mode/scripts/resume.sh         # find what to pick up
```

---

## Enforcement Hooks

This plugin enforces discipline through hooks, not just instructions:

- **PreToolUse(Edit|Write)**: Blocks code edits if no active plan exists
  in `.temp/plan-mode/active/`. Allows edits to `.temp/` (plan files).
  Bypass for trivial changes: create `.temp/plan-mode/.no-plan`.
- **PreToolUse(Task)**: Automatically injects engineering discipline into
  every sub-agent prompt. Sub-agents receive the core rules (no scope cuts,
  no type shortcuts, blast radius, verification) plus active plan path.
- **Stop**: Blocks Claude from stopping if the active plan has unchecked
  items. Forces explicit completion, status update, or user communication.

---

## Reference Files

All paths relative to `${CLAUDE_PLUGIN_ROOT}/skills/software-discipline/`:

### Process & Templates
- `references/exploration-protocol.md` — 8-question exploration checklist
- `references/exploration-guide.md` — deep exploration techniques
- `references/master-plan-format.md` — masterPlan.md template with structured discovery
- `references/sub-plan-format.md` — sub-plan and sweep templates
- `references/claude-md-snippet.md` — recommended CLAUDE.md addition

### Discipline Checklists (Layer 2)
- `references/testing-checklist.md` — before/during/after testing
- `references/ui-consistency-checklist.md` — design tokens, components, visual consistency
- `references/security-checklist.md` — auth, input validation, secrets
- `references/git-checklist.md` — commits, branches, messages
- `references/linting-checklist.md` — linter and formatter discipline
- `references/dependency-checklist.md` — package management and verification
- `references/api-contracts-checklist.md` — API boundary discipline

### Deep Guides (Layer 3)
- `references/testing-strategy.md` — TDD-lite, test pyramid, edge cases, test theater
- `references/ui-consistency-guide.md` — design tokens, component discipline, drift detection
- `references/security-guide.md` — OWASP Top 10, S.E.C.U.R.E. framework, slopsquatting

### Operational
- `references/verification-commands.md` — type checker/linter/test commands by ecosystem
- `scripts/init-plan-dir.sh` — initialize `.temp/plan-mode/` directory
- `scripts/plan-status.sh` — show status of all active plans
- `scripts/resume.sh` — find what to resume after compaction
