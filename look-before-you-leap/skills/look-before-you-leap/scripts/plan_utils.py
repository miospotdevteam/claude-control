#!/usr/bin/env python3
"""
Plan utilities for look-before-you-leap hooks.

Provides read/update operations on plan.json (immutable definition) and
progress.json (mutable execution state). After Orbit approval, plan.json
is frozen; all mutations go to progress.json.

read_plan() returns a merged view (plan + progress) for backwards
compatibility. Legacy plans without progress.json still work — mutable
fields are read from plan.json as a fallback.

CLI usage:
    python3 plan-utils.py status <plan.json>
    python3 plan-utils.py next-step <plan.json>
    python3 plan-utils.py active-steps <plan.json>
    python3 plan-utils.py runnable-steps <plan.json>
    python3 plan-utils.py update-step <plan.json> <step_id> <new_status>
    python3 plan-utils.py update-progress <plan.json> <step_id> <progress_index> <new_status>
    python3 plan-utils.py set-result <plan.json> <step_id> <result_text>
    python3 plan-utils.py add-summary <plan.json> <summary_text>
    python3 plan-utils.py add-deviation <plan.json> <deviation_text>
    python3 plan-utils.py is-fresh <plan.json>
    python3 plan-utils.py is-complete <plan.json>
    python3 plan-utils.py find-active <project_root>
    python3 plan-utils.py update-codex-session <plan.json> <threadId> <phase> [step_id]
    python3 plan-utils.py get-codex-session <plan.json> [step_id]
    python3 plan-utils.py clear-codex-session <plan.json>
"""

import fcntl
import json
import os
import signal
import sys


# ---------------------------------------------------------------------------
# progress.json helpers
# ---------------------------------------------------------------------------

def progress_path_for(plan_path):
    """Derive the progress.json path from a plan.json path."""
    return os.path.join(os.path.dirname(plan_path), "progress.json")


def read_progress(plan_path):
    """Read progress.json sibling. Returns empty dict if missing."""
    path = progress_path_for(plan_path)
    if not os.path.isfile(path):
        return {}
    with open(path) as f:
        return json.load(f)


def transactional_update(progress_path, mutator_fn):
    """Apply a read-modify-write update while holding an exclusive file lock."""
    parent_dir = os.path.dirname(progress_path)
    if parent_dir:
        os.makedirs(parent_dir, exist_ok=True)

    try:
        with open(progress_path, "x", encoding="utf-8") as f:
            f.write("{}\n")
    except FileExistsError:
        pass

    with open(progress_path, "r+", encoding="utf-8") as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        try:
            raw = f.read()
            data = json.loads(raw) if raw.strip() else {}
            mutator_fn(data)
            f.seek(0)
            f.truncate()
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
            return data
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)


def write_progress(plan_path, progress):
    """Write progress dict to progress.json sibling."""
    path = progress_path_for(plan_path)
    progress_copy = json.loads(json.dumps(progress))

    def _replace(existing):
        existing.clear()
        existing.update(progress_copy)

    transactional_update(path, _replace)


def _ensure_progress(plan_path):
    """Return progress dict, migrating from plan.json on first call.

    If progress.json doesn't exist yet, extracts mutable state from
    plan.json to bootstrap it (preserving in-flight status/results).
    """
    prog_path = progress_path_for(plan_path)
    if os.path.isfile(prog_path):
        with open(prog_path) as f:
            return json.load(f)

    # First write — migrate current mutable state from plan.json
    with open(plan_path) as f:
        plan = json.load(f)

    return extract_progress(plan)


