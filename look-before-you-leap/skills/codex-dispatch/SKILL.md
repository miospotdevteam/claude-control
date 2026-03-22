---
name: codex-dispatch
description: "Orchestrates all Codex MCP interactions for the look-before-you-leap plugin. Manages the persistent Codex thread lifecycle (create, reply, recover, overflow), routes to phase-specific prompt templates (discovery, plan-review, implementation, verification), assembles prompts with plan.json interpolation, parses responses, and updates codexSession state. Handles all 5 collaboration modes (claude-solo, claude-impl, codex-impl, collab-split, dual-pass) and symmetric error logging. Use whenever a plan step requires Codex interaction: adversarial discovery challenge, plan attack pass, Codex-owned implementation, or step verification. Do NOT use for: plans with no Codex involvement, claude-solo steps, or direct Codex MCP calls outside the plan lifecycle."
---

# Codex Dispatch

This skill orchestrates ALL Codex MCP interactions. Claude never calls
`mcp__codex__codex` or `mcp__codex__codex-reply` directly — it invokes
this skill, which handles thread management, template selection, prompt
assembly, response parsing, and state updates.

---

## Prerequisites

The Codex MCP server must be configured globally:
```bash
claude mcp add --scope user codex -- codex mcp-server
```

If `mcp__codex__codex` is not available, skip Codex interactions gracefully
and note "Codex: skipped — MCP not configured" in the step's result field.

---

## Thread Lifecycle

One persistent thread per plan. Created during discovery, reused for all
subsequent interactions.

### Create (discovery phase)

The first Codex interaction creates the thread:

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/references/codex-discover-template.md`
2. Interpolate plan.json values into the template
3. Call `mcp__codex__codex` with:
   - `prompt`: assembled discovery prompt
   - `developer-instructions`: lifecycle-wide instructions (allows phase
     switching via ROLE SWITCH directives)
   - `sandbox`: `"danger-full-access"`
   - `approval-policy`: `"never"`
   - `cwd`: project root
4. Save returned `threadId` to plan.json:
   ```bash
   python3 plan_utils.py update-codex-session <plan.json> <threadId> discovery
   ```

### Reply (all subsequent phases)

Every interaction after discovery uses `mcp__codex__codex-reply`:

1. Read the phase-appropriate template
2. Interpolate plan.json values
3. Call `mcp__codex__codex-reply` with:
   - `threadId`: from `plan.json.codexSession.threadId`
   - `prompt`: assembled prompt (includes ROLE SWITCH + role context +
     task, since codex-reply has no developer-instructions parameter)
4. Update session:
   ```bash
   python3 plan_utils.py update-codex-session <plan.json> <threadId> <phase>
   ```

### Recover (thread lost)

If `codex-reply` fails with a thread-not-found error:

1. Log the error
2. Create a fresh thread via `mcp__codex__codex` with:
   - Developer-instructions: same lifecycle-wide instructions as original
   - Prompt: compressed summary of prior interactions from
     `plan.json.completedSummary` + `discovery` + current task
3. Save new `threadId` to plan.json (replaces old one)
4. Continue with the current phase

No data is lost because plan.json has all state on disk.

### Overflow (thread too long)

Long threads degrade Codex response time and can cause timeouts. The
threshold is deliberately conservative — real-world testing showed timeouts
starting around 15 interactions.

**Trigger**: Check `codexSession.interactionCount` before every
`codex-reply` call. If **>= 10**, trigger overflow before the next
interaction. Do not wait for a timeout.

**Fresh thread initialization protocol:**

1. **Read current state** from plan.json:
   - `plan.context` (what the user asked for)
   - `discovery` object (scope, consumers, blast radius, patterns)
   - `completedSummary` array (what's been done so far)
   - Current step context (id, title, description, acceptanceCriteria)
   - `codexSession.phase` (what phase we're in)

2. **Assemble the handoff prompt** for the new thread's
   `developer-instructions`:

   ```
   You are a collaborator working with another AI (Claude) across a full
   plan lifecycle. Your role changes per phase — Claude will tell you your
   current role in each prompt via a ROLE SWITCH directive.

   ## Continuing from a previous thread

   This is a continuation of an earlier Codex thread that was retired due
   to length. Here is the accumulated context:

   ### Plan context
   {plan.context}

   ### Discovery findings
   Scope: {discovery.scope}
   Consumers: {discovery.consumers}
   Blast radius: {discovery.blastRadius}
   Existing patterns: {discovery.existingPatterns}

   ### Work completed so far
   {completedSummary — join with newlines}

   ### Current phase: {codexSession.phase}
   ```

3. **Create the fresh thread** via `mcp__codex__codex`:
   ```json
   {
     "prompt": "<current phase prompt — same as what you were about to send>",
     "developer-instructions": "<assembled handoff prompt above>",
     "sandbox": "danger-full-access",
     "approval-policy": "never",
     "cwd": "<project root>"
   }
   ```

4. **Update plan.json** — save new `threadId`, reset `interactionCount`
   to 1, keep the same `phase`:
   ```bash
   python3 plan_utils.py clear-codex-session <plan.json>
   python3 plan_utils.py update-codex-session <plan.json> <newThreadId> <phase>
   ```

5. **Continue** with the current phase as normal.

No data is lost because plan.json has all state on disk. The new thread
gets a compressed summary of everything the old thread knew.

---

## Phase Routing

Read `codexSession.phase` from plan.json and the current step's context
to select the correct template:

| Phase | Template | When |
|---|---|---|
| `discovery` | `codex-discover-template.md` | After Claude writes discovery.md |
| `plan-review` | `codex-plan-review-template.md` | After writing-plans produces the plan |
| `execution` (verify) | `codex-verify-template.md` | After Claude completes an `owner: "claude"` step |
| `execution` (implement) | `codex-implement-template.md` | When starting an `owner: "codex"` step |

### Template selection logic

```
IF phase == "discovery":
    template = codex-discover-template.md

