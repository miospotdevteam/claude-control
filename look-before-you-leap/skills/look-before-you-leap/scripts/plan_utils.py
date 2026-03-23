#!/usr/bin/env python3
"""
Plan utilities for look-before-you-leap hooks.

Provides read/update operations on plan.json files, replacing fragile
markdown regex parsing. Used by hooks via CLI and by session-start.sh
via import.

CLI usage:
    python3 plan-utils.py status <plan.json>
    python3 plan-utils.py next-step <plan.json>
    python3 plan-utils.py update-step <plan.json> <step_id> <new_status>
    python3 plan-utils.py update-progress <plan.json> <step_id> <progress_index> <new_status>
    python3 plan-utils.py set-result <plan.json> <step_id> <result_text>
    python3 plan-utils.py add-summary <plan.json> <summary_text>
    python3 plan-utils.py add-deviation <plan.json> <deviation_text>
    python3 plan-utils.py is-fresh <plan.json>
    python3 plan-utils.py is-complete <plan.json>
    python3 plan-utils.py find-active <project_root>
    python3 plan-utils.py update-codex-session <plan.json> <threadId> <phase>
    python3 plan-utils.py get-codex-session <plan.json>
    python3 plan-utils.py clear-codex-session <plan.json>
"""

import json
import os
import signal
import sys


def read_plan(plan_path):
    """Read and parse a plan.json file."""
    with open(plan_path) as f:
        return json.load(f)


def write_plan(plan_path, plan):
    """Write a plan dict back to plan.json with consistent formatting."""
    with open(plan_path, "w") as f:
        json.dump(plan, f, indent=2, ensure_ascii=False)
        f.write("\n")


def get_step(plan, step_id):
    """Get a specific step by ID. Returns None if not found."""
    for step in plan.get("steps", []):
        if step["id"] == step_id:
            return step
    return None


def count_by_status(plan):
    """Count steps by status. Returns dict of status -> count."""
    counts = {"pending": 0, "in_progress": 0, "done": 0, "blocked": 0}
    for step in plan.get("steps", []):
        status = step.get("status", "pending")
        counts[status] = counts.get(status, 0) + 1
    return counts


def get_next_step(plan):
    """Find the next step to work on (in_progress first, then pending)."""
    for step in plan.get("steps", []):
        if step["status"] == "in_progress":
            return step
    for step in plan.get("steps", []):
        if step["status"] == "pending":
            return step
    return None


def is_fresh(plan):
    """Check if plan is fresh (all steps pending, none done/in_progress)."""
    for step in plan.get("steps", []):
        if step["status"] != "pending":
            return False
    return len(plan.get("steps", [])) > 0


def is_complete(plan):
    """Check if all steps are done."""
    steps = plan.get("steps", [])
    if not steps:
        return False
    return all(s["status"] == "done" for s in steps)


VALID_MODES = {"claude-impl", "codex-impl", "collab-split", "dual-pass"}
VALID_SKILLS = {
    "none",
    "look-before-you-leap:test-driven-development",
    "look-before-you-leap:frontend-design",
    "look-before-you-leap:svg-art",
    "look-before-you-leap:immersive-frontend",
    "look-before-you-leap:react-native-mobile",
    "look-before-you-leap:systematic-debugging",
    "look-before-you-leap:refactoring",
    "look-before-you-leap:webapp-testing",
    "look-before-you-leap:mcp-builder",
    "look-before-you-leap:doc-coauthoring",
}


