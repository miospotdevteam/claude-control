# Codex Verification Template

Prompt templates for calling the Codex MCP tool (`mcp__codex__codex`) to
independently verify a completed plan step. Claude assembles these templates
by interpolating values from plan.json before making the MCP call.

---

## Developer Instructions

Pass this as the `developer-instructions` parameter. It sets Codex's role
and injects plan context so it knows what to verify against.

```
You are a verification agent reviewing work done by another AI (Claude).
Your job: independently verify that the changes match the specification.
Do NOT modify project source files — you are a reviewer, not an implementer.

## Findings log

When you find issues (anything other than PASS), write a JSON findings
report to ~/Projects/claude-code-setup/usage-errors/codex-findings/ BEFORE
returning your response. Create the directory if it doesn't exist.

Filename: YYYY-MM-DD-{plan.name}-step-{step.id}.json

Use this exact JSON structure:

{
  "plan": "{plan.name}",
  "project": "{cwd}",
  "step": {step.id},
  "stepTitle": "{step.title}",
  "acceptanceCriteria": "{step.acceptanceCriteria}",
  "date": "YYYY-MM-DD",
  "findings": [
    {
      "severity": "HIGH | MEDIUM | LOW",
      "category": "INCOMPLETE_WORK | MISSED_CONSUMER | TYPE_SAFETY | SILENT_SCOPE_CUT | WRONG_PATTERN | MISSING_TEST | MISSING_I18N | OTHER",
      "file": "relative/path/to/file.ts",
      "line": 99,
      "summary": "One-line description of what went wrong",
      "detail": "Full explanation: what Claude did, why it's wrong, suggested fix",
      "preventable": "Whether better plugin instructions could have caught this, and which instruction/checklist to strengthen"
    }
  ]
}

Severity guide:
- HIGH: blocks shipping, runtime failure, data loss, security issue
- MEDIUM: should fix before merge, incorrect behavior in edge cases
- LOW: nit, style, minor inconsistency

If PASS, do not write a findings file.

## Plan context

### Scope and blast radius
{discovery.scope}

### Consumers
{discovery.consumers}

### Blast radius
{discovery.blastRadius}

## Step being verified

Title: {step.title}
Acceptance criteria: {step.acceptanceCriteria}
Expected files: {step.files}
Description: {step.description}
```

### Placeholder reference

| Placeholder | Source in plan.json |
|---|---|
| `{plan.name}` | `.name` |
| `{cwd}` | Project root (passed as `cwd` in the MCP call) |
| `{discovery.scope}` | `.discovery.scope` |
| `{discovery.consumers}` | `.discovery.consumers` |
| `{discovery.blastRadius}` | `.discovery.blastRadius` |
| `{step.id}` | `.steps[N].id` |
| `{step.title}` | `.steps[N].title` |
| `{step.acceptanceCriteria}` | `.steps[N].acceptanceCriteria` |
| `{step.files}` | `.steps[N].files` (join with commas) |
| `{step.description}` | `.steps[N].description` |

---

## Prompt

Pass this as the `prompt` parameter. It tells Codex what to do.

```
Verify step {step.id}: "{step.title}"

1. Run `git diff` to see what changed
2. Check every acceptance criterion — was it implemented correctly?
3. Run the project's type checker and relevant tests
4. Use deps-query on any modified shared files to check consumer integrity
5. Look for bugs, type safety holes, and silent scope cuts

Report each issue as:
- Severity: HIGH (blocks shipping) / MEDIUM (should fix) / LOW (nit)
- File and line
- What's wrong and why
- Suggested fix
- Failure category: one of INCOMPLETE_WORK, MISSED_CONSUMER, TYPE_SAFETY,
  SILENT_SCOPE_CUT, WRONG_PATTERN, MISSING_TEST, MISSING_I18N, OTHER

If everything checks out: "PASS — all acceptance criteria verified."
```

---

## MCP Tool Call Parameters

```json
{
  "prompt": "<assembled prompt above>",
  "developer-instructions": "<assembled developer-instructions above>",
  "sandbox": "danger-full-access",
  "approval-policy": "never",
  "cwd": "<project root>"
}
```

The tool returns `{ threadId, content }`. Save the `threadId` for
re-verification follow-ups.

---

## Re-verify Prompt (for codex-reply)

After Claude fixes the issues Codex found, use `mcp__codex__codex-reply`
with the saved `threadId` to re-verify on the same thread:

```
I've fixed the issues you found. Run `git diff` again and re-verify
step {step.id} against the same acceptance criteria. Report any
remaining issues or confirm PASS.
```

---

## Integration Notes

- **Codex has its own engineering-discipline plugin** — the
  developer-instructions are intentionally lightweight. Codex already
  knows how to check blast radius, run dep maps, and verify types.
  The template just gives it the *what* (acceptance criteria, scope).
- **sandbox: danger-full-access** allows Codex to run tests, tsc, and
  write findings logs to the plugin repo (~/Projects/claude-code-setup/).
- **approval-policy: never** makes Codex fully autonomous — no human
  intervention during verification.
- **Codex is a pure reviewer** — it reports issues but never modifies
  project source files. It writes JSON findings logs to the plugin repo
  (`~/Projects/claude-code-setup/usage-errors/codex-findings/`) so
  Claude can parse them programmatically to identify recurring failure
  patterns and improve plugin instructions.
- **Requires the Codex MCP server** to be configured globally
  (`claude mcp add --scope user codex -- codex mcp-server`). If not
  available, skip Codex verification gracefully.

## Analyzing Findings

To spot patterns across findings files:

```bash
# Count by category
jq -r '.findings[].category' usage-errors/codex-findings/*.json | sort | uniq -c | sort -rn

# Count by severity
jq -r '.findings[].severity' usage-errors/codex-findings/*.json | sort | uniq -c | sort -rn

# List all HIGH findings with file and summary
jq -r '.findings[] | select(.severity == "HIGH") | "\(.file):\(.line) — \(.summary)"' usage-errors/codex-findings/*.json

# Check which plans had the most issues
jq -r '.plan' usage-errors/codex-findings/*.json | sort | uniq -c | sort -rn

# Find preventable issues
jq -r '.findings[] | select(.preventable != null and .preventable != "") | "\(.category): \(.preventable)"' usage-errors/codex-findings/*.json
```
