#!/usr/bin/env bash
# Direction-locked Codex implementation script.
#
# Runs `codex exec` for Codex-owned steps.
# Validates that the effective owner is Codex (rejects claude-owned targets).
#
# Usage:
#   run-codex-implement.sh <plan.json-path> <step-number>
#
# Output:
#   JSONL stream: <plan-dir>/.codex-stream-step-N.jsonl
#   Result file:  <plan-dir>/.codex-result-step-N.txt
#   Receipt JSON: <plan-dir>/codex-receipt-step-N.json
#
# Exit codes:
#   0 — codex exec completed (check result file for report)
#   1 — validation error (wrong owner, missing codex, bad args)
#   * — codex exec exit code passed through

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: run-codex-implement.sh <plan.json-path> <step-number>" >&2
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
python3 "$SCRIPT_DIR/validate_step_ownership.py" "$PLAN_JSON" "$STEP_NUM" --direction implement >/dev/null || exit 1

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
RECEIPT_FILE="$PLAN_DIR/codex-receipt-step-${STEP_NUM}.json"

# Source canonical find_project_root from hooks/lib/
source "${SCRIPT_DIR}/../hooks/lib/find-root.sh"

PROJECT_ROOT="$(find_project_root "$PLAN_DIR")"

# Build the prompt
PROMPT="Implement step ${STEP_NUM} of the plan at ${PLAN_JSON}.

Read the plan file to understand the step's description, acceptance criteria, files list, and progress items. Also read discovery.md in the same directory for codebase context (scope, consumers, blast radius, existing patterns).

For each file you need to modify:
- Read the file AND its imports before editing
- Check sibling files for patterns and conventions
- Implement exactly what the step description specifies — no scope additions, no scope cuts

After completing all progress items:
- Run the project's type checker (tsc, tsgo, mypy, etc.) and relevant tests
- Check consumers of any shared code you modified (use deps-query if dep maps are configured)

Report your results as:
- FILES CHANGED: list of files you created or modified
- WHAT WAS DONE: brief summary per progress item
- VERIFICATION: type checker and test results (pass/fail with output)
- ISSUES: anything that did not go as expected, or 'none'

Then emit a final fenced JSON block using this exact delimiter:
\`\`\`codex-receipt-v1
{ ...valid JSON... }
\`\`\`

The fenced JSON must match look-before-you-leap/references/codex-receipt-schema.md schemaVersion 1.0.0:
- schemaVersion: \"1.0.0\"
- kind: \"implement\"
- stepId: ${STEP_NUM}
- owner, mode, and planName copied from plan.json
- codexExitCode: 0 when Codex completed normally
- criteria: one entry per acceptance criterion with id, acceptanceCriterion, acceptanceCriterionSha256, verdict, and evidence
- filesChanged: structured version of FILES CHANGED
- findings: [] on clean implementation, otherwise structured findings
- finalVerdict: PASS only when every criterion passed, findings is empty, and codexExitCode is 0; otherwise FINDINGS
- generatedAt: UTC ISO-8601 timestamp"

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

python3 - "$PLAN_JSON" "$STEP_NUM" "$PROJECT_ROOT" "$RESULT_FILE" "$STREAM_FILE" "$RECEIPT_FILE" "$CODEX_EXIT" "$SCRIPT_DIR" <<'PY'
import datetime
import hashlib
import json
import os
import re
import sys
import tempfile

(
    plan_json,
    step_num_raw,
    project_root,
    result_file,
    stream_file,
    receipt_file,
    codex_exit_raw,
    script_dir,
) = sys.argv[1:]

step_num = int(step_num_raw)
codex_exit = int(codex_exit_raw)

sys.path.insert(0, script_dir)
import receipt_utils  # noqa: E402


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


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def normalize_criterion(text):
    return re.sub(r"\s+", " ", text.strip())


def criterion_sha256(text):
    return hashlib.sha256(normalize_criterion(text).encode("utf-8")).hexdigest()


def acceptance_criteria_items(value):
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if not isinstance(value, str):
        return []

    text = value.strip()
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


def load_plan_step():
    with open(plan_json, encoding="utf-8") as f:
        plan = json.load(f)

    for candidate in plan.get("steps", []):
        if candidate.get("id") == step_num:
            return plan, candidate

    raise ValueError(f"step {step_num} not found in plan.json")


def atomic_write(path, data):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(
        prefix=f".{os.path.basename(path)}.",
        suffix=".tmp",
        dir=directory,
        text=True,
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(data)
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def extract_receipt_block(path):
    if not os.path.exists(path):
        raise ValueError("Codex output missing required ```codex-receipt-v1 fence. Re-run.")

    blocks = []
    current = []
    in_block = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            marker = line.rstrip("\n")
            if marker == "```codex-receipt-v1":
                if in_block:
                    raise ValueError("Nested codex-receipt-v1 fence found.")
                in_block = True
                current = []
                continue
            if in_block and marker == "```":
                blocks.append("".join(current))
                in_block = False
                current = []
                continue
            if in_block:
                current.append(line)

    if in_block:
        raise ValueError("Unclosed codex-receipt-v1 fence.")
    if not blocks:
        raise ValueError("Codex output missing required ```codex-receipt-v1 fence. Re-run.")
    if len(blocks) > 1:
        raise ValueError("Codex output contains more than one codex-receipt-v1 fence.")
    return blocks[0]


