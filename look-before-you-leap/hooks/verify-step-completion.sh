#!/usr/bin/env bash
# PostToolUse hook: Verify step completion before proceeding to next step.
#
# After Edit/Write to plan.json/progress.json/masterPlan.md, or after Bash calls that
# update progress via plan_utils.py, compares step statuses with a cached
# snapshot. When a step transitions to done/[x]:
# 1. For codexVerify steps: checks signed receipt sidecars and bound
#    codex-receipt-step-N.json evidence artifacts. If invalid or missing,
#    reverts the step to in_progress and blocks with repair instructions.
# 2. For steps that pass the Codex gate (or don't have codexVerify):
#    creates .verify-pending-N marker and injects directive to dispatch
#    a verification sub-agent.
#
# The verification agent checks acceptance criteria, file changes, and
# progress completeness before removing the marker.
#
# Marker: <plan-dir>/.verify-pending-N (N = step number)
# Cache: <plan-dir>/.step-status-cache (N:status per line)
#
# Input: JSON on stdin with tool_name, tool_input, cwd

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
hook_read_input

# Find project root first (needed for Bash path)
source "${BASH_SOURCE[0]%/*}/lib/find-root.sh"

CWD=$(hook_get_cwd)

PROJECT_ROOT="$(find_project_root "${CWD:-$PWD}")"

# Determine PLAN_DIR based on tool type
TOOL_NAME=$(hook_get_tool_name)

PLAN_DIR=""