def extract_progress(plan):
    """Extract mutable fields from a plan dict into progress format.

    Used for first-write migration from legacy plan.json.
    """
    progress = {"steps": {}}

    for step in plan.get("steps", []):
        step_id = str(step["id"])
        step_prog = {
            "status": step.get("status", "pending"),
        }
        if "result" in step:
            step_prog["result"] = step["result"]
        if step.get("progress"):
            step_prog["progress"] = [
                {"status": p.get("status", "pending")} for p in step["progress"]
            ]
        # Migrate subPlan group mutable fields
        sub_plan = step.get("subPlan")
        if sub_plan and sub_plan.get("groups"):
            groups = {}
            for i, g in enumerate(sub_plan["groups"]):
                g_prog = {}
                if "status" in g:
                    g_prog["status"] = g["status"]
                if "notes" in g:
                    g_prog["notes"] = g["notes"]
                if g_prog:
                    groups[str(i)] = g_prog
            if groups:
                step_prog["groups"] = groups
        progress["steps"][step_id] = step_prog

    if plan.get("completedSummary"):
        progress["completedSummary"] = list(plan["completedSummary"])
    if plan.get("deviations"):
        progress["deviations"] = list(plan["deviations"])
    if plan.get("codexSessions"):
        progress["codexSessions"] = dict(plan["codexSessions"])
    elif plan.get("codexSession"):
        progress["codexSession"] = dict(plan["codexSession"])

    return progress


def _seed_progress_if_needed(plan_path, progress):
    """Bootstrap empty progress data from plan.json for first-write migration."""
    if progress:
        return
    progress.update(extract_progress(read_plan_definition(plan_path)))


def init_progress(plan):
    """Create a fresh progress.json for a new plan (all steps pending)."""
    progress = {"steps": {}}
    for step in plan.get("steps", []):
        step_id = str(step["id"])
        step_prog = {"status": "pending"}
        if step.get("progress"):
            step_prog["progress"] = [
                {"status": "pending"} for _ in step["progress"]
            ]
        sub_plan = step.get("subPlan")
        if sub_plan and sub_plan.get("groups"):
            groups = {}
            for i, g in enumerate(sub_plan["groups"]):
                groups[str(i)] = {"status": "pending"}
            step_prog["groups"] = groups
        progress["steps"][step_id] = step_prog
    return progress


def merge_plan_progress(plan, progress):
    """Merge progress into a copy of plan, returning the merged view.

    Overlays mutable fields from progress onto the immutable plan
    definition. Returns a new dict — does not mutate either input.
    """
    import copy
    merged = copy.deepcopy(plan)

    steps_prog = progress.get("steps", {})
    for step in merged.get("steps", []):
        step_id = str(step["id"])
        sp = steps_prog.get(step_id, {})
        if "status" in sp:
            step["status"] = sp["status"]
        if "result" in sp:
            step["result"] = sp["result"]
        # Merge progress item statuses
        if "progress" in sp and step.get("progress"):
            for i, p_status in enumerate(sp["progress"]):
                if i < len(step["progress"]):
                    step["progress"][i]["status"] = p_status.get(
                        "status", step["progress"][i].get("status", "pending")
                    )
        # Merge subPlan group mutable fields
        if "groups" in sp:
            sub_plan = step.get("subPlan")
            if sub_plan and sub_plan.get("groups"):
                for idx_str, g_prog in sp["groups"].items():
                    idx = int(idx_str)
                    if 0 <= idx < len(sub_plan["groups"]):
                        if "status" in g_prog:
                            sub_plan["groups"][idx]["status"] = g_prog["status"]
                        if "notes" in g_prog:
                            sub_plan["groups"][idx]["notes"] = g_prog["notes"]

    if "completedSummary" in progress:
        merged["completedSummary"] = list(progress["completedSummary"])
    if "deviations" in progress:
        merged["deviations"] = list(progress["deviations"])
    if "codexSessions" in progress:
        merged["codexSessions"] = copy.deepcopy(progress["codexSessions"])
        merged.pop("codexSession", None)
    elif "codexSession" in progress:
        merged["codexSession"] = copy.deepcopy(progress["codexSession"])

    return merged


def _plan_dir_mtime(plan_dir):
    """Get the most recent mtime across plan.json and progress.json."""
    plan_path = os.path.join(plan_dir, "plan.json")
    prog_path = os.path.join(plan_dir, "progress.json")
    mtime = 0
    if os.path.isfile(plan_path):
        mtime = os.path.getmtime(plan_path)
    if os.path.isfile(prog_path):
        mtime = max(mtime, os.path.getmtime(prog_path))
    return mtime


# ---------------------------------------------------------------------------
# Core read/write
# ---------------------------------------------------------------------------