def validate_artifact(artifact, plan, step, criteria_items):
    if not isinstance(artifact, dict):
        raise ValueError("Receipt artifact must be a JSON object.")

    unknown = sorted(set(artifact) - ALLOWED_TOP_LEVEL)
    if unknown:
        raise ValueError(f"Receipt artifact has unsupported top-level fields: {', '.join(unknown)}")

    missing = sorted(REQUIRED_TOP_LEVEL - set(artifact))
    if missing:
        raise ValueError(f"Receipt artifact missing required fields: {', '.join(missing)}")

    expected_owner = step.get("owner", "codex")
    expected_mode = step.get("mode", "codex-impl")
    expected_plan_name = plan.get("name", os.path.basename(os.path.dirname(plan_json)))

    checks = {
        "schemaVersion": "1.0.0",
        "kind": "implement",
        "stepId": step_num,
        "owner": expected_owner,
        "mode": expected_mode,
        "planName": expected_plan_name,
        "codexExitCode": codex_exit,
    }
    for key, expected in checks.items():
        if artifact.get(key) != expected:
            raise ValueError(
                f"Receipt artifact field {key}={artifact.get(key)!r}; expected {expected!r}."
            )

    criteria = artifact.get("criteria")
    if not isinstance(criteria, list):
        raise ValueError("Receipt artifact criteria must be an array.")
    count_mismatch = len(criteria) != len(criteria_items)
    if count_mismatch:
        print(
            f"WARN: receipt criteria length {len(criteria)} != heuristic-parsed plan items {len(criteria_items)}. "
            "Per-item text/sha validation will be skipped; receipt accepted on structural validity. "
            "Codex's criteria interpretation may be holistic — verifier subagent will decide.",
            file=sys.stderr,
        )

    for idx, criterion in enumerate(criteria, start=1):
        if not isinstance(criterion, dict):
            raise ValueError(f"criteria[{idx}] must be an object.")
        for key in ("id", "acceptanceCriterion", "acceptanceCriterionSha256", "verdict", "evidence"):
            if key not in criterion:
                raise ValueError(f"criteria[{idx}] missing required field {key}.")
        if criterion["id"] != idx:
            raise ValueError(f"criteria[{idx}] id={criterion['id']!r}; expected {idx}.")
        if criterion["verdict"] not in ("PASS", "FAIL", "SKIPPED"):
            raise ValueError(f"criteria[{idx}] has invalid verdict {criterion['verdict']!r}.")
        if not count_mismatch:
            expected_text = criteria_items[idx - 1]
            got_text = criterion.get("acceptanceCriterion") or ""
            # Compare normalized form because the heuristic plan splitter and
            # Codex's emitted receipt may differ only on punctuation/spacing.
            def _norm(s):
                return re.sub(r"\s+", " ", str(s)).strip().rstrip(".;,")
            if _norm(got_text) != _norm(expected_text):
                print(
                    f"WARN: receipt criteria[{idx}] acceptanceCriterion text differs from plan "
                    f"(normalized comparison failed). Receipt accepted on structural validity; "
                    f"verifier subagent decides on substance.",
                    file=sys.stderr,
                )
            expected_sha = criterion_sha256(expected_text)
            if criterion["acceptanceCriterionSha256"] != expected_sha:
                print(
                    f"WARN: receipt criteria[{idx}] acceptanceCriterionSha256 differs from plan-derived hash. "
                    f"Receipt accepted on structural validity; verifier subagent decides on substance.",
                    file=sys.stderr,
                )
        if criterion["verdict"] not in ("PASS", "FAIL", "SKIPPED"):
            raise ValueError(f"criteria[{idx}] has invalid verdict {criterion['verdict']!r}.")
        if not isinstance(criterion["evidence"], list):
            raise ValueError(f"criteria[{idx}] evidence must be an array.")

    if not isinstance(artifact.get("filesChanged"), list):
        raise ValueError("Receipt artifact filesChanged must be an array.")
    for idx, file_change in enumerate(artifact["filesChanged"], start=1):
        if not isinstance(file_change, dict):
            raise ValueError(f"filesChanged[{idx}] must be an object.")
        for key in ("path", "changeType"):
            if key not in file_change:
                raise ValueError(f"filesChanged[{idx}] missing required field {key}.")
        if file_change["changeType"] not in ("added", "modified", "deleted", "renamed"):
            raise ValueError(f"filesChanged[{idx}] has invalid changeType.")

    findings = artifact.get("findings")
    if not isinstance(findings, list):
        raise ValueError("Receipt artifact findings must be an array.")

    if "commands" in artifact and not isinstance(artifact["commands"], list):
        raise ValueError("Receipt artifact commands must be an array when present.")

    computed = "PASS"
    if codex_exit != 0:
        computed = "FAIL"
    elif findings or any(item["verdict"] != "PASS" for item in criteria):
        computed = "FINDINGS"

    if artifact.get("finalVerdict") != computed:
        raise ValueError(
            f"Receipt artifact finalVerdict={artifact.get('finalVerdict')!r}; expected {computed!r}."
        )

    return computed


