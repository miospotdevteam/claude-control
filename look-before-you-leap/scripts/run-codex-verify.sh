#!/usr/bin/env bash
# Direction-locked Codex verification script.
#
# Runs `codex exec` to verify a Claude-implemented step.
# Validates that the effective owner is Claude (rejects codex-owned targets).
#
# Usage:
#   run-codex-verify.sh <plan.json-path> <step-number>
#
# Output:
#   JSONL stream: <plan-dir>/.codex-stream-step-N.jsonl
#   Result file:  <plan-dir>/.codex-result-step-N.txt
#   Receipt JSON: <plan-dir>/codex-receipt-step-N.json
#
# Exit codes:
#   0 — codex exec completed (check result file for PASS/findings)
#   1 — validation error (wrong owner, missing codex, bad args)
#   * — codex exec exit code passed through

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: run-codex-verify.sh <plan.json-path> <step-number>" >&2
  exit 1
fi

PLAN_JSON="$1"
STEP_NUM="$2"

if [ ! -f "$PLAN_JSON" ]; then
  echo "Error: plan.json not found at $PLAN_JSON" >&2
  exit 1
fi

# Validate ownership FIRST — direction lock must reject before anything else
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
python3 "$SCRIPT_DIR/validate_step_ownership.py" "$PLAN_JSON" "$STEP_NUM" --direction verify >/dev/null || exit 1

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI not found. Install with: npm install -g @openai/codex" >&2
  exit 1
fi

PLAN_DIR="$(cd "$(dirname "$PLAN_JSON")" && pwd)"

SUFFIX="step-${STEP_NUM}"

# Write in-flight PID marker so stale codex cleanup can detect running Codex tasks
INFLIGHT_MARKER="$PLAN_DIR/.codex-inflight-${SUFFIX}.pid"
echo $$ > "$INFLIGHT_MARKER"
cleanup_inflight() {
  rm -f "$INFLIGHT_MARKER"
}
trap cleanup_inflight EXIT
STREAM_FILE="$PLAN_DIR/.codex-stream-${SUFFIX}.jsonl"
RESULT_FILE="$PLAN_DIR/.codex-result-${SUFFIX}.txt"

# Source canonical find_project_root from hooks/lib/
source "${SCRIPT_DIR}/../hooks/lib/find-root.sh"

PROJECT_ROOT="$(find_project_root "$PLAN_DIR")"

# Build the prompt
PROMPT="Verify step ${STEP_NUM} of the plan at ${PLAN_JSON}.

Read the plan file to understand the step's acceptance criteria, description, and files list. Also read discovery.md in the same directory for codebase context (scope, consumers, blast radius).

Check every acceptance criterion mechanically:
- Run the project's type checker (tsc, tsgo, mypy, etc.) and relevant tests
- Read the modified files and verify changes match the specification
- Use deps-query on modified shared files to check consumer integrity (if dep maps are configured)
- Look for bugs, type safety holes, silent scope cuts, and missed consumers

Also run the standard checks from the lbyl-verify skill (Step 3.5) regardless of criteria:
- i18n: check new user-visible strings exist in ALL locale files
- State transitions: check loading, switching, error paths — not just the initial render
- Description parity: compare step description deliverables against actual implementation
- Empty/edge states: check what happens when data is null, empty, zero, or error
- Pattern matching: if a UI pattern exists elsewhere, verify config matches

Report PASS if all criteria are met, or report structured findings with:
- Severity: HIGH (blocks shipping) / MEDIUM (should fix) / LOW (nit)
- File and line number
- What is wrong and why
- Suggested fix
- Failure category: INCOMPLETE_WORK, MISSED_CONSUMER, TYPE_SAFETY, SILENT_SCOPE_CUT, WRONG_PATTERN, MISSING_TEST, MISSING_I18N, or OTHER

Your output is both a human trace and the source for ${PLAN_DIR}/codex-receipt-step-${STEP_NUM}.json.
End the response with exactly one fenced JSON block:

