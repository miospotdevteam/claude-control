#!/usr/bin/env bash
# PreToolUse hook: Block moving plans to completed/ if they have unchecked items.
#
# Detects: mv commands that move plan directories from active/ to completed/
# Reads the masterPlan.md and checks for [ ], [~], or [!] markers.
# If any unchecked items remain, denies the mv.
#
# Input: JSON on stdin with tool_name, tool_input.command, cwd

set -euo pipefail

source "${BASH_SOURCE[0]%/*}/lib/hook-json.sh"
hook_read_input

# Extract command
COMMAND=$(hook_get_command)

[ -z "$COMMAND" ] && exit 0

# Only check mv commands that reference both active/ and completed/ in plan-mode
export HOOK_COMMAND="$COMMAND"

PLAN_PATH=$(python3 << 'PYEOF'
import re, os, sys

cmd = os.environ.get("HOOK_COMMAND", "")

# Must be a mv command involving plan-mode active/ -> completed/
if not re.search(r'\bmv\b', cmd):
    print("")
    sys.exit(0)

if 'plan-mode/active/' not in cmd and 'plan-mode/completed' not in cmd:
    # Also check if it has both active/ and completed/ in a plan context
    if not ('active/' in cmd and 'completed/' in cmd):
        print("")
        sys.exit(0)

# Try to extract the source path (the active plan directory or masterPlan.md)
# Common patterns:
#   mv '.temp/plan-mode/active/plan-name' '.temp/plan-mode/completed/plan-name'
#   mv '/full/path/.temp/plan-mode/active/plan-name' ...
parts = cmd.split()
source_path = ""
for i, part in enumerate(parts):
    # Skip the 'mv' command and flags
    if part == "mv" or part.startswith("-"):
        continue
    # Remove surrounding quotes
    cleaned = part.strip("'\"")
    if "plan-mode/active/" in cleaned or "/active/" in cleaned:
        source_path = cleaned
        break

if source_path:
    # Find the masterPlan.md in the source
    import os.path
    if source_path.endswith("masterPlan.md"):
        print(source_path)
    elif os.path.isfile(os.path.join(source_path, "masterPlan.md")):
        print(os.path.join(source_path, "masterPlan.md"))
    else:
        # Try appending masterPlan.md
        candidate = os.path.join(source_path, "masterPlan.md")
        print(candidate)
else:
    print("")
PYEOF
) || true

# Not a plan-moving command — allow
[ -z "$PLAN_PATH" ] && exit 0

# Check plan.json for unchecked items (fall back to masterPlan.md grep)
PLAN_DIR="$(dirname "$PLAN_PATH")"
PLAN_JSON="$PLAN_DIR/plan.json"

PLUGIN_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PLAN_UTILS="${PLUGIN_ROOT}/scripts/plan_utils.py"

export HOOK_PLAN_PATH="$PLAN_PATH"
export HOOK_PLAN_JSON="$PLAN_JSON"
export HOOK_PLAN_UTILS="$PLAN_UTILS"

python3 << 'PYEOF'
import json, os, sys

plan_path = os.environ["HOOK_PLAN_PATH"]
plan_json = os.environ["HOOK_PLAN_JSON"]
plan_utils_path = os.environ["HOOK_PLAN_UTILS"]

