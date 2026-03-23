---
name: codex-dispatch
description: "Orchestrates all Codex interactions for the look-before-you-leap plugin via codex exec CLI. Routes to direction-locked scripts (run-codex-verify.sh for claude-impl, run-codex-implement.sh for codex-impl), monitors JSONL streaming output, parses results, and enforces independent verification. Handles all 4 collaboration modes (claude-impl, codex-impl, collab-split, dual-pass), co-exploration dispatch, plan consensus dispatch, and symmetric error logging. Use whenever a plan step requires Codex interaction: verification of Claude's work, Codex-owned implementation, co-exploration during discovery, or plan consensus during planning. Do NOT use for: plans with no Codex involvement."
---

# Codex Dispatch

This skill orchestrates ALL Codex interactions during plan execution.
Claude never calls `codex exec` directly for step verification or
implementation — it invokes this skill, which selects the correct
direction-locked script, runs it in the background, monitors output,
and enforces the verification protocol.

---

## Prerequisites

The Codex CLI must be installed globally:
```bash
npm install -g @openai/codex
```

Codex skills must be installed to `~/.codex/skills/` (done automatically
by the SessionStart hook via `install-codex-skills.sh`):
- `lbyl-verify` — teaches Codex the verification protocol
- `lbyl-implement` — teaches Codex the implementation protocol

If `codex` is not available (`command -v codex` fails), skip Codex
interactions gracefully and note "Codex: skipped — codex CLI not
installed" in the step's result field.

---

## Script Selection

Two direction-locked scripts enforce the ownership model. Neither script
can be used for the wrong direction — they validate the step's `owner`
field and exit with an error if mismatched.

| Step owner | Script | Sandbox | What happens |
|---|---|---|---|
| `claude` | `run-codex-verify.sh` | `read-only` | Codex reviews Claude's work, cannot modify files |
| `codex` | `run-codex-implement.sh` | `workspace-write` | Codex implements the step, can edit files |

Both scripts live at:
```
${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/run-codex-verify.sh
${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/run-codex-implement.sh
```

Usage:
```bash
bash <script> <plan.json-path> <step-number>
```

Output files (in the plan directory):
- `.codex-stream-step-N.jsonl` — JSONL event stream (live progress)
- `.codex-result-step-N.txt` — final result text

---

## Dispatch Flow

### For `claude-impl` steps (Claude implements, Codex verifies)

1. Claude completes the step — all progress items done, own verification
   passing (tsc, lint, tests)
2. **Dispatch Codex verification:**
   ```
   Bash(
     command: "bash ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/run-codex-verify.sh <plan.json> <step-number>",
     run_in_background: true
   )
   ```
3. **Monitor JSONL** — periodically read `.codex-stream-step-N.jsonl`
   (see Monitoring section)
