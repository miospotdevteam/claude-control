#!/usr/bin/env python3

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PLUGIN_ROOT = Path(__file__).resolve().parents[1]
PLAN_UTILS = PLUGIN_ROOT / "skills" / "look-before-you-leap" / "scripts" / "plan_utils.py"

STRUCTURED_RESULT = """### Criterion: "criterion one"
- updated file
- ran verification

### Verdict
Codex: PASS"""


def make_plan(*, result=None, progress=None):
    step = {
        "id": 1,
        "title": "Regression target",
        "status": "in_progress",
        "owner": "claude",
        "mode": "claude-impl",
        "skill": "none",
        "codexVerify": True,
        "acceptanceCriteria": "1. first criterion. 2. second criterion.",
        "files": ["look-before-you-leap/tests/test_plan_utils.py"],
        "progress": progress if progress is not None else [],
    }
    if result is not None:
        step["result"] = result

    return {
        "name": "fixture",
        "title": "Fixture Plan",
        "status": "active",
        "steps": [step],
    }


class PlanUtilsCliTests(unittest.TestCase):
    def write_plan(self, temp_dir, plan):
        plan_path = Path(temp_dir) / "plan.json"
        plan_path.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
        return plan_path

    def read_plan(self, plan_path):
        return json.loads(plan_path.read_text(encoding="utf-8"))

    def run_cli(self, *args):
        return subprocess.run(
            [sys.executable, str(PLAN_UTILS), *args],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_marking_done_without_result_exits_nonzero(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            plan_path = self.write_plan(temp_dir, make_plan())

            completed = self.run_cli("update-step", str(plan_path), "1", "done")

            self.assertEqual(completed.returncode, 1)
            self.assertIn("cannot be marked done with no result", completed.stderr)
            self.assertEqual(
                self.read_plan(plan_path)["steps"][0]["status"],
                "in_progress",
            )

    def test_marking_done_with_valid_structured_result_exits_zero(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            plan_path = self.write_plan(
                temp_dir,
                make_plan(progress=[{"task": "Complete work", "status": "done", "files": []}]),
            )

            set_result = self.run_cli("set-result", str(plan_path), "1", STRUCTURED_RESULT)
            completed = self.run_cli("update-step", str(plan_path), "1", "done")

            self.assertEqual(set_result.returncode, 0)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            plan = self.read_plan(plan_path)
            self.assertEqual(plan["steps"][0]["status"], "done")
            self.assertEqual(plan["steps"][0]["result"], STRUCTURED_RESULT)

    def test_marking_done_with_empty_string_result_exits_nonzero(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            plan_path = self.write_plan(temp_dir, make_plan(result=""))

            completed = self.run_cli("update-step", str(plan_path), "1", "done")

            self.assertEqual(completed.returncode, 1)
            self.assertIn("cannot be marked done with no result", completed.stderr)
            self.assertEqual(
                self.read_plan(plan_path)["steps"][0]["status"],
                "in_progress",
            )

    def test_existing_warnings_still_fire(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            plan_path = self.write_plan(
                temp_dir,
                make_plan(
                    result=STRUCTURED_RESULT,
                    progress=[
                        {"task": "Missing files metadata", "status": "pending"},
                        {"task": "Done item", "status": "done", "files": []},
                    ],
                ),
            )

            completed = self.run_cli("update-step", str(plan_path), "1", "done")

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("incomplete progress item(s)", completed.stderr)
            self.assertIn("has no files field", completed.stderr)
            self.assertEqual(self.read_plan(plan_path)["steps"][0]["status"], "done")


if __name__ == "__main__":
    unittest.main()
