# `codex-receipt-step-N.json` Schema

Status: draft 2 (Claude design pass + Codex tamper-resistance review folded in)
Owner of authoritative parsing: `hooks/verify-step-completion.sh` and `scripts/plan_utils.py`
Owner of authoritative minting: `scripts/run-codex-implement.sh` and `scripts/run-codex-verify.sh` (these are the ONLY processes allowed to write a valid receipt; Claude has no Codex CLI access and cannot forge HMAC signatures because the secret lives in `~/.claude/look-before-you-leap/state/secret.key` mode 0600).

This document defines two artifacts and the binding between them. Together they replace the brittle regex-over-TXT verification gate currently in `verify-step-completion.sh:302-374`.

> **Hook-contract dependency**: this schema only delivers tamper resistance once the hooks/scripts that consume it adopt the strict verifier described in §1.1. The current `receipt_utils.check()` (line 159) only compares `type`/`projectId`/`planId` and accepts replayed sidecars from any step. The strict verifier in §1.1 is required for safety; building the schema without it leaves the system in the same posture as today.

---

## 1. Dual-authority model

| Artifact | Path | Authority | Signed? | Purpose |
|----------|------|-----------|---------|---------|
| **Sidecar receipt** (HMAC) | `~/.claude/look-before-you-leap/state/<projectId>/<planId>/<type>-step-<N>.json` | **Security gate** — hook trust anchor | Yes (HMAC-SHA256 via `receipt_utils.sign()`) | Proof that Codex ran. Hook accepts/rejects step completion based on its presence + signature. |
| **Evidence artifact** (rich JSON) | `<plan-dir>/codex-receipt-step-<N>.json` (in-tree, beside `plan.json`) | **Evidence record** — human + digest readable | No (its sha256 is bound into the sidecar payload) | Per-criterion verdicts, file:line evidence, command exit codes, findings. Read by `verify-step-completion.sh` and digest subagents. |
| **Human trace** (legacy) | `<plan-dir>/.codex-result-step-<N>.txt` | **Trace only** — NOT authoritative | No | Free-form Codex prose. Preserved for human debugging. The main thread MUST NOT read it. |

### Why two artifacts?

- HMAC-signed JSON cannot be embedded inside a Codex CLI prompt response without leaking the secret. Codex emits free-form text via `codex exec -o`; the wrapper script (which has filesystem access to the secret) is the only place that can sign.
- The evidence artifact must be large and addressable (file:line ranges, output shas, criterion arrays). Embedding it inside the HMAC payload would bloat receipts and force re-verification on every read.
- Binding the artifact's `sha256` into the sidecar payload gives tamper detection without inflating the signed payload: any post-mint mutation of the evidence artifact invalidates the binding and the hook rejects the step.

### Linkage field names (exact)

The sidecar receipt's `data` block (the `extra` arg to `receipt_utils.sign()`) MUST include these fields. Every one of them is bound into the HMAC signature; the strict verifier MUST compare every requested field against the signed payload (Codex review fix for the `receipt_utils.check()` replay hole at `receipt_utils.py:159`).

| Sidecar `data.<field>` | Type | Source | Used by |
|------------------------|------|--------|---------|
| `receiptFormatVersion` | str enum: `"1.0.0"` | constant per format revision | strict verifier rejects sidecars without it (cleanly distinguishes legacy step-only receipts) |
| `step` | int | step number | Already used (file naming + check) |
| `stepId` | int | duplicate of `step` for symmetry with the artifact's `stepId` | strict verifier asserts `data.stepId == data.step == artifact.stepId` |
| `kind` | str enum: `verify` \| `implement` | matches receipt type (`codex_verify` vs `codex_impl`) | strict verifier asserts `data.kind == artifact.kind` and `data.kind` matches receipt `type` |
| `artifactPath` | str (absolute, canonical) | absolute realpath to evidence artifact | hook locates the artifact; MUST be inside `realpath(plan_dir)` |
| `artifactSha256` | str (hex, 64 chars) | sha256 of the **exact bytes written to disk** as the evidence artifact | hook re-hashes the file and rejects if mismatch |
| `artifactSchemaVersion` | str (e.g. `"1.0.0"`) | mirrored from artifact's top-level `schemaVersion` field | hook fast-rejects unknown schemas before parsing; strict verifier asserts equality with artifact |
| `finalVerdict` | str enum: `PASS` \| `FINDINGS` \| `FAIL` | mirrored from artifact's top-level field | hook gate — only `PASS` is acceptance-eligible; strict verifier asserts equality with artifact |
| `planJsonSha256` | str (hex, 64 chars) | sha256 of the `plan.json` bytes at receipt-mint time | binds the receipt to the exact plan definition whose criteria were checked; prevents post-mint plan edits from re-using stale receipts |
| `planPath` | str (absolute, canonical) | realpath to `plan.json` | strict verifier asserts containment (`realpath(planPath)` parents `realpath(artifactPath)`) and reads it for `planJsonSha256` cross-check |