def update_step_status(plan_path, step_id, new_status):
    """Update a step's status and write back to disk.

    When setting to 'done', warns if progress items are incomplete or
    result field is empty. These are soft warnings — the guard hook
    (guard-plan-completion.sh) is the hard gate that blocks mv.
    """
    plan = read_plan(plan_path)
    step = get_step(plan, step_id)
    if step is None:
        print(f"Error: step {step_id} not found", file=sys.stderr)
        return False

    # Validate mode and skill values
    mode = step.get("mode")
    if mode and mode not in VALID_MODES:
        print(
            f"Warning: step {step_id} has invalid mode \"{mode}\" — "
            f"valid values: {', '.join(sorted(VALID_MODES))}",
            file=sys.stderr,
        )
    skill = step.get("skill")
    if skill and skill not in VALID_SKILLS:
        print(
            f"Warning: step {step_id} has invalid skill \"{skill}\" — "
            f"valid values: none, look-before-you-leap:<skill-name>",
            file=sys.stderr,
        )

    if new_status == "done":
        # Warn about incomplete progress items
        incomplete = [
            p["task"] for p in step.get("progress", [])
            if p.get("status") != "done"
        ]
        if incomplete:
            print(
                f"Warning: step {step_id} marked done but has "
                f"{len(incomplete)} incomplete progress item(s): "
                f"{', '.join(incomplete[:3])}"
                f"{'...' if len(incomplete) > 3 else ''}",
                file=sys.stderr,
            )

        # Warn about missing result
        result = step.get("result")
        if not result or (isinstance(result, str) and not result.strip()):
            print(
                f"Warning: step {step_id} marked done with no result. "
                f"Fill in the result field describing what was implemented.",
                file=sys.stderr,
            )

        # Warn about progress items missing files field
        for i, p in enumerate(step.get("progress", [])):
            if "files" not in p:
                print(
                    f"Warning: progress item {i} of step {step_id} has no "
                    f"files field — resumption after compaction will be degraded",
                    file=sys.stderr,
                )

    step["status"] = new_status
    write_plan(plan_path, plan)
    return True


def update_progress_item(plan_path, step_id, progress_index, new_status):
    """Update a progress item's status within a step."""
    plan = read_plan(plan_path)
    step = get_step(plan, step_id)
    if step is None:
        print(f"Error: step {step_id} not found", file=sys.stderr)
        return False
    progress = step.get("progress", [])
    if progress_index < 0 or progress_index >= len(progress):
        print(f"Error: progress index {progress_index} out of range", file=sys.stderr)
        return False
    item = progress[progress_index]
    if "files" not in item:
        print(
            f"Warning: progress item {progress_index} of step {step_id} has no "
            f"files field — resumption after compaction will be degraded",
            file=sys.stderr,
        )
    item["status"] = new_status
    write_plan(plan_path, plan)
    return True


def set_result(plan_path, step_id, result_text):
    """Set the result field on a step."""
    plan = read_plan(plan_path)
    step = get_step(plan, step_id)
    if step is None:
        print(f"Error: step {step_id} not found", file=sys.stderr)
        return False
    step["result"] = result_text
    write_plan(plan_path, plan)
    return True


def add_summary(plan_path, text):
    """Append to the completedSummary array."""
    plan = read_plan(plan_path)
    plan.setdefault("completedSummary", []).append(text)
    write_plan(plan_path, plan)
    return True


def add_deviation(plan_path, text):
    """Append to the deviations array."""
    plan = read_plan(plan_path)
    plan.setdefault("deviations", []).append(text)
    write_plan(plan_path, plan)
    return True


