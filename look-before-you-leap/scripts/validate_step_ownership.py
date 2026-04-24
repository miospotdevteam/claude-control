#!/usr/bin/env python3
"""Validate step ownership and return file scope for Codex scripts.

Used by run-codex-verify.sh and run-codex-implement.sh to validate that a
step has the correct owner before proceeding with verification or
implementation.

Usage:
    python3 validate_step_ownership.py <plan.json> <step_num> --direction verify|implement

For --direction verify:
  - Step must be owned by "claude" (Codex verifies Claude's work)

For --direction implement:
  - Step must be owned by "codex" (Codex implements codex-owned steps)

Output (stdout): space-separated file list (empty string = whole step scope)
Exit 0 on success, 1 on validation failure (message to stderr).
"""

import json
import sys


def main():
    if len(sys.argv) != 5:
        print(
            "Usage: validate_step_ownership.py <plan.json> <step_num> "
            "--direction verify|implement",
            file=sys.stderr,
        )
        sys.exit(1)

    plan_json = sys.argv[1]
    step_num = int(sys.argv[2])

    if sys.argv[3] != "--direction":
        print(
            "Usage: validate_step_ownership.py <plan.json> <step_num> "
            "--direction verify|implement",
            file=sys.stderr,
        )
        sys.exit(1)

    direction = sys.argv[4]

    if direction not in ("verify", "implement"):
        print("ERROR: --direction must be 'verify' or 'implement'", file=sys.stderr)
        sys.exit(1)

    expected_owner = "claude" if direction == "verify" else "codex"

    with open(plan_json) as f:
        plan = json.load(f)

    step = None
    for s in plan.get("steps", []):
        if s["id"] == step_num:
            step = s
            break

    if not step:
        print(f"ERROR: Step {step_num} not found in plan.json", file=sys.stderr)
        sys.exit(1)

    step_owner = step.get("owner", "codex")

    if step_owner != expected_owner:
        if direction == "verify":
            print(
                f"ERROR: Cannot verify a {step_owner}-owned step. "
                "Codex verifies Claude's work only. "
                "Claude must verify codex-impl steps independently.",
                file=sys.stderr,
            )
        else:
            print(
                f"ERROR: Cannot implement a {step_owner}-owned step. "
                "Codex implements codex-owned steps only.",
                file=sys.stderr,
            )
        sys.exit(1)
    print("")  # empty = whole step scope


if __name__ == "__main__":
    main()