Sidecar tampering (any field in `data`) invalidates the HMAC. Evidence-artifact tampering invalidates `artifactSha256`. Plan-definition tampering after mint invalidates `planJsonSha256`. The strict verifier checks ALL three.

**Hook flow** (replaces `verify-step-completion.sh:302-374` and tightens `receipt_utils.check()` semantics):

```
1. Compute expected sidecar path:    state/<projId>/<planId>/codex_verify-step-N.json
2. receipt_utils.verify(sidecar)  →  reject if HMAC invalid
3. Strict-check signed data:      →  reject if any of receiptFormatVersion / step / stepId /
                                     kind / artifactPath / artifactSha256 / artifactSchemaVersion /
                                     finalVerdict / planJsonSha256 / planPath are missing
4. realpath(artifactPath)         →  reject if not inside realpath(plan_dir)
   realpath(planPath)             →  reject if not the expected plan.json
5. sha256(open(artifactPath))     →  reject if != data.artifactSha256
                                     (hash the EXACT file bytes — wrappers MUST hash the same
                                     bytes they wrote to disk, no canonicalization round-trip)
6. sha256(open(planPath))         →  reject if != data.planJsonSha256
7. Parse artifact JSON            →  reject if schemaVersion not in known set
8. Cross-check artifact↔sidecar:  →  reject unless artifact.stepId == data.step
                                     AND artifact.kind == data.kind
                                     AND artifact.schemaVersion == data.artifactSchemaVersion
                                     AND artifact.finalVerdict == data.finalVerdict
                                     AND artifact.planName == receipt.planId (when present)
9. Iterate artifact.criteria[]    →  enforce len(criteria) == count_acceptance_criteria_items(step.acceptanceCriteria)
                                     AND every criteria[i].acceptanceCriterionSha256 matches
                                     sha256(normalize(plan_step.acceptanceCriteria[i]))
10. Accept step completion        →  iff data.finalVerdict == "PASS"
                                     AND artifact.finalVerdict == "PASS"
                                     AND every criteria[i].verdict == "PASS"
                                     AND artifact.findings is empty
                                     AND artifact.codexExitCode == 0
```

### §1.1 `receipt_utils.check()` strict mode (binding contract)

The current `receipt_utils.check()` only compares `type`, `projectId`, `planId`, and the file-naming subset of `extra`. **It does not compare arbitrary `extra` keys against the signed `receipt["data"]`** — so a valid `codex_verify-step-1.json` could be copied to `codex_verify-step-2.json` and accepted for step 2.

This schema requires a new helper, `receipt_utils.verify_step_artifact_receipt(receipt_type, proj_id, plan_id, step, plan_dir, expected_kind)`, that:

1. Loads the sidecar by deterministic name.
2. Verifies HMAC.
3. Compares **every** required `data.<field>` listed in the table above for presence and self-consistency.
4. Resolves `realpath(artifactPath)` and verifies plan-dir containment.
5. Re-hashes the artifact file and verifies `data.artifactSha256`.
6. Re-hashes `plan.json` and verifies `data.planJsonSha256`.
7. Parses the artifact and runs the `artifact↔sidecar` cross-checks.
8. Returns `(valid: bool, sidecar: dict, artifact: dict, reason: str)`.

Both `verify-step-completion.sh` (currently calls `receipt_utils.check(..., {"step": N})` at line 293) and `plan_utils.complete_step()` (line 587) MUST switch to this helper. Implementing the helper and the callers is out of scope for this design step but is a hard prerequisite before any wrapper is allowed to mint v1.0.0 receipts in strict-mode plans.

---

## 2. Evidence artifact schema (`codex-receipt-step-N.json`)

