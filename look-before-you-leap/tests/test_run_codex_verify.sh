#!/usr/bin/env bash
# Tests for run-codex-verify.sh receipt emission.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERIFY_SCRIPT="${PLUGIN_ROOT}/scripts/run-codex-verify.sh"
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

ORIG_HOME="$HOME"
TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/run-codex-verify.XXXXXX")
export HOME="$TEST_HOME"
trap 'export HOME="$ORIG_HOME"; rm -rf "$TEST_HOME"' EXIT

make_root() {
  mktemp -d "${TMPDIR:-/tmp}/run-codex-verify-root.XXXXXX"
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
    "title": "Demo",
    "context": "run-codex-verify receipt test",
    "status": "active",
    "steps": [
        {
            "id": 1,
            "title": "Verify target",
            "owner": "claude",
            "mode": "claude-impl",
            "status": "in_progress",
            "acceptanceCriteria": "1. first criterion. 2. second criterion.",
            "files": ["src/verify.ts"],
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

MODE="${FAKE_CODEX_MODE:-PASS}"
if [ "$MODE" = "EXIT42" ]; then
  if [ -n "$OUT_FILE" ]; then
    printf 'Codex crashed before receipt output.\n' > "$OUT_FILE"
  fi
  printf '{"type":"error","text":"exit42"}\n'
  exit 42
fi

PROMPT="${ARGS[$((${#ARGS[@]} - 1))]}"
python3 - "$OUT_FILE" "$PROMPT" "$MODE" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

out_file = Path(sys.argv[1])
prompt = sys.argv[2]
mode = sys.argv[3]

plan_match = re.search(r"plan at (.+?)\.\n", prompt)
step_match = re.search(r"Verify step (\d+)", prompt)
if not plan_match or not step_match:
    raise SystemExit("prompt did not include plan path/step")

plan_path = Path(plan_match.group(1))
step_id = int(step_match.group(1))
plan = json.loads(plan_path.read_text(encoding="utf-8"))
step = next(item for item in plan["steps"] if item["id"] == step_id)

def split_acceptance_criteria(text):
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

def criterion_hash(text):
    normalized = re.sub(r"\s+", " ", text.strip())
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()

texts = split_acceptance_criteria(step["acceptanceCriteria"])
is_pass = mode == "PASS"
criteria = []
for index, text in enumerate(texts, start=1):
    verdict = "PASS" if is_pass or index > 1 else "FAIL"
    criteria.append(
        {
            "id": index,
            "acceptanceCriterion": text,
            "acceptanceCriterionSha256": criterion_hash(text),
            "verdict": verdict,
            "evidence": [
                {
                    "type": "command",
                    "command": "fake verification",
                    "exitCode": 0 if verdict == "PASS" else 1,
                }
            ],
        }
    )

findings = []
if not is_pass:
    findings.append(
        {
            "severity": "HIGH",
            "category": "INCOMPLETE_WORK",
            "summary": "Fake finding for receipt emission test.",
            "criterionId": 1,
        }
    )

receipt = {
    "schemaVersion": "1.0.0",
    "kind": "verify",
    "stepId": step_id,
    "owner": step["owner"],
    "mode": step["mode"],
    "planName": plan["name"],
    "codexExitCode": 0,
    "criteria": criteria,
    "filesChanged": [],
    "findings": findings,
    "finalVerdict": "PASS" if is_pass else "FINDINGS",
    "generatedAt": "2026-04-24T00:00:00Z",
}

human = [
    "VERDICT:",
    f"{receipt['finalVerdict']} - fake verification.",
    "",
    "CRITERIA:",
]
human.extend(
    f"- C{item['id']} {item['verdict']}: fake criterion result."
    for item in criteria
)
human.extend(["", "FINDINGS:"])
if findings:
    human.append("- HIGH INCOMPLETE_WORK src/verify.ts:1 - fake finding")
else:
    human.append("- none")
human.extend(
    [
        "",
        "```codex-receipt-v1",
        json.dumps(receipt, indent=2),
        "```",
    ]
)
out_file.write_text("\n".join(human) + "\n", encoding="utf-8")
PY

printf '{"type":"message","text":"%s"}\n' "$MODE"
EOF
  chmod +x "$bin_dir/codex"
}

assert_json_field() {
  local file="$1"
  local expr="$2"
  local expected="$3"
  local desc="$4"
  local actual
  actual=$(python3 - "$file" "$expr" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

value = data
for part in sys.argv[2].split("."):
    value = value[part]
print(value)
PY
)
  if [ "$actual" = "$expected" ]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc (expected $expected, got $actual)"
  fi
}

receipt_path_for() {
  local root="$1"
  local plan_name="$2"
  local proj_id
  proj_id=$(python3 "$RECEIPT_UTILS" project-id "$root")
  echo "$HOME/.claude/look-before-you-leap/state/$proj_id/$plan_name/codex_verify-step-1.json"
}

assert_sidecar_valid() {
  local sidecar="$1"
  local artifact="$2"
  local verdict="$3"
  local desc="$4"
  if [ ! -f "$sidecar" ]; then
    fail "$desc (sidecar missing at $sidecar)"
    return
  fi
  if ! python3 "$RECEIPT_UTILS" verify "$sidecar" >/dev/null 2>&1; then
    fail "$desc (sidecar signature invalid)"
    return
  fi
  python3 - "$sidecar" "$artifact" "$verdict" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

sidecar = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
artifact_path = Path(sys.argv[2]).resolve()
expected_verdict = sys.argv[3]
data = sidecar["data"]
assert data["receiptFormatVersion"] == "1.0.0"
assert data["step"] == 1
assert data["stepId"] == 1
assert data["kind"] == "verify"
assert data["artifactPath"] == str(artifact_path)
assert data["artifactSchemaVersion"] == "1.0.0"
assert data["finalVerdict"] == expected_verdict
assert data["artifactSha256"] == hashlib.sha256(artifact_path.read_bytes()).hexdigest()
assert "planJsonSha256" in data
PY
  pass
  echo "  PASS: $desc"
}

run_case() {
  local mode="$1"
  local plan_name="$2"
  local expected_exit="$3"
  local expected_verdict="$4"
  local expect_sidecar="$5"

  local root
  root=$(make_root)
  mkdir -p "$root/.git" "$root/src"
  write_plan "$root" "$plan_name"
  write_fake_codex "$root/fake-bin"

  local plan_json="$root/.temp/plan-mode/active/$plan_name/plan.json"
  local plan_dir
  plan_dir="$(dirname "$plan_json")"
  local artifact="$plan_dir/codex-receipt-step-1.json"
  local sidecar
  sidecar="$(receipt_path_for "$root" "$plan_name")"

  local exit_code=0
  PATH="$root/fake-bin:$PATH" FAKE_CODEX_MODE="$mode" \
    bash "$VERIFY_SCRIPT" "$plan_json" 1 >/dev/null 2>&1 || exit_code=$?

  if [ "$exit_code" -eq "$expected_exit" ]; then
    pass
    echo "  PASS: $mode exits $expected_exit"
  else
    fail "$mode exit code (expected $expected_exit, got $exit_code)"
  fi

  if [ -f "$artifact" ]; then
    pass
    echo "  PASS: $mode writes receipt artifact"
  else
    fail "$mode did not write receipt artifact"
  fi

  if [ -f "$plan_dir/.codex-result-step-1.txt" ]; then
    pass
    echo "  PASS: $mode preserves TXT trace"
  else
    fail "$mode did not preserve TXT trace"
  fi

  assert_json_field "$artifact" "finalVerdict" "$expected_verdict" "$mode artifact finalVerdict"

  if [ "$expect_sidecar" = "yes" ]; then
    assert_sidecar_valid "$sidecar" "$artifact" "$expected_verdict" "$mode writes valid HMAC sidecar"
  elif [ -f "$sidecar" ]; then
    fail "$mode unexpectedly wrote sidecar"
  else
    pass
    echo "  PASS: $mode does not write sidecar"
  fi

  rm -rf "$root"
}

echo "=== Test: PASS writes JSON artifact + HMAC sidecar ==="
run_case "PASS" "pass-plan" 0 "PASS" "yes"

echo ""
echo "=== Test: FINDINGS writes JSON artifact + HMAC sidecar ==="
run_case "FINDINGS" "findings-plan" 0 "FINDINGS" "yes"

echo ""
echo "=== Test: Codex nonzero writes FAIL artifact without sidecar ==="
run_case "EXIT42" "exit-plan" 42 "FAIL" "no"

echo ""
echo "=== Test: bash syntax ==="
if bash -n "$VERIFY_SCRIPT"; then
  pass
  echo "  PASS: run-codex-verify.sh syntax OK"
else
  fail "run-codex-verify.sh syntax error"
fi

echo ""
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
fi
echo "ALL TESTS PASSED"