def read_plan(plan_path):
    """Read plan.json and merge with progress.json if it exists.

    Returns the merged view — immutable definition + mutable progress.
    Legacy plans without progress.json return plan.json contents as-is.
    """
    with open(plan_path) as f:
        plan = json.load(f)
    progress = read_progress(plan_path)
    if progress:
        return merge_plan_progress(plan, progress)
    return plan


def read_plan_definition(plan_path):
    """Read only the immutable plan definition (plan.json)."""
    with open(plan_path) as f:
        return json.load(f)


def write_plan(plan_path, plan):
    """Write a plan dict to plan.json. Used for initial plan creation only.

    After approval, use mutation functions that write to progress.json.
    """
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


def active_steps(plan):
    """Return all currently in-progress steps."""
    return [
        step for step in plan.get("steps", [])
        if step.get("status") == "in_progress"
    ]


def runnable_steps(plan):
    """Return all pending steps whose dependencies are satisfied."""
    statuses = {
        step["id"]: step.get("status", "pending")
        for step in plan.get("steps", [])
    }

    runnable = []
    for step in plan.get("steps", []):
        if step.get("status", "pending") != "pending":
            continue
        depends_on = step.get("dependsOn") or []
        if all(statuses.get(dep_id) == "done" for dep_id in depends_on):
            runnable.append(step)
    return runnable


def get_next_step(plan):
    """Find the next step to work on.

    Backwards compatibility:
    - Prefer the first in-progress step when any are active
    - Otherwise return the first runnable pending step
    """
    active = active_steps(plan)
    if active:
        return active[0]

    runnable = runnable_steps(plan)
    if runnable:
        return runnable[0]

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


def _update_step_in_progress(plan_path, step_id, updater):
    """Helper: read progress, apply updater to a step's progress entry, write back.

    updater(step_prog) should mutate step_prog in place.
    Returns the progress dict after writing.
    """
    step_key = str(step_id)
    progress_path = progress_path_for(plan_path)

    def _mutate(progress):
        _seed_progress_if_needed(plan_path, progress)
        if step_key not in progress.get("steps", {}):
            progress.setdefault("steps", {})[step_key] = {"status": "pending"}
        updater(progress["steps"][step_key])

    return transactional_update(progress_path, _mutate)


def update_step_status(plan_path, step_id, new_status):
    """Update a step's status and write to progress.json.

    When setting to 'done', warns if progress items are incomplete and
    errors if the result field is empty. A step cannot be marked done
    without a result.
    """
    plan = read_plan(plan_path)
    step = get_step(plan, step_id)
    if step is None:
        print(f"Error: step {step_id} not found", file=sys.stderr)
        return False

    # Validate mode and skill values (from immutable definition)
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
        # Block update-step done for strict plans — use complete-step instead
        receipt_mode = plan.get("_receiptMode", "legacy")
        if receipt_mode == "strict":
            print(
                f"Error: step {step_id} is in a strict plan. Use "
                f"'complete-step' instead of 'update-step done' — "
                f"complete-step gates on verification receipts.",
                file=sys.stderr,
            )
            return False

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

        # Error on missing result
        result = step.get("result")
        missing_result = not result or (isinstance(result, str) and not result.strip())

        # Warn about progress items missing files field
        for i, p in enumerate(step.get("progress", [])):
            if "files" not in p:
                print(
                    f"Warning: progress item {i} of step {step_id} has no "
                    f"files field — resumption after compaction will be degraded",
                    file=sys.stderr,
                )

        if missing_result:
            print(
                f"Error: step {step_id} cannot be marked done with no result. "
                f"Fill in the result field describing what was implemented.",
                file=sys.stderr,
            )
            sys.exit(1)

    _update_step_in_progress(
        plan_path, step_id, lambda sp: sp.__setitem__("status", new_status)
    )
    return True


