#!/usr/bin/env python3
"""
Receipt utilities for look-before-you-leap enforcement.

Provides HMAC-signed receipts stored outside the repo at
~/.claude/look-before-you-leap/state/<projectId>/. Receipts are
tamper-evident: modifying any field invalidates the signature.

State layout:
    ~/.claude/look-before-you-leap/state/
        secret.key              # 32-byte random key, 0600 permissions
        <projectId>/
            <planId>/
                <receipt-type>-<detail>.json

Receipt types:
    bypass          — user-approved enforcement bypass (via /bypass command)
    handoff_approved — user approved plan via Orbit
    codex_verify    — Codex verification passed for a step
    codex_impl      — Codex implementation completed for a step
    claude_verify   — Claude verification of a codex-impl step
    discovery       — co-exploration completed
    destructive_confirm — user approved destructive operation
    cross_root_confirm  — user approved cross-project mutation

CLI usage:
    python3 receipt_utils.py bootstrap
    python3 receipt_utils.py sign <type> <projectId> <planId> [key=value ...]
    python3 receipt_utils.py verify <receipt_path>
    python3 receipt_utils.py check <type> <projectId> <planId> [key=value ...]
    python3 receipt_utils.py classify <plan_json_path>
    python3 receipt_utils.py state-root
    python3 receipt_utils.py project-id <project_root>
"""

import hashlib
import hmac
import json
import os
import secrets
import sys
import time


STATE_ROOT = os.path.expanduser("~/.claude/look-before-you-leap/state")
SECRET_PATH = os.path.join(STATE_ROOT, "secret.key")


