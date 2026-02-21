---
name: software-discipline
description: >
  Unified engineering discipline for ALL coding tasks. Three layers: this file (the conductor), quick-reference checklists, and deep guides. Enforces structured exploration before planning, persistent plans that survive compaction, disciplined execution with blast radius tracking and type safety, and multi-discipline coverage (testing, UI consistency, security, git, linting, dependencies). Use for every task that touches source files — no exceptions, no shortcuts.
---

# Software Discipline

This skill is the conductor. It controls the process and routes to deeper
guidance. Deep content lives in `references/` — this file stays focused on
what to do and when.

**Core principle**: Every shortcut you take now becomes a bug someone else
finds later. Explore, plan, execute carefully, verify.

---

## Step 0: Discover Available Skills

At the start of every session, note which skills are available (the
SessionStart hook provides a skill inventory). When a step calls for
specialized knowledge (testing, frontend design, security review), check
if an installed skill covers it before relying on general knowledge.

**Routing rules** — look for installed skills that match these needs:

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

**Read `references/exploration-protocol.md` and answer all 8 questions.**

The protocol covers: Scope, Entry Points, Consumers, Existing Patterns,
Test Infrastructure, Conventions, Blast Radius, and Confidence Rating.

Exit criterion: confidence is Medium or higher. If Low, keep exploring.

For complex or unfamiliar codebases, also read `references/exploration-guide.md`
for advanced techniques.

### Minimum exploration actions

1. Read the files you plan to modify AND their imports
2. `Grep` for consumers of any file you'll change
3. Read 2-3 sibling files to learn patterns
4. Check CLAUDE.md/README for project conventions
5. Search for existing solutions before implementing from scratch

---

## Step 2: Plan (write to disk before editing code)

**Every task gets a plan file.** Use the template in
`references/master-plan-format.md`. Plans live in
`.temp/plan-mode/active/<plan-name>/masterPlan.md`.