def complete_step(plan_path, step_id, result_text, project_root=None):
    """Mark a step as done with receipt verification for strict plans.

    For strict plans (_receiptMode == "strict"), this command gates on
    the appropriate verification receipt:
    - claude-impl steps: require codex_verify receipt
    - codex-impl steps: require codex_impl + claude_verify receipts

    For legacy plans, falls through to update_step_status directly.
    Writes result and status to progress.json.
    """
    plan = read_plan(plan_path)
    step = get_step(plan, step_id)
    if step is None:
        print(f"Error: step {step_id} not found", file=sys.stderr)
        return False

    # Save result to progress immediately (even if gating fails)
    _update_step_in_progress(
        plan_path, step_id, lambda sp: sp.__setitem__("result", result_text)
    )

    # Check plan mode (from immutable definition)
    plan_def = read_plan_definition(plan_path)
    receipt_mode = plan_def.get("_receiptMode", "legacy")

    if receipt_mode == "strict" and not project_root:
        print(
            f"Error: step {step_id} is in a strict plan. "
            f"project_root is required for receipt verification. "
            f"Usage: complete-step <plan.json> <step_id> <result> <project_root>",
            file=sys.stderr,
        )
        return False

    if receipt_mode == "strict" and project_root:
        # Import receipt utils
        script_dir = os.path.dirname(os.path.abspath(__file__))
        receipt_utils_dir = os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(script_dir))),
            "scripts",
        )
        sys.path.insert(0, receipt_utils_dir)
        try:
            import receipt_utils
        except ImportError:
            print(
                "Warning: receipt_utils.py not found, skipping receipt check",
                file=sys.stderr,
            )
            receipt_mode = "legacy"

        if receipt_mode == "strict":
            proj_id = receipt_utils.project_id(project_root)
            plan_name = plan_def.get("name", "unknown")
            owner = step.get("owner", "claude")
            mode = step.get("mode", "claude-impl")
            extra = {"step": step_id}

            if mode in ("claude-impl", "dual-pass") or owner == "claude":
                exists, path = receipt_utils.check(
                    "codex_verify", proj_id, plan_name, extra
                )
                if not exists:
                    print(
                        f"Error: step {step_id} requires codex_verify receipt "
                        f"but none found at {path}. Run run-codex-verify.sh "
                        f"and get PASS before completing.",
                        file=sys.stderr,
                    )
                    return False

            elif mode == "codex-impl" or owner == "codex":
                impl_exists, impl_path = receipt_utils.check(
                    "codex_impl", proj_id, plan_name, extra
                )
                verify_exists, verify_path = receipt_utils.check(
                    "claude_verify", proj_id, plan_name, extra
                )
                if not impl_exists:
                    print(
                        f"Error: step {step_id} requires codex_impl receipt "
                        f"but none found. Run run-codex-implement.sh first.",
                        file=sys.stderr,
                    )
                    return False
                if not verify_exists:
                    print(
                        f"Error: step {step_id} requires claude_verify receipt "
                        f"but none found. Verify the step independently first.",
                        file=sys.stderr,
                    )
                    return False

    # All checks passed — mark done in progress.json
    _update_step_in_progress(
        plan_path, step_id, lambda sp: sp.__setitem__("status", "done")
    )
    return True


def update_progress_item(plan_path, step_id, progress_index, new_status):
    """Update a progress item's status within a step. Writes to progress.json."""
    plan = read_plan(plan_path)
    step = get_step(plan, step_id)
    if step is None:
        print(f"Error: step {step_id} not found", file=sys.stderr)
        return False
    progress_items = step.get("progress", [])
    if progress_index < 0 or progress_index >= len(progress_items):
        print(f"Error: progress index {progress_index} out of range", file=sys.stderr)
        return False
    item = progress_items[progress_index]
    if "files" not in item:
        print(
            f"Warning: progress item {progress_index} of step {step_id} has no "
            f"files field — resumption after compaction will be degraded",
            file=sys.stderr,
        )

    def _update(sp):
        sp.setdefault("progress", [])
        # Extend progress list if needed
        while len(sp["progress"]) <= progress_index:
            sp["progress"].append({"status": "pending"})
        sp["progress"][progress_index]["status"] = new_status

    _update_step_in_progress(plan_path, step_id, _update)
    return True


def set_result(plan_path, step_id, result_text):
    """Set the result field on a step. Writes to progress.json."""
    plan = read_plan(plan_path)
    step = get_step(plan, step_id)
    if step is None:
        print(f"Error: step {step_id} not found", file=sys.stderr)
        return False
    _update_step_in_progress(
        plan_path, step_id, lambda sp: sp.__setitem__("result", result_text)
    )
    return True


