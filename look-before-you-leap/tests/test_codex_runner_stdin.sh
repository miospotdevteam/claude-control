#!/usr/bin/env bash
# Regression tests for Codex runner scripts.
#
# Verifies run-codex-verify.sh and run-codex-implement.sh close stdin when
# invoking `codex exec`, so the Codex CLI does not hang waiting for
# additional stdin from the Bash tool.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERIFY_SCRIPT="${PLUGIN_ROOT}/scripts/run-codex-verify.sh"
IMPLEMENT_SCRIPT="${PLUGIN_ROOT}/scripts/run-codex-implement.sh"

PASS=0
FAIL=0

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

pass() {
  PASS=$((PASS + 1))
}

make_root() {
  mktemp -d "${TMPDIR:-/tmp}/codex-runner-stdin.XXXXXX"
}

write_plan() {
  local root="$1"
  python3 - "$root" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
plan_dir = root / ".temp" / "plan-mode" / "active" / "demo"
plan_dir.mkdir(parents=True, exist_ok=True)

plan = {
    "name": "demo",
    "title": "Demo",
    "context": "stdin regression",
    "status": "active",
    "steps": [
        {
            "id": 1,
            "title": "Verify target",
            "owner": "claude",
            "status": "in_progress",
            "files": ["src/verify.ts"],
        },
        {
            "id": 2,
            "title": "Implement target",
            "owner": "codex",
            "status": "pending",
            "files": ["src/implement.ts"],
        },
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

STDIN_KIND=$(python3 -c 'import os, stat; mode = os.fstat(0).st_mode; print("char" if stat.S_ISCHR(mode) else "fifo" if stat.S_ISFIFO(mode) else "other")')

if [ "$STDIN_KIND" != "char" ]; then
  echo "stdin not redirected to /dev/null (kind=$STDIN_KIND)" >&2
  exit 99
fi

if [ -n "$OUT_FILE" ]; then
  printf 'PASS\nstdin:%s\n' "$STDIN_KIND" > "$OUT_FILE"
fi

printf '{"type":"message","text":"PASS stdin:%s"}\n' "$STDIN_KIND"
EOF
  chmod +x "$bin_dir/codex"
}

run_case() {
  local script="$1"
  local step="$2"
  local desc="$3"
  local root
  root=$(make_root)
  mkdir -p "$root/.git" "$root/src"
  write_plan "$root"

  local fake_bin="$root/fake-bin"
  write_fake_codex "$fake_bin"

  local plan_json="$root/.temp/plan-mode/active/demo/plan.json"
  local exit_code=0
  PATH="$fake_bin:$PATH" bash "$script" "$plan_json" "$step" >/dev/null 2>&1 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass
    echo "  PASS: $desc"
  else
    fail "$desc (exit=$exit_code)"
  fi

  rm -rf "$root"
}

echo "=== Test: run-codex-verify.sh closes stdin ==="
run_case "$VERIFY_SCRIPT" 1 "verify runner redirects stdin away from Bash pipe"

echo ""
echo "=== Test: run-codex-implement.sh closes stdin ==="
run_case "$IMPLEMENT_SCRIPT" 2 "implement runner redirects stdin away from Bash pipe"

echo ""
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
