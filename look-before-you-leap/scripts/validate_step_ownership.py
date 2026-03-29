#!/usr/bin/env python3
"""Validate step ownership and return file scope for Codex scripts.

Used by run-codex-verify.sh and run-codex-implement.sh to validate that a
step (or group within a collab-split step) has the correct owner before
proceeding with verification or implementation.

Usage:
    python3 validate_step_ownership.py <plan.json> <step_num> [<group_idx>] --direction verify|implement

For --direction verify:
  - Step must be owned by "claude" (Codex verifies Claude's work)
  - Group must be owned by "claude" (if group_idx specified)

For --direction implement:
  - Step must be owned by "codex" (Codex implements codex-owned steps)
  - Group must be owned by "codex" (if group_idx specified)

Output (stdout): space-separated file list (empty string = whole step scope)
Exit 0 on success, 1 on validation failure (message to stderr).
"""

import json
import sys


def main():
    if len(sys.argv) < 4:
        print(
            "Usage: validate_step_ownership.py <plan.json> <step_num> "
            "[<group_idx>] --direction verify|implement",
            file=sys.stderr,
        )
        sys.exit(1)

    plan_json = sys.argv[1]
    step_num = int(sys.argv[2])

    # Parse remaining args for group_idx and --direction
    group_idx_str = ""
    direction = ""
    i = 3
    while i < len(sys.argv):
        if sys.argv[i] == "--direction" and i + 1 < len(sys.argv):
            direction = sys.argv[i + 1]
            i += 2
        else:
            group_idx_str = sys.argv[i]
            i += 1

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

    step_owner = step.get("owner", "claude")

    if group_idx_str:
        # Group-scoped: validate group-level ownership
        group_idx = int(group_idx_str)
        sub_plan = step.get("subPlan")
        if not sub_plan or not sub_plan.get("groups"):
            print(
                f"ERROR: Step {step_num} has no subPlan.groups", file=sys.stderr
            )
            sys.exit(1)
        groups = sub_plan["groups"]
        if group_idx < 0 or group_idx >= len(groups):
            print(
                f"ERROR: Group index {group_idx} out of range (0-{len(groups)-1})",
                file=sys.stderr,
            )
            sys.exit(1)
        group = groups[group_idx]
        effective_owner = group.get("owner", step_owner)
        if effective_owner != expected_owner:
            if direction == "verify":
                print(
                    f"ERROR: Cannot verify a {effective_owner}-owned group "
                    f"(group {group_idx}: '{group['name']}'). "
                    "Codex verifies Claude's work only.",
                    file=sys.stderr,
                )
            else:
                print(
                    f"ERROR: Cannot implement a {effective_owner}-owned group "
                    f"(group {group_idx}: '{group['name']}'). "
                    "Codex implements codex-owned steps only.",
                    file=sys.stderr,
                )
            sys.exit(1)
        # Output the group's files as scope
        print(" ".join(group.get("files", [])))
    else:
        # Step-scoped: validate step-level ownership
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