def add_summary(plan_path, text):
    """Append to the completedSummary array. Writes to progress.json."""
    def _mutate(progress):
        _seed_progress_if_needed(plan_path, progress)
        progress.setdefault("completedSummary", []).append(text)

    transactional_update(progress_path_for(plan_path), _mutate)
    return True


def add_deviation(plan_path, text):
    """Append to the deviations array. Writes to progress.json."""
    def _mutate(progress):
        _seed_progress_if_needed(plan_path, progress)
        progress.setdefault("deviations", []).append(text)

    transactional_update(progress_path_for(plan_path), _mutate)
    return True


def _resolve_codex_session_step_id(plan, step_id=None):
    """Resolve the step ID for step-scoped codex session storage."""
    if step_id is not None:
        try:
            resolved_step_id = int(step_id)
        except (TypeError, ValueError):
            return None
        step = get_step(plan, resolved_step_id)
        return str(step["id"]) if step else None

    current = active_step(plan)
    if current is not None:
        return str(current["id"])

    next_step = get_next_step(plan)
    if next_step is not None:
        return str(next_step["id"])

    return None


def _ensure_codex_sessions(progress, plan_path):
    """Normalize codex session storage to the step-keyed codexSessions map."""
    existing_sessions = progress.get("codexSessions")
    if isinstance(existing_sessions, dict):
        progress.pop("codexSession", None)
        return existing_sessions

    sessions = {}
    legacy_session = progress.pop("codexSession", None)
    if isinstance(legacy_session, dict):
        plan = merge_plan_progress(read_plan_definition(plan_path), progress)
        target_step_id = _resolve_codex_session_step_id(plan)
        if target_step_id is not None:
            sessions[target_step_id] = legacy_session

    progress["codexSessions"] = sessions
    return sessions


def update_codex_session(plan_path, thread_id, phase, step_id=None):
    """Set or update the per-step codexSessions entry in progress.json."""
    from datetime import datetime, timezone

    plan = read_plan(plan_path)
    target_step_id = _resolve_codex_session_step_id(plan, step_id)
    if target_step_id is None:
        print(
            "Error: could not resolve step for codex session update",
            file=sys.stderr,
        )
        return False

    def _mutate(progress):
        _seed_progress_if_needed(plan_path, progress)
        sessions = _ensure_codex_sessions(progress, plan_path)
        session = sessions.get(target_step_id)
        if not isinstance(session, dict):
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
            session["interactionCount"] = (
                (prev_count if isinstance(prev_count, int) else 0) + 1
            )
            session["lastInteraction"] = datetime.now(timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            )
        sessions[target_step_id] = session

    transactional_update(progress_path_for(plan_path), _mutate)
    return True


def get_codex_session(plan_path, step_id=None):
    """Read and return the per-step codex session object.

    On first access, legacy singleton codexSession data is migrated to the
    step-keyed codexSessions map using the current in-progress step, falling
    back to the next runnable step for sequential-plan compatibility.
    """
    plan = read_plan(plan_path)
    target_step_id = _resolve_codex_session_step_id(plan, step_id)
    if target_step_id is None:
        return None

    result = {"session": None}

    def _mutate(progress):
        _seed_progress_if_needed(plan_path, progress)
        sessions = _ensure_codex_sessions(progress, plan_path)
        result["session"] = sessions.get(target_step_id)

    transactional_update(progress_path_for(plan_path), _mutate)
    return result["session"]


