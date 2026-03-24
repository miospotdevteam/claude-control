#!/usr/bin/env python3
"""Tests for receipt_utils.py — HMAC signing, verification, state management."""

import json
import os
import shutil
import sys
import tempfile
import unittest

# Add scripts dir to path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPTS_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), "scripts")
sys.path.insert(0, SCRIPTS_DIR)

import receipt_utils


class TestBootstrap(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self._orig_state = receipt_utils.STATE_ROOT
        self._orig_secret = receipt_utils.SECRET_PATH
        receipt_utils.STATE_ROOT = os.path.join(self.tmpdir, "state")
        receipt_utils.SECRET_PATH = os.path.join(
            receipt_utils.STATE_ROOT, "secret.key"
        )

    def tearDown(self):
        receipt_utils.STATE_ROOT = self._orig_state
        receipt_utils.SECRET_PATH = self._orig_secret
        shutil.rmtree(self.tmpdir)

    def test_bootstrap_creates_state_root(self):
        root = receipt_utils.bootstrap()
        self.assertTrue(os.path.isdir(root))

    def test_bootstrap_creates_secret(self):
        receipt_utils.bootstrap()
        self.assertTrue(os.path.exists(receipt_utils.SECRET_PATH))
        # Check permissions (0600)
        mode = os.stat(receipt_utils.SECRET_PATH).st_mode & 0o777
        self.assertEqual(mode, 0o600)

    def test_bootstrap_secret_is_32_bytes(self):
        receipt_utils.bootstrap()
        with open(receipt_utils.SECRET_PATH, "rb") as f:
            key = f.read()
        self.assertEqual(len(key), 32)

    def test_bootstrap_idempotent(self):
        receipt_utils.bootstrap()
        with open(receipt_utils.SECRET_PATH, "rb") as f:
            key1 = f.read()
        receipt_utils.bootstrap()
        with open(receipt_utils.SECRET_PATH, "rb") as f:
            key2 = f.read()
        self.assertEqual(key1, key2, "Secret should not change on re-bootstrap")


class TestProjectId(unittest.TestCase):
    def test_stable_project_id(self):
        id1 = receipt_utils.project_id("/tmp/myproject")
        id2 = receipt_utils.project_id("/tmp/myproject")
        self.assertEqual(id1, id2)

    def test_different_projects_different_ids(self):
        id1 = receipt_utils.project_id("/tmp/project-a")
        id2 = receipt_utils.project_id("/tmp/project-b")
        self.assertNotEqual(id1, id2)

    def test_id_is_16_hex_chars(self):
        pid = receipt_utils.project_id("/tmp/test")
        self.assertEqual(len(pid), 16)
        int(pid, 16)  # Should not raise


class TestSignAndVerify(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self._orig_state = receipt_utils.STATE_ROOT
        self._orig_secret = receipt_utils.SECRET_PATH
        receipt_utils.STATE_ROOT = os.path.join(self.tmpdir, "state")
        receipt_utils.SECRET_PATH = os.path.join(
            receipt_utils.STATE_ROOT, "secret.key"
        )
        receipt_utils.bootstrap()

    def tearDown(self):
        receipt_utils.STATE_ROOT = self._orig_state
        receipt_utils.SECRET_PATH = self._orig_secret
        shutil.rmtree(self.tmpdir)

    def test_sign_creates_receipt(self):
        path = receipt_utils.sign("bypass", "proj1", "plan1")
        self.assertTrue(os.path.exists(path))

    def test_verify_valid_receipt(self):
        path = receipt_utils.sign("bypass", "proj1", "plan1")
        valid, receipt = receipt_utils.verify(path)
        self.assertTrue(valid)
        self.assertEqual(receipt["type"], "bypass")
        self.assertEqual(receipt["projectId"], "proj1")

    def test_tampering_fails_verification(self):
        path = receipt_utils.sign("bypass", "proj1", "plan1")
        # Tamper with the receipt
        with open(path) as f:
            receipt = json.load(f)
        receipt["type"] = "codex_verify"
        with open(path, "w") as f:
            json.dump(receipt, f)
        valid, _ = receipt_utils.verify(path)
        self.assertFalse(valid, "Tampered receipt should fail verification")

    def test_sign_with_extra(self):
        path = receipt_utils.sign(
            "codex_verify", "proj1", "plan1", {"step": 3}
        )
        self.assertIn("step-3", path)
        valid, receipt = receipt_utils.verify(path)
        self.assertTrue(valid)
        self.assertEqual(receipt["data"]["step"], 3)

    def test_check_exists(self):
        receipt_utils.sign("bypass", "proj1", "plan1")
        exists, _ = receipt_utils.check("bypass", "proj1", "plan1")
        self.assertTrue(exists)

    def test_check_missing(self):
        exists, _ = receipt_utils.check("bypass", "proj1", "plan1")
        self.assertFalse(exists)

    def test_check_wrong_type(self):
        receipt_utils.sign("bypass", "proj1", "plan1")
        exists, _ = receipt_utils.check("codex_verify", "proj1", "plan1")
        self.assertFalse(exists)

    def test_cross_project_replay_rejected(self):
        """A receipt signed for proj1 must not pass check for proj2."""
        receipt_utils.sign("bypass", "proj1", "plan1")
        # Copy receipt to proj2's path
        src = os.path.join(
            receipt_utils.STATE_ROOT, "proj1", "plan1", "bypass-default.json"
        )
        dst_dir = os.path.join(receipt_utils.STATE_ROOT, "proj2", "plan1")
        os.makedirs(dst_dir, exist_ok=True)
        import shutil
        shutil.copy(src, os.path.join(dst_dir, "bypass-default.json"))
        # Check should fail — projectId mismatch
        exists, _ = receipt_utils.check("bypass", "proj2", "plan1")
        self.assertFalse(exists, "Cross-project replay should be rejected")

    def test_cross_plan_replay_rejected(self):
        """A receipt signed for plan1 must not pass check for plan2."""
        receipt_utils.sign("bypass", "proj1", "plan1")
        src = os.path.join(
            receipt_utils.STATE_ROOT, "proj1", "plan1", "bypass-default.json"
        )
        dst_dir = os.path.join(receipt_utils.STATE_ROOT, "proj1", "plan2")
        os.makedirs(dst_dir, exist_ok=True)
        import shutil
        shutil.copy(src, os.path.join(dst_dir, "bypass-default.json"))
        exists, _ = receipt_utils.check("bypass", "proj1", "plan2")
        self.assertFalse(exists, "Cross-plan replay should be rejected")

    def test_sign_with_step_and_group(self):
        path = receipt_utils.sign(
            "codex_verify", "proj1", "plan1",
            {"step": 2, "group": 1}
        )
        self.assertIn("step-2-group-1", path)
        valid, _ = receipt_utils.verify(path)
        self.assertTrue(valid)


class TestClassifyPlan(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def test_legacy_plan(self):
        plan_path = os.path.join(self.tmpdir, "plan.json")
        with open(plan_path, "w") as f:
            json.dump({"name": "test", "steps": []}, f)
        self.assertEqual(receipt_utils.classify_plan(plan_path), "legacy")

    def test_strict_plan(self):
        plan_path = os.path.join(self.tmpdir, "plan.json")
        with open(plan_path, "w") as f:
            json.dump({
                "name": "test",
                "steps": [],
                "_receiptMode": "strict"
            }, f)
        self.assertEqual(receipt_utils.classify_plan(plan_path), "strict")

    def test_missing_plan(self):
        self.assertEqual(
            receipt_utils.classify_plan("/nonexistent/plan.json"),
            "legacy"
        )


if __name__ == "__main__":
    unittest.main()
