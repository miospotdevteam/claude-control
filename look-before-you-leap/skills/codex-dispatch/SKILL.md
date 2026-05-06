---
name: codex-dispatch
description: "Orchestrates all Codex interactions for the look-before-you-leap plugin via codex exec CLI. Routes to direction-locked scripts (run-codex-verify.sh for claude-impl steps, run-codex-implement.sh for codex-impl steps), parallelizes across the runnable DAG frontier, and is strictly receipt-first: the main thread reads ONLY codex-receipt-step-N.json plus its HMAC sidecar — never raw streams, never .codex-result-step-N.txt as authority, never git diff, never raw exploration / consensus markdown. All large artifacts (exploration outputs, consensus batches, verification cross-checks) are routed through the lbyl-digest sub-agent. Conductor mode is the default and only mode — collab-split is gone. Use whenever a plan step requires Codex interaction. Do NOT use for plans with no Codex involvement."
---

# Codex Dispatch

This skill orchestrates ALL Codex interactions during plan execution.
Claude never calls `codex exec` directly for step verification or
implementation — it invokes this skill, which selects the correct
direction-locked script, runs it in the background, and consumes only
the **signed receipt** the script produces. Large unstructured artifacts
(stream files, exploration MD, consensus batches, raw `git diff`) are
NEVER read by the main thread; they are routed through the
`lbyl-digest` sub-agent.

## Hard Routing Rules

This skill is not advisory. It is the required path for Codex work.

- If a plan step is Codex-owned, Claude does NOT substitute itself
  because the work seems small or straightforward.
- If a Claude-owned step requires Codex verification, Claude does NOT
  self-certify and move on.
- If a dispatch hangs or fails, that is NOT permission to skip Codex
  and declare success anyway.
- If Codex is unavailable, you must prove that with `command -v codex`
  in the current environment before recording any skip.

Do not treat "Codex later", "Codex probably unavailable", or "I already
checked enough myself" as acceptable substitutes for the actual
dispatch.

---

## Receipt-First Authority Model

The conductor (this skill plus `look-before-you-leap`) operates on
**signed receipts only**. The authority chain for any Codex step is:

1. `<plan-dir>/codex-receipt-step-<N>.json` — the structured evidence
   artifact written by the direction-locked wrapper. Schema:
   `references/codex-receipt-schema.md` §2.
2. `~/.claude/look-before-you-leap/state/<projectId>/<planId>/codex_<kind>-step-<N>.json`
   — the HMAC sidecar that binds the receipt's bytes to the trust
   anchor (`data.artifactSha256` ↔ sha256 of the artifact on disk).
3. (For codex-impl only) `<plan-dir>/codex-receipt-step-<N>.claude-review.json`
   — the sibling review file written by the verification digester
   sub-agent, binding `review.receiptSha256` back to the artifact.

The main thread reads ONLY these three files (and not all three for
every step — see flow tables below). It does NOT read:

- `.codex-result-step-N.txt` (or `-group-G.txt`) — human trace only,
  never authoritative. Schema doc §1 / §6.
- `.codex-stream-step-N.jsonl` — raw streaming events. Treat as
  opaque. There is no `tail -f`, no event tailing, no JSONL parsing on
  the main thread.
- `git diff` of step files — the digester sub-agent may run this
  internally, but the conductor does not.
- Raw `codex-exploration.md`, `codex-convergence.md`,
  `codex-consensus-round*.md`, `codex-consensus-batch-*.md`,
  `codex-consensus-cross-cutting.md` — these are inputs to the
  `lbyl-digest` sub-agent. The conductor reads only the digest output
  (`discovery-digest.md`, `consensus-round-<N>-digest.md`) and the
  bounded payload returned by the sub-agent.

If you find yourself opening a stream JSONL, a `.txt` result, or a raw
batch MD on the main thread to "check what really happened", **stop**.
Either the receipt is sufficient, or you dispatch `lbyl-digest`. There
is no third path.

After the `lbyl-digest` Agent returns, the conductor MUST immediately
consume the returned payload and proceed to the next step in the flow
without waiting for user input — the JSON payload IS the trigger to
continue.

---

## Prerequisites

The Codex CLI must be installed globally:
```bash
npm install -g @openai/codex
```

