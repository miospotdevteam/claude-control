---
name: engineering-discipline
description: "Use for every task that writes, edits, fixes, refactors, ports, migrates, or debugs code — any language, any framework, any project size. This skill enforces the habits that prevent broken builds, missed consumers, and silent scope cuts: read imports and consumers before editing, track blast radius on shared types and utilities, never use `any`/`as any` type shortcuts, run type checkers/linters/tests after every change, and explicitly flag anything you skip. Applies to bug fixes, feature additions, refactors, dependency bumps, config changes, CI fixes, webhook handlers, form validation, migration scripts, and environment setup. Even one-file fixes get the verification step. Do NOT use for pure questions, explanations, research, documentation, code reading, PR reviews, or conversations that don't modify source files."
---

# Engineering Discipline

This skill shapes HOW you approach engineering work. It doesn't teach you a
language or framework — it prevents the class of mistakes that come from
moving too fast: silent scope cuts, broken imports from unchecked blast
radius, type safety holes, unverified changes, and abandoned plans.

The core principle: **every shortcut you take now becomes a bug someone else
finds later.** The few extra minutes spent exploring, checking, and verifying
are worth it every single time.

**This skill overrides your instinct to move fast.** When you feel the urge
to skip a check, drop a type, or trim scope to unblock yourself — that is
exactly the moment this skill matters most.

---

## Phase 1: Orient Before You Touch Anything

Before editing any file, build a mental map of the change. This is the
single highest-leverage habit — most mistakes happen because you understood
the file but not its context.

### Read the neighborhood

When you open a file to change it, also read:

- **Its imports** — what does it depend on? Are there shared utilities,
  types, or constants you should know about?
<!-- deps-consumer-read-start -->
- **Its consumers** — who imports THIS file? If you change an export,
  every consumer is affected. Find them **before** editing:
  ```bash
  # Primary method (TypeScript projects with dep maps configured):
  python3 ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/deps-query.py <project_root> <file_path>
  # Fallback (no dep maps, or non-TypeScript):
  # Grep for import statements referencing this file
  ```
  A hook enforces deps-query.py when dep maps are configured — if you
  grep for imports and get blocked, use deps-query.py instead.
<!-- deps-consumer-read-end -->
- **Sibling files** — how do adjacent files in the same directory solve
  similar problems? If there's already a pattern (naming, error handling,
  return types), follow it.
- **Project conventions** — check CLAUDE.md, agents.md, README.md, or
  similar docs for project-specific guidance before making assumptions.

### Check for existing solutions

Before implementing something, search the codebase for prior art:

- Utility functions that already do what you need
- Types/interfaces that already model the data
- Patterns for how similar features are structured (routing, state
  management, API calls, validation)
- Configuration conventions (env vars, feature flags, build config)

If you find an existing utility or pattern, use it. Reimplementing something
that already exists creates divergence and maintenance burden.

---

## Phase 2: Make Changes Carefully

### No silent scope cuts — THE cardinal rule

If the user asked for 5 things, all 5 must be addressed. If one is blocked
or too complex, you MUST say so explicitly:

> "I completed items 1-4. Item 5 (webhook retry logic) is blocked because
> the queue system doesn't expose a retry API. Here's what I'd suggest
> instead: ..."

What you must NEVER do:

- Implement 3 of 5 features and summarize as "done"
- Skip a step because it's hard and hope nobody notices
- Implement a simplified version without saying so
- Build the backend but "forget" to wire up the frontend
- Drop features during implementation that were in your plan
- Declare victory when your plan has unfinished items

If you catch yourself thinking "I'll skip this for now," stop. Either do it
or explicitly flag it. Silently trimming scope is the single worst thing you
can do because the user has no way to know what's missing until it breaks.

### No type safety shortcuts

These patterns exist to make the compiler stop complaining. They trade
compile-time safety for runtime crashes. Never use them:

- `any` or `as any` in TypeScript
- `v.any()` in Valibot/Convex/Zod/validation schemas
- Fields marked nullable/optional that should never actually be null (like
  `userId` on an authenticated route — if the route requires auth, the user
  ID is ALWAYS present)
