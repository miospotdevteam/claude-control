#!/usr/bin/env bash
# Shell helpers for receipt-based enforcement in hooks.
#
# Provides functions to check receipts from shell hooks without
# spawning a full Python process for simple checks.
#
# Usage: source this file from hook scripts.
#   source "${BASH_SOURCE[0]%/*}/lib/receipt-state.sh"

# Resolve the receipt_utils.py path relative to the plugin structure.
# Hooks live at hooks/, scripts at scripts/, both under the plugin root.
_RECEIPT_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"
RECEIPT_UTILS="${_RECEIPT_UTILS_DIR}/receipt_utils.py"

# State root path (matches receipt_utils.py)
RECEIPT_STATE_ROOT="${HOME}/.claude/look-before-you-leap/state"

receipt_bootstrap() {
  # Ensure state root and secret exist. Safe to call multiple times.
  python3 "$RECEIPT_UTILS" bootstrap >/dev/null 2>&1
}

receipt_project_id() {
  # Get stable project ID for a project root path.
  # Usage: receipt_project_id /path/to/project
  python3 "$RECEIPT_UTILS" project-id "$1" 2>/dev/null
}

receipt_plan_id() {
  # Get plan ID from a plan.json path (extracts the "name" field).
  # Usage: receipt_plan_id /path/to/plan.json
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get('name', 'unknown'))
" "$1" 2>/dev/null
}

receipt_check() {
  # Check if a valid receipt exists.
  # Usage: receipt_check <type> <projectId> <planId> [key=value ...]
  # Returns 0 if exists, 1 if missing.
  python3 "$RECEIPT_UTILS" check "$@" >/dev/null 2>&1
}