if [[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" ]]; then
  # Edit/Write: extract file_path and check if it's a plan file
  FILE_PATH=$(hook_get_file_path)

  if [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/plan.json" ]]; then
    PLAN_DIR="$(dirname "$FILE_PATH")"
  elif [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/progress.json" ]]; then
    PLAN_DIR="$(dirname "$FILE_PATH")"
  elif [[ "$FILE_PATH" == *"/.temp/plan-mode/active/"*"/masterPlan.md" ]]; then
    PLAN_DIR="$(dirname "$FILE_PATH")"
  fi

elif [[ "$TOOL_NAME" == "Bash" ]]; then
  # Bash: check if command is a plan_utils call that marks a step done.
  # Extract the specific plan.json path from the command to handle multiple
  # active plans correctly (not just the first one found on disk).
  COMMAND=$(hook_get_command)

  export HOOK_COMMAND="$COMMAND"
  export HOOK_PROJECT_ROOT="$PROJECT_ROOT"

  PLAN_DIR=$(python3 << 'PYEOF'
import re, os, sys

command = os.environ.get("HOOK_COMMAND", "")
project_root = os.environ.get("HOOK_PROJECT_ROOT", "")

# Must contain plan_utils
if "plan_utils" not in command:
    sys.exit(0)

# Must contain update-step done OR complete-step
if not (re.search(r"update-step\s+\S+\s+\d+\s+done(?:\s|$|&|;)", command) or
        re.search(r"complete-step\s+", command)):
    sys.exit(0)

# Extract plan.json path from PLAN_JSON="..." variable assignment in the command
m = re.search(r'PLAN_JSON="(.*?\.temp/plan-mode/active/[^/]+/plan\.json)"', command)
if m:
    print(os.path.dirname(m.group(1)))
    sys.exit(0)

# Fallback: scan active plans directory (for commands where PLAN_JSON was set
# in a previous Bash call and only referenced as $PLAN_JSON here)
active_dir = os.path.join(project_root, ".temp", "plan-mode", "active")
if os.path.isdir(active_dir):
    for name in sorted(os.listdir(active_dir)):
        pj = os.path.join(active_dir, name, "plan.json")
        if os.path.isfile(pj):
            print(os.path.join(active_dir, name))
            break
PYEOF
  ) || true
fi

# No relevant plan file found — exit silently
if [[ -z "$PLAN_DIR" ]]; then
  exit 0
fi

CACHE_FILE="$PLAN_DIR/.step-status-cache"

PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
source "${PLUGIN_ROOT}/hooks/lib/receipt-state.sh"

PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"
PLAN_JSON="$PLAN_DIR/plan.json"
MASTER_PLAN="$PLAN_DIR/masterPlan.md"

export HOOK_PLAN_DIR="$PLAN_DIR"
export HOOK_PLAN_JSON="$PLAN_JSON"
export HOOK_MASTER_PLAN="$MASTER_PLAN"
export HOOK_PLAN_UTILS="$PLAN_UTILS"
export HOOK_CACHE_FILE="$CACHE_FILE"
export HOOK_RECEIPT_UTILS="$RECEIPT_UTILS"

# Compare current step statuses with cached, detect done transitions
RESULT=$(python3 << 'PYEOF'
import json, os, re, sys

plan_json = os.environ["HOOK_PLAN_JSON"]
master_plan = os.environ["HOOK_MASTER_PLAN"]
plan_utils_path = os.environ["HOOK_PLAN_UTILS"]
cache_file = os.environ["HOOK_CACHE_FILE"]
plan_dir_env = os.environ["HOOK_PLAN_DIR"]

# Parse current step statuses — prefer plan.json
current_steps = {}
plan_path_for_marker = master_plan  # default for marker file content

if os.path.isfile(plan_json):
    sys.path.insert(0, os.path.dirname(plan_utils_path))
    import plan_utils
    plan = plan_utils.read_plan(plan_json)
    for step in plan.get("steps", []):
        step_id = str(step["id"])
        # Map JSON statuses to single-char for cache compatibility
        status_map = {"pending": " ", "in_progress": "~", "done": "x", "blocked": "!"}
        current_steps[step_id] = status_map.get(step["status"], " ")
    plan_path_for_marker = plan_json
elif os.path.isfile(master_plan):
    # Legacy: parse masterPlan.md
    with open(master_plan) as f:
        content = f.read()
    step_pattern = re.compile(
        r'^###\s+Step\s+(\d+):.*?\n'
        r'.*?-\s+\*\*Status\*\*:\s*\[(.)\]',
        re.MULTILINE | re.DOTALL
    )
    for match in step_pattern.finditer(content):
        current_steps[match.group(1)] = match.group(2)
    plan_path_for_marker = master_plan
else:
    print(json.dumps({"newly_completed": []}))
    sys.exit(0)

# Read cached statuses
cached_steps = {}
if os.path.exists(cache_file):
    with open(cache_file) as f:
        for line in f:
            line = line.strip()
            if ':' in line:
                num, status = line.split(':', 1)
                cached_steps[num.strip()] = status.strip()

# Find steps that just transitioned to done/[x]
newly_completed = []
for step_num, status in current_steps.items():
    if status == 'x' and cached_steps.get(step_num, ' ') != 'x':
        newly_completed.append(step_num)

# Update cache
os.makedirs(plan_dir_env, exist_ok=True)
with open(cache_file, 'w') as f:
    for num in sorted(current_steps.keys(), key=int):
        f.write(f"{num}:{current_steps[num]}\n")

if not newly_completed:
    print(json.dumps({"newly_completed": []}))
    sys.exit(0)

# Create .verify-pending-N markers
markers_created = []
for step_num in newly_completed:
    marker_path = os.path.join(plan_dir_env, f".verify-pending-{step_num}")
    with open(marker_path, 'w') as f:
        f.write(f"{step_num}\n{plan_path_for_marker}\n")
    markers_created.append(step_num)

print(json.dumps({"newly_completed": markers_created, "plan_path": plan_path_for_marker}))
PYEOF
) || true

# Parse result
newly_completed=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
steps = data.get('newly_completed', [])
print(' '.join(str(s) for s in steps))
" <<< "$RESULT" 2>/dev/null) || true

# No new completions — exit silently
if [ -z "$newly_completed" ]; then
  exit 0
fi

plan_path=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data.get('plan_path', ''))
" <<< "$RESULT" 2>/dev/null) || true

plan_name="$(basename "$(dirname "$plan_path")")"

export HOOK_NEWLY_COMPLETED="$newly_completed"
export HOOK_PLAN_PATH="$plan_path"
export HOOK_PLAN_NAME="$plan_name"
export HOOK_PROJECT_ROOT="$PROJECT_ROOT"

python3 << 'PYEOF'
import hashlib
import importlib.util
import json
import os
import re
import sys


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


def criterion_sha256(text):
    normalized = re.sub(r"\s+", " ", str(text).strip())
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def realpath(path):
    return os.path.realpath(os.path.abspath(path))


def is_within(child, parent):
    try:
        return os.path.commonpath([realpath(child), realpath(parent)]) == realpath(parent)
    except ValueError:
        return False


def load_receipt_utils(path):
    spec = importlib.util.spec_from_file_location("receipt_utils", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def find_step(plan, step_id):
    for step in plan.get("steps", []):
        if int(step.get("id", -1)) == int(step_id):
            return step
    return None


def required_data_fields():
    return [
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
    ]


def verify_signed_artifact_receipt(receipt_utils, receipt_type, expected_kind,
                                   proj_id, plan_name_val, step, plan,
                                   plan_dir, plan_json_path):
    step_id = int(step["id"])
    artifact_default = os.path.join(plan_dir, f"codex-receipt-step-{step_id}.json")
    receipt_path = os.path.join(
        receipt_utils.STATE_ROOT,
        proj_id,
        plan_name_val,
        f"{receipt_type}-step-{step_id}.json",
    )

    if not os.path.exists(artifact_default):
        return False, f"missing JSON receipt artifact at {artifact_default}", None
    if not os.path.exists(receipt_path):
        return False, f"missing {receipt_type} HMAC sidecar at {receipt_path}", None

    try:
        valid, receipt = receipt_utils.verify(receipt_path)
    except Exception as exc:
        return False, f"cannot verify {receipt_type} sidecar: {exc}", None
    if not valid:
        return False, f"invalid HMAC for {receipt_type} sidecar at {receipt_path}", None

    if receipt.get("type") != receipt_type:
        return False, f"{receipt_type} sidecar has wrong type {receipt.get('type')!r}", None
    if receipt.get("projectId") != proj_id:
        return False, f"{receipt_type} sidecar projectId mismatch", None
    if receipt.get("planId") != plan_name_val:
        return False, f"{receipt_type} sidecar planId mismatch", None

    data = receipt.get("data")
    if not isinstance(data, dict):
        return False, f"{receipt_type} sidecar missing data block", None
    for field in required_data_fields():
        if field not in data:
            return False, f"{receipt_type} sidecar missing data.{field}", None

    if data["receiptFormatVersion"] != "1.0.0":
        return False, f"{receipt_type} sidecar has unsupported receiptFormatVersion", None
    if int(data["step"]) != step_id or int(data["stepId"]) != step_id:
        return False, f"{receipt_type} sidecar step id mismatch", None
    if data["kind"] != expected_kind:
        return False, f"{receipt_type} sidecar kind mismatch", None
    if data["artifactSchemaVersion"] != "1.0.0":
        return False, f"{receipt_type} sidecar has unsupported artifact schema", None
    if data["finalVerdict"] != "PASS":
        return False, f"{receipt_type} sidecar finalVerdict is {data['finalVerdict']}", None

    artifact_path = realpath(data["artifactPath"])
    if not is_within(artifact_path, plan_dir):
        return False, f"{receipt_type} artifactPath is outside the plan directory", None
    if artifact_path != realpath(artifact_default):
        return False, f"{receipt_type} artifactPath does not match codex-receipt-step-{step_id}.json", None
    if not os.path.exists(artifact_path):
        return False, f"missing JSON receipt artifact at {artifact_path}", None
    if sha256_file(artifact_path) != data["artifactSha256"]:
        return False, f"{receipt_type} artifact sha256 mismatch", None

    if realpath(data["planPath"]) != realpath(plan_json_path):
        return False, f"{receipt_type} sidecar planPath mismatch", None
    if sha256_file(plan_json_path) != data["planJsonSha256"]:
        return False, f"{receipt_type} sidecar planJsonSha256 mismatch", None

    try:
        with open(artifact_path, encoding="utf-8") as f:
            artifact = json.load(f)
    except Exception as exc:
        return False, f"cannot parse JSON receipt artifact: {exc}", None

    if artifact.get("schemaVersion") != "1.0.0":
        return False, "JSON receipt schemaVersion mismatch", None
    if artifact.get("kind") != expected_kind:
        return False, f"JSON receipt kind mismatch: expected {expected_kind}", None
    if int(artifact.get("stepId", -1)) != step_id:
        return False, "JSON receipt step-id mismatch", None
    if artifact.get("planName") != plan_name_val:
        return False, "JSON receipt planName mismatch", None
    if artifact.get("owner") != step.get("owner", "codex"):
        return False, "JSON receipt owner mismatch", None
    if artifact.get("mode") != step.get("mode", "codex-impl"):
        return False, "JSON receipt mode mismatch", None
    if artifact.get("finalVerdict") != "PASS":
        return False, f"JSON receipt finalVerdict is {artifact.get('finalVerdict')}", None
    if artifact.get("codexExitCode") != 0:
        return False, f"JSON receipt codexExitCode is {artifact.get('codexExitCode')}", None
    if artifact.get("findings") != []:
        return False, "JSON receipt findings must be empty for PASS", None

    expected_criteria = acceptance_criteria_items(step.get("acceptanceCriteria") or "")
    actual_criteria = artifact.get("criteria")
    if len(actual_criteria or []) != len(expected_criteria):
        return False, "JSON receipt criterion count mismatch", None
    for index, expected_text in enumerate(expected_criteria, start=1):
        criterion = actual_criteria[index - 1]
        if criterion.get("id") != index:
            return False, f"JSON receipt criterion {index} id mismatch", None
        if criterion.get("acceptanceCriterionSha256") != criterion_sha256(expected_text):
            return False, f"JSON receipt criterion {index} sha256 mismatch", None
        if criterion.get("verdict") != "PASS":
            return False, f"JSON receipt criterion {index} verdict is {criterion.get('verdict')}", None

    return True, "", artifact


def verify_claude_review(plan_dir, step_id, artifact):
    review_path = os.path.join(plan_dir, f"codex-receipt-step-{step_id}.claude-review.json")
    artifact_path = os.path.join(plan_dir, f"codex-receipt-step-{step_id}.json")
    if not os.path.exists(review_path):
        return False, f"missing Claude verification digest at {review_path}"

    try:
        with open(review_path, encoding="utf-8") as f:
            review = json.load(f)
    except Exception as exc:
        return False, f"cannot parse Claude verification digest: {exc}"

    if review.get("schemaVersion") != "1.0.0":
        return False, "Claude verification digest schemaVersion mismatch"
    if review.get("kind") != "claude-verification-digest":
        return False, "Claude verification digest kind mismatch"
    if int(review.get("stepId", -1)) != int(step_id):
        return False, "Claude verification digest step-id mismatch"
    if realpath(review.get("receiptPath", "")) != realpath(artifact_path):
        return False, "Claude verification digest receiptPath mismatch"
    if review.get("receiptSha256") != sha256_file(artifact_path):
        return False, "Claude verification digest receiptSha256 mismatch"
    if review.get("claudeVerified") != "PASS":
        return False, f"Claude verification digest verdict is {review.get('claudeVerified')}"
    if review.get("findings") not in ([], None):
        return False, "Claude verification digest findings must be empty for PASS"

    cross_checks = review.get("crossChecks") or {}
    for key in ("diffMatchesReceipt", "sha256AllMatch", "findingsReceiptConsistent"):
        if cross_checks.get(key) is not True:
            return False, f"Claude verification digest crossChecks.{key} is not true"

    if artifact.get("finalVerdict") != "PASS":
        return False, "Codex artifact was not PASS when Claude reviewed it"
    return True, ""

steps = os.environ["HOOK_NEWLY_COMPLETED"]
plan_path = os.environ["HOOK_PLAN_PATH"]
plan_name = os.environ["HOOK_PLAN_NAME"]
plan_dir = os.environ["HOOK_PLAN_DIR"]
plan_json_path = os.environ["HOOK_PLAN_JSON"]
plan_utils_path = os.environ["HOOK_PLAN_UTILS"]
receipt_utils_path = os.environ["HOOK_RECEIPT_UTILS"]

step_list = steps.split()
step_display = ", ".join(f"Step {s}" for s in step_list)
markers = ", ".join(f".verify-pending-{s}" for s in step_list)

project_root = os.environ.get("HOOK_PROJECT_ROOT", "")
receipt_blocked = {}
plan = None
sys.path.insert(0, os.path.dirname(plan_utils_path))
import plan_utils

if os.path.isfile(plan_json_path):
    try:
        receipt_utils = load_receipt_utils(receipt_utils_path)
        plan = plan_utils.read_plan(plan_json_path)
        proj_id = receipt_utils.project_id(project_root)
        plan_name_val = plan.get("name", "unknown")

        for sid in step_list:
            step = find_step(plan, int(sid))
            if step is None or not step.get("codexVerify", True):
                continue

            owner = step.get("owner", "codex")
            mode = step.get("mode", "codex-impl")
            if owner == "codex" or mode == "codex-impl":
                ok, reason, artifact = verify_signed_artifact_receipt(
                    receipt_utils,
                    "codex_impl",
                    "implement",
                    proj_id,
                    plan_name_val,
                    step,
                    plan,
                    plan_dir,
                    plan_json_path,
                )
                if not ok:
                    receipt_blocked[sid] = reason
                    continue
                ok, reason = verify_claude_review(plan_dir, int(sid), artifact)
                if not ok:
                    receipt_blocked[sid] = reason
                    continue
            else:
                ok, reason, _ = verify_signed_artifact_receipt(
                    receipt_utils,
                    "codex_verify",
                    "verify",
                    proj_id,
                    plan_name_val,
                    step,
                    plan,
                    plan_dir,
                    plan_json_path,
                )
                if ok:
                    continue
                first_reason = reason
                ok, reason, _ = verify_signed_artifact_receipt(
                    receipt_utils,
                    "claude_impl_digest",
                    "verify",
                    proj_id,
                    plan_name_val,
                    step,
                    plan,
                    plan_dir,
                    plan_json_path,
                )
                if not ok:
                    receipt_blocked[sid] = (
                        f"{first_reason}; no valid claude_impl_digest alternative: {reason}"
                    )
    except Exception as exc:
        for sid in step_list:
            receipt_blocked.setdefault(sid, f"receipt verification error: {exc}")
else:
    for sid in step_list:
        receipt_blocked[sid] = "plan.json not found for receipt verification"

if receipt_blocked:
    for sid in receipt_blocked:
        try:
            plan_utils.update_step_status(plan_json_path, int(sid), "in_progress")
        except Exception:
            pass
        marker_path = os.path.join(plan_dir, f".verify-pending-{sid}")
        if os.path.exists(marker_path):
            os.remove(marker_path)

    blocked_display = ", ".join(f"Step {s}" for s in receipt_blocked)
    reason_text = "\n".join(
        f"- Step {sid}: {reason}" for sid, reason in sorted(receipt_blocked.items(), key=lambda item: int(item[0]))
    )
    output = {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": (
                f"RECEIPT VERIFICATION REQUIRED — {blocked_display} "
                "requires signed JSON receipt evidence before it can be marked done.\n\n"
                "This step has been reverted to `in_progress`.\n\n"
                f"{reason_text}\n\n"
                "For claude-impl steps: run run-codex-verify.sh to mint a "
                "codex_verify sidecar bound to codex-receipt-step-N.json, or provide "
                "a valid claude_impl_digest receipt.\n"
                "For codex-impl steps: run run-codex-implement.sh to mint the "
                "codex_impl sidecar, then run the lbyl-digest verification flow so "
                "codex-receipt-step-N.claude-review.json reports PASS."
            )
        }
    }
    json.dump(output, sys.stdout)
    sys.exit(0)

# All codexVerify gates passed (or no codexVerify steps) — proceed with
# generic verification sub-agent flow
output = {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            f"STEP VERIFICATION REQUIRED — {step_display} just marked [x] in "
            f"plan '{plan_name}'.\n\n"
            "STOP. Before proceeding to the next step, you MUST dispatch a "
            "verification sub-agent to confirm the completed step was "
            "implemented correctly and fully.\n\n"
            "## Dispatch verification agent\n\n"
            "Use the Agent tool (general-purpose, foreground) with this prompt:\n\n"
            "```\n"
            f"Verify that {step_display} of the plan at `{plan_path}` was "
            "implemented correctly and FULLY. Do the following checks:\n\n"
            "1. Read the step from plan.json (definition) and progress.json (state) — "
            "note acceptanceCriteria, files array, and progress item statuses.\n"
            "2. Check `git diff --name-only` for modified tracked files AND "
            "`git status --short` for untracked new files. Every file in "
            "the step's `files` array should appear in one of these — "
            "either as a modified tracked file or as a new untracked file.\n"
            "3. Check that ALL progress items in the step have status 'done' — "
            "none should be 'pending' or 'in_progress'.\n"
            "4. If the acceptance criteria include a test or verification "
            "command, run it.\n"
            "5. Read the modified files briefly to confirm the changes match "
            "the step's description.\n\n"
            "If ALL checks pass:\n"
            "- Report: 'Verification PASSED for " + step_display + "'\n"
            "- The verification markers will be cleared automatically.\n\n"
            "If ANY check fails:\n"
            "- Report exactly what is missing or incomplete\n"
            "- Do NOT remove the marker — code edits remain blocked until "
            "the issues are fixed\n"
            "```\n\n"
            "Code file edits are BLOCKED until verification passes (the "
            f"enforce-plan hook checks for {markers}).\n\n"
            "To bypass, ask the user to run /bypass."
        )
    }
}

json.dump(output, sys.stdout)
PYEOF
