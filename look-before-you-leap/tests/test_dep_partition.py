#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "dep_partition.py"

spec = importlib.util.spec_from_file_location("dep_partition", SCRIPT_PATH)
assert spec and spec.loader
dep_partition = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dep_partition)


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_config(root: Path, config: dict) -> None:
    """Write a .claude/look-before-you-leap.local.md with YAML frontmatter."""
    lines = ["---"]
    for key, val in config.items():
        if isinstance(val, dict):
            lines.append(f"{key}:")
            for k, v in val.items():
                if isinstance(v, list):
                    lines.append(f"  {k}:")
                    for item in v:
                        lines.append(f"    - {item}")
                else:
                    lines.append(f"  {k}: {v}")
        else:
            lines.append(f"{key}: {val}")
    lines.append("---")
    lines.append("")
    config_path = root / ".claude" / "look-before-you-leap.local.md"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text("\n".join(lines), encoding="utf-8")


class DepPartitionTests(unittest.TestCase):
    def test_isolated_targets_are_split_into_parallel_groups(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            write_config(root, {"dep_maps": {"dir": ".claude/deps", "modules": ["apps/web", "apps/api"]}})
            write_json(
                root / ".claude" / "deps" / "deps-apps-web.json",
                {"apps/web/a.ts": ["apps/web/local.ts"]},
            )
            write_json(
                root / ".claude" / "deps" / "deps-apps-api.json",
                {"apps/api/b.ts": ["apps/api/lib.ts"]},
            )

            with patch.object(dep_partition, "read_config", return_value={
                "dep_maps": {"dir": ".claude/deps", "modules": ["apps/web", "apps/api"]}
            }):
                result = dep_partition.build_partition(str(root), ["apps/web/a.ts", "apps/api/b.ts"])

            self.assertEqual(len(result["groups"]), 2)
            self.assertTrue(all(group["safeParallel"] for group in result["groups"]))
            self.assertEqual(result["sharedBoundaries"], [])

    def test_shared_dependency_merges_targets_into_one_group(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            write_config(root, {"dep_maps": {"dir": ".claude/deps", "modules": ["apps/mobile"]}})
            write_json(
                root / ".claude" / "deps" / "deps-apps-mobile.json",
                {
                    "apps/mobile/a.ts": ["packages/shared/colors.ts"],
                    "apps/mobile/b.ts": ["packages/shared/colors.ts"],
                },
            )

            with patch.object(dep_partition, "read_config", return_value={
                "dep_maps": {"dir": ".claude/deps", "modules": ["apps/mobile"]}
            }):
                result = dep_partition.build_partition(str(root), ["apps/mobile/a.ts", "apps/mobile/b.ts"])

            self.assertEqual(len(result["groups"]), 1)
            self.assertEqual(
                result["groups"][0]["targets"],
                ["apps/mobile/a.ts", "apps/mobile/b.ts"],
            )
            reasons = {link["reason"] for link in result["directLinks"]}
            self.assertIn("shared_dependency", reasons)

    def test_cross_module_dependents_raise_boundary_group_first(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            write_config(root, {
                "dep_maps": {
                    "dir": ".claude/deps",
                    "modules": ["packages/shared", "apps/web", "apps/mobile"],
                }
            })
            write_json(
                root / ".claude" / "deps" / "deps-packages-shared.json",
                {
                    "packages/shared/theme.ts": [],
                    "apps/web/home.tsx": ["packages/shared/theme.ts"],
                    "apps/mobile/home.tsx": ["packages/shared/theme.ts"],
                },
            )
            write_json(root / ".claude" / "deps" / "deps-apps-web.json", {})
            write_json(root / ".claude" / "deps" / "deps-apps-mobile.json", {})

            with patch.object(dep_partition, "read_config", return_value={
                "dep_maps": {
                    "dir": ".claude/deps",
                    "modules": ["packages/shared", "apps/web", "apps/mobile"],
                }
            }):
                result = dep_partition.build_partition(str(root), ["packages/shared/theme.ts"])

            group = result["groups"][0]
            self.assertEqual(group["parallelHint"], "cross_module_boundary")
            self.assertFalse(group["safeParallel"])
            self.assertEqual(group["suggestedOrder"], 1)

    def test_missing_config_returns_isolated_groups(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            # No config file, no dep maps — targets still appear but as isolated groups
            with patch.object(dep_partition, "read_config", return_value={}):
                result = dep_partition.build_partition(str(root), ["src/foo.ts"])

            self.assertEqual(len(result["groups"]), 1)
            self.assertEqual(result["groups"][0]["targets"], ["src/foo.ts"])
            self.assertEqual(result["groups"][0]["parallelHint"], "isolated")
            self.assertTrue(result["groups"][0]["safeParallel"])
            self.assertEqual(result["sharedBoundaries"], [])
            self.assertEqual(result["directLinks"], [])


if __name__ == "__main__":
    unittest.main()
