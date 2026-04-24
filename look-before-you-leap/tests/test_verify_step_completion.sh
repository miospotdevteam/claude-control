#!/usr/bin/env bash
# Regression tests for verify-step-completion.sh JSON receipt gating.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/verify-step-completion.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output to not contain: $needle"
}

assert_exists() {
  local path="$1"
  [[ -e "$path" ]] || fail "expected file to exist: $path"
}

assert_not_exists() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "expected file to be absent: $path"
}

make_root() {
  mktemp -d "${TMPDIR:-/tmp}/verify-step-completion.XXXXXX"
}

make_home() {
  mktemp -d "${TMPDIR:-/tmp}/verify-step-home.XXXXXX"
}

write_fixture() {
  local root="$1"
  local owner="$2"
  local mode="$3"
  local acceptance="$4"

  mkdir -p "$root/.git" "$root/.temp/plan-mode/active/demo"

  python3 - "$root" "$owner" "$mode" "$acceptance" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
owner = sys.argv[2]
mode = sys.argv[3]
acceptance = sys.argv[4]

plan_dir = root / ".temp" / "plan-mode" / "active" / "demo"
plan = {
    "name": "demo",
    "title": "Demo",
    "status": "active",
    "_receiptMode": "strict",
    "steps": [
        {
            "id": 1,
            "title": "Hook regression",
            "status": "done",
            "owner": owner,
            "mode": mode,
            "skill": "none",
            "codexVerify": True,
            "acceptanceCriteria": acceptance,
            "files": ["look-before-you-leap/tests/test_verify_step_completion.sh"],
            "progress": [],
            "result": "receipt-gated",
        }
    ],
}

(plan_dir / "plan.json").write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
payload = {
    "tool_name": "Edit",
    "tool_input": {"file_path": str(plan_dir / "plan.json")},
    "cwd": str(root),
}
(root / "input.json").write_text(json.dumps(payload), encoding="utf-8")
PY
}

write_receipt() {
  local root="$1"
  local home_dir="$2"
  local receipt_type="$3"
  local kind="$4"
  local criterion_verdict="${5:-PASS}"
  local artifact_step_id="${6:-1}"

  HOME="$home_dir" python3 - "$PLUGIN_ROOT" "$root" "$receipt_type" "$kind" "$criterion_verdict" "$artifact_step_id" <<'PY'
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

plugin_root = Path(sys.argv[1])
root = Path(sys.argv[2])
receipt_type = sys.argv[3]
kind = sys.argv[4]
criterion_verdict = sys.argv[5]
artifact_step_id = int(sys.argv[6])

sys.path.insert(0, str(plugin_root / "scripts"))
import receipt_utils


def sha256_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def normalize_criterion(text):
    return re.sub(r"\s+", " ", str(text).strip())


def criterion_sha256(text):
    return hashlib.sha256(normalize_criterion(text).encode("utf-8")).hexdigest()


def criteria_items(text):
    text = text.strip()
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


plan_dir = root / ".temp" / "plan-mode" / "active" / "demo"
plan_path = plan_dir / "plan.json"
artifact_path = plan_dir / "codex-receipt-step-1.json"
plan = json.loads(plan_path.read_text(encoding="utf-8"))
step = plan["steps"][0]
criteria = []
for index, text in enumerate(criteria_items(step["acceptanceCriteria"]), start=1):
    criteria.append(
        {
            "id": index,
            "acceptanceCriterion": text,
            "acceptanceCriterionSha256": criterion_sha256(text),
            "verdict": criterion_verdict,
            "evidence": [
                {
                    "type": "file",
                    "file": "look-before-you-leap/tests/test_verify_step_completion.sh",
                    "lineStart": 1,
                    "lineEnd": 1,
                }
            ],
        }
    )

artifact = {
    "schemaVersion": "1.0.0",
    "kind": kind,
    "stepId": artifact_step_id,
    "owner": step["owner"],
    "mode": step["mode"],
    "projectRoot": str(root.resolve()),
    "planPath": str(plan_path.resolve()),
    "planName": plan["name"],
    "codexExitCode": 0,
    "criteria": criteria,
    "filesChanged": [
        {
            "path": "look-before-you-leap/tests/test_verify_step_completion.sh",
            "changeType": "modified",
        }
    ],
    "commands": [{"command": "bash -n hook", "exitCode": 0}],
    "findings": [],
    "finalVerdict": "PASS",
    "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
artifact_path.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")

receipt_utils.bootstrap()
proj_id = receipt_utils.project_id(str(root))
receipt_utils.sign(
    receipt_type,
    proj_id,
    plan["name"],
    {
        "receiptFormatVersion": "1.0.0",
        "step": 1,
        "stepId": 1,
        "kind": kind,
        "artifactPath": str(artifact_path.resolve()),
        "artifactSha256": sha256_file(artifact_path),
        "artifactSchemaVersion": "1.0.0",
        "finalVerdict": "PASS",
        "planPath": str(plan_path.resolve()),
        "planJsonSha256": sha256_file(plan_path),
    },
)
PY
}

write_claude_review() {
  local root="$1"

  python3 - "$root" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1])