def clear_codex_session(plan_path):
    """Remove all stored codexSessions from progress.json."""
    def _mutate(progress):
        _seed_progress_if_needed(plan_path, progress)
        progress["codexSessions"] = {}
        progress.pop("codexSession", None)

    transactional_update(progress_path_for(plan_path), _mutate)
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
    """Find the most recently modified plan in active plans.

    Uses max(plan.json, progress.json) mtime to find the latest plan,
    since active plans update progress.json (not plan.json).

    Returns the plan.json path, or None if no active plan.
    """
    active_dir = os.path.join(project_root, ".temp", "plan-mode", "active")
    if not os.path.isdir(active_dir):
        return None

    latest_path = None
    latest_mtime = 0

    for entry in os.listdir(active_dir):
        plan_dir = os.path.join(active_dir, entry)
        plan_path = os.path.join(plan_dir, "plan.json")
        if os.path.isfile(plan_path):
            mtime = _plan_dir_mtime(plan_dir)
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

    Uses max(plan.json, progress.json) mtime for sorting.
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
            mtime = _plan_dir_mtime(plan_dir)
            unclaimed.append((entry, plan_path, mtime))
            continue

        try:
            with open(lock_file) as f:
                lock_pid = f.read().strip()
        except OSError:
            mtime = _plan_dir_mtime(plan_dir)
            unclaimed.append((entry, plan_path, mtime))
            continue

        if not lock_pid or not _is_pid_alive(lock_pid):
            mtime = _plan_dir_mtime(plan_dir)
            unclaimed.append((entry, plan_path, mtime))

    # Sort by mtime descending (most recent first)
    unclaimed.sort(key=lambda x: x[2], reverse=True)
    return [(name, path) for name, path, _ in unclaimed]


def active_step(plan):
    """Find the currently active step (in_progress).

    Returns the step dict, or None if no step is in progress.
    """
    active = active_steps(plan)
    return active[0] if active else None


def effective_owner(step, group_index=None):
    """Get the effective owner of a step or group within a step.

    For collab-split steps with sub-plan groups, the effective owner
    is group.owner if set, falling back to step.owner.

    Args:
        step: Step dict from plan.json
        group_index: Optional 0-based group index for collab-split steps

    Returns:
        Owner string ("claude" or "codex")
    """
    step_owner = step.get("owner", "claude")

    if group_index is not None:
        sub_plan = step.get("subPlan")
        if sub_plan and "groups" in sub_plan:
            groups = sub_plan["groups"]
            if 0 <= group_index < len(groups):
                return groups[group_index].get("owner", step_owner)

    return step_owner


def step_files(step, group_index=None):
    """Get the list of files for a step or group.

    For collab-split steps with groups, returns the group's files
    if group_index is specified.

    Args:
        step: Step dict from plan.json
        group_index: Optional 0-based group index

    Returns:
        List of file paths (relative to project root)
    """
    if group_index is not None:
        sub_plan = step.get("subPlan")
        if sub_plan and "groups" in sub_plan:
            groups = sub_plan["groups"]
            if 0 <= group_index < len(groups):
                return groups[group_index].get("files", [])

    return step.get("files", [])


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


def cli_active_steps(plan_path):
    """Print all active steps."""
    plan = read_plan(plan_path)
    print(json.dumps([
        {
            "id": step["id"],
            "title": step["title"],
            "status": step["status"],
            "owner": step.get("owner", "claude"),
            "mode": step.get("mode", "claude-impl"),
            "files": step.get("files", []),
        }
        for step in active_steps(plan)
    ]))


def cli_runnable_steps(plan_path):
    """Print all runnable pending steps."""
    plan = read_plan(plan_path)
    print(json.dumps([
        {
            "id": step["id"],
            "title": step["title"],
            "status": step["status"],
            "description": step.get("description", ""),
        }
        for step in runnable_steps(plan)
    ]))


