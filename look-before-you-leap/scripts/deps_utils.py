#!/usr/bin/env python3
"""Shared utilities for dep-map scripts (deps-query, deps-generate, dep_partition).

Consolidates duplicated functions: read_config, module_slug, get_deps_dir,
get_stale_modules, load_all_dep_maps, query_file.

The query_file function standardizes on camelCase `foundIn` (not snake_case
`found_in`) for consistency with dep_partition.py's output.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from typing import Any


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
READ_CONFIG = os.path.join(SCRIPT_DIR, "..", "hooks", "lib", "read-config.py")


def read_config(project_root: str) -> dict[str, Any]:
    """Read project config via read-config.py (matches hook pattern)."""
    try:
        result = subprocess.run(
            [sys.executable, READ_CONFIG, project_root],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout)
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    return {}


def module_slug(module_path: str) -> str:
    """Convert module path to filename slug: apps/api -> apps-api"""
    return module_path.replace("/", "-")


def get_deps_dir(project_root: str, config: dict[str, Any]) -> str:
    """Resolve deps directory from config."""
    dep_maps = config.get("dep_maps", {})
    rel_dir = dep_maps.get("dir", ".claude/deps")
    return os.path.join(project_root, rel_dir)


def get_stale_modules(deps_dir: str) -> set[str]:
    """Read .stale marker file and return set of stale module slugs."""
    stale_file = os.path.join(deps_dir, ".stale")
    if not os.path.exists(stale_file):
        return set()
    try:
        with open(stale_file) as f:
            return {line.strip() for line in f if line.strip()}
    except (FileNotFoundError, PermissionError):
        return set()


def load_all_dep_maps(deps_dir: str) -> dict[str, dict[str, list[str]]]:
    """Load all deps-*.json files from deps_dir."""
    maps: dict[str, dict[str, list[str]]] = {}
    if not os.path.isdir(deps_dir):
        return maps
    for fname in os.listdir(deps_dir):
        if fname.startswith("deps-") and fname.endswith(".json"):
            fpath = os.path.join(deps_dir, fname)
            try:
                with open(fpath, encoding="utf-8") as f:
                    maps[fname] = json.load(f)
            except (FileNotFoundError, json.JSONDecodeError):
                pass
    return maps


def query_file(
    file_path: str,
    all_maps: dict[str, dict[str, list[str]]],
) -> dict[str, Any]:
    """Find dependencies and dependents for a file across all dep maps.

    Returns dict with camelCase key `foundIn` (standardized).
    """
    dependencies: list[str] = []
    dependents: list[str] = []
    found_in_module = None

    for map_name, dep_map in all_maps.items():
        if file_path in dep_map:
            found_in_module = map_name
            dependencies = dep_map[file_path]
        for source, deps in dep_map.items():
            if file_path in deps:
                dependents.append(source)

    return {
        "file": file_path,
        "foundIn": found_in_module,
        "dependencies": sorted(set(dependencies)),
        "dependents": sorted(set(dependents)),
    }