plan_dir = root / ".temp" / "plan-mode" / "active" / "demo"
artifact = plan_dir / "codex-receipt-step-1.json"
review = {
    "schemaVersion": "1.0.0",
    "kind": "claude-verification-digest",
    "stepId": 1,
    "receiptPath": str(artifact.resolve()),
    "receiptSha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
    "claudeVerified": "PASS",
    "findings": [],
    "crossChecks": {
        "diffMatchesReceipt": True,
        "sha256AllMatch": True,
        "findingsReceiptConsistent": True,
    },
    "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
(plan_dir / "codex-receipt-step-1.claude-review.json").write_text(
    json.dumps(review, indent=2) + "\n",
    encoding="utf-8",
)
PY
}

tamper_sidecar() {
  local home_dir="$1"
  python3 - "$home_dir" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
sidecar = next((home / ".claude" / "look-before-you-leap" / "state").glob("*/demo/codex_verify-step-1.json"))
data = json.loads(sidecar.read_text(encoding="utf-8"))
data["data"]["stepId"] = 99
sidecar.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
}

run_hook() {
  local root="$1"
  local home_dir="$2"
  HOME="$home_dir" bash "$HOOK" < "$root/input.json"
}

test_claude_impl_with_codex_verify_receipt_passes() {
  local root home_dir output
  root="$(make_root)"
  home_dir="$(make_home)"
  trap 'rm -rf "$root" "$home_dir"' RETURN

  write_fixture "$root" "claude" "claude-impl" "1. first criterion."
  write_receipt "$root" "$home_dir" "codex_verify" "verify"

  output="$(run_hook "$root" "$home_dir")"

  assert_contains "$output" "STEP VERIFICATION REQUIRED"
  assert_not_contains "$output" "RECEIPT VERIFICATION REQUIRED"
  assert_exists "$root/.temp/plan-mode/active/demo/.verify-pending-1"
}

test_missing_json_is_blocked() {
  local root home_dir output
  root="$(make_root)"
  home_dir="$(make_home)"
  trap 'rm -rf "$root" "$home_dir"' RETURN

  write_fixture "$root" "claude" "claude-impl" "1. first criterion."
  write_receipt "$root" "$home_dir" "codex_verify" "verify"
  rm "$root/.temp/plan-mode/active/demo/codex-receipt-step-1.json"

  output="$(run_hook "$root" "$home_dir")"

  assert_contains "$output" "RECEIPT VERIFICATION REQUIRED"
  assert_contains "$output" "missing JSON receipt artifact"
  assert_not_exists "$root/.temp/plan-mode/active/demo/.verify-pending-1"
}

