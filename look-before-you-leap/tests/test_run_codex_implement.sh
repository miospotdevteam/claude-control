#!/usr/bin/env bash
# Regression tests for run-codex-implement.sh receipt artifact emission.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMPLEMENT_SCRIPT="${PLUGIN_ROOT}/scripts/run-codex-implement.sh"
RECEIPT_UTILS="${PLUGIN_ROOT}/scripts/receipt_utils.py"

PASS=0
FAIL=0

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  PASS=$((PASS + 1))
}

assert_file() {
  local path="$1"
  local desc="$2"
  if [ -f "$path" ]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc missing at $path"
  fi
}

assert_no_file() {
  local path="$1"
  local desc="$2"
  if [ ! -f "$path" ]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc unexpectedly exists at $path"
  fi
}

make_root() {
  mktemp -d "${TMPDIR:-/tmp}/codex-impl-receipt.XXXXXX"
}

write_plan() {
  local root="$1"
  local plan_name="$2"
  python3 - "$root" "$plan_name" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
plan_name = sys.argv[2]
plan_dir = root / ".temp" / "plan-mode" / "active" / plan_name
plan_dir.mkdir(parents=True, exist_ok=True)

plan = {
    "name": plan_name,
    "title": "Codex implement receipt test",
    "context": "fixture",
    "status": "active",
    "steps": [
        {
            "id": 1,
            "title": "Implement fixture",
            "owner": "codex",
            "mode": "codex-impl",
            "status": "pending",
            "files": ["src/feature.ts"],
            "acceptanceCriteria": "Fixture implementation passes. Verification commands are recorded.",
        }
    ],
}

(plan_dir / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
(plan_dir / "discovery.md").write_text("# Discovery\n", encoding="utf-8")
PY
}

write_fake_codex() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

OUT_FILE=""
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output-last-message)
      OUT_FILE="$2"
      shift 2
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

PROMPT="${ARGS[$((${#ARGS[@]} - 1))]}"
MODE="${FAKE_CODEX_MODE:-pass}"

python3 - "$OUT_FILE" "$PROMPT" "$MODE" <<'PY'
import datetime
import hashlib
import json
import re
import sys
from pathlib import Path

out_file = Path(sys.argv[1])
prompt = sys.argv[2]
mode = sys.argv[3]

if mode == "exec-fail":
    out_file.write_text("Codex failed before producing a receipt.\n", encoding="utf-8")
    print('{"type":"error","message":"fake failure"}')
    sys.exit(42)

plan_match = re.search(r"plan at (.+?plan\.json)", prompt)
step_match = re.search(r"Implement step (\d+)", prompt)
if not plan_match or not step_match:
    raise SystemExit("fake codex could not parse prompt")

plan_path = Path(plan_match.group(1))
step_num = int(step_match.group(1))
plan = json.loads(plan_path.read_text(encoding="utf-8"))
step = next(item for item in plan["steps"] if item["id"] == step_num)

criteria_text = step["acceptanceCriteria"]
criteria_items = [
    item.strip()
    for item in re.split(r"[.;](?:\s+|$)", criteria_text.strip())
    if item.strip()
]

def criterion_sha(text):
    normalized = re.sub(r"\s+", " ", text.strip())
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()

criteria = []
for idx, text in enumerate(criteria_items, start=1):
    verdict = "PASS"
    if mode == "findings" and idx == 1:
        verdict = "FAIL"
    criteria.append(
        {
            "id": idx,
            "acceptanceCriterion": text,
            "acceptanceCriterionSha256": criterion_sha(text),
            "verdict": verdict,
            "evidence": [
                {
                    "type": "command",
                    "command": "bash -n look-before-you-leap/scripts/run-codex-implement.sh",
                    "exitCode": 0 if verdict == "PASS" else 1,
                }
            ],
        }
    )

findings = []
if mode == "findings":
    findings.append(
        {
            "severity": "HIGH",
            "category": "INCOMPLETE_WORK",
            "summary": "Fixture structured finding.",
            "criterionId": 1,
        }
    )

artifact = {
    "schemaVersion": "1.0.0",
    "kind": "implement",
    "stepId": step_num,
    "owner": step["owner"],
    "mode": step["mode"],
    "planName": plan["name"],
    "codexExitCode": 0,
    "criteria": criteria,
    "filesChanged": [
        {
            "path": "src/feature.ts",
            "changeType": "modified",
            "sha256After": "0" * 64,
            "linesAdded": 1,
            "linesDeleted": 0,
        }
    ],
    "commands": [
        {
            "command": "bash -n look-before-you-leap/scripts/run-codex-implement.sh",
            "exitCode": 0 if mode == "pass" else 1,
        }
    ],
    "findings": findings,
    "finalVerdict": "PASS" if mode == "pass" else "FINDINGS",
    "generatedAt": datetime.datetime.now(datetime.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
}

human = """FILES CHANGED:
- src/feature.ts (modified)

WHAT WAS DONE:
- Progress item 1: Fixture output.

VERIFICATION:
- Type checker: N/A
- Linter: N/A
- Tests: PASS
- Consumer check: N/A

ISSUES:
- none
"""
out_file.write_text(
    human + "\n```codex-receipt-v1\n" + json.dumps(artifact, indent=2) + "\n```\n",
    encoding="utf-8",
)
print('{"type":"message","text":"fake codex completed"}')
PY
EOF
  chmod +x "$bin_dir/codex"
}