Codex skills must be installed to `~/.codex/skills/` (done automatically
by the SessionStart hook via `install-codex-skills.sh`):
- `lbyl-verify` — teaches Codex the verification protocol and the
  receipt schema it must emit.
- `lbyl-implement` — teaches Codex the implementation protocol and the
  receipt schema it must emit.

Only if `command -v codex` was just run in the current environment and
failed may you skip Codex interactions. When that happens, note the
skip in the step's `### Verdict` section (e.g.,
`### Verdict\nCodex: skipped — codex CLI not installed`).

---

## Script Selection

Two direction-locked scripts enforce the ownership model. Neither
script can be used for the wrong direction — they validate the
step's `owner` and exit with an error if mismatched.

| Step owner | Script | What happens |
|---|---|---|
| `claude` | `run-codex-verify.sh` | Codex reviews Claude's work, emits `codex-receipt-step-<N>.json` (kind=verify). |
| `codex` | `run-codex-implement.sh` | Codex implements the target, can edit files, emits `codex-receipt-step-<N>.json` (kind=implement). |

Both scripts live at:
```
${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh
${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-implement.sh
```

Usage:
```bash
bash <script> <plan.json-path> <step-number>
```

Each invocation produces:
- `<plan-dir>/codex-receipt-step-<N>.json` — the authoritative
  receipt the conductor reads.
- HMAC sidecar in
  `~/.claude/look-before-you-leap/state/<projectId>/<planId>/`.
- `<plan-dir>/.codex-result-step-N.txt` and
  `<plan-dir>/.codex-stream-step-N.jsonl` — human traces only. Do
  not read these from the main thread.

---

## Dispatch Flow

### For `claude-impl` steps (Claude implements, Codex verifies)

1. Claude completes the step — all progress items done, own
   verification passing (tsc, lint, tests).
2. **Dispatch Codex verification:**
   ```
   Bash(
     command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-verify.sh <plan.json> <step-number>"
     run_in_background: true
   )
   ```
3. **Wait for the wrapper to finish.** Use Monitor on the background
   shell or block on the next message. Do NOT tail the stream file to
   "watch progress". The wrapper exits when Codex is done and the
   receipt + HMAC sidecar are on disk.
4. **Read the receipt only:** open
   `<plan-dir>/codex-receipt-step-<N>.json`. The strict
   `verify-step-completion` hook will independently re-validate the
   sidecar binding when `complete-step` fires, so the conductor only
   needs the receipt's `finalVerdict` for routing.