ELSE IF phase == "plan-review":
    template = codex-plan-review-template.md

ELSE IF phase == "execution":
    IF step.owner == "claude" AND step is completed:
        template = codex-verify-template.md (persistent thread path)
    ELSE IF step.owner == "codex" AND step is starting:
        template = codex-implement-template.md
    ELSE IF step.mode == "dual-pass":
        # Both agents work independently
        # Use verify template for Codex's independent pass
        template = codex-verify-template.md (with dual-pass context)
```

---

## Prompt Assembly

Every template uses `{placeholder}` syntax. Interpolate from plan.json:

### Common placeholders (all templates)

| Placeholder | Source |
|---|---|
| `{plan.name}` | `plan.json .name` |
| `{plan.context}` | `plan.json .context` |
| `{discovery.scope}` | `plan.json .discovery.scope` |
| `{discovery.entryPoints}` | `plan.json .discovery.entryPoints` |
| `{discovery.consumers}` | `plan.json .discovery.consumers` |
| `{discovery.existingPatterns}` | `plan.json .discovery.existingPatterns` |
| `{discovery.blastRadius}` | `plan.json .discovery.blastRadius` |
| `{discovery.confidence}` | `plan.json .discovery.confidence` |

### Step-specific placeholders (execution templates)

| Placeholder | Source |
|---|---|
| `{step.id}` | `plan.json .steps[N].id` |
| `{step.title}` | `plan.json .steps[N].title` |
| `{step.description}` | `plan.json .steps[N].description` |
| `{step.acceptanceCriteria}` | `plan.json .steps[N].acceptanceCriteria` |
| `{step.files}` | `plan.json .steps[N].files` (join with commas) |
| `{step.progress}` | `plan.json .steps[N].progress` (format as numbered list) |
| `{plan.completedSummary}` | `plan.json .completedSummary` (join with newlines) |
| `{cwd}` | Project root path |

### Plan-review placeholder

| Placeholder | Source |
|---|---|
| `{masterPlan.content}` | Read `masterPlan.md` from the plan directory |

### Skill injection placeholder

| Placeholder | Source |
|---|---|
| `{step.skill.content}` | Read the SKILL.md for the step's `skill` field. Empty if `"none"`. See Skill Injection below. |

---

## Collaboration Mode Execution

### `claude-solo`

No Codex interaction. Skip this step entirely in codex-dispatch.

### `claude-impl` (default)

1. Claude implements the step (normal flow)
2. After Claude marks all progress items done and passes own verification:
   - Invoke codex-dispatch with verify template
   - Codex reviews via `codex-reply`
   - If issues found: Claude fixes, then re-verifies via `codex-reply`
   - Repeat until PASS
3. Record "Codex: PASS" in step result

### `codex-impl`

1. Invoke codex-dispatch with implement template
2. Codex implements via `codex-reply` (has edit permission from
   lifecycle-wide developer-instructions)
3. After Codex reports completion:
   - Claude verifies: read all modified files, run tsc/lint/tests, check
     consumers via deps-query
   - If issues found: Claude either fixes directly OR sends back via
     `codex-reply` for Codex to fix
   - Log Claude's findings to `usage-errors/claude-findings/` (see
     Symmetric Error Logging)
4. Record "Claude: verified" in step result

### `collab-split`

1. Claude proposes an approach in a `codex-reply`:
   - "Here's how I think we should split this step..."
2. Codex pushes back, suggests alternatives, identifies risks
3. They converge on a design
4. The step is split into sub-steps with mixed ownership:
   - Create progress items with clear owner annotations
   - Execute each sub-task based on its owner (claude-impl or codex-impl
     flow for each)
5. Record the split and outcomes in step result

### `dual-pass`

1. Claude does its independent pass first (design/UX/architecture focus)
2. Invoke codex-dispatch with verify template + dual-pass context:
   - Add to prompt: "This is a dual-pass review. Focus on implementation
     correctness, security, edge cases, and test coverage. I (Claude)
     focused on design and architecture."
3. Claude synthesizes both sets of findings
4. Record combined findings in step result

---

## Skill Injection

When `step.owner == "codex"`, check the step's `skill` field. If it's not
`"none"`, read the skill's SKILL.md and inject it into the prompt via the
`{step.skill.content}` placeholder.

### Injectable skills (Codex can use these)

| Skill | SKILL.md path |
|---|---|
| `look-before-you-leap:test-driven-development` | `${CLAUDE_PLUGIN_ROOT}/skills/test-driven-development/SKILL.md` |
| `look-before-you-leap:refactoring` | `${CLAUDE_PLUGIN_ROOT}/skills/refactoring/SKILL.md` |
| `look-before-you-leap:systematic-debugging` | `${CLAUDE_PLUGIN_ROOT}/skills/systematic-debugging/SKILL.md` |
| `look-before-you-leap:webapp-testing` | `${CLAUDE_PLUGIN_ROOT}/skills/webapp-testing/SKILL.md` |
| `look-before-you-leap:mcp-builder` | `${CLAUDE_PLUGIN_ROOT}/skills/mcp-builder/SKILL.md` |

### Claude-only skills (never inject)

These require visual taste or user interaction:
- `frontend-design`
- `svg-art`
- `immersive-frontend`
- `react-native-mobile`
- `brainstorming`
- `writing-plans`
- `doc-coauthoring`

If a step has `owner: "codex"` AND a Claude-only skill, this is a routing
error. Log it, fall back to `"none"` (engineering-discipline only), and
note the mismatch in the step's result field.

### Injection format

Wrap the skill content in a clear section:

```
## Skill guidance for this step