4. **When Codex finishes** — read `.codex-result-step-N.txt`
5. **If PASS**: record "Codex: PASS" in step result, mark done
6. **If findings**: fix issues, then re-run verification:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/run-codex-verify.sh <plan.json> <step-number>
   ```
   Repeat until PASS.

### For `codex-impl` steps (Codex implements, Claude verifies)

1. **Dispatch Codex implementation:**
   ```
   Bash(
     command: "bash ${CLAUDE_PLUGIN_ROOT}/skills/look-before-you-leap/scripts/run-codex-implement.sh <plan.json> <step-number>",
     run_in_background: true
   )
   ```
2. **Monitor JSONL** — watch for file changes, commands, issues
3. **When Codex finishes** — read `.codex-result-step-N.txt`
4. **Claude verifies independently** (see Independent Verification below)
5. Record "Claude: verified" in step result, mark done

---

## JSONL Monitoring

While Codex runs in the background, periodically read the stream file
to report progress to the user:

```bash
# Read latest events
tail -20 <plan-dir>/.codex-stream-step-N.jsonl
```

Key JSONL event types:
- `item.completed` + `type: "agent_message"` — Codex's text output
  (findings, status updates)
- `item.completed` + `type: "command_execution"` — commands Codex ran
  and their output (tsc, grep, tests)
- `item.completed` + `type: "file_change"` — files Codex modified
  (implement only)
- `turn.completed` — Codex is done, includes token usage

Report to the user only what's relevant:
- "Codex is running tsc..." (from command_execution)
- "Codex found 2 issues in ModalShell.tsx" (from agent_message)
- "Codex modified 5 files" (from file_change count)
- "Codex finished — PASS" or "Codex finished — 3 findings"

---

## Claude's Independent Verification (codex-impl steps)

When Codex implements a step, Claude MUST verify independently. Do NOT
use `run-codex-verify.sh` — that would have Codex verify its own work,
which is exactly the failure mode this architecture prevents.

### Verification protocol

1. **Read what changed**: `git diff --name-only` to see Codex's modifications
2. **Read EVERY modified file** — at least the changed sections, not just
   the diff summary
3. **Run verification commands**: tsc/lint/tests — same commands Codex ran
4. **Check each acceptance criterion** against the actual code — read the
   step's `acceptanceCriteria` from plan.json and verify each one
5. **Check consumers**: if Codex modified shared code, run deps-query on
   modified files (if dep maps configured) or grep for import statements
6. **Write result**: "Claude: verified — read N files, checked M criteria,
   [all pass | found issues: ...]"

### If Claude finds issues

- Fix directly (for minor issues) or note what needs fixing
- Log findings to `usage-errors/claude-findings/` (see Symmetric Error
  Logging below)
- Re-run verification after fixes
- Update progress items in plan.json

The `verify-step-completion` hook enforces this:
- For `owner: "codex"` steps: result must contain `Claude: verified`
  AND must NOT contain `Codex: PASS`
- This makes "Codex verifies Codex" structurally impossible

---

## Collaboration Mode Execution

### `claude-impl` (default)

1. Claude implements the step
2. After own verification passes: dispatch `run-codex-verify.sh`
3. Fix findings, re-verify until PASS
4. Record "Codex: PASS" in step result

### `codex-impl`

1. Dispatch `run-codex-implement.sh`
2. After Codex reports completion: Claude verifies independently
3. Fix issues, re-verify
4. Record "Claude: verified" in step result

### `collab-split`

1. Claude proposes an approach (notes in plan.json or discovery.md)
2. Split the step into sub-tasks with mixed ownership
3. Execute each sub-task based on its owner:
   - Claude-owned: Claude implements, then `run-codex-verify.sh`
   - Codex-owned: `run-codex-implement.sh`, then Claude verifies
4. Record the split and outcomes in step result

### `dual-pass`

1. Claude does its independent pass first (design/UX/architecture)
2. Dispatch `run-codex-verify.sh` with the step context — Codex
   focuses on correctness, security, edge cases
3. Claude synthesizes both sets of findings
4. Record combined findings in step result

---

## Skill Injection

Codex skills are globally installed at `~/.codex/skills/`. When Codex
runs via `codex exec`, it automatically loads its installed skills
(`lbyl-verify` and `lbyl-implement`) which provide the verification
and implementation protocols.

For step-specific skills (TDD, refactoring, etc.), the relevant skill
guidance is not injected into the prompt — Codex reads plan.json's
`skill` field and can find the skill files in the plugin directory if
needed. The minimal prompt approach means Codex explores and reads
what it needs.

### Injectable skills (Codex can use these)

| Skill | What Codex does |
|---|---|
| `test-driven-development` | Follows red-green-refactor in progress items |
| `refactoring` | Follows contract-based rename/move protocol |
| `systematic-debugging` | Follows 4-phase investigation |
| `webapp-testing` | Follows Playwright test patterns |
| `mcp-builder` | Follows MCP server development workflow |

### Claude-only skills (never assigned to codex-impl steps)

- `frontend-design`, `svg-art`, `immersive-frontend`, `react-native-mobile`
- `brainstorming`, `writing-plans`, `doc-coauthoring`

If a step has `owner: "codex"` AND a Claude-only skill, this is a routing
error. Log it, fall back to `"none"`, and note the mismatch.

---

## Response Parsing

### Verification result (from `run-codex-verify.sh`)

Read `.codex-result-step-N.txt` and look for:
- **"PASS"** — all acceptance criteria verified. Record "Codex: PASS".
- **Findings list** — structured issues with severity, file, line.
  Fix each issue, then re-run `run-codex-verify.sh`.

### Implementation result (from `run-codex-implement.sh`)

Read `.codex-result-step-N.txt` and extract:
- **FILES CHANGED**: list of files Codex created or modified
- **WHAT WAS DONE**: summary per progress item
- **VERIFICATION**: type checker and test results
- **ISSUES**: anything that went wrong

Update progress items in plan.json based on the report. Then proceed
to Claude's independent verification.

---

## Symmetric Error Logging

Findings flow in both directions, logged to separate directories:

### Codex verifies Claude → `usage-errors/codex-findings/`

Codex auto-logs findings via the `lbyl-verify` skill. You do not
need to log these manually.
- Initial: `YYYY-MM-DD-{plan}-step-{N}.json`
- Re-verify: `YYYY-MM-DD-{plan}-step-{N}-reverify-{M}.json`

### Claude verifies Codex → `usage-errors/claude-findings/`

When Claude's verification of a Codex-owned step finds issues, write
findings manually:
- Review: `YYYY-MM-DD-{plan}-step-{N}-claude-review.json`
- Re-review: `YYYY-MM-DD-{plan}-step-{N}-claude-review-{M}.json`

### JSON schema (both directions)

```json
{
  "plan": "{plan.name}",
  "project": "{cwd}",
  "step": 0,
  "stepTitle": "{step.title}",
  "acceptanceCriteria": "{step.acceptanceCriteria}",
  "date": "YYYY-MM-DD",
  "reviewer": "claude",
  "findings": [
    {
      "severity": "HIGH | MEDIUM | LOW",
      "category": "INCOMPLETE_WORK | MISSED_CONSUMER | TYPE_SAFETY | SILENT_SCOPE_CUT | WRONG_PATTERN | MISSING_TEST | MISSING_I18N | OTHER",
      "file": "relative/path",
      "line": 0,
      "summary": "One-line description",
      "detail": "Full explanation",
      "preventable": "Which instruction could have prevented this"
    }
  ]
}
```

The `reviewer` field distinguishes direction: `"claude"` for Claude's
findings on Codex work, absent for Codex's findings on Claude's work.

### When to log

Log when verification finds issues. Do NOT log when the step passes.

---

## Co-Exploration Dispatch

During discovery (conductor Step 1), Codex explores the codebase in
parallel with Claude. This uses `codex exec` directly (not the
direction-locked scripts) since there is no step ownership yet.

**Phase 1 — Parallel exploration (background):**

```bash
codex exec -C <project-root> --sandbox read-only --dangerously-bypass-approvals-and-sandbox \
  "Explore the codebase for the task: <task-description>. Focus on: \
   1. All consumers of files in scope (trace import chains) \
   2. Blast radius — what breaks if these files change? \
   3. Test infrastructure — what tests cover this code? \
   4. Edge cases and error paths in the current implementation \
   5. Cross-module dependencies that might be missed \
   Write findings to <plan-dir>/discovery.md using append (>>). \
   Format: ## [Codex: <topic>]\n- **finding** (evidence: ...)"