sidecar_path() {
  local root="$1"
  local plan_name="$2"
  local proj_id
  proj_id=$(python3 "$RECEIPT_UTILS" project-id "$root")
  echo "$HOME/.claude/look-before-you-leap/state/$proj_id/$plan_name/codex_impl-step-1.json"
}

assert_artifact_verdict() {
  local artifact="$1"
  local verdict="$2"
  local desc="$3"
  if python3 - "$artifact" "$verdict" <<'PY'
import json
import sys

artifact = json.load(open(sys.argv[1], encoding="utf-8"))
expected = sys.argv[2]
assert artifact["schemaVersion"] == "1.0.0"
assert artifact["kind"] == "implement"
assert artifact["finalVerdict"] == expected
assert isinstance(artifact["criteria"], list) and artifact["criteria"]
assert isinstance(artifact["filesChanged"], list)
assert isinstance(artifact["findings"], list)
PY
  then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc"
  fi
}

assert_sidecar_bound() {
  local sidecar="$1"
  local artifact="$2"
  local verdict="$3"
  local desc="$4"
  if python3 "$RECEIPT_UTILS" verify "$sidecar" >/dev/null 2>&1 && \
     python3 - "$sidecar" "$artifact" "$verdict" <<'PY'
import hashlib
import json
import os
import sys

sidecar_path, artifact_path, expected_verdict = sys.argv[1:]
sidecar = json.load(open(sidecar_path, encoding="utf-8"))
data = sidecar["data"]
assert sidecar["type"] == "codex_impl"
assert data["receiptFormatVersion"] == "1.0.0"
assert data["step"] == 1
assert data["stepId"] == 1
assert data["kind"] == "implement"
assert data["artifactPath"] == os.path.realpath(artifact_path)
assert data["artifactSha256"] == hashlib.sha256(open(artifact_path, "rb").read()).hexdigest()
assert data["artifactSchemaVersion"] == "1.0.0"
assert data["finalVerdict"] == expected_verdict
assert data["planJsonSha256"]
PY
  then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc"
  fi
}

run_case() {
  local mode="$1"
  local plan_name="$2"
  local expected_exit="$3"
  local expected_verdict="$4"

  local root
  root=$(make_root)
  mkdir -p "$root/.git" "$root/src"
  write_plan "$root" "$plan_name"

  local fake_bin="$root/fake-bin"
  write_fake_codex "$fake_bin"

  local plan_json="$root/.temp/plan-mode/active/$plan_name/plan.json"
  local plan_dir
  plan_dir="$(dirname "$plan_json")"
  local artifact="$plan_dir/codex-receipt-step-1.json"
  local result_txt="$plan_dir/.codex-result-step-1.txt"
  local sidecar
  sidecar="$(sidecar_path "$root" "$plan_name")"

  local exit_code=0
  PATH="$fake_bin:$PATH" FAKE_CODEX_MODE="$mode" bash "$IMPLEMENT_SCRIPT" "$plan_json" 1 >/dev/null 2>&1 || exit_code=$?

  if [ "$exit_code" -eq "$expected_exit" ]; then
    pass
    echo "  PASS: $plan_name exit code $expected_exit"
  else
    fail "$plan_name exit code was $exit_code, expected $expected_exit"
  fi

  assert_file "$artifact" "$plan_name receipt artifact"
  assert_file "$result_txt" "$plan_name TXT trace preserved"
  assert_artifact_verdict "$artifact" "$expected_verdict" "$plan_name artifact verdict $expected_verdict"

  if [ "$expected_exit" -eq 0 ]; then
    assert_file "$sidecar" "$plan_name HMAC sidecar"
    assert_sidecar_bound "$sidecar" "$artifact" "$expected_verdict" "$plan_name sidecar binds artifact"
  else
    assert_no_file "$sidecar" "$plan_name HMAC sidecar"
  fi

  rm -rf "$root"
}

ORIG_HOME="$HOME"
TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/codex-impl-receipt-home.XXXXXX")
export HOME="$TEST_HOME"
trap 'export HOME="$ORIG_HOME"; rm -rf "$TEST_HOME"' EXIT

echo "=== Test: PASS receipt emission ==="
run_case "pass" "pass-plan" 0 "PASS"

echo ""
echo "=== Test: FINDINGS receipt emission ==="
run_case "findings" "findings-plan" 0 "FINDINGS"

echo ""
echo "=== Test: Codex failure writes unsigned FAIL artifact ==="
run_case "exec-fail" "failure-plan" 42 "FAIL"

echo ""
echo "=== Test: Syntax check ==="
if bash -n "$IMPLEMENT_SCRIPT"; then
  pass
  echo "  PASS: run-codex-implement.sh syntax OK"
else
  fail "run-codex-implement.sh syntax error"
fi

echo ""
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