# Try plan.json first
if os.path.isfile(plan_json):
    sys.path.insert(0, os.path.dirname(plan_utils_path))
    import plan_utils
    plan = plan_utils.read_plan(plan_json)
    counts = plan_utils.count_by_status(plan)
    pending = counts.get("pending", 0)
    active = counts.get("in_progress", 0)
    blocked = counts.get("blocked", 0)
    done = counts.get("done", 0)

    # Even if all steps are "done", check result quality
    if pending == 0 and active == 0 and blocked == 0 and done > 0:
        # Check for steps marked done but missing results or with incomplete progress
        null_result_steps = []
        incomplete_progress_steps = []
        for step in plan.get("steps", []):
            if step["status"] != "done":
                continue
            sid = step["id"]
            # Check result field
            result = step.get("result")
            if not result or (isinstance(result, str) and not result.strip()):
                null_result_steps.append(sid)
            # Check progress items
            for p in step.get("progress", []):
                if p.get("status") != "done":
                    incomplete_progress_steps.append(sid)
                    break

        if null_result_steps or incomplete_progress_steps:
            problems = []
            if null_result_steps:
                ids = ", ".join(str(s) for s in null_result_steps)
                problems.append(
                    f"Steps with empty/null result: {ids}\n"
                    "  Every done step MUST have a result describing what was implemented."
                )
            if incomplete_progress_steps:
                ids = ", ".join(str(s) for s in incomplete_progress_steps)
                problems.append(
                    f"Steps with incomplete progress items: {ids}\n"
                    "  All progress items must be 'done' before the step is complete."
                )
            detail = "\n".join(problems)
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": (
                        f"Cannot move plan to completed/ — steps are marked done but "
                        f"work is not fully verified:\n\n{detail}\n\n"
                        f"Plan: {plan_json}\n\n"
                        "Fix: fill in result fields (via plan_utils.py set-result) and "
                        "mark all progress items done (via plan_utils.py update-progress) before moving."
                    )
                }
            }
            json.dump(output, sys.stdout)
            sys.exit(0)

        # For strict plans, check that all steps have receipts
        receipt_mode = plan.get("_receiptMode", "legacy")
        if receipt_mode == "strict":
            # Find project root from plan path
            import hashlib
            import pathlib
            import re
            plan_dir_path = pathlib.Path(plan_json).parent
            # Walk up to find .git
            project_root = str(plan_dir_path)
            p = plan_dir_path
            while p != p.parent:
                if (p / ".git").exists():
                    project_root = str(p)
                    break
                p = p.parent

            receipt_utils_dir = os.path.dirname(plan_utils_path)
            try:
                sys.path.insert(0, os.path.realpath(receipt_utils_dir))
                sys.path.insert(0, os.path.realpath(os.path.dirname(plan_utils_path)))
                import plan_utils
                import receipt_utils as ru

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

                def criteria_items(value):
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

                def verify_json_receipt(receipt_type, expected_kind, step):
                    sid = int(step["id"])
                    artifact_default = os.path.join(
                        str(plan_dir_path), f"codex-receipt-step-{sid}.json"
                    )
                    sidecar_path = os.path.join(
                        ru.STATE_ROOT,
                        proj_id,
                        plan_name_val,
                        f"{receipt_type}-step-{sid}.json",
                    )
                    if not os.path.exists(artifact_default):
                        return False, f"missing JSON receipt artifact at {artifact_default}", None
                    if not os.path.exists(sidecar_path):
                        return False, f"missing {receipt_type} HMAC sidecar at {sidecar_path}", None

                    try:
                        valid, sidecar = ru.verify(sidecar_path)
                    except Exception as exc:
                        return False, f"cannot verify {receipt_type} sidecar: {exc}", None
                    if not valid:
                        return False, f"invalid HMAC for {receipt_type} sidecar at {sidecar_path}", None
                    if sidecar.get("type") != receipt_type:
                        return False, f"{receipt_type} sidecar has wrong type {sidecar.get('type')!r}", None
                    if sidecar.get("projectId") != proj_id:
                        return False, f"{receipt_type} sidecar projectId mismatch", None
                    if sidecar.get("planId") != plan_name_val:
                        return False, f"{receipt_type} sidecar planId mismatch", None

                    data = sidecar.get("data")
                    if not isinstance(data, dict):
                        return False, f"{receipt_type} sidecar missing data block", None
                    for field in required_data_fields():
                        if field not in data:
                            return False, f"{receipt_type} sidecar missing data.{field}", None

                    if data["receiptFormatVersion"] != "1.0.0":
                        return False, f"{receipt_type} sidecar has unsupported receiptFormatVersion", None
                    if int(data["step"]) != sid or int(data["stepId"]) != sid:
                        return False, f"{receipt_type} sidecar step id mismatch", None
                    if data["kind"] != expected_kind:
                        return False, f"{receipt_type} sidecar kind mismatch", None
                    if data["artifactSchemaVersion"] != "1.0.0":
                        return False, f"{receipt_type} sidecar has unsupported artifact schema", None
                    if data["finalVerdict"] != "PASS":
                        return False, f"{receipt_type} sidecar finalVerdict is {data['finalVerdict']}", None
                    if not is_within(data["artifactPath"], str(plan_dir_path)):
                        return False, f"{receipt_type} artifactPath is outside the plan directory", None
                    if realpath(data["artifactPath"]) != realpath(artifact_default):
                        return False, f"{receipt_type} artifactPath does not match codex-receipt-step-{sid}.json", None
                    if sha256_file(artifact_default) != data["artifactSha256"]:
                        return False, f"{receipt_type} artifact sha256 mismatch", None
                    if realpath(data["planPath"]) != realpath(plan_json):
                        return False, f"{receipt_type} sidecar planPath mismatch", None
                    if sha256_file(plan_json) != data["planJsonSha256"]:
                        return False, f"{receipt_type} sidecar planJsonSha256 mismatch", None

                    try:
                        with open(artifact_default, encoding="utf-8") as f:
                            artifact = json.load(f)
                    except Exception as exc:
                        return False, f"cannot parse JSON receipt artifact: {exc}", None

                    if artifact.get("schemaVersion") != "1.0.0":
                        return False, "JSON receipt schemaVersion mismatch", None
                    if artifact.get("kind") != expected_kind:
                        return False, f"JSON receipt kind mismatch: expected {expected_kind}", None
                    if int(artifact.get("stepId", -1)) != sid:
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

                    expected_criteria = criteria_items(step.get("acceptanceCriteria") or "")
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

                def verify_claude_review(step, artifact):
                    sid = int(step["id"])
                    artifact_path = os.path.join(
                        str(plan_dir_path), f"codex-receipt-step-{sid}.json"
                    )
                    review_path = os.path.join(
                        str(plan_dir_path), f"codex-receipt-step-{sid}.claude-review.json"
                    )
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
                    if int(review.get("stepId", -1)) != sid:
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

                proj_id = ru.project_id(project_root)
                plan_name_val = plan.get("name", "unknown")
                missing_receipts = []
                for step in plan.get("steps", []):
                    sid = step["id"]
                    owner = step.get("owner", "codex")
                    mode = step.get("mode", "codex-impl")
                    if owner == "codex" or mode == "codex-impl":
                        ok, reason, artifact = verify_json_receipt(
                            "codex_impl", "implement", step
                        )
                        if not ok:
                            missing_receipts.append(f"Step {sid}: {reason}")
                            continue
                        ok, reason = verify_claude_review(step, artifact)
                        if not ok:
                            missing_receipts.append(f"Step {sid}: {reason}")
                    else:
                        ok, reason, _ = verify_json_receipt(
                            "codex_verify", "verify", step
                        )
                        if ok:
                            continue
                        first_reason = reason
                        ok, reason, _ = verify_json_receipt(
                            "claude_impl_digest", "verify", step
                        )
                        if not ok:
                            missing_receipts.append(
                                f"Step {sid}: {first_reason}; no valid "
                                f"claude_impl_digest alternative: {reason}"
                            )
                if missing_receipts:
                    detail = "\n".join(missing_receipts)
                    output = {
                        "hookSpecificOutput": {
                            "hookEventName": "PreToolUse",
                            "permissionDecision": "deny",
                            "permissionDecisionReason": (
                                f"Cannot move strict plan to completed/ — "
                                f"verification receipts missing:\n\n{detail}\n\n"
                                f"Plan: {plan_json}\n\n"
                                "Run verification scripts for each step to mint receipts."
                            )
                        }
                    }
                    json.dump(output, sys.stdout)
                    sys.exit(0)
            except ImportError:
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": (
                            "Cannot verify strict-plan receipts because receipt_utils.py "
                            "could not be loaded. Fix the plugin script path before moving "
                            "the plan to completed/."
                        )
                    }
                }
                json.dump(output, sys.stdout)
                sys.exit(0)
            except Exception as exc:
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": (
                            "Cannot verify strict-plan JSON receipts because receipt "
                            f"verification failed: {exc}"
                        )
                    }
                }
                json.dump(output, sys.stdout)
                sys.exit(0)

        # All checks pass — allow
        sys.exit(0)