```

Run in the background while Claude explores simultaneously.

**Phase 2 — Convergence (foreground):**

After both agents finish, dispatch Codex for a convergence review:

```bash
codex exec -C <project-root> --sandbox read-only --dangerously-bypass-approvals-and-sandbox \
  "Read ALL findings in <plan-dir>/discovery.md. The other agent (Claude) \
   explored patterns, conventions, and architecture. You explored consumers \
   and blast radius. Now: \
   1. What did the other agent miss? \
   2. What do you disagree with? \
   3. What blast radius was underestimated? \
   4. What cross-cutting concerns connect both sets of findings? \
   Append convergence notes to discovery.md under ## [Codex: Convergence]"
```

Claude reconciles after this round — merge findings, flag disagreements.

---

## Plan Consensus Dispatch

After writing-plans produces the plan (conductor Step 2), Codex and Claude
reach consensus through structured debate before Orbit review. Uses
`codex exec` directly (not direction-locked scripts).

**Round 1 — Codex reviews the plan:**

```bash
codex exec -C <project-root> --sandbox read-only --dangerously-bypass-approvals-and-sandbox \
  "Read the plan at <plan-dir>/masterPlan.md and <plan.json>. \
   For EACH step, return a structured proposal: \
   - ACCEPT: step is well-sized, criteria are concrete, ownership is correct \
   - REJECT <reason>: step should be removed or fundamentally rethought \
   - MODIFY <changes>: step needs specific changes \
   Also flag: missing steps, wrong ordering, vague acceptance criteria, \
   ownership assignments that contradict the routing matrix."