receipt_verify_step_artifact() {
  # Verify a step JSON evidence artifact and its HMAC sidecar linkage.
  # Usage:
  #   receipt_verify_step_artifact <project_root> <plan.json> <step> <receipt_type> <expected_kind>
  #
  # Returns 0 only when:
  #   - <plan-dir>/codex-receipt-step-N.json exists
  #   - the matching <receipt_type>-step-N.json sidecar has a valid HMAC
  #   - sidecar data binds artifactPath/artifactSha256/planPath/planJsonSha256
  #   - the artifact is schemaVersion 1.0.0, finalVerdict PASS, and all criteria PASS
  python3 - "$RECEIPT_UTILS" "$1" "$2" "$3" "$4" "$5" <<'PY'
import hashlib
import importlib.util
import json
import os
import re
import sys

receipt_utils_path, project_root, plan_json, step_raw, receipt_type, expected_kind = sys.argv[1:]
step_id = int(step_raw)


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def load_receipt_utils(path):
    spec = importlib.util.spec_from_file_location("receipt_utils", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def realpath(path):
    return os.path.realpath(os.path.abspath(path))


def within(child, parent):
    try:
        return os.path.commonpath([realpath(child), realpath(parent)]) == realpath(parent)
    except ValueError:
        return False


def split_criteria(value):
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if not isinstance(value, str):
        return []
    text = value.strip()
    if not text:
        return []
    if re.search(r"(?:^|\s)\d+\.\s+", text):
        return [item.strip() for item in re.split(r"(?:^|\s)(?=\d+\.\s+)", text) if item.strip()]
    return [item.strip() for item in re.split(r"[.;](?:\s+|$)", text) if item.strip()]


def criterion_sha256(text):
    normalized = re.sub(r"\s+", " ", str(text).strip())
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


receipt_utils = load_receipt_utils(receipt_utils_path)

try:
    with open(plan_json, encoding="utf-8") as f:
        plan = json.load(f)
except Exception as exc:
    fail(f"cannot read plan.json: {exc}")

step = next((candidate for candidate in plan.get("steps", []) if int(candidate.get("id", -1)) == step_id), None)
if step is None:
    fail(f"step {step_id} not found in plan.json")

plan_dir = os.path.dirname(realpath(plan_json))
artifact_path = os.path.join(plan_dir, f"codex-receipt-step-{step_id}.json")
if not os.path.exists(artifact_path):
    fail(f"missing JSON receipt artifact at {artifact_path}")

proj_id = receipt_utils.project_id(project_root)
plan_name = plan.get("name", "unknown")
sidecar_path = os.path.join(
    receipt_utils.STATE_ROOT,
    proj_id,
    plan_name,
    f"{receipt_type}-step-{step_id}.json",
)
if not os.path.exists(sidecar_path):
    fail(f"missing {receipt_type} HMAC sidecar at {sidecar_path}")

try:
    valid, sidecar = receipt_utils.verify(sidecar_path)
except Exception as exc:
    fail(f"cannot verify {receipt_type} sidecar: {exc}")
if not valid:
    fail(f"invalid HMAC for {receipt_type} sidecar at {sidecar_path}")
if sidecar.get("type") != receipt_type:
    fail(f"{receipt_type} sidecar has wrong type {sidecar.get('type')!r}")
if sidecar.get("projectId") != proj_id:
    fail(f"{receipt_type} sidecar projectId mismatch")
if sidecar.get("planId") != plan_name:
    fail(f"{receipt_type} sidecar planId mismatch")

data = sidecar.get("data")
if not isinstance(data, dict):
    fail(f"{receipt_type} sidecar missing data block")
for field in (
    "receiptFormatVersion",
    "step",
    "stepId",
    "kind",
    "artifactPath",
    "artifactSha256",
    "artifactSchemaVersion",
    "finalVerdict",
    "planJsonSha256",
    "planPath",
):
    if field not in data:
        fail(f"{receipt_type} sidecar missing data.{field}")

if data["receiptFormatVersion"] != "1.0.0":
    fail(f"{receipt_type} sidecar has unsupported receiptFormatVersion")
if int(data["step"]) != step_id or int(data["stepId"]) != step_id:
    fail(f"{receipt_type} sidecar step id mismatch")
if data["kind"] != expected_kind:
    fail(f"{receipt_type} sidecar kind mismatch")
if data["artifactSchemaVersion"] != "1.0.0":
    fail(f"{receipt_type} sidecar has unsupported artifact schema")
if data["finalVerdict"] != "PASS":
    fail(f"{receipt_type} sidecar finalVerdict is {data['finalVerdict']}")
if not within(data["artifactPath"], plan_dir):
    fail(f"{receipt_type} artifactPath is outside the plan directory")
if realpath(data["artifactPath"]) != realpath(artifact_path):
    fail(f"{receipt_type} artifactPath does not match codex-receipt-step-{step_id}.json")
if sha256_file(artifact_path) != data["artifactSha256"]:
    fail(f"{receipt_type} artifact sha256 mismatch")
if realpath(data["planPath"]) != realpath(plan_json):
    fail(f"{receipt_type} sidecar planPath mismatch")
if sha256_file(plan_json) != data["planJsonSha256"]:
    fail(f"{receipt_type} sidecar planJsonSha256 mismatch")

try:
    with open(artifact_path, encoding="utf-8") as f:
        artifact = json.load(f)
except Exception as exc:
    fail(f"cannot parse JSON receipt artifact: {exc}")

expected_owner = step.get("owner", "codex")
expected_mode = step.get("mode", "codex-impl")
if artifact.get("schemaVersion") != "1.0.0":
    fail("JSON receipt schemaVersion mismatch")
if artifact.get("kind") != expected_kind:
    fail(f"JSON receipt kind mismatch: expected {expected_kind}")
if int(artifact.get("stepId", -1)) != step_id:
    fail("JSON receipt step-id mismatch")
if artifact.get("planName") != plan_name:
    fail("JSON receipt planName mismatch")
if artifact.get("owner") != expected_owner:
    fail("JSON receipt owner mismatch")
if artifact.get("mode") != expected_mode:
    fail("JSON receipt mode mismatch")
if artifact.get("finalVerdict") != "PASS":
    fail(f"JSON receipt finalVerdict is {artifact.get('finalVerdict')}")
if artifact.get("codexExitCode") != 0:
    fail(f"JSON receipt codexExitCode is {artifact.get('codexExitCode')}")
if artifact.get("findings") != []:
    fail("JSON receipt findings must be empty for PASS")

expected_criteria = split_criteria(step.get("acceptanceCriteria") or "")
actual_criteria = artifact.get("criteria")
if not isinstance(actual_criteria, list):
    fail("JSON receipt criteria must be an array")
if len(actual_criteria) != len(expected_criteria):
    fail("JSON receipt criterion count mismatch")
for index, expected_text in enumerate(expected_criteria, start=1):
    criterion = actual_criteria[index - 1]
    if criterion.get("id") != index:
        fail(f"JSON receipt criterion {index} id mismatch")
    if criterion.get("acceptanceCriterionSha256") != criterion_sha256(expected_text):
        fail(f"JSON receipt criterion {index} sha256 mismatch")
    if criterion.get("verdict") != "PASS":
        fail(f"JSON receipt criterion {index} verdict is {criterion.get('verdict')}")
PY
}

receipt_verify_claude_review() {
  # Verify the digest file that independently reviews a codex-impl receipt.
  # Usage: receipt_verify_claude_review <plan-dir> <step>
  python3 - "$1" "$2" <<'PY'
import hashlib
import json
import os
import sys

plan_dir, step_raw = sys.argv[1:]
step_id = int(step_raw)
artifact_path = os.path.realpath(os.path.join(plan_dir, f"codex-receipt-step-{step_id}.json"))
review_path = os.path.join(plan_dir, f"codex-receipt-step-{step_id}.claude-review.json")


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if not os.path.exists(review_path):
    fail(f"missing Claude verification digest at {review_path}")
try:
    with open(review_path, encoding="utf-8") as f:
        review = json.load(f)
except Exception as exc:
    fail(f"cannot parse Claude verification digest: {exc}")

if review.get("schemaVersion") != "1.0.0":
    fail("Claude verification digest schemaVersion mismatch")
if review.get("kind") != "claude-verification-digest":
    fail("Claude verification digest kind mismatch")
if int(review.get("stepId", -1)) != step_id:
    fail("Claude verification digest step-id mismatch")
if os.path.realpath(review.get("receiptPath", "")) != artifact_path:
    fail("Claude verification digest receiptPath mismatch")
if review.get("receiptSha256") != sha256_file(artifact_path):
    fail("Claude verification digest receiptSha256 mismatch")
if review.get("claudeVerified") != "PASS":
    fail(f"Claude verification digest verdict is {review.get('claudeVerified')}")
if review.get("findings") not in ([], None):
    fail("Claude verification digest findings must be empty for PASS")

cross_checks = review.get("crossChecks") or {}
for key in ("diffMatchesReceipt", "sha256AllMatch", "findingsReceiptConsistent"):
    if cross_checks.get(key) is not True:
        fail(f"Claude verification digest crossChecks.{key} is not true")
PY
}

receipt_sign() {
  # Create a signed receipt.
  # Usage: receipt_sign <type> <projectId> <planId> [key=value ...]
  # Prints the receipt path.
  python3 "$RECEIPT_UTILS" sign "$@" 2>/dev/null
}

receipt_verify() {
  # Verify a receipt file's signature.
  # Usage: receipt_verify /path/to/receipt.json
  # Returns 0 if valid, 1 if invalid.
  python3 "$RECEIPT_UTILS" verify "$1" >/dev/null 2>&1
}

receipt_verify_bypass() {
  # Verify a bypass receipt with session-scoping and maxEdits consumption.
  # Usage: receipt_verify_bypass /path/to/receipt.json <caller_ppid>
  # Returns 0 if valid, 1 if stale/consumed/invalid.
  # Stdout suppressed — hooks rely on exit code only.
  python3 "$RECEIPT_UTILS" verify-bypass "$1" "$2" >/dev/null 2>&1
}

receipt_classify() {
  # Classify a plan as legacy or strict.
  # Usage: receipt_classify /path/to/plan.json
  # Prints "legacy" or "strict".
  python3 "$RECEIPT_UTILS" classify "$1" 2>/dev/null
}

receipt_state_root() {
  echo "$RECEIPT_STATE_ROOT"
}