def bootstrap():
    """Create state root and generate secret if missing."""
    os.makedirs(STATE_ROOT, mode=0o700, exist_ok=True)
    if not os.path.exists(SECRET_PATH):
        key = secrets.token_bytes(32)
        fd = os.open(SECRET_PATH, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            os.write(fd, key)
        finally:
            os.close(fd)
    else:
        # Ensure permissions are correct
        os.chmod(SECRET_PATH, 0o600)
    return STATE_ROOT


def _read_secret():
    """Read the HMAC secret key."""
    if not os.path.exists(SECRET_PATH):
        raise FileNotFoundError(
            f"Secret key not found at {SECRET_PATH}. Run 'bootstrap' first."
        )
    with open(SECRET_PATH, "rb") as f:
        return f.read()


def project_id(project_root):
    """Compute a stable project identifier from the project root path.

    Uses SHA-256 of the canonical path, truncated to 16 hex chars.
    This is deterministic: same path always produces the same ID.
    """
    canonical = os.path.realpath(project_root)
    return hashlib.sha256(canonical.encode()).hexdigest()[:16]


def plan_id(plan_name):
    """Return a stable plan identifier. Uses the plan name directly
    (kebab-case, already unique within a project)."""
    return plan_name


def _receipt_dir(proj_id, p_id):
    """Get the receipt directory for a project+plan."""
    return os.path.join(STATE_ROOT, proj_id, p_id)


def _compute_signature(payload, secret):
    """Compute HMAC-SHA256 signature over the canonical payload."""
    # Sort keys for deterministic serialization
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hmac.new(secret, canonical.encode(), hashlib.sha256).hexdigest()


def sign(receipt_type, proj_id, p_id, extra=None):
    """Create and store a signed receipt. Returns the receipt path."""
    secret = _read_secret()

    payload = {
        "type": receipt_type,
        "projectId": proj_id,
        "planId": p_id,
        "timestamp": time.time(),
    }
    if extra:
        payload["data"] = extra

    signature = _compute_signature(payload, secret)
    receipt = {**payload, "signature": signature}

    # Determine filename
    detail_parts = []
    if extra:
        if "step" in extra:
            detail_parts.append(f"step-{extra['step']}")
        if "group" in extra:
            detail_parts.append(f"group-{extra['group']}")
    detail = "-".join(detail_parts) if detail_parts else "default"
    filename = f"{receipt_type}-{detail}.json"

    receipt_dir = _receipt_dir(proj_id, p_id)
    os.makedirs(receipt_dir, mode=0o700, exist_ok=True)

    receipt_path = os.path.join(receipt_dir, filename)
    with open(receipt_path, "w") as f:
        json.dump(receipt, f, indent=2)
        f.write("\n")

    return receipt_path


def verify(receipt_path):
    """Verify a receipt's signature. Returns (valid, receipt_dict)."""
    with open(receipt_path) as f:
        receipt = json.load(f)

    secret = _read_secret()

    # Extract signature and rebuild payload
    stored_sig = receipt.pop("signature", None)
    if stored_sig is None:
        return False, receipt

    expected_sig = _compute_signature(receipt, secret)
    valid = hmac.compare_digest(stored_sig, expected_sig)

    receipt["signature"] = stored_sig
    return valid, receipt


def check(receipt_type, proj_id, p_id, extra=None):
    """Check if a valid receipt exists for the given parameters.

    Returns (exists, receipt_path) where exists is True if a valid
    signed receipt of the given type exists.
    """
    detail_parts = []
    if extra:
        if "step" in extra:
            detail_parts.append(f"step-{extra['step']}")
        if "group" in extra:
            detail_parts.append(f"group-{extra['group']}")
    detail = "-".join(detail_parts) if detail_parts else "default"
    filename = f"{receipt_type}-{detail}.json"

    receipt_dir = _receipt_dir(proj_id, p_id)
    receipt_path = os.path.join(receipt_dir, filename)

    if not os.path.exists(receipt_path):
        return False, receipt_path

    try:
        valid, receipt = verify(receipt_path)
        if (valid
                and receipt.get("type") == receipt_type
                and receipt.get("projectId") == proj_id
                and receipt.get("planId") == p_id):
            return True, receipt_path
    except (json.JSONDecodeError, OSError):
        pass

    return False, receipt_path


def verify_bypass(receipt_path, caller_ppid):
    """Verify a bypass receipt with session-scoping and maxEdits consumption.

    Checks:
    1. HMAC signature validity
    2. data.session matches caller_ppid (session scope)
    3. data.session PID is alive (liveness)
    4. data.maxEdits consumption (if present)

    Returns (valid, receipt_dict, status) where status is one of:
        'valid'    - receipt is valid, session matches, PID alive
        'stale'    - session mismatch or PID dead (receipt auto-deleted)
        'consumed' - maxEdits exhausted (receipt auto-deleted)
        'invalid'  - HMAC signature invalid
    """
    try:
        valid, receipt = verify(receipt_path)
    except (json.JSONDecodeError, OSError):
        return False, {}, "invalid"

    if not valid:
        return False, receipt, "invalid"

    data = receipt.get("data", {})
    session_pid = data.get("session")

    # Session field is required — receipts without it are legacy/stale
    if session_pid is None:
        try:
            os.remove(receipt_path)
        except OSError:
            pass
        return False, receipt, "stale"

    # Parse session PID safely
    try:
        session_pid_int = int(session_pid)
    except (ValueError, TypeError):
        try:
            os.remove(receipt_path)
        except OSError:
            pass
        return False, receipt, "invalid"

    # Parse caller_ppid safely
    try:
        caller_pid_int = int(caller_ppid)
    except (ValueError, TypeError):
        return False, receipt, "invalid"

    # Session mismatch: receipt belongs to a different session
    if session_pid_int != caller_pid_int:
        try:
            os.remove(receipt_path)
        except OSError:
            pass
        return False, receipt, "stale"

    # PID liveness: check if the session that created this receipt is still alive
    try:
        os.kill(session_pid_int, 0)
    except (OSError, ProcessLookupError):
        try:
            os.remove(receipt_path)
        except OSError:
            pass
        return False, receipt, "stale"

    # maxEdits consumption
    max_edits = data.get("maxEdits")
    if max_edits is not None:
        try:
            max_edits = int(max_edits)
        except (ValueError, TypeError):
            try:
                os.remove(receipt_path)
            except OSError:
                pass
            return False, receipt, "invalid"
        if max_edits <= 0:
            try:
                os.remove(receipt_path)
            except OSError:
                pass
            return False, receipt, "consumed"
        remaining = max_edits - 1
        if remaining <= 0:
            # Last allowed edit — rewrite with maxEdits=0 so next call returns CONSUMED
            data["maxEdits"] = 0
            receipt["data"] = data
            secret = _read_secret()
            receipt.pop("signature", None)
            new_sig = _compute_signature(receipt, secret)
            receipt["signature"] = new_sig
            with open(receipt_path, "w") as f:
                json.dump(receipt, f, indent=2)
                f.write("\n")
        else:
            # Decrement and rewrite the receipt with a new signature
            data["maxEdits"] = remaining
            receipt["data"] = data
            secret = _read_secret()
            receipt.pop("signature", None)
            new_sig = _compute_signature(receipt, secret)
            receipt["signature"] = new_sig
            with open(receipt_path, "w") as f:
                json.dump(receipt, f, indent=2)
                f.write("\n")

    return True, receipt, "valid"


def classify_plan(plan_json_path):
    """Classify a plan as 'legacy' or 'strict'.

    Legacy plans: created before the receipt system existed (no receipt
    infrastructure was bootstrapped when the plan was created).
    Strict plans: created after receipt infrastructure exists.

    For now, plans are classified as 'strict' if a receipt state root
    exists and the plan has a `_receiptMode` field set to 'strict'.
    Plans without this field default to 'legacy' for backwards
    compatibility during the migration period.
    """
    try:
        with open(plan_json_path) as f:
            plan = json.load(f)
    except (OSError, json.JSONDecodeError):
        return "legacy"

    mode = plan.get("_receiptMode")
    if mode == "strict":
        return "strict"
    return "legacy"


def _parse_extra(args):
    """Parse key=value arguments into a dict."""
    extra = {}
    for arg in args:
        if "=" in arg:
            key, value = arg.split("=", 1)
            # Try to parse numeric values
            try:
                value = int(value)
            except ValueError:
                pass
            extra[key] = value
    return extra if extra else None


def main():
    if len(sys.argv) < 2:
        print("Usage: receipt_utils.py <command> [args...]", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "bootstrap":
        root = bootstrap()
        print(root)
        return

    if command == "state-root":
        print(STATE_ROOT)
        return

    if command == "project-id":
        if len(sys.argv) < 3:
            print("Usage: receipt_utils.py project-id <project_root>",
                  file=sys.stderr)
            sys.exit(1)
        print(project_id(sys.argv[2]))
        return

    if command == "sign":
        if len(sys.argv) < 5:
            print("Usage: receipt_utils.py sign <type> <projectId> <planId> "
                  "[key=value ...]", file=sys.stderr)
            sys.exit(1)
        rtype = sys.argv[2]
        proj = sys.argv[3]
        plan = sys.argv[4]
        extra = _parse_extra(sys.argv[5:])
        path = sign(rtype, proj, plan, extra)
        print(path)
        return

    if command == "verify":
        if len(sys.argv) < 3:
            print("Usage: receipt_utils.py verify <receipt_path>",
                  file=sys.stderr)
            sys.exit(1)
        valid, receipt = verify(sys.argv[2])
        if valid:
            print("VALID")
            print(json.dumps(receipt, indent=2))
        else:
            print("INVALID")
            sys.exit(1)
        return

    if command == "check":
        if len(sys.argv) < 5:
            print("Usage: receipt_utils.py check <type> <projectId> <planId> "
                  "[key=value ...]", file=sys.stderr)
            sys.exit(1)
        rtype = sys.argv[2]
        proj = sys.argv[3]
        plan = sys.argv[4]
        extra = _parse_extra(sys.argv[5:])
        exists, path = check(rtype, proj, plan, extra)
        if exists:
            print(f"EXISTS {path}")
        else:
            print(f"MISSING {path}")
            sys.exit(1)
        return

    if command == "verify-bypass":
        if len(sys.argv) < 4:
            print("Usage: receipt_utils.py verify-bypass <receipt_path> "
                  "<caller_ppid>", file=sys.stderr)
            sys.exit(1)
        valid, receipt, status = verify_bypass(sys.argv[2], sys.argv[3])
        print(status.upper())
        if valid:
            sys.exit(0)
        else:
            sys.exit(1)
        return

    if command == "classify":
        if len(sys.argv) < 3:
            print("Usage: receipt_utils.py classify <plan_json_path>",
                  file=sys.stderr)
            sys.exit(1)
        classification = classify_plan(sys.argv[2])
        print(classification)
        return

    print(f"Unknown command: {command}", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