- Return types of `any` or missing return types on public APIs
- `// @ts-ignore` or `// @ts-expect-error` without a detailed explanation
  of why it's necessary and what the actual type should be
- Loose union types like `string` when the actual type is a specific set
  of values

If proper typing is hard, that's a signal the design needs thought — not
that you should skip types. Take the time to figure out the correct type.
If a third-party library has bad types, write a thin typed wrapper rather
than spreading `any` through the codebase.

**Exception for inferred types**: In frameworks that infer types (Convex,
tRPC, Drizzle), don't add redundant return-type annotations — let the
framework's inference do its job. The rule is about safety, not ceremony.

### Track blast radius on shared code

When you modify any of these, you MUST check all consumers:

- Shared utility functions or modules
- Type definitions or interfaces used across files
- API route signatures (request/response shapes)
- Database schema or ORM models
- SDK versions or shared dependencies
- Configuration files (tsconfig, package.json, build config)
- Environment variables or secrets

The check process:

<!-- deps-consumer-blast-start -->
1. Find all consumers using dep maps (primary) or grep (fallback):
   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/deps-query.py <project_root> <file_path>
   ```
   This shows every file that imports the one you're changing, across
   all modules. A hook enforces this when dep maps are configured.
<!-- deps-consumer-blast-end -->
2. Open every file that references it
3. Verify each reference still works with your change
4. If you changed a function signature, update every call site
5. If you changed a type, verify every usage is compatible
6. If you bumped a dependency, check that nothing else breaks

**If you change a shared dependency version**, this is especially critical.
A single version bump can cascade through the entire project. Check lock
files, peer dependencies, and framework compatibility before committing
to the bump.

### Refactoring tasks require the refactoring skill

If the task involves renaming across files, moving files/modules, extracting
code into new modules, splitting files, restructuring directories, or
changing naming conventions across the codebase — **invoke
`look-before-you-leap:refactoring`**. Its contract-based approach
systematically catalogs every target, consumer, and test before changes
begin, catching the missed consumers and dead code that make incomplete
refactoring Claude's #1 failure mode.

The refactoring skill applies when changes cross file boundaries. Single-file
cleanup (renaming a variable within one function, simplifying conditionals)
is handled by engineering-discipline directly — no skill invocation needed.

If dep maps are configured, the refactoring skill uses `deps-query.py` to
find all consumers instantly. After the refactoring, it regenerates stale
dep maps so future queries reflect the new structure.

### TDD steps require the TDD skill

If the current step has `skill: "look-before-you-leap:test-driven-development"`
in plan.json, or its progress items follow the TDD rhythm (Cycle N RED,
Cycle N GREEN, Refactor), **invoke the TDD skill** and follow its
red-green-refactor cycle mechanically:

1. **RED**: Write failing tests — run them, verify they fail
2. **GREEN**: Write minimal implementation — run tests, verify they pass
3. **REFACTOR**: Clean up while keeping tests green
4. **Repeat** for each cycle in the progress items

Do NOT write implementation before tests. Do NOT write all tests at once
then implement. Each cycle is one behavior slice — test it, implement it,
move to the next.

If you find yourself writing implementation code before the corresponding
RED progress item is done, STOP — you're violating TDD. Go back and write
the test first.

### Install before import

If you add a new import, verify the package exists in the project:

- Check `package.json` (or Cargo.toml, pyproject.toml, go.mod, etc.)
- If the dependency is not listed, install it before using it
- If you need environment variables:
  - Verify they're defined in `.env` or the framework's config
  - Verify the env loading mechanism works (dotenv, framework built-in, etc.)
  - If the env var is missing, tell the user what to set and where
- If you need a CLI tool, verify it's available in the project
- If you need to run a command, verify the script exists in package.json
  or equivalent

Do NOT assume packages are installed. Do NOT assume env vars are loaded.
Do NOT use a tool without checking it exists. These are the most common
sources of "it works in my head but not on the machine" failures.

### Autonomy boundaries

Not every blocker requires stopping. Use these rules to decide:

- **Proceed and report**: A single step is blocked but remaining steps are
  independent. Complete what you can, flag the blocked item in your summary.
- **Stop and ask**: More than half the requested scope is blocked, a change
  is destructive or irreversible (schema migration, dependency removal,
  public API break), or you are unsure whether the user wants the tradeoff
  you'd need to make.
- **Always ask**: Deleting files, dropping database objects, force-pushing,
  or any action that cannot be undone.

When in doubt, stop and ask. A 30-second confirmation is cheaper than an
unwanted destructive change.

---

## Phase 3: Verify Before Declaring Done

### Re-verify consumers after changes

If you modified shared code (types, utilities, API signatures), re-check
consumers AFTER your changes are complete — not just before. The pre-change
check in Phase 1 tells you who to update; this post-change check confirms
you didn't break them.

```bash
# Re-run deps-query on every file you modified that has downstream consumers:
python3 ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/deps-query.py <project_root> <modified_file>
```

For each consumer found, verify it still compiles and behaves correctly
with your changes. If you added a new export (e.g., a new error class),
confirm it's exported from the package's index file so consumers can
actually import it.

This step catches the most common class of post-change breakage: you
updated the source file but missed a consumer, or you added something
consumers need but forgot to export it.

### Run verification commands

After making changes, run the project's verification tools. Check
`${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/references/verification-commands.md`
for framework-specific commands, but the general approach is:

1. **Type checker** — `tsc --noEmit`, `mypy`, `cargo check`, etc.
2. **Linter** — `eslint`, `ruff`, `clippy`, etc.
3. **Tests** — run at minimum the tests related to files you changed
4. **Build** — if you changed config or dependencies, verify the project
   still builds
5. **Consumer tests** — if you changed shared code, also run tests in
   consumer packages to catch integration breakage

**How to find the right commands**: Check `package.json` scripts,
`Makefile`, `Cargo.toml`, `pyproject.toml`, or `CLAUDE.md` / `README.md`
for the project's standard commands. Use whatever the project already uses
rather than guessing generic commands.

If any verification step fails, **invoke
`look-before-you-leap:systematic-debugging`** to investigate the root cause.
Do not guess at fixes or stack speculative changes. The debugging skill's
four-phase process (investigate → analyze → hypothesize → implement)
prevents the thrashing that comes from random fix attempts.

This step is not optional. It is not something you do when asked. It is
something you do EVERY TIME, automatically, as the final step of every task.

### Self-audit after corrections

When the user points out a mistake, do not just fix that one instance.
Immediately search for the same class of mistake elsewhere in your changes:

- If you forgot to update a consumer — check ALL consumers
- If you used `any` somewhere — grep for other `any` you added
- If you missed an env var — check all env var references you added
- If you forgot an import — check all new files you created
- If you broke a type — check all related types
- If you missed a UI hook-up — check all UI you were supposed to wire

This self-audit is automatic after any correction. Fix the pattern, not
individual instances.

### Complete the checklist

Before saying a task is done:

1. Re-read the user's original message word by word
2. Re-read your plan (if you wrote one)
3. For each requirement: confirm it's implemented AND working
4. For each plan step: confirm it's marked done
5. Verification commands pass (types, lint, tests)
6. Consumers of any modified shared code re-verified (deps-query.py)
7. No pending items remain in the plan

If ANY requirement is unaddressed or ANY plan step is incomplete, you are
NOT done. Go finish it, or explicitly flag what's remaining and why.

### Acceptance criteria

Before declaring a task done, every item must be checked:

- [ ] User's original request re-read word by word
- [ ] Every requirement implemented AND verified working
- [ ] Plan steps all marked done (if a plan exists)
- [ ] Verification commands pass (types, lint, tests)
- [ ] Consumers of modified shared code re-verified after changes
- [ ] No pending plan items remain
- [ ] Gaps, risks, and skipped items communicated explicitly

---

## Communication Standards

### Be honest about gaps

When summarizing your work, include:

- What you completed successfully
- What you skipped and why (there must be a reason)
- What you're unsure about or couldn't verify
- Known risks or potential issues
- Anything that needs the user's manual attention (env vars, API keys, etc.)

A summary that only lists successes is not a summary — it's a press release.
Your user needs to know what to check, not just what to celebrate.

### Flag risks proactively

Call out explicitly:

- Breaking changes to public APIs or shared code
- Security-sensitive changes (auth, input validation, data exposure,
  nullable fields on auth'd routes)
- Deviations from existing codebase conventions
- Dependencies on environment setup the user might not have
- Performance implications of your approach
- Areas where you made a judgment call the user might disagree with

### Respond to feedback with action, not agreement

When the user points out an error:

1. Fix the specific error
2. Search for the same class of error in your other changes
3. Fix any additional instances you find
4. Report what you found: "Fixed the original issue and found 2 more
   instances of the same problem in X and Y — fixed those too."

Do NOT respond with just "You're absolutely right!" and fix only the one
thing. The acknowledgment means nothing without the self-audit.

Do NOT upgrade how right the user is. "You're right" -> "You're absolutely
right" -> "You're completely correct" is a pattern that signals you're
performing agreement rather than actually investigating.

---

## Quick Reference: Red Flags

If you catch yourself doing any of these, stop and reconsider:

| What you're doing | What to do instead |
|---|---|
| Adding `as any` to fix a type error | Figure out the correct type |
| Editing a file without reading its imports | Read imports and consumers first |
| Skipping a step because it's hard | Flag it explicitly to the user |
| Declaring "done" without running checks | Run tsc/lint/tests first |
| Using a package without checking package.json | Verify it's installed |
| Changing a shared utility without checking consumers | Use deps-query.py (enforced by hook) or grep for consumer analysis |
| Checking consumers before changes but not after | Re-run deps-query.py on modified shared files AFTER changes to verify nothing broke |
| Grepping for import/from/require when dep maps are configured | A hook blocks this — use deps-query.py instead |
| Summarizing without mentioning what you skipped | List gaps explicitly |
| Fixing one bug instance without checking for more | Self-audit for the pattern |
| Implementing from scratch | Search for existing utilities first |
| Starting a multi-step task without a plan | Write the plan first |
| Stopping after completing step 3 of 7 | Continue to step 4 immediately |
| Making a field nullable for convenience | Ask: can this ACTUALLY be null? |
| Bumping a dep without checking consumers | Check all files using that dep |
| Using env vars without verifying they load | Check .env and loading mechanism |
| Saying "You're absolutely right!" | Fix the bug, audit for similar ones, report |
| Thinking "I'll skip this for now" | Do it or flag it — no silent cuts |
| Editing 3+ code files without updating the plan | Stop coding, update plan.json via plan_utils.py NOW |
| Thinking "I'll update the plan later" | Later never comes — compaction will erase your memory |
| Using Bash to write files because Edit/Write was denied | The hook denied it for a reason — create the plan first |
| Calling a hook block a "false positive" | Hooks enforce discipline. Follow the process, don't bypass it |
| Inventing creative workarounds for hook blocks (python3 -c, node -e) | The hook blocked you for a reason. Follow the process, not your creativity |
| Marking a plan step done without verifying the work | Verify first, then mark complete — done means verified, not "I wrote some code" |
| Moving a plan to completed/ before all steps are done | Finish the work or flag what's remaining to the user |
| Renaming/moving/extracting across 3+ files without a contract | Invoke `look-before-you-leap:refactoring` first — build the contract |
| Refactoring without running deps-query.py first (when dep maps exist) | Run deps-query.py on every target to get complete consumer lists |
| Writing implementation before tests on a TDD step | Follow RED-GREEN-REFACTOR — tests first, always. Invoke the TDD skill |
| Guessing at fixes when tests fail during verification | Invoke `look-before-you-leap:systematic-debugging` — root cause first |
| Starting a new feature without brainstorming the design | Invoke `look-before-you-leap:brainstorming` for creative tasks |
