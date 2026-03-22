# Codex Plan Review Template

Prompt template for calling `mcp__codex__codex-reply` during the planning
phase. Codex acts as an attack pass reviewer — it reads the plan and
critiques step sizing, acceptance criteria clarity, missing steps, and
ordering risks. Uses the persistent thread from discovery.

---

## Developer Instructions

For `codex-reply` calls (the normal path), `developer-instructions` cannot
be passed as a separate parameter — only `threadId` and `prompt` are
accepted. Therefore, the role context below is embedded directly in the
prompt. Codex retains the lifecycle-wide base instructions from the
discovery thread, which allow phase switching via ROLE SWITCH directives.

### Placeholder reference

| Placeholder | Source in plan.json |
|---|---|
| `{plan.context}` | `.context` |
| `{discovery.scope}` | `.discovery.scope` |
| `{discovery.consumers}` | `.discovery.consumers` |
| `{discovery.blastRadius}` | `.discovery.blastRadius` |
| `{discovery.confidence}` | `.discovery.confidence` |
| `{masterPlan.content}` | Read from `masterPlan.md` file alongside plan.json |

---

## Prompt

Pass this as the `prompt` parameter. It includes both the role context
and the task because `codex-reply` has no separate developer-instructions.

```
ROLE SWITCH: You are now an attack pass reviewer critiquing a plan written
by me (Claude). Your job: find weaknesses in the plan before it goes to
the user for approval. You are NOT an implementer — do NOT modify any
source files.

## Plan context

What the user asked for: {plan.context}
Discovery scope: {discovery.scope}
Consumers: {discovery.consumers}
Blast radius: {discovery.blastRadius}
Confidence: {discovery.confidence}

## The plan to review

---
{masterPlan.content}
---

## Your task

Attack this plan critically:

1. Are any steps too large for a single context window?
2. Are acceptance criteria concrete and mechanically verifiable?
3. Are there missing steps or gaps between steps?
4. Is the step ordering correct (definitions before consumers)?
5. Does the plan account for all consumers from the discovery?
6. Are step ownership assignments correct per the routing matrix?
7. Is anything missing from the user's original request?

Focus on:
- Steps that are too large to survive context compaction
- Vague acceptance criteria ("works correctly" vs "tsc --noEmit passes")
- Wrong ordering (consumers before definitions)
- Blast radius gaps
- Wrong agent ownership

Be specific. Reference step IDs and quote the problematic text.

For each finding, report:
- Step ID and what's wrong
- Severity: HIGH (plan will fail) / MEDIUM (should fix) / LOW (suggestion)
- Suggested fix

If the plan is solid: "PLAN LOOKS SOLID — ready for user review."
```

---

## MCP Tool Call Parameters

This uses the persistent thread from discovery — call `mcp__codex__codex-reply`.

```json
{
  "threadId": "<from plan.json.codexSession.threadId>",
  "prompt": "<assembled prompt above>"
}
```

`codex-reply` only accepts `threadId` and `prompt`. Role context and plan
context are embedded directly in the prompt. Codex retains the base
developer-instructions from the discovery thread creation.

After this call, update the session:
```bash
python3 plan_utils.py update-codex-session <plan.json> <threadId> plan-review
```

---

## Integration Notes

- **Uses the existing thread** from discovery. Codex has full context of
  what was explored and can reference earlier findings.
- **Codex does NOT edit files** — its role is purely advisory in this phase.
- **After receiving findings**, Claude should adjust the plan (fix step
  sizing, sharpen criteria, add missing steps) before presenting to the
  user via Orbit.
- **The plan goes to Orbit AFTER Codex review**, not before. This ensures
  the user sees a plan that has already been stress-tested.
- **masterPlan.md content** must be read from disk and interpolated into
  the prompt. It is NOT a field in plan.json — it's a separate file in
  the same directory.
