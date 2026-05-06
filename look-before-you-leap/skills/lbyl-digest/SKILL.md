---
name: lbyl-digest
description: "INTERNAL conductor-dispatched digester skill for the look-before-you-leap plugin. Reads raw on-disk artifacts (Codex exploration MD, consensus batch MD files, codex-receipt-step-N.json + diff + modified files) and produces bounded, substance-preserving digests so the main Claude thread never reads raw bytes. Three operating modes: (1) co-exploration digester — merges Claude+Codex exploration outputs into discovery-digest.md; (2) consensus digester — collapses multi-batch consensus outputs into consensus-round-N-digest.md with ACCEPT/MODIFY/REJECT counts and open disagreements; (3) verification digester — reads the codex-receipt-step-N.json evidence artifact, the file changes Codex made, and the modified files themselves, and writes a sibling claude-review file with PASS/FINDINGS verdict + per-finding evidence. Dispatched ONLY by the conductor (look-before-you-leap, codex-dispatch, writing-plans) via the Skill or Agent tool. NEVER assignable as a plan-step skill in plan.json. NEVER write code, NEVER mint HMAC sidecars, NEVER pass --model flags."
---

# lbyl-digest

> **INTERNAL skill — conductor-dispatched only.**
>
> This skill is invoked exclusively by the conductor (the
> `look-before-you-leap`, `codex-dispatch`, and `writing-plans` skills)
> through the Skill tool or as the sub-agent context for an Agent tool
> dispatch. It MUST NOT appear as the value of `step.skill` in any
> `plan.json`. It is not a plan-routable skill — it has no acceptance
> criteria, no progress items, and no result template. It is a stateless
> reader/summarizer that the conductor uses to keep its own context
> bounded.
>
> If you find yourself reading this SKILL.md because a plan step listed
> `look-before-you-leap:lbyl-digest` as its skill, that is a routing
> error. Stop, log it, fall back to `"none"` for that step, and notify
> the conductor.

---

## Why this skill exists

The `codex-first-conductor` refactor moves implementation, verification,
and exploration into sub-agents so the main Claude thread reads only
**receipts and digests**, never raw artifacts. Three classes of raw
artifact recur:

1. **Co-exploration outputs** — Claude's notes plus
   `codex-exploration.md` (often plus `codex-convergence.md`). Together
   these can be hundreds of lines of bullets, half of which restate
   things the conductor already knows.
2. **Consensus batch outputs** — when a plan has more than 5 steps,
   `codex-dispatch` runs Codex in batches of 5 and produces
   `codex-consensus-batch-1.md`, `-batch-2.md`, etc. Each one repeats
   the ACCEPT/MODIFY/REJECT structure. The conductor needs counts and
   the surviving disagreements, not the full prose.
3. **Verification artifacts** — `codex-receipt-step-N.json` (per the
   schema in `references/codex-receipt-schema.md`) plus `git diff` of
   the step's files plus the files themselves. The conductor needs to
   know whether the Codex receipt actually matches what changed on disk.

`lbyl-digest` reads each class of artifact in a fresh sub-agent context
and returns a bounded payload to the conductor.

---

## Hard rules (apply to every digester mode)

### Substance-vs-restatement rule (verbatim)

> **Include every finding that would change a plan decision or identify
> a consumer/blast-radius. Drop restatements, tutorials, and file
> listings that aren't consumed.**

This is the central correctness rule. It is not a brevity guideline —
it is a substance rule. Trim restatement, never trim substance. There
is **no hard size limit** on any digest. A correct digest of a
500-finding consensus round may legitimately be longer than an
incorrect digest of a 20-finding round.

#### Worked example

Bad (restatement, would be cut):
> "Codex reviewed step 4 and noted that step 4's acceptance criteria
> include passing tsc. Codex confirmed that tsc passes. Step 4 also
> requires that the new component renders without errors, and Codex
> confirmed it does. Codex reviewed each of the 6 acceptance criteria
> and confirmed all 6 pass."

Why bad: The conductor already has the acceptance criteria from
`plan.json`. Repeating "Codex confirmed criterion N" 6 times burns
context for zero new information. The PASS verdict alone (with
per-criterion verdict counts pulled from the receipt) carries the same
information.

Good (substance, must be kept):
> "PASS, 6/6 criteria. Note: Codex reports that
> `src/components/Modal.tsx:142-156` was modified to handle the new
> prop, but the same prop type is also consumed by
> `src/components/Drawer.tsx:88` and
> `src/components/Sheet.tsx:73-80`, neither of which Codex modified.
> Conductor should grep these consumers before marking step done."