\`\`\`codex-receipt-v1
{ ...valid JSON matching look-before-you-leap/references/codex-receipt-schema.md schemaVersion 1.0.0... }
\`\`\`

The fenced block must be the final block in the response. It must include:
- schemaVersion=\"1.0.0\", kind=\"verify\", stepId=${STEP_NUM}, owner/mode/planName from plan.json, codexExitCode=0
- one criteria[] entry per acceptance criterion, with normalized acceptanceCriterionSha256 values
- filesChanged, findings, finalVerdict, generatedAt
- finalVerdict PASS only when every criterion passes, findings is empty, and codexExitCode is 0; otherwise FINDINGS"

# Run codex exec
set +e
codex exec \
  -C "$PROJECT_ROOT" \
  --dangerously-bypass-approvals-and-sandbox \
  --json \
  -o "$RESULT_FILE" \
  "$PROMPT" \
  < /dev/null \
  > "$STREAM_FILE" 2>&1

CODEX_EXIT=$?
set -e

RECEIPT_FILE="$PLAN_DIR/codex-receipt-step-${STEP_NUM}.json"

if ! python3 - "$PLAN_JSON" "$STEP_NUM" "$PROJECT_ROOT" "$RESULT_FILE" "$STREAM_FILE" "$CODEX_EXIT" "$RECEIPT_FILE" "$SCRIPT_DIR" <<'PY'; then
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

(
    plan_json,
    step_num_raw,
    project_root,
    result_file,
    stream_file,
    codex_exit_raw,
    receipt_file,
    script_dir,
) = sys.argv[1:]

SCHEMA_VERSION = "1.0.0"
FENCE = "```codex-receipt-v1"
step_num = int(step_num_raw)
codex_exit = int(codex_exit_raw)
plan_path = Path(plan_json).resolve()
project_root_path = Path(project_root).resolve()
result_path = Path(result_file)
stream_path = Path(stream_file)
receipt_path = Path(receipt_file)

ALLOWED_TOP_LEVEL = {
    "schemaVersion",
    "kind",
    "stepId",
    "owner",
    "mode",
    "projectRoot",
    "planPath",
    "planName",
    "codexExitCode",
    "resultTxtPath",
    "streamJsonlPath",
    "resultTxtSha256",
    "streamJsonlSha256",
    "criteria",
    "filesChanged",
    "commands",
    "findings",
    "digestHints",
    "finalVerdict",
    "generatedAt",
}
REQUIRED_TOP_LEVEL = {
    "schemaVersion",
    "kind",
    "stepId",
    "owner",
    "mode",
    "planName",
    "codexExitCode",
    "criteria",
    "filesChanged",
    "findings",
    "finalVerdict",
    "generatedAt",
}


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    try:
        return sha256_bytes(Path(path).read_bytes())
    except OSError:
        return None


def normalize_criterion(text):
    return re.sub(r"\s+", " ", str(text).strip())


def criterion_sha256(text):
    return sha256_bytes(normalize_criterion(text).encode("utf-8"))


def split_acceptance_criteria(acceptance_criteria):
    if not isinstance(acceptance_criteria, str):
        return []
    text = acceptance_criteria.strip()
    if not text:
        return []
    if re.search(r"(?:^|\s)\d+\.\s+", text):
        return [
            item.strip()
            for item in re.split(r"(?:^|\s)(?=\d+\.\s+)", text)
            if item.strip()
        ]
    return [
        item.strip()
        for item in re.split(r"[.;](?:\s+|$)", text)
        if item.strip()
    ]


def extract_receipt_json(path):
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        fail(f"Cannot read Codex result file: {exc}")

    blocks = []
    current = []
    in_block = False
    for line in lines:
        if line == FENCE:
            if in_block:
                fail("Nested codex-receipt-v1 fence found.")
            in_block = True
            current = []
            continue
        if in_block and line == "```":
            blocks.append("\n".join(current))
            in_block = False
            current = []
            continue
        if in_block:
            current.append(line)

    if in_block:
        fail("Codex output has an unterminated codex-receipt-v1 fence.")
    if not blocks:
        fail("Codex output missing required ```codex-receipt-v1 fence. Re-run.")
    if len(blocks) > 1:
        fail("Codex output contains more than one codex-receipt-v1 fence.")
    return blocks[0]


def load_plan():
    try:
        with open(plan_path, encoding="utf-8") as f:
            plan_data = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"Cannot read plan.json: {exc}")
    for candidate in plan_data.get("steps", []):
        if candidate.get("id") == step_num:
            return plan_data, candidate
    fail(f"Step {step_num} not found in plan.json.")


def expected_mode_for(step):
    if step.get("mode"):
        return step["mode"]
    owner = step.get("owner", "codex")
    if owner == "claude":
        return "claude-impl"
    if owner == "codex":
        return "codex-impl"
    return "dual-pass"