elif os.path.isfile(plan_path):
    # Legacy: grep masterPlan.md
    import re
    with open(plan_path) as f:
        content = f.read()
    pending = len(re.findall(r'^\s*-\s*\[ \]', content, re.MULTILINE))
    active = len(re.findall(r'^\s*-\s*\[~\]', content, re.MULTILINE))
    blocked = len(re.findall(r'^\s*-\s*\[!\]', content, re.MULTILINE))
    done = len(re.findall(r'^\s*-\s*\[x\]', content, re.MULTILINE))
else:
    # Can't verify — allow
    sys.exit(0)

remaining = pending + active + blocked
if remaining == 0 and done > 0:
    # All done — allow
    sys.exit(0)

# Incomplete — deny
status_parts = []
if active > 0:
    status_parts.append(f"{active} in-progress")
if pending > 0:
    status_parts.append(f"{pending} pending")
if blocked > 0:
    status_parts.append(f"{blocked} blocked")

status = ", ".join(status_parts) if status_parts else "no completed items"

output = {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"Cannot move plan to completed/ — it has unfinished work: {status}.\n\n"
            f"Plan: {plan_path}\n"
            f"Progress: {done} done, {remaining} remaining\n\n"
            "A plan is only complete when ALL steps are done. "
            "Complete the remaining steps or explicitly flag them to the user "
            "before moving the plan."
        )
    }
}
json.dump(output, sys.stdout)
PYEOF