Why good: The blast-radius observation (two unmodified consumers of the
same prop type) is exactly the kind of finding that would change a
plan decision. It is not in the receipt's `criteria[]` array — it is a
cross-cutting observation that only emerges when the digester reads
the receipt and the surrounding files together.

### Model pinning (NEVER override)

**NEVER pass `--model` flags when dispatching sub-agents or running
`codex exec` from inside this skill. Inherit the machine defaults.**

- The Claude Code default on this machine MUST be Opus 4.7 high.
- The Codex default profile MUST be GPT-5.5 high fast.
- NEVER downgrade to `sonnet`, `haiku`, `gpt-5`, or any non-default
  model variant — not "to save tokens", not "because the task seems
  small", not "because the dispatch is just a digester".

A digester running on a weaker model produces a worse digest, and the
conductor cannot detect the degradation because the conductor is
literally avoiding reading the raw artifacts. Model downgrades here
silently destroy the conductor's accuracy. There are zero acceptable
exceptions.

If you find yourself typing `--model`, `-m`, `--effort low`, or any
similar override flag, **stop**. The default is the contract.

### Boundaries — what this skill never does

- **Never write code.** This is a read/summarize skill. If a digest
  surfaces a finding that requires a code fix, the conductor decides
  who fixes it (Codex re-dispatch, Claude sub-agent, or escalation to
  the user).
- **Never mint or modify HMAC sidecar receipts.** The signed sidecar
  in `~/.claude/look-before-you-leap/state/<projectId>/<planId>/` is
  written ONLY by `run-codex-verify.sh` / `run-codex-implement.sh` via
  `receipt_utils.sign()`. Touching the sidecar from a digester would
  invalidate the artifact↔sidecar binding (see Hook/security note
  below).
- **Never modify `codex-receipt-step-N.json` in place.** The HMAC
  sidecar binds `data.artifactSha256` to the exact bytes of the
  artifact on disk; mutating the artifact breaks the strict verifier
  in `references/codex-receipt-schema.md` §1.1.
- **Never re-dispatch Codex on its own.** If the verification digester
  finds problems, it returns FINDINGS. The conductor decides whether
  to re-dispatch.
- **Never read `.codex-result-step-N.txt` as authoritative.** That
  file is a human trace only (per `references/codex-receipt-schema.md`
  §1 and §6). Authoritative parsing reads
  `codex-receipt-step-N.json` only.

---

## Digester (1): Co-exploration digester

### Input contract

The conductor passes:
- `<plan-dir>` — absolute path to the active plan directory
  (e.g., `.temp/plan-mode/active/<plan-name>/`).