def validate_artifact(artifact, plan_data, step, criteria_texts):
    missing = sorted(REQUIRED_TOP_LEVEL - artifact.keys())
    if missing:
        fail(f"Receipt JSON missing required field(s): {', '.join(missing)}")
    extra = sorted(set(artifact.keys()) - ALLOWED_TOP_LEVEL)
    if extra:
        fail(f"Receipt JSON has unsupported top-level field(s): {', '.join(extra)}")

    expected_owner = step.get("owner", "codex")
    expected_mode = expected_mode_for(step)
    expected_plan_name = plan_data.get("name", "unknown")
    expected = {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "verify",
        "stepId": step_num,
        "owner": expected_owner,
        "mode": expected_mode,
        "planName": expected_plan_name,
        "codexExitCode": codex_exit,
    }
    for key, value in expected.items():
        if artifact.get(key) != value:
            fail(
                f"Receipt JSON field {key}={artifact.get(key)!r}; "
                f"expected {value!r}."
            )

    criteria = artifact.get("criteria")
    if not isinstance(criteria, list):
        fail("Receipt JSON field criteria must be an array.")
    count_mismatch = len(criteria) != len(criteria_texts)
    if count_mismatch:
        print(
            f"WARN: receipt criteria length {len(criteria)} != heuristic-parsed plan items {len(criteria_texts)}. "
            "Per-item text/sha validation will be skipped; receipt accepted on structural validity. "
            "Codex's criteria interpretation may be holistic — verifier subagent will decide.",
            file=sys.stderr,
        )

    for index, criterion in enumerate(criteria, start=1):
        if not isinstance(criterion, dict):
            fail(f"Receipt JSON criteria[{index}] must be an object.")
        required = {
            "id",
            "acceptanceCriterion",
            "acceptanceCriterionSha256",
            "verdict",
            "evidence",
        }
        missing_criterion = sorted(required - criterion.keys())
        if missing_criterion:
            fail(
                f"Receipt JSON criteria[{index}] missing field(s): "
                f"{', '.join(missing_criterion)}"
            )
        if criterion.get("id") != index:
            fail(f"Receipt JSON criteria[{index}] has incorrect id.")
        if criterion.get("verdict") not in {"PASS", "FAIL", "SKIPPED"}:
            fail(f"Receipt JSON criteria[{index}] has invalid verdict.")
        if not isinstance(criterion.get("evidence"), list):
            fail(f"Receipt JSON criteria[{index}] evidence must be an array.")
        if not count_mismatch:
            expected_text = criteria_texts[index - 1]
            got_text = criterion.get("acceptanceCriterion") or ""
            # Compare normalized form (trim whitespace, drop trailing punctuation)
            # rather than exact string — heuristic plan splitter and Codex's emit
            # may differ on trailing periods/whitespace; the meaning is identical.
            def _norm(s):
                return re.sub(r"\s+", " ", str(s)).strip().rstrip(".;,")
            if _norm(got_text) != _norm(expected_text):
                print(
                    f"WARN: receipt criteria[{index}] acceptanceCriterion text differs from plan "
                    f"(normalized comparison failed). Receipt accepted on structural validity; "
                    f"verifier subagent decides on substance.",
                    file=sys.stderr,
                )

    if not isinstance(artifact.get("filesChanged"), list):
        fail("Receipt JSON field filesChanged must be an array.")
    if not isinstance(artifact.get("findings"), list):
        fail("Receipt JSON field findings must be an array.")

    if codex_exit != 0:
        expected_verdict = "FAIL"
    elif (
        all(item.get("verdict") == "PASS" for item in criteria)
        and len(artifact["findings"]) == 0
    ):
        expected_verdict = "PASS"
    else:
        expected_verdict = "FINDINGS"
    if artifact.get("finalVerdict") != expected_verdict:
        fail(
            "Receipt JSON finalVerdict mismatch: "
            f"expected {expected_verdict}, got {artifact.get('finalVerdict')!r}."
        )


def enrich_artifact(artifact):
    artifact["projectRoot"] = str(project_root_path)
    artifact["planPath"] = str(plan_path)
    artifact["resultTxtPath"] = str(result_path.resolve())
    artifact["streamJsonlPath"] = str(stream_path.resolve())
    result_sha = sha256_file(result_path)
    stream_sha = sha256_file(stream_path)
    if result_sha:
        artifact["resultTxtSha256"] = result_sha
    if stream_sha:
        artifact["streamJsonlSha256"] = stream_sha
    return artifact