def update_codex_session(plan_path, thread_id, phase):
    """Set or update the codexSession object in plan.json.

    Creates the codexSession if it doesn't exist. Increments
    interactionCount and updates lastInteraction timestamp.
    """
    from datetime import datetime, timezone

    plan = read_plan(plan_path)
    session = plan.get("codexSession")
    if not isinstance(session, dict):
        # Missing, null, or malformed — initialize fresh
        session = {
            "threadId": thread_id,
            "phase": phase,
            "interactionCount": 1,
            "lastInteraction": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
    else:
        session["threadId"] = thread_id
        session["phase"] = phase
        prev_count = session.get("interactionCount", 0)
        session["interactionCount"] = (prev_count if isinstance(prev_count, int) else 0) + 1
        session["lastInteraction"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    plan["codexSession"] = session
    write_plan(plan_path, plan)
    return True


def get_codex_session(plan_path):
    """Read and return the codexSession object. Returns None if absent."""
    plan = read_plan(plan_path)
    return plan.get("codexSession")


def clear_codex_session(plan_path):
    """Remove the codexSession object from plan.json.

    Used when a thread is lost, a plan completes, or a fresh thread
    is needed. Safe to call even if codexSession doesn't exist.
    """
    plan = read_plan(plan_path)
    plan.pop("codexSession", None)
    write_plan(plan_path, plan)
    return True


def _is_pid_alive(pid):
    """Check if a process is alive. Returns False for invalid PIDs."""
    try:
        pid = int(pid)
        if pid <= 0:
            return False
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        return False


def find_active_plan(project_root):
    """Find the most recently modified plan.json in active plans.

    Returns the plan.json path, or None if no active plan.
    """
    active_dir = os.path.join(project_root, ".temp", "plan-mode", "active")
    if not os.path.isdir(active_dir):
        return None

    latest_path = None
    latest_mtime = 0

    for entry in os.listdir(active_dir):
        plan_path = os.path.join(active_dir, entry, "plan.json")
        if os.path.isfile(plan_path):
            mtime = os.path.getmtime(plan_path)
            if mtime > latest_mtime:
                latest_mtime = mtime
                latest_path = plan_path

    return latest_path


def find_plan_for_session(project_root, ppid):
    """Find the plan claimed by a specific session (PPID).

    Scans .session-lock files in active/ subdirectories. Returns the
    plan.json path where the lock matches ppid, or None.
    """
    active_dir = os.path.join(project_root, ".temp", "plan-mode", "active")
    if not os.path.isdir(active_dir):
        return None

    ppid_str = str(ppid)

    for entry in os.listdir(active_dir):
        plan_dir = os.path.join(active_dir, entry)
        if not os.path.isdir(plan_dir):
            continue
        lock_file = os.path.join(plan_dir, ".session-lock")
        plan_path = os.path.join(plan_dir, "plan.json")
        if os.path.isfile(lock_file) and os.path.isfile(plan_path):
            try:
                with open(lock_file) as f:
                    lock_pid = f.read().strip()
                if lock_pid == ppid_str:
                    return plan_path
            except OSError:
                continue

    return None


def find_unclaimed_plans(project_root):
    """Find active plans with dead or missing .session-lock PIDs.

    Returns list of (plan_name, plan_json_path) sorted by mtime desc.
    """
    active_dir = os.path.join(project_root, ".temp", "plan-mode", "active")
    if not os.path.isdir(active_dir):
        return []

    unclaimed = []

    for entry in os.listdir(active_dir):
        plan_dir = os.path.join(active_dir, entry)
        if not os.path.isdir(plan_dir):
            continue
        plan_path = os.path.join(plan_dir, "plan.json")
        if not os.path.isfile(plan_path):
            continue

        lock_file = os.path.join(plan_dir, ".session-lock")
        if not os.path.isfile(lock_file):
            # No lock at all — unclaimed
            mtime = os.path.getmtime(plan_path)
            unclaimed.append((entry, plan_path, mtime))
            continue

        try:
            with open(lock_file) as f:
                lock_pid = f.read().strip()
        except OSError:
            mtime = os.path.getmtime(plan_path)
            unclaimed.append((entry, plan_path, mtime))
            continue

        if not lock_pid or not _is_pid_alive(lock_pid):
            mtime = os.path.getmtime(plan_path)
            unclaimed.append((entry, plan_path, mtime))

    # Sort by mtime descending (most recent first)
    unclaimed.sort(key=lambda x: x[2], reverse=True)
    return [(name, path) for name, path, _ in unclaimed]


def format_status(plan):
    """Format a human-readable status summary."""
    counts = count_by_status(plan)
    parts = []
    if counts["done"]:
        parts.append(f"{counts['done']} done")
    if counts["in_progress"]:
        parts.append(f"{counts['in_progress']} active")
    if counts["pending"]:
        parts.append(f"{counts['pending']} pending")
    if counts["blocked"]:
        parts.append(f"{counts['blocked']} blocked")
    return " | ".join(parts) if parts else "empty"


def cli_status(plan_path):
    """Print plan status summary."""
    plan = read_plan(plan_path)
    counts = count_by_status(plan)
    print(json.dumps({
        "name": plan.get("name", "unknown"),
        "title": plan.get("title", "unknown"),
        "status": plan.get("status", "unknown"),
        "counts": counts,
        "summary": format_status(plan),
        "total_steps": len(plan.get("steps", [])),
    }))


def cli_next_step(plan_path):
    """Print the next step to work on."""
    plan = read_plan(plan_path)
    step = get_next_step(plan)
    if step:
        print(json.dumps({
            "id": step["id"],
            "title": step["title"],
            "status": step["status"],
            "description": step.get("description", ""),
        }))
    else:
        print(json.dumps({"id": None, "title": None, "message": "No pending steps"}))


def print_help():
    """Print usage information with all available commands."""
    print("""Usage: plan_utils.py <command> <plan.json|project_root> [args...]

Plan state commands:
  status <plan.json>                              Show plan status summary
  next-step <plan.json>                           Show next step to work on
  is-fresh <plan.json>                            Check if plan is untouched
  is-complete <plan.json>                         Check if all steps are done

Plan update commands:
  update-step <plan.json> <step_id> <status>      Update step status
  update-progress <plan.json> <step_id> <idx> <s> Update progress item status
  set-result <plan.json> <step_id> <text>         Set step result text
  add-summary <plan.json> <text>                  Append to completedSummary
  add-deviation <plan.json> <text>                Append to deviations

Codex session commands:
  update-codex-session <plan.json> <threadId> <phase>  Set/update codex session
  get-codex-session <plan.json>                        Read codex session state
  clear-codex-session <plan.json>                      Remove codex session

Plan discovery commands:
  find-active <project_root>                      Find most recent active plan
  find-for-session <project_root> <ppid>          Find plan for a session PID
  find-unclaimed <project_root>                   Find plans with dead locks""")


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("--help", "-h"):
        print_help()
        sys.exit(0)

    if len(sys.argv) < 3:
        print("Usage: plan_utils.py <command> <plan.json|project_root> [args...]", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "find-active":
        project_root = sys.argv[2]
        result = find_active_plan(project_root)
        if result:
            print(result)
        else:
            print("")
        return

    if command == "find-for-session":
        if len(sys.argv) < 4:
            print("Usage: plan-utils.py find-for-session <project_root> <ppid>", file=sys.stderr)
            sys.exit(1)
        project_root = sys.argv[2]
        ppid = sys.argv[3]
        result = find_plan_for_session(project_root, ppid)
        if result:
            print(result)
        else:
            print("")
        return

    if command == "find-unclaimed":
        project_root = sys.argv[2]
        result = find_unclaimed_plans(project_root)
        if result:
            for name, path in result:
                print(f"{name}\t{path}")
        else:
            print("")
        return

    plan_path = sys.argv[2]

    if command == "status":
        cli_status(plan_path)

    elif command == "next-step":
        cli_next_step(plan_path)

    elif command == "update-step":
        if len(sys.argv) < 5:
            print("Usage: plan-utils.py update-step <plan.json> <step_id> <status>", file=sys.stderr)
            sys.exit(1)
        step_id = int(sys.argv[3])
        new_status = sys.argv[4]
        if not update_step_status(plan_path, step_id, new_status):
            sys.exit(1)

    elif command == "update-progress":
        if len(sys.argv) < 6:
            print("Usage: plan-utils.py update-progress <plan.json> <step_id> <index> <status>", file=sys.stderr)
            sys.exit(1)
        step_id = int(sys.argv[3])
        progress_index = int(sys.argv[4])
        new_status = sys.argv[5]
        if not update_progress_item(plan_path, step_id, progress_index, new_status):
            sys.exit(1)

    elif command == "set-result":
        if len(sys.argv) < 5:
            print("Usage: plan-utils.py set-result <plan.json> <step_id> <result_text>", file=sys.stderr)
            sys.exit(1)
        step_id = int(sys.argv[3])
        result_text = sys.argv[4]
        if not set_result(plan_path, step_id, result_text):
            sys.exit(1)

    elif command == "add-summary":
        if len(sys.argv) < 4:
            print("Usage: plan-utils.py add-summary <plan.json> <text>", file=sys.stderr)
            sys.exit(1)
        text = sys.argv[3]
        add_summary(plan_path, text)

    elif command == "add-deviation":
        if len(sys.argv) < 4:
            print("Usage: plan-utils.py add-deviation <plan.json> <text>", file=sys.stderr)
            sys.exit(1)
        text = sys.argv[3]
        add_deviation(plan_path, text)

    elif command == "update-codex-session":
        if len(sys.argv) < 5:
            print("Usage: plan-utils.py update-codex-session <plan.json> <threadId> <phase>", file=sys.stderr)
            sys.exit(1)
        thread_id = sys.argv[3]
        phase = sys.argv[4]
        if not update_codex_session(plan_path, thread_id, phase):
            sys.exit(1)

    elif command == "get-codex-session":
        session = get_codex_session(plan_path)
        if session:
            print(json.dumps(session))
        else:
            print(json.dumps(None))

    elif command == "clear-codex-session":
        if not clear_codex_session(plan_path):
            sys.exit(1)

    elif command == "is-fresh":
        plan = read_plan(plan_path)
        print("true" if is_fresh(plan) else "false")

    elif command == "is-complete":
        plan = read_plan(plan_path)
        print("true" if is_complete(plan) else "false")

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