- The current `discovery.md` (already contains Claude's exploration
  notes; may also contain Codex's appended findings).

Files to read:
- `<plan-dir>/discovery.md` — Claude's exploration notes plus any
  `## [Codex: …]` sections appended via `cat codex-exploration.md >>
  discovery.md`.
- `<plan-dir>/codex-exploration.md` — raw Codex exploration output
  from Phase 1 (if present and not yet merged).
- `<plan-dir>/codex-convergence.md` — raw Codex convergence output
  from Phase 2 (if present).

Fields to extract:
- Consumers / blast-radius observations (file:line + consumer file).
- Cross-module dependencies neither agent's solo pass would have caught.
- Disagreements between Claude and Codex (cite the specific lines that
  disagree).
- Test infrastructure and coverage gaps.
- Open questions that block planning.

Discard:
- Pure restatements of which files exist in the repo.
- Tutorial-style explanations of how a framework works.
- File listings that no subsequent step consumes.

### On-disk output

Write to: `<plan-dir>/discovery-digest.md`

Format: one section per topic, each topic begins with the topic name
in square brackets and a one-line headline, then bullets with concrete
file:line evidence. Example:

```
# Discovery Digest — <plan-name>

## [Blast radius]
- src/lib/auth-guard.ts is consumed by 14 callers across 3 packages
  (apps/web/src/middleware/*.ts:12-89, apps/api/src/handlers/*.ts:7-42,
  packages/shared/auth/index.ts:5). Plan must split per package or
  serialize.

## [Disagreements]
- Claude says SessionStore is stateful (discovery.md:88-94); Codex says
  the writes are debounced via the queue at src/lib/session-queue.ts:34.
  Resolution: both correct — store is stateful but writes are async.
  Conductor should plan tests that exercise both paths.

## [Open questions]
- Should the new auth flow share the existing rate-limit middleware
  (apps/api/src/middleware/rate-limit.ts:18) or get its own? No
  precedent in repo.
```

### Returned payload shape (to the conductor)

```
{
  "kind": "co-exploration",
  "digestPath": "<plan-dir>/discovery-digest.md",
  "topicsCount": <int>,
  "openQuestionsCount": <int>,
  "summary": "<2-4 sentence prose>: blast radius headline, key
              disagreement (if any), open questions count."
}
```

The conductor reads `summary`, sees `openQuestionsCount`, and decides
whether to surface open questions to the user before proceeding to
`writing-plans`. The conductor does NOT read the digest file unless
the summary indicates it must.

### Substance rule applied here

Drop file inventories ("here are the 47 files in src/lib"). Keep
consumer counts and disagreement citations — those change planning
decisions.

---

## Digester (2): Consensus digester

### Input contract

The conductor passes:
- `<plan-dir>` — absolute path to the active plan directory.
- `<round-N>` — integer round number (1, 2, or 3).

Files to read (glob patterns):
- `<plan-dir>/codex-consensus-round<N>.md` — single-call consensus
  output (used when plan has ≤5 steps).
- `<plan-dir>/codex-consensus-batch-*.md` — multi-batch outputs (used
  when plan has >5 steps; may be `batch-1.md`, `batch-2.md`, etc.).
- `<plan-dir>/codex-consensus-cross-cutting.md` — optional, present
  only when the conductor ran a follow-up cross-cutting check across
  merged batches.

Fields to extract:
- For each step proposal in each batch: the verdict (`ACCEPT`,
  `MODIFY <changes>`, or `REJECT <reason>`).
- The set of steps whose ownership / sizing / criteria are being
  contested.
- Cross-cutting concerns flagged in the cross-cutting file (missing
  steps, wrong ordering, ownership contradictions with the routing
  matrix).

Discard:
- Re-quoting of step descriptions from `plan.json` — the conductor
  has those.
- Codex's restatement of the routing matrix.
- Praise prose ("this step looks good") — the ACCEPT count carries
  the same information.

### On-disk output

Write to: `<plan-dir>/consensus-round-<N>-digest.md`

Format:

```
# Consensus Round <N> Digest — <plan-name>

## Counts
- ACCEPT: <int>
- MODIFY: <int>
- REJECT: <int>
- Total steps reviewed: <int>

## Modifications (one bullet per step that needs work)
- Step <id> "<title>": MODIFY — <Codex's concrete change request,
  one line>. Conductor action: <accept | counter-propose | escalate>.

## Rejections
- Step <id> "<title>": REJECT — <reason>. Conductor action: <…>.

## Cross-cutting concerns
- <one bullet per cross-cutting issue, with the steps it touches>

## Open disagreements (carry to next round if any)
- <one bullet per disagreement Claude has not yet responded to>
```

### Returned payload shape (to the conductor)

```
{
  "kind": "consensus",
  "round": <N>,
  "digestPath": "<plan-dir>/consensus-round-<N>-digest.md",
  "counts": { "accept": <int>, "modify": <int>, "reject": <int>,
              "total": <int> },
  "decisions": [
    { "stepId": <int>, "title": "<step title>",
      "verdict": "MODIFY" | "REJECT",
      "request": "<one-line: Codex's concrete change/reason>",
      "conductorAction": "accept" | "counter-propose" | "escalate" }
  ],
  "openDisagreements": [
    { "stepId": <int>, "title": "<step title>",
      "summary": "<one-line>" }
  ],
  "summary": "<2-3 sentence prose>: counts, headline disagreements."
}
```

`decisions` MUST include EVERY MODIFY and REJECT step (no cap — each
one is an actionable plan decision the conductor must respond to;
ACCEPT items are intentionally omitted because the count alone is
sufficient). `openDisagreements` carries any disagreement Claude has
not yet responded to (may overlap with `decisions` when a MODIFY is
also unresolved across rounds).

The conductor reads `counts` to decide whether the plan can advance to
Orbit (e.g., `reject == 0 && openDisagreements.length == 0`) or
whether Round 2 is needed. It reads `decisions` to know which steps
need plan edits and what action to take, and `openDisagreements` to
know what to respond to — all without opening the digest file.

### Substance rule applied here

Drop the per-step ACCEPT prose — a single count is sufficient. Keep
every MODIFY/REJECT line because each one is a plan decision the
conductor must respond to.

---

## Digester (3): Verification digester

### Input contract

The conductor passes:
- `<plan-dir>` — absolute path to the active plan directory.
- `<step-N>` — integer step number being verified.
- `<project-root>` — absolute path to the project root (for `git diff`
  scoping).

Files to read:
- `<plan-dir>/codex-receipt-step-<N>.json` — the **authoritative**
  evidence artifact, schema per
  `references/codex-receipt-schema.md` §2. This is the only source of
  truth for what Codex claims it did.
- `<project-root>` `git diff` scoped to the step's `files` array
  (read via `git diff -- <file1> <file2> …` against the parent of
  Codex's working commit). The digester checks that
  `receipt.filesChanged[].path` matches the actual diff and that
  `receipt.filesChanged[].sha256After` matches the file on disk.
- The modified files themselves — at the line ranges referenced in
  `receipt.criteria[].evidence[].file/lineStart/lineEnd`. The digester
  reads only the cited line ranges, not entire files.

Fields to extract from the receipt (per schema):
- `schemaVersion`, `kind`, `stepId`, `owner`, `mode` — sanity check.
- `codexExitCode` — must be 0 for any non-FAIL outcome.
- `criteria[].id`, `criteria[].acceptanceCriterion`,
  `criteria[].acceptanceCriterionSha256`, `criteria[].verdict`,
  `criteria[].evidence[]` — per-criterion verdicts and evidence.
- `filesChanged[].path`, `filesChanged[].changeType`,
  `filesChanged[].sha256After` — what Codex says it changed.
- `findings[]` — Codex's self-reported findings (severity, category,
  file, line, summary).
- `finalVerdict` — Codex's mechanically-computed top-level verdict
  (PASS / FINDINGS / FAIL).
- `digestHints` (optional) — Codex's hints to digesters about which
  files/findings to surface first.

Independent checks the digester MUST run:
1. **Diff vs receipt cross-check.** Every path in `git diff
   --name-only` for the step's files MUST appear in
   `receipt.filesChanged[]` (and vice versa). Mismatches are a
   FINDINGS-class problem — Codex modified a file it did not declare,
   or declared a file it did not modify.
2. **Sha256 cross-check.** For each `receipt.filesChanged[i].path`,
   re-hash the file at `<project-root>/<path>` and verify it equals
   `receipt.filesChanged[i].sha256After`. A mismatch means the file
   has been touched after Codex finished — escalate.
3. **Evidence read.** For each `criteria[i].evidence[]` entry of
   `type: "file"`, read the cited line range and verify it actually
   contains code that satisfies `criteria[i].acceptanceCriterion`.
   This is the qualitative check the receipt cannot self-attest.
4. **Findings reconciliation.** If `receipt.findings[]` is non-empty,
   note that the receipt's own `finalVerdict` should be `FINDINGS`
   (not `PASS`). If the receipt claims `PASS` while findings exist,
   that is a schema violation — escalate.

### On-disk output

Write to: `<plan-dir>/codex-receipt-step-<N>.claude-review.json`

This is a **sibling file** to the receipt, NOT an in-place update of
the receipt. The receipt JSON is left byte-identical so the HMAC
sidecar binding in `~/.claude/look-before-you-leap/state/…` remains
valid (see Hook/security note below).

Sibling-file shape:

```json
{
  "schemaVersion": "1.0.0",
  "kind": "claude-verification-digest",
  "stepId": <N>,
  "receiptPath": "<plan-dir>/codex-receipt-step-<N>.json",
  "receiptSha256": "<hex sha256 of the receipt file as read>",
  "claudeVerified": "PASS" | "FINDINGS",
  "findings": [
    {
      "severity": "HIGH" | "MEDIUM" | "LOW",
      "category": "INCOMPLETE_WORK" | "MISSED_CONSUMER" |
                  "TYPE_SAFETY" | "SILENT_SCOPE_CUT" |
                  "WRONG_PATTERN" | "MISSING_TEST" |
                  "MISSING_I18N" | "OTHER",
      "summary": "<one-line>",
      "rationale": "<why this is a finding>",
      "evidence": [
        { "type": "file", "file": "<rel path>",
          "lineStart": <int>, "lineEnd": <int> }
      ],
      "criterionId": <int | null>
    }
  ],
  "crossChecks": {
    "diffMatchesReceipt": true | false,
    "sha256AllMatch": true | false,
    "findingsReceiptConsistent": true | false
  },
  "generatedAt": "<ISO 8601 UTC>"
}
```

Why a sibling file rather than an in-place `claudeVerified` field on
the artifact: see "Hook/security note" below. The sibling is bound to
the receipt by `receiptPath` + `receiptSha256` — downstream readers
(hook updates in plan steps 5–10) verify the binding by re-hashing
the receipt file and checking equality.

### Returned payload shape (to the conductor)

```
{
  "kind": "verification",
  "stepId": <N>,
  "claudeVerified": "PASS" | "FINDINGS",
  "findingCount": <int>,
  "reviewPath": "<plan-dir>/codex-receipt-step-<N>.claude-review.json",
  "criteria": [
    { "id": <int>, "verdict": "PASS" | "FAIL" | "SKIPPED" }
  ],
  "summary": "<2-4 sentence prose>: PASS or FINDINGS verdict, the
              top-severity finding category if FINDINGS, the
              cross-check that failed if any."
}
```

`criteria` MUST include EVERY entry from the receipt's `criteria[]`
array (id + verdict only — no rationale/evidence; those live in the
sibling `reviewPath` file). This mirrors the receipt schema's
`criteria[]` shape (see `references/codex-receipt-schema.md` §2,
`required: ["id", ..., "verdict", ...]`) so the conductor can show
per-criterion status without opening the review file. No size cap is
needed: criterion counts are bounded by the step's
`acceptanceCriteria` length (typically 1–6).

The conductor reads `claudeVerified` + `findingCount` for the gate
decision and `criteria` to surface per-criterion status. On PASS it
proceeds to mark the step done (subject to the existing strict
receipt gate). On FINDINGS it inspects `criteria` for the failed ids
and decides whether to re-dispatch Codex, patch via a Claude
sub-agent, or escalate.

### Substance rule applied here

Drop the receipt's per-criterion prose if every criterion verdict is
PASS — the verdict counts and `claudeVerified: PASS` carry the
information. Keep every cross-check failure (diff/receipt mismatch,
sha256 mismatch) because each one is a trust-anchor problem the
conductor must act on.

---

## Hook / security note (verification digester only)

**The digester MUST NOT modify the HMAC sidecar.** The signed sidecar
in `~/.claude/look-before-you-leap/state/<projectId>/<planId>/codex_verify-step-<N>.json`
binds `data.artifactSha256` to the exact bytes of
`<plan-dir>/codex-receipt-step-<N>.json` on disk. Any in-place
mutation of the artifact — including adding a `claudeVerified` key —
would change the artifact bytes, change the sha256, and break the
binding. The strict verifier defined in
`references/codex-receipt-schema.md` §1.1 rejects sidecars whose
`data.artifactSha256` does not match the on-disk file. So an in-place
update would silently invalidate the receipt the next time the hook
runs, and the step would become un-verifiable.

The digester ALSO MUST NOT re-mint or re-sign the sidecar. Only
`run-codex-verify.sh` and `run-codex-implement.sh` are allowed to call
`receipt_utils.sign()` (the secret key in
`~/.claude/look-before-you-leap/state/secret.key` is mode 0600 and the
direction-locked scripts are the only sanctioned writers). Calling
`receipt_utils.sign()` from a digester sub-agent would conceptually
extend the trust boundary in a way the security model does not
permit.

**Chosen approach: sibling file.** The digester writes
`<plan-dir>/codex-receipt-step-<N>.claude-review.json` next to the
receipt, with `receiptPath` + `receiptSha256` binding the review back
to the exact receipt bytes it inspected. Downstream consumers
(`verify-step-completion.sh` updates in plan steps 5–10, the
conductor's done-gate) check both files exist, that
`review.receiptSha256 == sha256(open(review.receiptPath).read())`, and
that `review.claudeVerified == "PASS"` before allowing the step to be
marked done.

This approach was chosen over two alternatives:
- **In-place `claudeVerified` field on the artifact** — rejected
  because it would invalidate the HMAC sidecar binding (above).
- **Re-signing the artifact via a "sanctioned" plugin script** —
  rejected because adding a second writer to the secret-key boundary
  doubles the attack surface for negligible benefit. The sibling file
  is unsigned and that is fine: it is *Claude's review of Codex's
  signed work*, not a fresh trust anchor. The signed sidecar still
  carries the only trust anchor — that Codex actually ran and
  produced the artifact whose sha256 is on file. The sibling adds
  Claude's qualitative judgement on top, not a new layer of
  cryptographic authority.

Plan steps 5–10 (which wire the new digest pipeline into hooks) MUST
update `verify-step-completion.sh` to:
1. Read the existing signed sidecar (unchanged).
2. Read the artifact (unchanged).
3. Additionally read the sibling `*.claude-review.json` if it exists.
4. Verify `review.receiptSha256` matches a fresh re-hash of the
   artifact (catches review-vs-artifact drift).
5. Require `review.claudeVerified == "PASS"` for `owner: "codex"`
   steps, replacing the current "result must contain `Claude:
   verified`" string check.

---

## How the conductor invokes this skill

The conductor never calls this skill speculatively — only when raw
artifacts exist on disk that need digesting before the conductor
reads them. Three concrete invocation sites in the existing
plugin skills:

| Conductor site | Mode | When |
|---|---|---|
| `look-before-you-leap` Step 1 (Explore) Phase 1/2 — co-exploration | (1) co-exploration | After both `codex-exploration.md` and `codex-convergence.md` exist on disk and Claude's Phase 1 notes are appended to `discovery.md`. |
| `codex-dispatch` "Plan Consensus Dispatch" Round 1/3 | (2) consensus | After all `codex-consensus-batch-*.md` (and optional `codex-consensus-cross-cutting.md`) for round N have been written by background `codex exec` calls. |
| `look-before-you-leap` Step 3 execution loop, codex-impl verification | (3) verification | After `run-codex-implement.sh` has finished and the conductor has the `codex-receipt-step-N.json` artifact on disk. |

In all three cases the conductor dispatches a sub-agent (Agent tool,
`subagent_type: "general-purpose"`) and the sub-agent loads this
SKILL.md as its primary guidance. The sub-agent receives the input
contract values (plan-dir, step-N, etc.) in its prompt, performs the
reads, writes the on-disk output, and returns the payload shape
defined for that mode. The conductor consumes only the returned
payload — never the underlying raw files.

If the conductor needs to dispatch this skill to inspect a raw
artifact that does not fit one of the three modes (e.g., an ad-hoc
debugging request to digest a single Codex stream JSONL), it MUST
fall back to a generic "read this file and return a bounded summary"
sub-agent dispatch — not pretend it's one of the three modes. The
three modes have on-disk output contracts that downstream hooks rely
on; do not reuse those output paths for ad-hoc digests.

---

## Quick reference

| Mode | Reads | Writes | Returns |
|---|---|---|---|
| co-exploration | `discovery.md`, `codex-exploration.md`, `codex-convergence.md` | `<plan-dir>/discovery-digest.md` | `{ kind, digestPath, topicsCount, openQuestionsCount, summary }` |
| consensus | `codex-consensus-round<N>.md` OR `codex-consensus-batch-*.md` (+ optional `codex-consensus-cross-cutting.md`) | `<plan-dir>/consensus-round-<N>-digest.md` | `{ kind, round, digestPath, counts, decisions, openDisagreements, summary }` |
| verification | `codex-receipt-step-<N>.json` + `git diff` of step files + cited line ranges in modified files | `<plan-dir>/codex-receipt-step-<N>.claude-review.json` (sibling, NOT in-place) | `{ kind, stepId, claudeVerified, findingCount, reviewPath, criteria, summary }` |

---

## Self-check before returning

Before returning the payload, the digester MUST verify:

1. The on-disk output file was actually written and is readable.
2. The substance-vs-restatement rule was applied — every kept bullet
   is a finding that would change a plan decision or identify a
   consumer/blast-radius. If any kept bullet is a restatement, drop
   it.
3. No `--model` flag was passed in any sub-shell invocation made
   during the digest.
4. (Verification mode only) The HMAC sidecar was NOT touched and the
   receipt artifact was NOT modified in place. The sibling
   `.claude-review.json` is the only new file written.
5. The returned payload matches the shape defined for the mode
   exactly — the conductor parses it programmatically.

If any check fails, fix before returning. Returning a bad digest
silently corrupts every downstream conductor decision.

## End-of-turn contract

This contract applies to all three modes: co-exploration, consensus,
and verification. After emitting the returned bounded payload, you
MUST immediately end your turn. You MUST NOT generate further text.
You MUST NOT ask follow-up questions. You MUST NOT run additional tool
calls. The bounded JSON-shaped payload is the FINAL thing this skill
outputs. The parent conductor consumes the payload programmatically
and resumes — your job ends when the payload is emitted.