JSON Schema (draft 2020-12, minimal subset):

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://look-before-you-leap/schemas/codex-receipt-1.0.0.json",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schemaVersion", "kind", "stepId", "owner", "mode", "planName",
    "codexExitCode", "criteria", "filesChanged",
    "findings", "finalVerdict", "generatedAt"
  ],
  "properties": {
    "schemaVersion": { "type": "string", "const": "1.0.0" },
    "kind": { "type": "string", "enum": ["verify", "implement"] },
    "stepId": { "type": "integer", "minimum": 1 },
    "owner": { "type": "string", "enum": ["claude", "codex", "dual-pass"] },
    "mode": { "type": "string", "enum": ["claude-impl", "codex-impl", "dual-pass"] },
    "projectRoot": { "type": "string" },
    "planPath": { "type": "string" },
    "planName": { "type": "string" },
    "codexExitCode": { "type": "integer" },
    "resultTxtPath": { "type": "string" },
    "streamJsonlPath": { "type": "string" },
    "resultTxtSha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
    "streamJsonlSha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },

    "criteria": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "acceptanceCriterion", "acceptanceCriterionSha256", "verdict", "evidence"],
        "properties": {
          "id": { "type": "integer", "minimum": 1 },
          "acceptanceCriterion": {
            "type": "string",
            "description": "Verbatim copy of the corresponding item from plan_step.acceptanceCriteria."
          },
          "acceptanceCriterionSha256": {
            "type": "string",
            "pattern": "^[0-9a-f]{64}$",
            "description": "sha256 of the normalized criterion text — see normalization rules in §2.2. The hook recomputes from plan.json and rejects on mismatch (catches stale or swapped criteria; count-only check is insufficient)."
          },
          "verdict": { "type": "string", "enum": ["PASS", "FAIL", "SKIPPED"] },
          "rationale": { "type": "string" },
          "evidence": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["type"],
              "oneOf": [
                {
                  "properties": {
                    "type": { "const": "file" },
                    "file": { "type": "string" },
                    "lineStart": { "type": "integer", "minimum": 1 },
                    "lineEnd": { "type": "integer", "minimum": 1 },
                    "sha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
                    "note": { "type": "string" }
                  },
                  "required": ["file", "lineStart"]
                },
                {
                  "properties": {
                    "type": { "const": "command" },
                    "command": { "type": "string" },
                    "exitCode": { "type": "integer" },
                    "stdoutSha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
                    "stderrSha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
                    "durationMs": { "type": "integer" }
                  },
                  "required": ["command", "exitCode"]
                },
                {
                  "properties": {
                    "type": { "const": "output" },
                    "label": { "type": "string" },
                    "sha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" }
                  },
                  "required": ["label", "sha256"]
                }
              ]
            }
          }
        }
      }
    },

    "filesChanged": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["path", "changeType"],
        "properties": {
          "path": { "type": "string" },
          "changeType": { "type": "string", "enum": ["added", "modified", "deleted", "renamed"] },
          "sha256After": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
          "linesAdded": { "type": "integer" },
          "linesDeleted": { "type": "integer" }
        }
      }
    },

    "commands": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["command", "exitCode"],
        "properties": {
          "command": { "type": "string" },
          "exitCode": { "type": "integer" },
          "stdoutSha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
          "stderrSha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
          "durationMs": { "type": "integer" }
        }
      }
    },

    "findings": {
      "type": "array",
      "default": [],
      "description": "Findings list. The wrapper MUST always emit this key, even if empty (`[]`). The hook treats an absent or null `findings` as a schema violation.",
      "items": {
        "type": "object",
        "required": ["severity", "category", "summary"],
        "properties": {
          "severity": { "type": "string", "enum": ["HIGH", "MEDIUM", "LOW"] },
          "category": {
            "type": "string",
            "enum": [
              "INCOMPLETE_WORK", "MISSED_CONSUMER", "TYPE_SAFETY",
              "SILENT_SCOPE_CUT", "WRONG_PATTERN", "MISSING_TEST",
              "MISSING_I18N", "OTHER"
            ]
          },
          "file": { "type": "string" },
          "lineStart": { "type": "integer", "minimum": 1 },
          "lineEnd": { "type": "integer", "minimum": 1 },
          "summary": { "type": "string" },
          "rationale": { "type": "string" },
          "suggestedFix": { "type": "string" },
          "criterionId": {
            "type": "integer",
            "description": "If present, MUST reference an existing criteria[].id."
          }
        }
      }
    },

    "digestHints": {
      "type": "object",
      "description": "Optional pointers a digest subagent should surface to the conductor first.",
      "properties": {
        "headlineFiles": { "type": "array", "items": { "type": "string" } },
        "headlineFindings": { "type": "array", "items": { "type": "integer" } },
        "blastRadiusNote": { "type": "string" }
      }
    },

    "finalVerdict": { "type": "string", "enum": ["PASS", "FINDINGS", "FAIL"] },
    "generatedAt": { "type": "string", "format": "date-time" }
  }
}
```

### Required vs optional

**Minimal shape** (the fields a hook needs to gate):
- Top-level: `schemaVersion`, `kind`, `stepId`, `owner`, `mode`, `planName`, `codexExitCode`, `criteria`, `filesChanged`, `findings` (always present, `[]` when empty), `finalVerdict`, `generatedAt`.
- Per criterion: `id`, `acceptanceCriterion`, `acceptanceCriterionSha256`, `verdict`, `evidence`.

**Full shape** adds:
- `projectRoot`, `planPath`, `planName` — for cross-context recovery.
- `resultTxtPath`/`resultTxtSha256`, `streamJsonlPath`/`streamJsonlSha256` — bind the human trace and JSONL stream so they can't be swapped post-mint.
- `commands` (a step-level collection, in addition to per-criterion command evidence).
- `findings` (always present; empty array on PASS — see invariant 5 below and the schema `required` list at lines 105-109).
- `digestHints` (advisory; consumed by `lbyl-digest` subagent if present).
- Per-criterion `rationale`, evidence `note`, `linesAdded`/`linesDeleted`.

### Per-criterion verdict shape — invariants

1. `criteria[].id` is a stable 1-based index that maps 1:1 to items in the step's `acceptanceCriteria` field. The hook enforces `len(criteria) == count_acceptance_criteria_items(step.acceptanceCriteria)` (already implemented in `verify-step-completion.sh:219-240`) AND `criteria[i].acceptanceCriterionSha256 == sha256(normalize(plan_step.acceptanceCriteria[i]))`. The sha binding catches stale/swapped criterion content that count-only checks miss (Codex review fix).
2. `finalVerdict == "PASS"` REQUIRES every `criteria[].verdict == "PASS"` AND `findings == []` AND `codexExitCode == 0`. Any deviation downgrades to `FINDINGS` (or `FAIL` for an exec error). The wrapper computes `finalVerdict` mechanically — Codex MUST NOT free-form choose it.
3. `findings[].criterionId`, when present, MUST reference an existing `criteria[].id`. Cross-cutting findings without a criterion link are allowed (`criterionId` omitted).
4. Evidence with `type: "file"` MUST use a path relative to `projectRoot` (rejecting absolute paths outside the project blocks evidence forging via symlinks).
5. `findings` is **always** present (empty array if no findings). Absent or `null` is a schema violation — this lets the hook treat `jq '.findings | length == 0'` as authoritative.

### §2.2 Normalization rules for `acceptanceCriterionSha256`

Both wrapper and hook compute the sha256 over the **normalized** acceptance-criterion string:

1. Decode UTF-8.
2. Strip leading/trailing whitespace.
3. Collapse runs of any whitespace (spaces, tabs, newlines) to a single space.
4. Lowercase NO transformations — preserve original casing.
5. Compute `sha256(normalized.encode("utf-8"))` and emit hex.

Reference Python:

```python
import hashlib, re
def normalize_criterion(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip())
def criterion_sha256(text: str) -> str:
    return hashlib.sha256(normalize_criterion(text).encode("utf-8")).hexdigest()