```

**Round 2 — Claude responds** to each proposal (ACCEPT / REJECT with
reasoning / COUNTER-PROPOSE). Update plan files with accepted changes.

**Round 3 (if needed) — Final resolution:**

```bash
codex exec -C <project-root> --sandbox read-only --dangerously-bypass-approvals-and-sandbox \
  "Read the updated plan at <plan-dir>/plan.json and Claude's responses \
   to your proposals. For each remaining disagreement: \
   - ACCEPT Claude's reasoning, or \
   - ESCALATE with both positions stated (for the user to decide in Orbit)"
```

**Max 3 rounds.** Unresolved items go to Orbit with both positions stated.

Both co-exploration and plan consensus are optional — skip if Codex is
not available.

---

## Error Handling

### Codex CLI not available

If `command -v codex` fails:
- Skip all Codex interactions
- Note "Codex: skipped — codex CLI not installed" in each step's result
- The plan proceeds as fully Claude-owned

### Codex hangs (no new JSONL lines)

If no new events appear in the stream file for > 3 minutes:
- Check if the `codex exec` process is still running
- If hung, kill the process and retry once
- If it hangs again, skip Codex for this step and note it

### Codex fails mid-implementation

If Codex reports ISSUES or exits with errors:
1. Check `git diff` and `git status` to assess what Codex changed
2. Run tsc/lint/tests
3. If mostly complete: Claude fixes the remaining issues
4. If fundamentally broken: ask the user before reverting changes

### Codex times out

`codex exec` has its own timeout handling. If it exits non-zero:
- Read whatever is in the result file
- Treat as a partial result — Claude assesses and decides

---

## Compaction Recovery

After context compaction, codex-dispatch recovers from plan.json:

1. Read plan.json — find the current step and its status
2. If a step is `in_progress`:
   - Check for `.codex-stream-step-N.jsonl` and `.codex-result-step-N.txt`
   - If result file exists: Codex finished, parse the result
   - If only stream file: Codex may still be running or may have failed.
     Check if the process is still running.
3. Continue the execution loop based on plan state

No thread state to recover — each `codex exec` call is standalone.
All context lives on disk (plan.json, discovery.md, source files).

---

## Quick Reference

| Situation | Action |
|---|---|
| `claude-impl` step done | Run `run-codex-verify.sh` in background |
| `codex-impl` step starting | Run `run-codex-implement.sh` in background |
| Codex returns PASS | Record "Codex: PASS" in result, mark done |
| Codex returns findings | Fix issues, re-run `run-codex-verify.sh` |
| Codex implements step | Claude verifies independently (read files, run tests) |
| Co-exploration (discovery) | Dispatch Phase 1 in background, Phase 2 after |
| Plan consensus (planning) | Max 3 rounds of structured debate |
| `collab-split` step | Split into sub-tasks, execute each by owner |
| `dual-pass` step | Claude pass, then Codex pass, synthesize |
| Codex not installed | Skip, note in result |
| Codex hangs | Kill after 3 min timeout, retry once |
| After compaction | Read plan.json, check for result files, continue |
| Claude finds issues in Codex work | Log to `usage-errors/claude-findings/` |