5. **If `finalVerdict == "PASS"`**: write the step result using the
   `### Criterion:` template (map each acceptance criterion to the
   receipt's `criteria[]` entries), add `### Verdict\nCodex: PASS`,
   then mark done via `complete-step`.
6. **If `finalVerdict == "FINDINGS"` or `"FAIL"`**: read `findings[]`
   from the receipt, fix each one, then re-run verification. Repeat
   until the receipt comes back PASS.

### For `codex-impl` steps (Codex implements, Claude verifies)

1. **Dispatch Codex implementation:**
   ```
   Bash(
     command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-implement.sh <plan.json> <step-number>"
     run_in_background: true
   )
   ```
2. **Wait for the wrapper to finish.** Same as above — no stream
   tailing.
3. **Read the receipt only:** open
   `<plan-dir>/codex-receipt-step-<N>.json` to confirm Codex emitted
   it. The conductor does NOT inspect `git diff` or modified files
   directly.
4. **Dispatch the verification digester sub-agent.** This is
   mandatory for every codex-impl step:
   ```
   Agent(
     description: "lbyl-digest verification",
     subagent_type: "general-purpose",
     prompt: "Load <project-root>/look-before-you-leap/skills/lbyl-digest/SKILL.md as primary guidance. Run mode=verification with plan-dir=<plan-dir>, step-N=<N>, project-root=<project-root>. Return ONLY the bounded verification payload shape defined by that skill: { kind, stepId, claudeVerified, findingCount, reviewPath, criteria, summary }. Do not include prose, markdown fences, or follow-up text."
   )
   ```
   The sub-agent reads the receipt + the cited file ranges + runs the
   independent diff-vs-receipt and sha256 cross-checks, and writes
   `<plan-dir>/codex-receipt-step-<N>.claude-review.json`. It returns
   a bounded payload `{ kind, stepId, claudeVerified, findingCount,
   reviewPath, criteria, summary }`.
   After the `lbyl-digest` Agent returns, the conductor MUST
   auto-resume by consuming that payload and continuing; the JSON
   payload IS the trigger to continue.
5. **Gate on the digester's payload:**
   - `claudeVerified == "PASS"` → write the step result using the
     `### Criterion:` template (driven by the returned `criteria[]`
     verdicts), add `### Verdict\nClaude: verified`, mark done.
   - `claudeVerified == "FINDINGS"` → inspect the returned `criteria`
     to identify failing ids and decide whether to re-dispatch Codex,
     patch via a Claude implementation sub-agent, or escalate to the
     user. If the conductor patches, dispatch Codex implement again
     and re-run the digester on the new receipt.

The `verify-step-completion` hook (per receipt-schema §1.1) enforces
the trust chain: the HMAC sidecar must verify, the receipt's
`artifactSha256` must match the on-disk receipt, and for codex-impl
steps the sibling `claude-review.json` must exist with
`claudeVerified == "PASS"` and a matching `receiptSha256`. This makes
"Codex verifies Codex" structurally impossible.

---

## Conductor Mode (the only mode)

Two collaboration modes exist on plan steps: `claude-impl` and
`codex-impl`. The conductor handles both via the receipt-first flow
above. There is no `collab-split` and no in-step group ownership —
file isolation lives at the step boundary, enforced by the DAG.

A small number of steps may carry the optional `dual-pass` flag (see
"Dual-Pass" below); these are still receipt-driven, just with two
sequential dispatches.

---

## Parallel DAG Dispatch

The conductor parallelizes across the runnable frontier of the
dependency graph. To find what is runnable right now:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/plan_utils.py runnable-steps <plan.json>
```

This returns every step whose `status == "pending"` and whose
`dependsOn[]` predecessors are all `done`. The DAG is constructed so
that overlapping `files[]` create dependency edges — steps in the
runnable frontier are guaranteed to have disjoint files (modulo the
wrapper-self-modification exception below).

For each step in the frontier, dispatch in parallel via
`run_in_background: true`:

- `claude-impl` steps: Claude implements (potentially via Claude
  sub-agents for batches), then dispatches `run-codex-verify.sh` in
  the background.
- `codex-impl` steps: dispatch `run-codex-implement.sh` in the
  background.

Each `codex exec` invocation runs independently — no coordination
between parallel Codex processes is needed because:

- Each step has isolated files (enforced by `dependsOn`).
- Each step writes to its own receipt + sidecar pair
  (`codex-receipt-step-<N>.json` + sidecar in
  `~/.claude/look-before-you-leap/state/<projectId>/<planId>/`).
- Per-step codexSessions in `progress.json` prevent session collision.

When dispatching Codex for a step that is part of a parallel batch,
the prompt MUST note which other steps are running concurrently (for
awareness, not coordination — Codex should not attempt to coordinate
with parallel steps). This helps Codex avoid touching files outside
its step's scope. The wrappers already inject this from the runnable
frontier.

After dispatching the batch, wait for all background shells to
finish, then for each completed step:

1. Read its `codex-receipt-step-<N>.json`.
2. For `codex-impl`: dispatch `lbyl-digest` (verification mode).
3. Apply the receipt-first gate, write the step result, call
   `complete-step`.
4. Re-fetch `runnable-steps` and dispatch the new frontier.

### MUST: Serialize steps that modify the dispatch wrappers themselves

**NEVER dispatch a `codex-impl` step that edits `run-codex-implement.sh`,
`run-codex-verify.sh`, or any other wrapper script you are actively using
to dispatch Codex — in parallel with other dispatches that use that script.**

Bash reads scripts incrementally. If a wrapper script is rewritten while
other shells are still executing it, the running shells hit different bytes
than they originally parsed. This produces silent corruption: `exit 127`
("command not found") on fragments like `dex-receipt-v1` when a heredoc
delimiter changes; truncated post-processing; lost HMAC sidecars; or
unpredictable parse errors at arbitrary line numbers. In the worst cases
the script appears to "succeed" with a misleading exit code. The Codex
side typically still completes (the receipt is written), but the wrapper's
post-codex bookkeeping is destroyed.

**Identifying self-modifying steps:** before dispatching the DAG frontier,
inspect each step's `files[]`. If ANY step in the candidate parallel batch
has `look-before-you-leap/scripts/run-codex-implement.sh`,
`run-codex-verify.sh`, or any other actively-used dispatch script in its
`files[]`, that step MUST be dispatched ALONE. Hooks the wrappers source
(e.g., `hooks/lib/find-root.sh`, `hooks/lib/receipt-state.sh`) count too —
a step editing them has the same race risk.

**Correct sequencing:**

1. Partition the runnable frontier into:
   - **Wrapper-modifying steps** (any file in the actively-used dispatch
     toolchain).
   - **Safe-to-parallelize steps** (everything else).
2. Dispatch the safe set in parallel as usual.
3. Wait for the safe set to finish + complete-step + clear markers.
4. Dispatch each wrapper-modifying step ALONE. Wait for it to finish
   completely (Codex AND the wrapper's post-codex section AND
   `complete-step`) before dispatching anything else — including
   verification subagents that themselves invoke the wrapper.
5. Re-fetch the runnable frontier; resume parallel dispatch.

**Symptom recognition:** if you see `exit 127` with a "command not found"
error referencing a fragment of a heredoc delimiter, OR `exit 143`
(SIGTERM) on parallel codex-impl tasks, suspect a wrapper-modification
race or a SessionStart kill loop. Check `git diff` on the wrapper script
for the steps that were running concurrently. The Codex receipt
(`codex-receipt-step-<N>.json`) often shows `finalVerdict: "PASS"` even
when the bash exit code is nonzero — read the receipt before deciding
the work is lost.

---

## Dual-Pass

A step flagged `dual-pass` runs both directions sequentially:

1. Claude does its independent pass first (design / UX / architecture
   judgement that Codex is not well suited to make). This is normal
   `claude-impl` work — implement, then dispatch `run-codex-verify.sh`,
   read the receipt, gate on `finalVerdict == "PASS"`.
2. After the verify-receipt is PASS, dispatch a second
   `run-codex-verify.sh` pass with a focused prompt asking Codex to
   re-examine the same files for correctness, security, and edge cases
   the first pass did not target. This produces a second receipt
   (`codex-receipt-step-<N>.json` is overwritten — the first pass's
   PASS verdict is the gate that allowed the second pass).
3. Synthesize both receipts' `findings[]` into the step result. Both
   passes must reach `finalVerdict == "PASS"` before the step can be
   marked done.

Dual-pass semantics are unchanged from prior versions — only the
mechanism (receipt-driven instead of raw-result-driven) is updated.

---

## Skill Injection

Codex skills are globally installed at `~/.codex/skills/`. When Codex
runs via `codex exec`, it automatically loads its installed skills
(`lbyl-verify` and `lbyl-implement`) which provide the verification
and implementation protocols, including the exact receipt schema
Codex must emit.

For step-specific skills (TDD, refactoring, etc.), the relevant skill
guidance is not injected into the prompt — Codex reads `plan.json`'s
`skill` field and can find the skill files in the plugin directory if
needed. The minimal-prompt approach means Codex explores and reads
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

If a step has `owner: "codex"` AND a Claude-only skill, this is a
routing error. Log it, fall back to `"none"`, and note the mismatch.

---

## Symmetric Error Logging

Findings flow in both directions, logged to separate directories.
Both flows are receipt-driven — the conductor never hand-extracts
findings from raw text traces.

### Codex verifies Claude → `usage-errors/codex-findings/`

The `lbyl-verify` skill embeds `findings[]` in the receipt and the
wrapper auto-archives them to `usage-errors/codex-findings/` keyed by
`{plan, step, retry}`. The conductor reads `findings[]` from the
receipt for fixing; the on-disk archive is for plugin-level lessons.

### Claude verifies Codex → `usage-errors/claude-findings/`

When the verification digester sub-agent returns `claudeVerified ==
"FINDINGS"`, the conductor archives the bounded payload's `findings`
(via the digester's `reviewPath` sibling file) to
`usage-errors/claude-findings/` keyed by `{plan, step, retry}`. The
sub-agent does not write into `usage-errors/` itself; the conductor
does, after consuming the payload.

### When to log

Log when verification finds issues. Do NOT log when the receipt's
`finalVerdict == "PASS"` and (for codex-impl) the digester returns
`claudeVerified == "PASS"`.

---

## Co-Exploration Dispatch

During discovery (conductor Step 1), Codex explores the codebase in
parallel with Claude. This uses `codex exec` directly (not the
direction-locked scripts) since there is no step ownership yet.

**Phase 1 — Parallel exploration (background):**

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-exploration.md \
  </dev/null \
  "Explore the codebase for the task: <task-description>. Focus on: \
   1. All consumers of files in scope (trace import chains) \
   2. Blast radius — what breaks if these files change? \
   3. Test infrastructure — what tests cover this code? \
   4. Edge cases and error paths in the current implementation \
   5. Cross-module dependencies that might be missed \
   Format: ## [Codex: <topic>] then bullet points with findings."
```

Run in the background (`run_in_background: true`) — Claude explores
simultaneously while Codex runs. Always close stdin with `</dev/null`
when invoking `codex exec` from the Bash tool; otherwise Codex can hang
waiting for additional stdin.

**Phase 2 — Convergence (background):**

After both agents finish, dispatch Codex for a focused convergence
review. The prompt must ask for **gaps and disagreements only** — not
a rehash of all findings.

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-convergence.md \
  </dev/null \
  "Read <plan-dir>/discovery.md. Focus ONLY on gaps and disagreements: \
   1. What did Claude's exploration miss? (bullet points, max 5) \
   2. Where do you disagree with Claude's findings? (cite specific lines) \
   3. What blast radius was underestimated? (file:consumer count) \
   4. Cross-cutting concerns connecting both sets of findings? (max 3) \
   Keep output to structured bullets — no prose summaries."
```

**Phase 3 — Digest (mandatory).** The conductor does NOT read
`codex-exploration.md` or `codex-convergence.md` itself. Instead, it
dispatches `lbyl-digest` in co-exploration mode:

```
Agent(
  description: "lbyl-digest co-exploration",
  subagent_type: "general-purpose",
  prompt: "Load <project-root>/look-before-you-leap/skills/lbyl-digest/SKILL.md as primary guidance. Run mode=co-exploration with plan-dir=<plan-dir>. Return ONLY the bounded co-exploration payload shape defined by that skill: { kind, digestPath, topicsCount, openQuestionsCount, summary }. Do not include prose, markdown fences, or follow-up text."
)
```

The sub-agent reads `discovery.md`, `codex-exploration.md`, and
`codex-convergence.md`, writes `<plan-dir>/discovery-digest.md`, and
returns `{ kind, digestPath, topicsCount, openQuestionsCount, summary }`.
After the `lbyl-digest` Agent returns, the conductor MUST auto-resume
by consuming that payload and continuing; the JSON payload IS the
trigger to continue.
The conductor reads only `summary` and `openQuestionsCount` to decide
whether to surface open questions to the user before proceeding to
`writing-plans`. The conductor opens `discovery-digest.md` only if the
summary indicates it must.

If discovery.md exceeds ~100 lines, the prompt to Codex (Phase 2)
should already specify which sections to focus on; the digester
absorbs further compression.

---

## Codex Output Batching Principle

Large Codex dispatches stall when the prompt asks Codex to process
unbounded input (e.g., "For EACH of 15 steps..." or "Read ALL 200 lines
of findings..."). Apply this rule to every `codex exec` call:

- **Batch into groups of 5.** If the input has more than 5 items
  (steps, disagreements, findings sections), split into sequential
  `codex exec` calls of ≤5 items each. The downstream digester merges
  results between batches.
- **Never retry an oversized prompt.** If a `codex exec` call times
  out or produces truncated output, split it — do not re-run the same
  prompt.
- **Cap output scope.** Ask for structured bullet points, not
  open-ended prose. Specify what to focus on (gaps, disagreements,
  missing items) — not "review everything."

This principle applies to consensus, convergence, verification, and
any other multi-item Codex dispatch.

---

## Plan Consensus Dispatch

After `writing-plans` produces the plan (conductor Step 2), Codex and
Claude reach consensus through structured debate before Orbit review.
Uses `codex exec` directly (not direction-locked scripts).

**IMPORTANT: Run all consensus `codex exec` calls in foreground (no
`run_in_background`).** Background notifications arriving during plan
mode handoff break the context clear.

**Round 1 — Codex reviews the plan:**

If the plan has **≤5 steps**, dispatch a single call:

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-round1.md \
  </dev/null \
  "Read the plan at <plan-dir>/masterPlan.md and <plan.json>. \
   For steps 1-N, return a structured proposal per step: \
   - ACCEPT: step is well-sized, criteria are concrete, ownership is correct \
   - REJECT <reason>: step should be removed or fundamentally rethought \
   - MODIFY <changes>: step needs specific changes (sizing, criteria, ownership, ordering) \
   Also flag: missing steps, wrong ordering, vague acceptance criteria, \
   ownership assignments that contradict the routing matrix."
```

If the plan has **>5 steps**, batch into groups of 5:

```bash
# Batch 1: steps 1-5
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-batch-1.md \
  </dev/null \
  "Read the plan at <plan-dir>/masterPlan.md and <plan.json>. \
   Review ONLY steps 1-5. For each, return: \
   - ACCEPT: step is well-sized, criteria are concrete, ownership is correct \
   - REJECT <reason>: step should be removed or fundamentally rethought \
   - MODIFY <changes>: step needs specific changes (sizing, criteria, ownership, ordering)"

# Batch 2: steps 6-10 (adjust range for actual step count)
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-batch-2.md \
  </dev/null \
  "Read the plan at <plan-dir>/masterPlan.md and <plan.json>. \
   Review ONLY steps 6-10. For each, return: \
   - ACCEPT / REJECT <reason> / MODIFY <changes>"

# Continue batching until all steps are covered.
# After all batches, optionally dispatch a cross-cutting check:
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-cross-cutting.md \
  </dev/null \
  "Read <plan-dir>/codex-consensus-batch-*.md. Flag: missing steps, \
   wrong ordering across the full plan, ownership assignments that \
   contradict the routing matrix."
```

**Digest the round (mandatory).** The conductor does NOT read the
batch MD files itself. It dispatches `lbyl-digest` in consensus mode:

```
Agent(
  description: "lbyl-digest consensus",
  subagent_type: "general-purpose",
  prompt: "Load <project-root>/look-before-you-leap/skills/lbyl-digest/SKILL.md as primary guidance. Run mode=consensus with plan-dir=<plan-dir>, round-N=1. Return ONLY the bounded consensus payload shape defined by that skill: { kind, round, digestPath, counts, decisions, openDisagreements, summary }. Do not include prose, markdown fences, or follow-up text."
)
```

The sub-agent reads every `codex-consensus-round1.md` and/or
`codex-consensus-batch-*.md` (and the cross-cutting file if present),
writes `<plan-dir>/consensus-round-1-digest.md`, and returns
`{ kind, round, digestPath, counts, decisions, openDisagreements,
summary }`. The conductor reads only the bounded payload —
`counts` to decide whether the plan can advance, `decisions` to know
which steps need plan edits, `openDisagreements` to know what to
respond to in Round 2.
After the `lbyl-digest` Agent returns, the conductor MUST auto-resume
by consuming that payload and continuing; the JSON payload IS the
trigger to continue.

**Round 2 — Claude responds** to each `decision` from the digester
(ACCEPT / REJECT with reasoning / COUNTER-PROPOSE). Update plan files
with accepted changes.

**Round 3 (if needed) — Final resolution:**

If `openDisagreements` remain after Round 2, dispatch Codex one more
time with the disagreement list (≤5 per call; batch as in Round 1):

```bash
codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox \
  -o <plan-dir>/codex-consensus-round3.md \
  </dev/null \
  "Read the updated plan at <plan-dir>/plan.json and Claude's responses \
   to your proposals. For these remaining disagreements: [list ≤5 items] \
   - ACCEPT Claude's reasoning, or \
   - ESCALATE with both positions stated (for the user to decide in Orbit)"
```

Then re-dispatch `lbyl-digest` in consensus mode for round 3 and gate
on its returned `openDisagreements`.

**Max 3 rounds.** Unresolved items go to Orbit with both positions
stated.

Co-exploration and plan consensus are **mandatory when Codex is
available**. If `command -v codex` fails, document the fallback in
`discovery.md` and pass `codexStatus=unavailable` to the discovery
receipt. Do NOT skip co-exploration without running the preflight
check first.

---

## Error Handling

### Codex CLI not available

If `command -v codex` fails:
- Skip all Codex interactions.
- Use the `### Criterion:` template for each step's result, with
  `### Verdict\nCodex: skipped — codex CLI not installed`.
- The plan proceeds as fully Claude-owned.

### Codex hangs (no receipt produced)

If a backgrounded wrapper has not exited after a reasonable wait
(default: 5 minutes for verify, 15 minutes for implement):
- Check whether `codex-receipt-step-<N>.json` was written. If it
  was, the wrapper crashed in its post-codex section but Codex
  itself completed — read the receipt and proceed (the strict hook
  will still validate the sidecar).
- If no receipt exists, kill the background shell and retry the
  dispatch once.
- If the second attempt also fails to produce a receipt, skip
  Codex for this step and note it in the verdict.

Do NOT tail or open the stream JSONL or the `.txt` trace to
diagnose the hang from the main thread. If you need to inspect raw
trace data, dispatch a generic sub-agent ("read this file and
return a bounded summary") — never read it inline.

### Codex fails mid-implementation

If the receipt exists with `finalVerdict == "FAIL"` or a non-zero
`codexExitCode`:
1. Dispatch `lbyl-digest` in verification mode anyway — the digester
   will run the diff-vs-receipt cross-check and return what is
   recoverable.
2. Decide based on the digester's payload: patch via a Claude
   sub-agent, re-dispatch Codex, or escalate to the user before
   reverting changes.

### Codex times out

`codex exec` has its own timeout handling. If it exits non-zero, the
wrapper still attempts to write the receipt with whatever Codex
produced. Treat as above — read the receipt, gate on
`finalVerdict`.

---

## Compaction Recovery

After context compaction, codex-dispatch recovers from `plan.json` +
`progress.json`:

1. Read `plan.json` (definition) + `progress.json` (state) — find
   ALL `in_progress` steps (there may be multiple during parallel
   execution).
2. For each in-progress step:
   - Check its `dependsOn` — if all predecessors are done, the step
     was legitimately parallel.
   - Check whether `<plan-dir>/codex-receipt-step-<N>.json` exists.
     If yes, Codex finished — proceed with the receipt-first gate
     (and dispatch `lbyl-digest` for codex-impl steps).
   - If no receipt exists, the wrapper is either still running or
     was killed. Re-dispatch.
3. Continue the execution loop based on plan state.

No thread state to recover — each `codex exec` call is standalone.
All authoritative context lives on disk: `plan.json`, `progress.json`,
the receipt + sidecar pair per step, and the digester output files
(`discovery-digest.md`, `consensus-round-<N>-digest.md`,
`codex-receipt-step-<N>.claude-review.json`).

---

## Quick Reference

| Situation | Action |
|---|---|
| `claude-impl` step done | Run `run-codex-verify.sh` in background; on completion, read receipt, gate on `finalVerdict == "PASS"`. |
| `codex-impl` step starting | Run `run-codex-implement.sh` in background; on completion, dispatch `lbyl-digest` (verification mode). |
| Receipt `finalVerdict == "PASS"` (claude-impl) | Write `### Criterion:` result, add `### Verdict\nCodex: PASS`, mark done. |
| Receipt `finalVerdict == "FINDINGS"` | Read `findings[]` from receipt, fix issues, re-run wrapper. |
| Codex implements step | Receipt + `lbyl-digest` (verification mode) → gate on `claudeVerified == "PASS"`. |
| Co-exploration (discovery) | Phase 1 + Phase 2 codex exec, then `lbyl-digest` (co-exploration mode). |
| Plan consensus (planning) | Up to 3 rounds; after each round, `lbyl-digest` (consensus mode). |
| Dual-pass step | Two sequential `run-codex-verify.sh` dispatches; both receipts must be PASS. |
| Codex not installed | Skip, note in result. |
| Codex hangs | Wait reasonable timeout, check for receipt; retry once if missing; skip and note if persistent. |
| Parallel dispatch | Use `runnable-steps`; serialize wrapper-modifying steps alone. |
| After compaction | Read `plan.json` + `progress.json`, look for receipts on disk, continue. |
| Claude finds issues in Codex work | Conductor archives digester payload findings to `usage-errors/claude-findings/`. |