```

The wrapper MUST split `step.acceptanceCriteria` using the same logic as `count_acceptance_criteria_items()` in `verify-step-completion.sh:219-240` (numbered list `\d+\.\s+` first, falling back to `[.;]` separators) and hash each item.

---

## 3. Sidecar receipt schema

The sidecar follows the existing `receipt_utils.sign()` payload shape (no API changes to `receipt_utils.py`):

```json
{
  "type": "codex_verify",
  "projectId": "<16-hex>",
  "planId": "<plan-name>",
  "timestamp": 1712345678.123,
  "data": {
    "receiptFormatVersion": "1.0.0",
    "step": 3,
    "stepId": 3,
    "kind": "verify",
    "artifactPath": "/abs/path/.temp/plan-mode/active/<plan>/codex-receipt-step-3.json",
    "artifactSha256": "ab12...ef34",
    "artifactSchemaVersion": "1.0.0",
    "finalVerdict": "PASS",
    "planPath": "/abs/path/.temp/plan-mode/active/<plan>/plan.json",
    "planJsonSha256": "cd34...ab56"
  },
  "signature": "<hmac-sha256-hex>"
}
```

All ten `data.<field>` entries are mandatory and match the §1 linkage table exactly. Any missing field causes the strict verifier (§1.1) to reject the sidecar.

`type` is `codex_verify` for `kind: verify` runs and `codex_impl` for `kind: implement` runs. (`claude_verify` retains its current shape — Claude-side independent verification of codex-impl steps; addressed in a separate step of this plan.)

---

## 4. Concrete examples

### 4.1 PASS example

Evidence artifact `<plan-dir>/codex-receipt-step-3.json`:

```json
{
  "schemaVersion": "1.0.0",
  "kind": "verify",
  "stepId": 3,
  "owner": "claude",
  "mode": "claude-impl",
  "projectRoot": "/Users/me/Projects/myapp",
  "planPath": ".temp/plan-mode/active/refactor-auth/plan.json",
  "planName": "refactor-auth",
  "codexExitCode": 0,
  "resultTxtPath": ".temp/plan-mode/active/refactor-auth/.codex-result-step-3.txt",
  "resultTxtSha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  "streamJsonlPath": ".temp/plan-mode/active/refactor-auth/.codex-stream-step-3.jsonl",
  "streamJsonlSha256": "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae",
  "criteria": [
    {
      "id": 1,
      "acceptanceCriterion": "AuthGuard rejects expired tokens with 401",
      "acceptanceCriterionSha256": "1a18e91b08ad19fa84b7f1fa4e5f06c39b2f9ef9aabc79b1cbd9d3e3b9d6f3a4",
      "verdict": "PASS",
      "rationale": "Test asserts 401 on expired JWT; manual read confirms middleware rejects.",
      "evidence": [
        {
          "type": "file",
          "file": "src/middleware/auth-guard.ts",
          "lineStart": 42,
          "lineEnd": 58,
          "sha256": "5994471abb01112afcc18159f6cc74b4f511b99806da59b3caf5a9c173cacfc5",
          "note": "isExpired check throws 401 before downstream"
        },
        {
          "type": "command",
          "command": "pnpm test src/middleware/__tests__/auth-guard.test.ts",
          "exitCode": 0,
          "stdoutSha256": "6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b",
          "durationMs": 1843
        }
      ]
    },
    {
      "id": 2,
      "acceptanceCriterion": "Refresh-token rotation persists in session store",
      "acceptanceCriterionSha256": "5e3b07c6c9eaf0a7f6e2c8d1aebe9d5b1c9a3a4e2bd1f7d6e0c8a1f2b4d6e8f0",
      "verdict": "PASS",
      "evidence": [
        {
          "type": "file",
          "file": "src/auth/session-store.ts",
          "lineStart": 71,
          "lineEnd": 95,
          "sha256": "d4735e3a265e16eee03f59718b9b5d03019c07d8b6c51f90da3a666eec13ab35"
        },
        {
          "type": "command",
          "command": "pnpm test src/auth/__tests__/session-store.test.ts",
          "exitCode": 0,
          "stdoutSha256": "4e07408562bedb8b60ce05c1decfe3ad16b72230967de01f640b7e4729b49fce",
          "durationMs": 921
        }
      ]
    }
  ],
  "filesChanged": [
    {
      "path": "src/middleware/auth-guard.ts",
      "changeType": "modified",
      "sha256After": "5994471abb01112afcc18159f6cc74b4f511b99806da59b3caf5a9c173cacfc5",
      "linesAdded": 18,
      "linesDeleted": 4
    },
    {
      "path": "src/auth/session-store.ts",
      "changeType": "modified",
      "sha256After": "d4735e3a265e16eee03f59718b9b5d03019c07d8b6c51f90da3a666eec13ab35",
      "linesAdded": 24,
      "linesDeleted": 0
    }
  ],
  "commands": [
    {"command": "pnpm tsc --noEmit", "exitCode": 0, "stdoutSha256": "ef2d127de37b942baad06145e54b0c619a1f22327b2ebbcfbec78f5564afe39d", "durationMs": 4123},
    {"command": "pnpm test", "exitCode": 0, "stdoutSha256": "e7f6c011776e8db7cd330b54174fd76f7d0216b612387a5ffcfb81e6f0919683", "durationMs": 12404}
  ],
  "findings": [],
  "finalVerdict": "PASS",
  "generatedAt": "2026-04-24T18:32:11Z"
}
```

Sidecar receipt at `~/.claude/look-before-you-leap/state/<projId>/refactor-auth/codex_verify-step-3.json`:

```json
{
  "type": "codex_verify",
  "projectId": "a1b2c3d4e5f60718",
  "planId": "refactor-auth",
  "timestamp": 1745518331.42,
  "data": {
    "receiptFormatVersion": "1.0.0",
    "step": 3,
    "stepId": 3,
    "kind": "verify",
    "artifactPath": "/Users/me/Projects/myapp/.temp/plan-mode/active/refactor-auth/codex-receipt-step-3.json",
    "artifactSha256": "7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730",
    "artifactSchemaVersion": "1.0.0",
    "finalVerdict": "PASS",
    "planPath": "/Users/me/Projects/myapp/.temp/plan-mode/active/refactor-auth/plan.json",
    "planJsonSha256": "d76f23b8e9a31c7c2b6d9e5f1c4a8b3e7d2f0c6a9b1e5d3f8c7a2b4e9d1f6a3c"
  },
  "signature": "f4d2..."
}
```

### 4.2 FINDINGS example

Evidence artifact:

```json
{
  "schemaVersion": "1.0.0",
  "kind": "verify",
  "stepId": 4,
  "owner": "claude",
  "mode": "claude-impl",
  "projectRoot": "/Users/me/Projects/myapp",
  "planPath": ".temp/plan-mode/active/refactor-auth/plan.json",
  "planName": "refactor-auth",
  "codexExitCode": 0,
  "resultTxtPath": ".temp/plan-mode/active/refactor-auth/.codex-result-step-4.txt",
  "resultTxtSha256": "fcde2b2edba56bf408601fb721fe9b5c338d10ee429ea04fae5511b68fbf8fb9",
  "streamJsonlPath": ".temp/plan-mode/active/refactor-auth/.codex-stream-step-4.jsonl",
  "streamJsonlSha256": "67586e98fad27da0b9968bc039a1ef34c939b9b8e523a8bef89d478608c5ecf6",
  "criteria": [
    {
      "id": 1,
      "acceptanceCriterion": "Login form validates email format client-side",
      "acceptanceCriterionSha256": "9b4f2c8a7e1d6b5a3c0f8e7d2b9a4c1e6f8d3a0b5c7e2d9f1b4a6c8e0d3f5a7b",
      "verdict": "PASS",
      "evidence": [
        {"type": "file", "file": "src/forms/login.tsx", "lineStart": 88, "lineEnd": 112}
      ]
    },
    {
      "id": 2,
      "acceptanceCriterion": "Error states announce via aria-live to screen readers",
      "acceptanceCriterionSha256": "2a8f1c4d6e7b9a3c0d5f8e2b4a7c1e6d9f3b5a0c8d2e4f7a1b9c6d3e0f5a8b2c",
      "verdict": "FAIL",
      "rationale": "ErrorBanner has no aria-live attribute; screen readers will not announce.",
      "evidence": [
        {"type": "file", "file": "src/forms/error-banner.tsx", "lineStart": 14, "lineEnd": 32, "note": "Missing role/aria-live"},
        {"type": "command", "command": "pnpm test src/forms/__tests__/error-banner.a11y.test.tsx", "exitCode": 1, "stdoutSha256": "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3", "durationMs": 612}
      ]
    },
    {
      "id": 3,
      "acceptanceCriterion": "Submit button disables during request",
      "acceptanceCriterionSha256": "7c3e9b1a4d8f0c5e2b6a9d3f7c1e4b8a0d6f2c9e5b3a7d1f8c0e4b6a2d9f3c5e",
      "verdict": "PASS",
      "evidence": [
        {"type": "file", "file": "src/forms/login.tsx", "lineStart": 145, "lineEnd": 160}
      ]
    }
  ],
  "filesChanged": [
    {"path": "src/forms/login.tsx", "changeType": "modified", "sha256After": "73475cb40a568e8da8a045ced110137e159f890ac4da883b6b17dc651b3a8049", "linesAdded": 42, "linesDeleted": 11},
    {"path": "src/forms/error-banner.tsx", "changeType": "added", "sha256After": "ea6d1b40b6f9d3a4cdf7eaa9b2a5ec2a9d0b6d9b88c43c00f8f2cf6e2dda5b3a", "linesAdded": 32, "linesDeleted": 0}
  ],
  "commands": [
    {"command": "pnpm tsc --noEmit", "exitCode": 0, "stdoutSha256": "ef2d127de37b942baad06145e54b0c619a1f22327b2ebbcfbec78f5564afe39d", "durationMs": 4001}
  ],
  "findings": [
    {
      "severity": "HIGH",
      "category": "MISSING_I18N",
      "file": "src/forms/error-banner.tsx",
      "lineStart": 18,
      "lineEnd": 18,
      "summary": "Hardcoded English error string 'Something went wrong' — bypasses i18n catalog.",
      "rationale": "Other forms in this app use t('errors.generic'); this one is hardcoded.",
      "suggestedFix": "Replace with t('errors.generic') and add the key to all locale files in src/i18n/.",
      "criterionId": 2
    },
    {
      "severity": "HIGH",
      "category": "INCOMPLETE_WORK",
      "file": "src/forms/error-banner.tsx",
      "lineStart": 14,
      "lineEnd": 14,
      "summary": "ErrorBanner missing role='alert' / aria-live='assertive'.",
      "rationale": "Acceptance criterion 2 requires screen-reader announcement. Without aria-live the SR is silent.",
      "suggestedFix": "Add role='alert' and aria-live='assertive' to the wrapping element.",
      "criterionId": 2
    }
  ],
  "digestHints": {
    "headlineFiles": ["src/forms/error-banner.tsx"],
    "headlineFindings": [1, 2],
    "blastRadiusNote": "All a11y consumers of ErrorBanner share this gap; check src/forms/* for sibling pattern uses."
  },
  "finalVerdict": "FINDINGS",
  "generatedAt": "2026-04-24T18:55:09Z"
}
```

Sidecar receipt — note `finalVerdict: "FINDINGS"`. The sidecar still gets minted (proof Codex ran), but the hook will reject the step completion attempt because it requires `finalVerdict == "PASS"`. Claude must address findings and re-dispatch.

```json
{
  "type": "codex_verify",
  "projectId": "a1b2c3d4e5f60718",
  "planId": "refactor-auth",
  "timestamp": 1745520109.81,
  "data": {
    "receiptFormatVersion": "1.0.0",
    "step": 4,
    "stepId": 4,
    "kind": "verify",
    "artifactPath": "/Users/me/Projects/myapp/.temp/plan-mode/active/refactor-auth/codex-receipt-step-4.json",
    "artifactSha256": "8b1a9953c4611296a827abf8c47804d7e6c49a6b1a3f46e0c6d5b9d2a9d7cabe",
    "artifactSchemaVersion": "1.0.0",
    "finalVerdict": "FINDINGS",
    "planPath": "/Users/me/Projects/myapp/.temp/plan-mode/active/refactor-auth/plan.json",
    "planJsonSha256": "d76f23b8e9a31c7c2b6d9e5f1c4a8b3e7d2f0c6a9b1e5d3f8c7a2b4e9d1f6a3c"
  },
  "signature": "9c6f..."
}
```

---

## 5. Parseable output contract (Codex-script consumable)

Codex emits free-form text via `codex exec --json -o <file>`. The wrapper script (`run-codex-verify.sh` / `run-codex-implement.sh`) MUST extract a fenced JSON block from that output and write it to the evidence-artifact path.

### Delimiter (mandatory in the Codex prompt)

The prompt instructs Codex to emit the receipt as a single fenced block:

````
```codex-receipt-v1
{ ...evidence artifact JSON... }
```
````

The fence info-string is `codex-receipt-v1` (matches `schemaVersion` major.minor namespace). The wrapper script extracts using this regex (BSD/GNU portable):

```bash
awk '/^```codex-receipt-v1$/{flag=1;next} /^```$/{flag=0} flag' "$RESULT_FILE"
```

Then validates against the JSON schema before writing the evidence artifact and minting the sidecar.

### Wrapper-script flow (replaces lines 124-149 of `run-codex-verify.sh`)

```
 1. codex exec ... -o $RESULT_FILE     (unchanged)
 2. Extract fenced codex-receipt-v1 block from $RESULT_FILE
 3. Validate JSON parse + schemaVersion == "1.0.0"
 4. Validate required fields + additionalProperties: false at top level
 5. Compute count_acceptance_criteria_items(plan_step.acceptanceCriteria);
    REJECT if len(criteria) != count
 6. For each criteria[i], compute criterion_sha256(plan_step.acceptanceCriteria[i])
    and REJECT if != criteria[i].acceptanceCriterionSha256
 7. Recompute finalVerdict mechanically from criteria[].verdict + findings + codexExitCode
    and REJECT if not equal to artifact.finalVerdict (Codex must not free-form choose)
 8. Write evidence artifact bytes to <plan-dir>/codex-receipt-step-N.json
    via atomic write (tempfile + rename)
 9. Compute artifactSha256 = sha256(open(<plan-dir>/codex-receipt-step-N.json).read())
    — hash the EXACT bytes on disk, no canonicalization round-trip