def print_help():
    """Print usage information with all available commands."""
    print("""Usage: plan_utils.py <command> <plan.json|project_root> [args...]

Plan state commands (reads plan.json + progress.json merged view):
  status <plan.json>                              Show plan status summary
  next-step <plan.json>                           Show next step to work on
  active-steps <plan.json>                        Show all in-progress steps
  runnable-steps <plan.json>                      Show runnable pending steps
  is-fresh <plan.json>                            Check if plan is untouched
  is-complete <plan.json>                         Check if all steps are done

Plan update commands (writes to progress.json):
  update-step <plan.json> <step_id> <status>      Update step status
  complete-step <plan.json> <step_id> <result> [project_root]  Mark step done with receipt gate
  update-progress <plan.json> <step_id> <idx> <s> Update progress item status
  set-result <plan.json> <step_id> <text>         Set step result text
  add-summary <plan.json> <text>                  Append to completedSummary
  add-deviation <plan.json> <text>                Append to deviations

Codex session commands (writes to progress.json):
  update-codex-session <plan.json> <threadId> <phase> [step_id]  Set/update codex session
  get-codex-session <plan.json> [step_id]              Read codex session state
  clear-codex-session <plan.json>                      Remove codex session

Step introspection commands:
  active-step <plan.json>                         Show the in-progress step
  effective-owner <plan.json> <step_id> [group]   Get effective owner of step/group
  step-files <plan.json> <step_id> [group]        List files for step/group

Progress commands:
  init-progress <plan.json>                       Create fresh progress.json for new plan
  migrate-progress <plan.json>                    Extract mutable state from plan.json → progress.json

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

    elif command == "active-steps":
        cli_active_steps(plan_path)

    elif command == "runnable-steps":
        cli_runnable_steps(plan_path)

    elif command == "update-step":
        if len(sys.argv) < 5:
            print("Usage: plan-utils.py update-step <plan.json> <step_id> <status>", file=sys.stderr)
            sys.exit(1)
        step_id = int(sys.argv[3])
        new_status = sys.argv[4]
        if not update_step_status(plan_path, step_id, new_status):
            sys.exit(1)

    elif command == "complete-step":
        if len(sys.argv) < 5:
            print(
                "Usage: plan-utils.py complete-step <plan.json> <step_id> "
                "<result_text> [project_root]",
                file=sys.stderr,
            )
            sys.exit(1)
        step_id = int(sys.argv[3])
        result_text = sys.argv[4]
        project_root = sys.argv[5] if len(sys.argv) > 5 else None
        if not complete_step(plan_path, step_id, result_text, project_root):
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
            print(
                "Usage: plan-utils.py update-codex-session <plan.json> "
                "<threadId> <phase> [step_id]",
                file=sys.stderr,
            )
            sys.exit(1)
        thread_id = sys.argv[3]
        phase = sys.argv[4]
        step_id = sys.argv[5] if len(sys.argv) > 5 else None
        if not update_codex_session(plan_path, thread_id, phase, step_id):
            sys.exit(1)

    elif command == "get-codex-session":
        step_id = sys.argv[3] if len(sys.argv) > 3 else None
        session = get_codex_session(plan_path, step_id)
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

    elif command == "active-step":
        plan = read_plan(plan_path)
        step = active_step(plan)
        if step:
            print(json.dumps({
                "id": step["id"],
                "title": step["title"],
                "owner": step.get("owner", "claude"),
                "mode": step.get("mode", "claude-impl"),
                "files": step.get("files", []),
            }))
        else:
            print(json.dumps(None))

    elif command == "effective-owner":
        if len(sys.argv) < 4:
            print("Usage: plan-utils.py effective-owner <plan.json> <step_id> [group_index]",
                  file=sys.stderr)
            sys.exit(1)
        step_id = int(sys.argv[3])
        group_idx = int(sys.argv[4]) if len(sys.argv) > 4 else None
        plan = read_plan(plan_path)
        step = get_step(plan, step_id)
        if step is None:
            print(f"Error: step {step_id} not found", file=sys.stderr)
            sys.exit(1)
        print(effective_owner(step, group_idx))

    elif command == "step-files":
        if len(sys.argv) < 4:
            print("Usage: plan-utils.py step-files <plan.json> <step_id> [group_index]",
                  file=sys.stderr)
            sys.exit(1)
        step_id = int(sys.argv[3])
        group_idx = int(sys.argv[4]) if len(sys.argv) > 4 else None
        plan = read_plan(plan_path)
        step = get_step(plan, step_id)
        if step is None:
            print(f"Error: step {step_id} not found", file=sys.stderr)
            sys.exit(1)
        files = step_files(step, group_idx)
        for f in files:
            print(f)

    elif command == "init-progress":
        plan_def = read_plan_definition(plan_path)
        prog = init_progress(plan_def)
        write_progress(plan_path, prog)
        print(json.dumps({"created": progress_path_for(plan_path)}))

    elif command == "migrate-progress":
        prog = _ensure_progress(plan_path)
        write_progress(plan_path, prog)
        print(json.dumps({"migrated": progress_path_for(plan_path)}))

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