def failure_artifact(plan_data, step, criteria_texts):
    result_sha = sha256_file(result_path)
    stream_sha = sha256_file(stream_path)
    evidence = []
    if result_sha:
        evidence.append({"type": "output", "label": "codex-result", "sha256": result_sha})
    if stream_sha:
        evidence.append({"type": "output", "label": "codex-stream", "sha256": stream_sha})
    if not evidence:
        evidence.append(
            {
                "type": "output",
                "label": "codex-exit",
                "sha256": sha256_bytes(str(codex_exit).encode("utf-8")),
            }
        )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "verify",
        "stepId": step_num,
        "owner": step.get("owner", "codex"),
        "mode": expected_mode_for(step),
        "projectRoot": str(project_root_path),
        "planPath": str(plan_path),
        "planName": plan_data.get("name", "unknown"),
        "codexExitCode": codex_exit,
        "resultTxtPath": str(result_path.resolve()),
        "streamJsonlPath": str(stream_path.resolve()),
        **({"resultTxtSha256": result_sha} if result_sha else {}),
        **({"streamJsonlSha256": stream_sha} if stream_sha else {}),
        "criteria": [
            {
                "id": index,
                "acceptanceCriterion": text,
                "acceptanceCriterionSha256": criterion_sha256(text),
                "verdict": "SKIPPED",
                "rationale": f"Codex verification exited with code {codex_exit}.",
                "evidence": evidence,
            }
            for index, text in enumerate(criteria_texts, start=1)
        ],
        "filesChanged": [],
        "commands": [
            {
                "command": "codex exec -C <project-root> --dangerously-bypass-approvals-and-sandbox --json -o <result-file> <prompt>",
                "exitCode": codex_exit,
                **({"stdoutSha256": stream_sha} if stream_sha else {}),
            }
        ],
        "findings": [
            {
                "severity": "HIGH",
                "category": "OTHER",
                "summary": f"Codex verification exited with code {codex_exit}.",
            }
        ],
        "finalVerdict": "FAIL",
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def write_artifact(artifact):
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(artifact, indent=2, ensure_ascii=False) + "\n"
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{receipt_path.name}.", suffix=".tmp", dir=str(receipt_path.parent)
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(payload)
        os.replace(tmp_name, receipt_path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def sign_sidecar(artifact, plan_data):
    sys.path.insert(0, script_dir)
    try:
        import receipt_utils
    except ImportError as exc:
        fail(f"Cannot import receipt_utils.py: {exc}")
    try:
        receipt_utils.bootstrap()
        artifact_sha = sha256_file(receipt_path)
        plan_sha = sha256_file(plan_path)
        if not artifact_sha or not plan_sha:
            fail("Cannot hash receipt artifact or plan.json for sidecar.")
        receipt_utils.sign(
            "codex_verify",
            receipt_utils.project_id(str(project_root_path)),
            plan_data.get("name", "unknown"),
            {
                "receiptFormatVersion": SCHEMA_VERSION,
                "step": step_num,
                "stepId": step_num,
                "kind": "verify",
                "artifactPath": str(receipt_path.resolve()),
                "artifactSha256": artifact_sha,
                "artifactSchemaVersion": artifact["schemaVersion"],
                "finalVerdict": artifact["finalVerdict"],
                "planPath": str(plan_path),
                "planJsonSha256": plan_sha,
            },
        )
    except Exception as exc:
        fail(f"Failed to write codex_verify sidecar receipt: {exc}")


plan_data, step = load_plan()
criteria_texts = split_acceptance_criteria(step.get("acceptanceCriteria") or "")
if not criteria_texts:
    fail("Step has no parseable acceptanceCriteria; cannot emit schema-valid receipt.")

if codex_exit == 0:
    raw = extract_receipt_json(result_path)
    try:
        artifact_data = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"Codex receipt JSON parse failure: {exc}")
    validate_artifact(artifact_data, plan_data, step, criteria_texts)
    artifact_data = enrich_artifact(artifact_data)
    validate_artifact(artifact_data, plan_data, step, criteria_texts)
    write_artifact(artifact_data)
    sign_sidecar(artifact_data, plan_data)
else:
    artifact_data = failure_artifact(plan_data, step, criteria_texts)
    validate_artifact(artifact_data, plan_data, step, criteria_texts)
    write_artifact(artifact_data)
PY
  exit 1
fi

exit $CODEX_EXIT
