# Codex Implementation Template

Prompt template for calling `mcp__codex__codex-reply` when Codex is the
implementer for a step (`owner: "codex"`). Codex has full edit permission
and implements the step's work, following the step's skill guidance if
applicable. Uses the persistent thread.

---

## Developer Instructions

For `codex-reply` calls (the normal path), `developer-instructions` cannot
be passed as a separate parameter — only `threadId` and `prompt` are
accepted. Therefore, the role context below is embedded directly in the
prompt. Codex retains the lifecycle-wide base instructions from the
discovery thread, which explicitly allow phase switching (including into
implementation with full edit permission) via ROLE SWITCH directives.

### Placeholder reference

| Placeholder | Source |
|---|---|
| `{plan.context}` | `plan.json .context` |
| `{discovery.scope}` | `plan.json .discovery.scope` |
| `{discovery.entryPoints}` | `plan.json .discovery.entryPoints` |
| `{discovery.consumers}` | `plan.json .discovery.consumers` |
| `{discovery.existingPatterns}` | `plan.json .discovery.existingPatterns` |
| `{discovery.blastRadius}` | `plan.json .discovery.blastRadius` |
| `{plan.completedSummary}` | `plan.json .completedSummary` (join with newlines) |
| `{step.id}` | `plan.json .steps[N].id` |
| `{step.title}` | `plan.json .steps[N].title` |
| `{step.description}` | `plan.json .steps[N].description` |
| `{step.acceptanceCriteria}` | `plan.json .steps[N].acceptanceCriteria` |
| `{step.files}` | `plan.json .steps[N].files` (join with commas) |
| `{step.progress}` | `plan.json .steps[N].progress` (format as numbered list) |
| `{step.skill.content}` | Content of the skill's SKILL.md referenced by `step.skill`, or empty if `"none"`. See Skill Injection below. |

---

## Prompt

Pass this as the `prompt` parameter. It includes role context, plan
context, step details, and skill guidance because `codex-reply` has no
separate developer-instructions parameter.

```
ROLE SWITCH: You are now an implementation agent. Your job: implement the
specified plan step by editing project source files. You have full edit
permission.

Follow these rules:
- Implement exactly what the acceptance criteria specify — no more, no less
- Follow existing codebase patterns and conventions
- Do NOT cut scope silently. If something is blocked, report it explicitly
- Run the project's type checker and relevant tests after your changes
- Check consumers of any shared code you modify

## Plan context

What the user asked for: {plan.context}
Discovery scope: {discovery.scope}
Entry points: {discovery.entryPoints}
Consumers: {discovery.consumers}
Existing patterns: {discovery.existingPatterns}
Blast radius: {discovery.blastRadius}

Completed steps so far:
{plan.completedSummary}

## Step to implement

Step {step.id}: {step.title}
Description: {step.description}
Acceptance criteria: {step.acceptanceCriteria}
Files: {step.files}

Progress items (work through in order):
{step.progress}

{step.skill.content}

## Your task

Implement this step. For each progress item:
1. Read the relevant files first
2. Make the changes
3. Verify they compile/pass

After completing all items:
1. Run the project's type checker (e.g., tsc --noEmit)
2. Run relevant tests
3. Report what you implemented, what files you changed, and any issues

Format your report as:
- FILES CHANGED: list of files
- WHAT WAS DONE: brief summary per progress item
- VERIFICATION: type checker and test results
- ISSUES: anything that didn't go as expected (or "none")
```

---

## MCP Tool Call Parameters

Uses the persistent thread — call `mcp__codex__codex-reply`.

```json
{
  "threadId": "<from plan.json.codexSession.threadId>",
  "prompt": "<assembled prompt above>"
}
```

`codex-reply` only accepts `threadId` and `prompt`. Role context, plan
context, step details, and skill guidance are all embedded in the prompt.
Codex retains the base developer-instructions from the discovery thread.

After this call, update the session:
```bash
python3 plan_utils.py update-codex-session <plan.json> <threadId> execution
```

---

## Skill Injection

The `{step.skill.content}` placeholder is filled based on the step's
`skill` field:

| `step.skill` value | What to inject |
|---|---|
| `"none"` | Empty string (engineering-discipline is already in Codex's base instructions) |
| `look-before-you-leap:test-driven-development` | Read `skills/test-driven-development/SKILL.md` and inject its content |
| `look-before-you-leap:refactoring` | Read `skills/refactoring/SKILL.md` and inject its content |
| `look-before-you-leap:systematic-debugging` | Read `skills/systematic-debugging/SKILL.md` and inject its content |
| `look-before-you-leap:webapp-testing` | Read `skills/webapp-testing/SKILL.md` and inject its content |
| `look-before-you-leap:mcp-builder` | Read `skills/mcp-builder/SKILL.md` and inject its content |

**Never inject** Claude-only skills (`frontend-design`, `svg-art`,
`immersive-frontend`, `react-native-mobile`, `brainstorming`,
`writing-plans`, `doc-coauthoring`). Steps with these skills must have
`owner: "claude"`. If a mismatch is found, log it and fall back to
`"none"` (engineering-discipline only).

Wrap the injected content in a clear section header:

```
## Skill guidance for this step

The following skill provides specialized guidance for implementing this
step. Follow its instructions alongside the engineering discipline rules.

---
{skill SKILL.md content here}
---
```

---

## Integration Notes

- **sandbox: danger-full-access** is set on the original thread creation
  (`mcp__codex__codex` during discovery). Codex retains this permission
  for all subsequent `codex-reply` calls on the same thread.
- **Codex CAN edit files** — this is the only template where Codex has
  edit permission. The developer-instructions explicitly tell it to
  implement by editing source files.
- **After Codex completes**, Claude does a full verification pass: reads
  all modified files, runs tsc/lint/tests, checks consumers via deps-query.
  This is symmetric verification — same rigor as Codex applies to Claude's
  work.
- **If Codex reports issues** (blocked, couldn't complete, tests failing),
  Claude decides: retry via codex-reply, take over the step, or ask the
  user.
- **Progress item tracking**: After Codex completes, Claude updates the
  progress items in plan.json based on Codex's report. Codex does not
  update plan.json directly.
