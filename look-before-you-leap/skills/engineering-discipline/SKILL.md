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
  python3 ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/deps-query.py <project_root> "<file_path>"
  # Fallback (no dep maps, or non-TypeScript):
  # Grep for import statements referencing this file
  ```
  A hook enforces deps-query.py when dep maps are configured — if you
  grep for imports and get blocked, use deps-query.py instead.
<!-- deps-consumer-read-end -->
- **Sibling files** — how do adjacent files in the same directory solve
  similar problems? If there's already a pattern (naming, error handling,
  return types), follow it.
- **State producers / message emitters** — if your change depends on a
  state value, derived state, navigation mode, or postMessage event, list
  EVERY code path that can produce it before editing. Do not assume the
  click handler you are reading is the only producer. Trace wizard buttons,
  URL initialization, effects, imperative setters, and iframe/script
  emitters. Before writing any event listener, message handler, postMessage
  listener, webhook handler, or callback: read the code that SENDS the
  event/message. Verify: what triggers it, what payload it sends, under
  what conditions it fires.
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

### Never cache facts about code

Memory (the auto-memory system) should only store **procedural rules** —
how to work. Never store **declarative facts** about code — what the code
looks like, what fields an API returns, how many locales a project has,
what a type contains.

Facts go stale. Code changes between sessions. If you memorize "the API
returns `uploadedKey`" and the field gets renamed next week, your memory
becomes a source of bugs instead of help.

**DO store** (procedural):
- "Always read the API handler before typing response shapes"
- "This project uses dep maps — run deps-query.py, not grep"
- "User prefers bundled PRs for refactors"

**DO NOT store** (declarative):
- "Project has 6 locales"
- "API returns `{ settings, uploadedKey }`"
- "MenuPublishSettings type has a `slugStatus` field"
- "The publish flow gates on `slugStatus === 'available'`"

CLAUDE.md per project is for current project state, maintained by reading
the codebase. Memory is for behavioral rules that transcend any single
codebase state.

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
   python3 ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/deps-query.py <project_root> "<file_path>"
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

### No swallowed errors

Error handling that hides failures is worse than no error handling at all.
Never write these patterns:

- `.catch(() => {})` or `.catch(() => null)` — swallows the error and
  continues as if nothing happened. If the operation matters enough to
  call, its failure matters enough to handle.
- Broad `try/catch` around multi-step operations that resolves
  successfully on failure — a single failed step aborts the rest, but
  the caller never knows. Catch at the narrowest scope and either
  rethrow, log meaningfully, or degrade explicitly.
- Fire-and-forget API calls where the result determines correctness
  (e.g., a DELETE that must succeed for the UI to be consistent) —
  if the response matters, check it.

The pattern to watch for: code that **looks** like it handles errors but
actually just makes them invisible. A `.catch` that returns a fallback
the consumer can't distinguish from success is not error handling — it's
error hiding.

**What to do instead:**
- If the error is recoverable: handle it explicitly and make the
  recovery visible (log, UI feedback, retry with backoff)
- If the error is not recoverable: let it propagate so the caller
  can decide what to do
- If you genuinely don't care about the result: add a comment
  explaining WHY the failure is safe to ignore (e.g., "best-effort
  analytics ping — failure doesn't affect user flow")

### New endpoints need tests and docs

When you add a new API endpoint (route, handler, RPC method), it MUST
land with:

1. **At least one integration test** — happy-path coverage at minimum.
   Boundary/empty-state coverage strongly preferred. An endpoint without
   a test is an endpoint that will silently break on the next refactor.
2. **Project documentation update** — if the project maintains an API
   inventory (e.g., `project-structure/api.md`, OpenAPI spec, route
   registry), update it in the same step. This is not a follow-up task —
   it's part of adding the endpoint.

Do NOT defer either of these. "I'll add tests later" means "these tests
will never exist." The plan step that adds the endpoint must include both
the test and the doc update as progress items.

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

### Read API handlers before typing response shapes

Before writing any typed API call — a fetch wrapper, a hook that reads a
response, a client method that destructures a result — **grep for the
endpoint path and read the return statement in the handler**. Never guess
what an API returns based on what you think it should return.

The check:

1. Find the route handler: `Grep` for the endpoint path (e.g., `/api/settings`)
2. Read the handler's return statement — what fields does it actually send?
3. Type your client code to match the ACTUAL response, not your assumption

This prevents the class of bug where you type a response as `{ heroImage }`
but the API actually returns `{ settings, uploadedKey }`. These bugs are
invisible in the UI until the user saves and loses data.

### Diff against source when reimplementing behavior

When a new component, hook, or handler reimplements behavior that already
exists elsewhere in the codebase (e.g., a new page that replaces an old
one, a unified flow that wraps existing operations), **read the source
you're replacing and verify parity**:

1. Open the existing implementation and keep it open while you implement
2. List what it does: data sources, mappings, defaults/fallbacks, validation
   rules, error handling, edge cases, emitted messages, save paths, and
   precondition checks
3. Verify your new implementation covers each item line by line
4. Explicitly compare source-of-truth fields (for example template vs palette,
   page config vs menu config) instead of assuming one pattern implies the rest
5. If you intentionally omit something, document why before verification
6. Before marking the progress item done, write a short parity checklist in
   your scratch summary so the comparison is auditable after compaction

The pattern to watch for: you read the old code during exploration, then
write the new code from memory hours later. Memory drifts. The old code
uses `slugStatus === "available"` as a gate; you write `slug.length > 0`.
The old code strips leading/trailing hyphens from slugs; you only strip
invalid characters. Always diff — never rely on recall.

### Trace the save path for every editable field

After writing any UI with mutable state (forms, inline editing, settings
panels), verify that **every editable field has a complete path from UI
change → state update → API mutation → persistence**:

1. List every field the user can edit in the UI
2. For each field, trace: onChange handler → state variable → mutation
   call → API endpoint → database write
3. If any field has no save path, it's a data-loss bug — the user edits,
   sees the change reflected, then loses everything on navigation

This is the highest-damage class of UI bug because it's invisible during
development. The UI looks correct. The state updates. But the mutation
never fires, so the next page load shows the old data. Check every field,
every time.

### Match existing operation preconditions when wrapping

When building a unified flow that calls existing operations (e.g., a
"publish all" button that triggers individual publish operations), **read
each operation's handler and replicate its precondition checks**:

1. For each operation your flow will trigger, read its handler
2. List its preconditions (auth checks, status gates, validation)
3. Replicate those checks in your unified flow's readiness logic
4. If the existing handler checks `slugStatus === "available"`, your
   wrapper must check the same — not a weaker version

The failure mode: you build a unified publish flow that only checks
`isPro && !isDraft && slug.length > 0`, but the existing publish handler
gates on `slugStatus === "available"` (which requires async validation).
Your flow lets users publish with invalid slugs because you invented
simpler preconditions instead of reading the real ones.

### Extract a deliverables checklist before coding

Before writing code for any step, **extract every deliverable from the
step's description and acceptance criteria into a numbered checklist**.
Write it down — in the plan notes, in a comment, anywhere persistent.
Then verify each item before marking the step done.

The process:

1. Re-read the step description word by word
2. List every concrete deliverable (not just the main feature — also
   supporting items like i18n keys, adapted labels, documentation)
3. After coding, walk through the checklist item by item
4. If any item is missing, implement it before declaring done

This prevents the failure mode where you focus on the primary feature
and forget secondary deliverables. Example: step description says
"Tab label adapts to vertical (Menu vs Lookbook)" — you implement the
tab content but forget the label adaptation because you focused on the
harder part.

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
python3 ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/deps-query.py <project_root> "<modified_file>"
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

For heuristic, layout, timing, and threshold bugs, changing a constant is
NOT evidence of understanding. Do not bump margins, delays, widths, retry
counts, or safety factors until you have recorded:
1. what concrete behavior is wrong,
2. what assumption in the current code is false,
3. what measurement, trace, or source proves your new value is justified.

This step is not optional. It is not something you do when asked. It is
something you do EVERY TIME, automatically, as the final step of every task.

### No pre-existing exemptions

If the acceptance criteria say "tsc passes" and tsc does not pass, fix
the issue — regardless of whether this step introduced the failure or it
existed before. "Pre-existing" is not a valid dismissal. Either fix the
failure or get the acceptance criteria changed before the plan was
approved.

This applies to all verification: type checker errors, lint failures,
test failures, and Codex findings. If the criteria require it to pass
and it doesn't, that's a finding — full stop.

### Verify against closed sets

Before declaring a step done, if your work produces values that must
conform to a closed set — enum values, schema fields, function signatures,
API contracts, mode/status strings — **re-read the source definition** and
verify your values match character-for-character.

Do NOT verify from memory. Open the file that defines the enum, schema, or
contract. Compare your output against it. If you wrote `"dynamic"` and the
enum only allows 5 specific values, you have a bug — even if `"dynamic"`
seems like a reasonable value.

Common closed sets to verify against:

- **Enum/union type values** — mode, status, category, and role strings.
  Re-read the type definition; do not recall it.
- **Schema field names and types** — plan.json fields, API response shapes,
  database columns. Grep for the source and match exactly.
- **Function/tool signatures** — parameter names, types, return types. For
  MCP tools, use `ToolSearch` to read the schema before calling. For
  internal functions, read the declaration.
- **File paths** — resolve from the directory where the file will be read
  or written, not from where you happen to be editing. A path like
  `references/foo.md` is wrong if the consumer lives in a different
  subdirectory than the references folder.

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
- [ ] Closed-set values verified against source definitions (enums, schemas, signatures, tool params, file paths)
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
| Writing plan.json/masterPlan.md directly without invoking writing-plans skill | Call `Skill(skill: "look-before-you-leap:writing-plans")` — it sets codexVerify, evaluates sub-plans, applies TDD rhythm |
| Doing work that a skill covers without invoking that skill first | Check the skill routing table in the conductor — if a skill exists for this work, invoke it via the Skill tool |
| Ignoring a warning from plan_utils.py or a hook script | Stop and fix the issue — warnings mean something is wrong, not "proceed with caution" |
| Reacting to IDE/LSP diagnostics mid-edit without running the real type checker | LSP diagnostics go stale during edits — run `tsc --noEmit` (or equivalent) to confirm before "fixing" phantom errors |
| Writing plan.json directly after brainstorming (skipping writing-plans skill) | Brainstorming produces design.md, then you MUST call `Skill(skill: "look-before-you-leap:writing-plans")` — do not shortcut |
| Fixing Codex findings then moving on without re-verifying via codex-reply | Call `mcp__codex__codex-reply` with the threadId after fixes — tsc passing is not the same as Codex confirming |
| Dismissing a failure as "pre-existing" when acceptance criteria require it to pass | Fix the failure or change the acceptance criteria — "pre-existing" is not an exemption |
| Marking a step done before Codex verification passes (for codexVerify steps) | Codex is a gate — complete the fix → re-verify loop until PASS, then mark done |
| Writing `.catch(() => {})` or `.catch(() => null)` | Handle the error, rethrow, or comment why ignoring is safe |
| Broad `try/catch` that resolves successfully on failure | Catch at the narrowest scope — let failures propagate or degrade visibly |
| Adding a new API endpoint without an integration test | Every new endpoint lands with at least one happy-path test — no exceptions |
| Adding a new API endpoint without updating project docs | Update the API inventory (api.md, OpenAPI spec) in the same step — not later |
| Writing any closed-set value from memory (enum, schema field, API shape, signature) | Re-read the source definition and copy the exact value — memory drifts, source files don't |
| Assuming a tool/function accepts a parameter without reading its schema | Use `ToolSearch` for MCP tools; read the function declaration for internal code |
| Writing a file path without resolving from the target directory | Resolve relative to where the consumer reads/writes, not where you're editing |
| Reimplementing existing behavior without reading the source | Open the original, list what it does, verify parity in your new code |
| Rendering editable fields without tracing the save path | For every editable field: trace onChange → state → mutation → API → DB |
| Writing simpler preconditions than the operation you're wrapping | Read the handler, list its gates, replicate them exactly |
| Starting to code a step without listing its deliverables | Extract every deliverable from description + acceptance criteria first |
| Writing an event listener without reading the code that sends the event | Read the producer: what triggers it, what payload, under what conditions |
| Depending on a state value without listing all its producers | List EVERY code path that can set it: handlers, effects, URL params, wizard nav |
| Bumping a margin/threshold/constant to fix a Codex finding | Not evidence of understanding — record what's wrong, what assumption is false, and what proves the new value |
| Reinterpreting acceptance criteria after a failed Codex round | This is a plan deviation — ask the user to approve the narrower scope first |
| Fixing one part of a multi-part Codex finding and re-verifying | Number every distinct issue, address ALL before re-verifying |