10. Compute planJsonSha256 = sha256(open(plan.json).read())
11. receipt_sign codex_verify ... step=N \
        receiptFormatVersion=1.0.0 \
        stepId=N \
        kind=verify \
        artifactPath=<realpath of step 8 file> \
        artifactSha256=<hex from step 9> \
        artifactSchemaVersion=1.0.0 \
        finalVerdict=<PASS|FINDINGS|FAIL> \
        planPath=<realpath plan.json> \
        planJsonSha256=<hex from step 10>
12. Exit 0 (sidecar minted) — hook gate runs on next plan.json mutation
```

`receipt_utils.sign()` already accepts arbitrary `extra` fields and binds them all into the HMAC payload; no API change is required to mint v1.0.0 receipts.

The hook side MUST switch from `receipt_utils.check(type, proj, plan, {"step": N})` (which only file-name-matches) to the strict helper described in §1.1 (`receipt_utils.verify_step_artifact_receipt(...)`) that re-hashes the artifact, re-hashes plan.json, and runs the artifact↔sidecar cross-checks.

### Failure modes the wrapper MUST surface (and NOT mint a sidecar):

| Failure | Behavior |
|---------|----------|
| Codex exit code != 0 | Do not mint. Write `codex-receipt-step-N.json` with `finalVerdict: "FAIL"` (sentinel for digest agents) but DO NOT sign — hook will reject for missing sidecar. |
| Fenced block missing | Do not mint. Stderr message: `ERROR: Codex output missing required \`\`\`codex-receipt-v1 fence. Re-run.` |
| JSON parse failure | Do not mint. Stderr message includes parser error. |
| Schema validation failure | Do not mint. Stderr message lists missing required fields. |
| `criteria.length` != acceptance-criterion count | Do not mint. Stderr message lists expected vs actual count. |