Initialize the plan directory if needed:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/software-discipline/scripts/init-plan-dir.sh
```

### Plan requirements

1. Fill the structured Discovery Summary (all 8 sections from exploration)
2. List Required Skills (which installed skills to invoke at which steps)
3. List Applicable Disciplines (which checklists apply — see discipline list below)
4. Size steps for one context window each
5. Steps touching >10 files or sweep keywords MUST get a sub-plan
   (see `references/sub-plan-format.md`)

### Applicable discipline checklists

Read the relevant checklist BEFORE starting the associated step:

| Discipline | Read when... | File |
|---|---|---|
| Testing | Writing or modifying tests | `references/testing-checklist.md` |
| UI Consistency | Building or modifying UI | `references/ui-consistency-checklist.md` |
| Security | Handling auth, input, secrets | `references/security-checklist.md` |
| Git | Committing or branching | `references/git-checklist.md` |
| Linting | After any code changes | `references/linting-checklist.md` |
| Dependencies | Adding, removing, or updating packages | `references/dependency-checklist.md` |
| Exploration | Before planning any task | `references/exploration-protocol.md` |

Each checklist points to a deep guide for comprehensive coverage.

Exception: the user explicitly says "just do it" or "no plan" for a trivially
obvious single-line change.

---

## Step 3: Execute (the loop)

Follow this loop mechanically:

1. Read masterPlan.md from disk
2. Find the next `[ ] pending` or `[~] in-progress` step
3. Mark it `[~] in-progress` — **write to disk NOW**
4. If the step has a sub-plan, read it and follow its groups/sub-steps
5. Execute the step, applying the core rules below
6. **Checkpoint every 2-3 file edits**: update Progress checklist on disk
7. When done: mark `[x] complete`, write Result, update Completed Summary
8. If all steps complete: move plan folder to `completed/`, report to user
9. Else: loop back to step 1

### The checkpoint question

After every few edits, ask yourself: **"If auto-compaction fired RIGHT NOW,
would my plan file let me resume exactly where I left off?"** If no, update
the plan file before doing anything else.

### Result fields matter

Bad result: "Done."
Good result: "Created apiClient.ts in src/lib/ with typed wrappers for 5
endpoints. Used existing AuthContext for token injection. Updated imports
in Dashboard.tsx, Settings.tsx, Profile.tsx."

---

## Step 4: Verify (every time, no exceptions)

1. **Type checker** — `tsc --noEmit`, `mypy`, `cargo check`, etc.
2. **Linter** — `eslint`, `ruff`, `clippy`, etc.
3. **Tests** — at minimum, tests related to files you changed
4. **Build** — if you changed config or dependencies

See `references/verification-commands.md` for framework-specific commands.
Always check the project's own scripts first (package.json, Makefile).

Before declaring done, re-read the user's original request word by word.
Confirm every requirement is implemented and working. If anything is
unaddressed, finish it or explicitly flag it.

---

## Compaction Survival Protocol

Plans on disk survive compaction. Your memory does not.

### After ANY compaction (including auto-compaction)

1. Check `.temp/plan-mode/active/` for active plans
2. Read the masterPlan.md completely — especially Discovery Summary and
   Completed Summary
3. Find the next `[ ] pending` or `[~] in-progress` step
4. If `[~] in-progress`: check the Progress checklist to see what's done
5. State to the user: "Resuming plan '<title>'. Steps 1-N complete. Picking
   up at Step N+1, starting from <specific progress point>."
6. Continue the execution loop

**Do NOT wait for the user to say "continue".** If there's an active plan,
read it immediately and resume.

Helper scripts:
```bash
bash .temp/plan-mode/scripts/plan-status.sh    # see all plan states
bash .temp/plan-mode/scripts/resume.sh         # find what to pick up
```

---

## Core Rules

### No silent scope cuts — the cardinal rule

If the user asked for 5 things, all 5 must be addressed. If one is blocked,
say so explicitly. NEVER silently drop scope.

What you must never do:
- Implement 3 of 5 features and summarize as "done"
- Skip a step because it's hard and hope nobody notices
- Declare victory when your plan has unchecked items

### No type safety shortcuts

Never use: `any`, `as any`, `v.any()`, unnecessary nullables, `@ts-ignore`
without explanation. If typing is hard, that's a signal the design needs
thought. Exception: framework-inferred types (Convex, tRPC, Drizzle) don't
need redundant annotations.

### Track blast radius on shared code

When modifying shared utilities, types, API signatures, schemas, dependencies,
or config: grep for ALL consumers, read them, verify they still work.

### Install before import

Before using a package: check it exists in package.json (or equivalent).
Before using an env var: verify it's defined and loaded. Don't assume.

### Honest communication

When summarizing: include what you completed, what you skipped and why,
what you're unsure about, and known risks. A summary that only lists
successes is a press release, not a report.

### Respond to feedback with self-audit

When the user points out a mistake: fix it, then search for the same class
of mistake elsewhere in your changes. Report what you found. Don't just say
"You're right!" — investigate and fix the pattern.

---

## Quick Reference: Red Flags

| Doing this... | Do this instead |
|---|---|
| Editing without reading imports/consumers | Read the neighborhood first |
| Adding `as any` to fix a type error | Figure out the correct type |
| Skipping a step because it's hard | Flag it explicitly to the user |
| Declaring "done" without running checks | Run type checker/linter/tests |
| Using a package without checking it's installed | Check package.json first |
| Changing shared code without checking consumers | Grep for all usages |
| Summarizing without mentioning gaps | List what you skipped and why |
| Fixing one bug without checking for more | Self-audit for the pattern |
| Starting multi-step work without a plan | Write the plan first |
| Stopping at step 3 of 7 | Continue to step 4 immediately |
| Thinking "I'll skip this for now" | Do it or flag it — no silent cuts |

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

### Deep Guides (Layer 3)
- `references/testing-strategy.md` — TDD-lite, test pyramid, edge cases, test theater
- `references/ui-consistency-guide.md` — design tokens, component discipline, drift detection
- `references/security-guide.md` — OWASP Top 10, S.E.C.U.R.E. framework, slopsquatting

### Operational
- `references/verification-commands.md` — type checker/linter/test commands by ecosystem
- `scripts/init-plan-dir.sh` — initialize `.temp/plan-mode/` directory
- `scripts/plan-status.sh` — show status of all active plans
- `scripts/resume.sh` — find what to resume after compaction