def make_failure_artifact(plan, step, criteria_items):
    now = datetime.datetime.now(datetime.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    result_sha = sha256_file(result_file) if os.path.exists(result_file) else None
    stream_sha = sha256_file(stream_file) if os.path.exists(stream_file) else None
    criteria = []
    for idx, text in enumerate(criteria_items, start=1):
        criteria.append(
            {
                "id": idx,
                "acceptanceCriterion": text,
                "acceptanceCriterionSha256": criterion_sha256(text),
                "verdict": "SKIPPED",
                "evidence": [
                    {
                        "type": "command",
                        "command": "codex exec",
                        "exitCode": codex_exit,
                    }
                ],
            }
        )

    artifact = {
        "schemaVersion": "1.0.0",
        "kind": "implement",
        "stepId": step_num,
        "owner": step.get("owner", "codex"),
        "mode": step.get("mode", "codex-impl"),
        "projectRoot": os.path.realpath(project_root),
        "planPath": os.path.realpath(plan_json),
        "planName": plan.get("name", os.path.basename(os.path.dirname(plan_json))),
        "codexExitCode": codex_exit,
        "resultTxtPath": os.path.realpath(result_file),
        "streamJsonlPath": os.path.realpath(stream_file),
        "criteria": criteria,
        "filesChanged": [],
        "commands": [
            {
                "command": "codex exec",
                "exitCode": codex_exit,
            }
        ],
        "findings": [
            {
                "severity": "HIGH",
                "category": "OTHER",
                "summary": f"Codex exec exited with code {codex_exit}.",
            }
        ],
        "finalVerdict": "FAIL",
        "generatedAt": now,
    }
    if result_sha:
        artifact["resultTxtSha256"] = result_sha
    if stream_sha:
        artifact["streamJsonlSha256"] = stream_sha
    return json.dumps(artifact, indent=2) + "\n"


plan, step = load_plan_step()
criteria_items = acceptance_criteria_items(step.get("acceptanceCriteria", ""))
if not criteria_items:
    raise ValueError("Step has no parseable acceptanceCriteria; cannot emit schema-valid receipt.")

if codex_exit == 0:
    receipt_text = extract_receipt_block(result_file)
    artifact = json.loads(receipt_text)
    final_verdict = validate_artifact(artifact, plan, step, criteria_items)
    atomic_write(receipt_file, receipt_text)

    receipt_utils.bootstrap()
    proj_id = receipt_utils.project_id(project_root)
    plan_name = plan.get("name", os.path.basename(os.path.dirname(plan_json)))
    sidecar_path = receipt_utils.sign(
        "codex_impl",
        proj_id,
        plan_name,
        {
            "receiptFormatVersion": "1.0.0",
            "step": step_num,
            "stepId": step_num,
            "kind": "implement",
            "artifactPath": os.path.realpath(receipt_file),
            "artifactSha256": sha256_file(receipt_file),
            "artifactSchemaVersion": "1.0.0",
            "finalVerdict": final_verdict,
            "planPath": os.path.realpath(plan_json),
            "planJsonSha256": sha256_file(plan_json),
        },
    )
    print(f"Receipt artifact written: {receipt_file}")
    print(f"HMAC sidecar written: {sidecar_path}")
else:
    atomic_write(receipt_file, make_failure_artifact(plan, step, criteria_items))
    print(f"Receipt artifact written without sidecar: {receipt_file}", file=sys.stderr)
PY

exit $CODEX_EXIT