Claude (the conductor) cannot bypass any of these because: (a) the wrapper script is the only writer of the sidecar; (b) the secret key is mode 0600 and Claude has no Bash access to it (guard-sensitive-state hook blocks); (c) `codex` CLI is not present in Claude's tool surface (the conductor dispatches via wrapper scripts only).

---

## 6. Migration note

The existing `.codex-result-step-N.txt` file is **preserved as a human-readable trace only**.

- It continues to exist (Codex's `-o` flag still writes it).
- Its sha256 is bound into the evidence artifact (`resultTxtSha256`) so post-hoc tampering is detectable.
- The main Claude thread MUST NOT read it (no `cat`/`Read` of the TXT). All authoritative parsing reads `codex-receipt-step-N.json`.
- `verify-step-completion.sh` lines 302-374 (regex over TXT) are replaced by the schema-driven flow in §1 and §5.
- `codex-skills/lbyl-verify/SKILL.md` (TXT report contract) is updated in a separate step of this plan to instruct Codex to emit the fenced JSON block in addition to (not instead of) its current sectioned prose. The prose remains the human trace; the fenced block is the authoritative receipt source.

The existing per-criterion hook-side counter (`verify-step-completion.sh:359-374` counting `### Criterion:` markers) is removed — replaced by `len(receipt.criteria) == count_acceptance_criteria_items(...)` enforced inside the wrapper before sidecar minting (push validation upstream).

---

## 7. Acceptance-criterion coverage

| Criterion | Met by | Evidence pointer |
|-----------|--------|------------------|
| (a) full JSON schema with `schemaVersion` | §2 (artifact), §3 (sidecar) | `schemaVersion: "1.0.0"` const, `additionalProperties: false`; sidecar carries `receiptFormatVersion: "1.0.0"` and `artifactSchemaVersion` |
| (b) HMAC sidecar linkage by exact field names | §1 linkage table, §3, §1.1 | `data.receiptFormatVersion`, `data.step`, `data.stepId`, `data.kind`, `data.artifactPath`, `data.artifactSha256`, `data.artifactSchemaVersion`, `data.finalVerdict`, `data.planPath`, `data.planJsonSha256` |
| (c) PASS + FINDINGS examples rendered inline | §4.1, §4.2 | Two fenced JSON blocks per example (artifact + sidecar) with full evidence and full bound-data |
| (d) `.codex-result-step-N.txt` preserved as trace, not authority | §6 | "Migration note" — TXT preserved, sha bound via `resultTxtSha256`, main thread MUST NOT read it |
| (e) parseable output contract — exact delimiter | §5 | Fence info-string ```` ```codex-receipt-v1 ```` ... ``` ```` ` `, plus the portable `awk` extractor and the 12-step wrapper flow |

## Deferred (out of scope for step 2)

These came up in the Codex review and were intentionally left for a later step or rejected:

- **`group` field for collab-split sidecars/artifacts** — Codex flagged that `receipt_utils.py:120-127,165-172` already supports a `group` filename detail, so the schema could mirror it. Deferred because the parent plan explicitly **deletes collab-split** (see plan.json context, discovery.md §"collab-split References"). Adding `group` here would re-introduce a concept the rest of the plan removes. If post-removal a real grouping primitive is reintroduced, it can be added as schema v1.1.
- **`additionalProperties: false` on every nested evidence variant** — only added at the security-critical top-level, sidecar `data`, and `criteria[]` items. Evidence sub-variants intentionally left open so Codex can attach diagnostic hints (e.g., `note`) without schema bumps. Risk is low because evidence is advisory, not gating.
- **Plan-name slug constraint (NICE-TO-HAVE #1)** — Codex suggested constraining `planId`/`planName` to a safe slug. Deferred because plan-name validation is a `plan_utils.create_plan()` concern, not a receipt-schema concern. Tracked as a separate hardening item.
- **`artifactCreatedBy` diagnostic field (NICE-TO-HAVE #4)** — Codex explicitly said "do not use as trust input." Adding it would invite future code paths to misuse it. Rejected — diagnostics live in the human-readable trace (`.codex-result-step-N.txt`), not in the receipt.
- **Renaming top-level `criteria` → `criteriaResults` (Field rename #1)** — kept as `criteria` because the consuming `jq` paths and shell hook code are simpler with the shorter name, and the rename inside criteria items (`criterion → acceptanceCriterion`) already disambiguates from `acceptanceCriteria` in plan.json.
- **Implementing the `verify_step_artifact_receipt()` helper and rewriting `verify-step-completion.sh` / `complete_step()` to use it** — this is plan step 3+ work. The schema *requires* this happen before strict mode is on; the schema doc itself only specifies the contract.