test_invalid_hmac_is_blocked() {
  local root home_dir output
  root="$(make_root)"
  home_dir="$(make_home)"
  trap 'rm -rf "$root" "$home_dir"' RETURN

  write_fixture "$root" "claude" "claude-impl" "1. first criterion."
  write_receipt "$root" "$home_dir" "codex_verify" "verify"
  tamper_sidecar "$home_dir"

  output="$(run_hook "$root" "$home_dir")"

  assert_contains "$output" "RECEIPT VERIFICATION REQUIRED"
  assert_contains "$output" "invalid HMAC"
}

test_failed_criterion_is_blocked() {
  local root home_dir output
  root="$(make_root)"
  home_dir="$(make_home)"
  trap 'rm -rf "$root" "$home_dir"' RETURN

  write_fixture "$root" "claude" "claude-impl" "1. first criterion."
  write_receipt "$root" "$home_dir" "codex_verify" "verify" "FAIL"

  output="$(run_hook "$root" "$home_dir")"

  assert_contains "$output" "RECEIPT VERIFICATION REQUIRED"
  assert_contains "$output" "criterion 1 verdict is FAIL"
}

test_step_id_mismatch_is_blocked() {
  local root home_dir output
  root="$(make_root)"
  home_dir="$(make_home)"
  trap 'rm -rf "$root" "$home_dir"' RETURN

  write_fixture "$root" "claude" "claude-impl" "1. first criterion."
  write_receipt "$root" "$home_dir" "codex_verify" "verify" "PASS" "2"

  output="$(run_hook "$root" "$home_dir")"

  assert_contains "$output" "RECEIPT VERIFICATION REQUIRED"
  assert_contains "$output" "step-id mismatch"
}

test_codex_owned_requires_impl_receipt_and_claude_review() {
  local root home_dir output
  root="$(make_root)"
  home_dir="$(make_home)"
  trap 'rm -rf "$root" "$home_dir"' RETURN

  write_fixture "$root" "codex" "codex-impl" "1. first criterion."
  write_receipt "$root" "$home_dir" "codex_impl" "implement"
  write_claude_review "$root"

  output="$(run_hook "$root" "$home_dir")"

  assert_contains "$output" "STEP VERIFICATION REQUIRED"
  assert_not_contains "$output" "RECEIPT VERIFICATION REQUIRED"
}

test_codex_owned_without_claude_review_is_blocked() {
  local root home_dir output
  root="$(make_root)"
  home_dir="$(make_home)"
  trap 'rm -rf "$root" "$home_dir"' RETURN

  write_fixture "$root" "codex" "codex-impl" "1. first criterion."
  write_receipt "$root" "$home_dir" "codex_impl" "implement"

  output="$(run_hook "$root" "$home_dir")"

  assert_contains "$output" "RECEIPT VERIFICATION REQUIRED"
  assert_contains "$output" "missing Claude verification digest"
}

test_claude_owned_accepts_digest_receipt_alternative() {
  local root home_dir output
  root="$(make_root)"
  home_dir="$(make_home)"
  trap 'rm -rf "$root" "$home_dir"' RETURN

  write_fixture "$root" "claude" "claude-impl" "1. first criterion."
  write_receipt "$root" "$home_dir" "claude_impl_digest" "verify"

  output="$(run_hook "$root" "$home_dir")"

  assert_contains "$output" "STEP VERIFICATION REQUIRED"
  assert_not_contains "$output" "RECEIPT VERIFICATION REQUIRED"
}

test_claude_impl_with_codex_verify_receipt_passes
test_missing_json_is_blocked
test_invalid_hmac_is_blocked
test_failed_criterion_is_blocked
test_step_id_mismatch_is_blocked
test_codex_owned_requires_impl_receipt_and_claude_review
test_codex_owned_without_claude_review_is_blocked
test_claude_owned_accepts_digest_receipt_alternative

echo "PASS: verify-step-completion JSON receipt tests"