The following skill provides specialized guidance for implementing this
step. Follow its instructions alongside the engineering discipline rules.

---
{SKILL.md content}
---
```

---

## Response Parsing

### Discovery phase

Extract from Codex's response:
- List of missed consumers (file paths)
- Underestimated blast radius items
- Dangerous assumptions identified
- Missing patterns or utilities

Update `discovery.md` and `plan.json.discovery` with significant findings.

### Plan-review phase

Extract from Codex's response:
- Steps that are too large (IDs + reasoning)
- Vague acceptance criteria (IDs + suggestion)
- Missing steps
- Ordering issues
- Ownership disagreements

Adjust plan.json and masterPlan.md before Orbit review.

### Execution phase (verify)

Extract from Codex's response:
- PASS or list of findings
- Each finding: severity, file, line, category, detail

If PASS: record "Codex: PASS" in step result.
If findings: fix issues, re-verify via `codex-reply`.

### Execution phase (implement)

Extract from Codex's response:
- FILES CHANGED list
- WHAT WAS DONE summary
- VERIFICATION results
- ISSUES encountered

Update progress items in plan.json based on the report. Then proceed to
Claude's verification pass.

---

## Symmetric Error Logging

When Claude verifies Codex-owned steps and finds issues, write findings
to `usage-errors/claude-findings/` using the same JSON schema as Codex
uses for `usage-errors/codex-findings/`:

### File naming

- `YYYY-MM-DD-{plan.name}-step-{N}-claude-review.json`
- Re-review: `YYYY-MM-DD-{plan.name}-step-{N}-claude-review-{M}.json`

### JSON schema

```json
{
  "plan": "{plan.name}",
  "project": "{cwd}",
  "step": {step.id},
  "stepTitle": "{step.title}",
  "acceptanceCriteria": "{step.acceptanceCriteria}",
  "date": "YYYY-MM-DD",
  "reviewer": "claude",
  "findings": [
    {
      "severity": "HIGH | MEDIUM | LOW",
      "category": "INCOMPLETE_WORK | MISSED_CONSUMER | TYPE_SAFETY | SILENT_SCOPE_CUT | WRONG_PATTERN | MISSING_TEST | MISSING_I18N | OTHER",
      "file": "relative/path/to/file",
      "line": 0,
      "summary": "One-line description",
      "detail": "Full explanation",
      "preventable": "Which instruction could have prevented this"
    }
  ]
}
```

The only difference from Codex's schema is the `"reviewer": "claude"` field.
This allows the analyzing scripts in codex-verify-template.md to work
across both directories.

### When to log

Log findings when Claude's verification of a Codex-owned step finds issues.
Do NOT log when the step passes verification — same rule as Codex follows.

---

## Error Handling

### Codex MCP not available

If `mcp__codex__codex` tool is not available:
- Skip all Codex interactions for this plan
- Note "Codex: skipped — MCP not configured" in each step's result field
- The plan proceeds as fully Claude-owned (all steps become `claude-solo`)

### Thread lost mid-plan

If `codex-reply` returns an error indicating the thread is gone:
1. Log the error to `usage-errors/` if it's a plugin issue
2. Follow the Recovery protocol (see Thread Lifecycle above)
3. Continue with the current phase

### Codex fails mid-implementation

If Codex returns an error or incomplete response during implementation:
1. Check `git diff` and `git status` to see what Codex changed
2. Run tsc/lint/tests to assess the state
3. Decision:
   - If mostly complete with minor issues: Claude fixes directly
   - If partially complete: retry the remaining work via `codex-reply`
   - If fundamentally broken: ask the user before reverting any changes
     (do NOT use destructive git operations without user confirmation)
   - If unclear: ask the user

### Codex times out

If the MCP call doesn't return in a reasonable time:
- The MCP framework handles timeouts
- Treat as a failed call — follow the mid-implementation failure path

---

## Compaction Recovery

After context compaction, codex-dispatch recovers from plan.json:

1. Read `plan.json.codexSession`:
   - `threadId`: resume via `codex-reply`
   - `phase`: know which template to use
   - `interactionCount`: know if overflow is near
   - `lastInteraction`: detect staleness
2. If `codexSession` exists and `threadId` is set:
   - Continue via `codex-reply` on the existing thread
   - Codex retains all prior context independently of Claude's compaction
3. If `codexSession` is missing or `threadId` is null:
   - No Codex thread exists — create one if needed

This is the key advantage of persistent threads: Codex's context is
independent of Claude's. When Claude compacts, Codex still has the full
conversation history on its thread.

---

## Quick Reference

| Situation | Action |
|---|---|
| First Codex interaction in a plan | `mcp__codex__codex` (creates thread) |
| Every subsequent interaction | `mcp__codex__codex-reply` (uses threadId) |
| After every Codex call | `plan_utils.py update-codex-session` |
| Thread lost | Recover with fresh thread + summary |
| interactionCount >= 10 | Overflow: fresh thread via initialization protocol |
| Codex not available | Skip gracefully, note in result |
| `claude-solo` step | Skip entirely |
| `claude-impl` step done | Verify via codex-verify-template |
| `codex-impl` step starting | Implement via codex-implement-template |
| `collab-split` step | Design discussion, then split into sub-tasks |
| `dual-pass` step | Both pass independently, Claude synthesizes |
| Claude finds issues in Codex work | Log to `usage-errors/claude-findings/` |
| After compaction | Read codexSession from plan.json, continue |
