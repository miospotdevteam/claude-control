#!/usr/bin/env python3
"""Partition target files into planning groups using dep maps.

Usage:
    python3 dep_partition.py <project_root> <file> [<file> ...]

Outputs machine-readable JSON describing:
- connected target groups
- cross-group shared boundaries
- direct target-to-target links
- suggested execution order based on exposure/risk
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from collections import defaultdict, deque
from typing import Any


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
READ_CONFIG = os.path.join(SCRIPT_DIR, "..", "hooks", "lib", "read-config.py")


def read_config(project_root: str) -> dict[str, Any]:
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


def load_all_dep_maps(deps_dir: str) -> dict[str, dict[str, list[str]]]:
    maps: dict[str, dict[str, list[str]]] = {}
    if not os.path.isdir(deps_dir):
        return maps
    for fname in os.listdir(deps_dir):
        if fname.startswith("deps-") and fname.endswith(".json"):
            fpath = os.path.join(deps_dir, fname)
            try:
                with open(fpath, encoding="utf-8") as handle:
                    maps[fname] = json.load(handle)
            except (FileNotFoundError, json.JSONDecodeError):
                pass
    return maps


def query_file(file_path: str, all_maps: dict[str, dict[str, list[str]]]) -> dict[str, Any]:
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


def normalize_target(project_root: str, raw_path: str) -> str:
    if os.path.isabs(raw_path):
        return os.path.relpath(raw_path, project_root)
    return raw_path


def module_prefix(path: str) -> str:
    parts = path.split("/")
    return "/".join(parts[:2]) if len(parts) > 1 else path


def connect(adjacency: dict[str, set[str]], left: str, right: str) -> None:
    if left == right:
        return
    adjacency[left].add(right)
    adjacency[right].add(left)


def group_targets(targets: list[str], target_results: dict[str, dict[str, Any]]) -> tuple[list[list[str]], list[dict[str, str]]]:
    adjacency: dict[str, set[str]] = {target: set() for target in targets}
    direct_links: list[dict[str, str]] = []
    target_set = set(targets)

    shared_dependencies: dict[str, set[str]] = defaultdict(set)
    shared_dependents: dict[str, set[str]] = defaultdict(set)

    for target, result in target_results.items():
        for dependency in result["dependencies"]:
            if dependency in target_set:
                connect(adjacency, target, dependency)
                direct_links.append({"from": target, "to": dependency, "reason": "target_dependency"})
            else:
                shared_dependencies[dependency].add(target)
        for dependent in result["dependents"]:
            if dependent in target_set:
                connect(adjacency, target, dependent)
                direct_links.append({"from": dependent, "to": target, "reason": "target_dependency"})
            else:
                shared_dependents[dependent].add(target)

    for shared_map, reason in (
        (shared_dependencies, "shared_dependency"),
        (shared_dependents, "shared_dependent"),
    ):
        for owners in shared_map.values():
            owner_list = sorted(owners)
            if len(owner_list) < 2:
                continue
            first = owner_list[0]
            for other in owner_list[1:]:
                connect(adjacency, first, other)
                direct_links.append({"from": first, "to": other, "reason": reason})

    visited: set[str] = set()
    groups: list[list[str]] = []
    for target in sorted(targets):
        if target in visited:
            continue
        queue = deque([target])
        visited.add(target)
        component: list[str] = []
        while queue:
            current = queue.popleft()
            component.append(current)
            for neighbor in sorted(adjacency[current]):
                if neighbor in visited:
                    continue
                visited.add(neighbor)
                queue.append(neighbor)
        groups.append(sorted(component))

    unique_links = sorted(
        {
            (link["from"], link["to"], link["reason"])
            for link in direct_links
        }
    )
    return groups, [
        {"from": source, "to": target, "reason": reason}
        for source, target, reason in unique_links
    ]


def classify_group(group: list[str], target_results: dict[str, dict[str, Any]]) -> dict[str, Any]:
    target_set = set(group)
    dependencies = sorted(
        {
            dependency
            for target in group
            for dependency in target_results[target]["dependencies"]
            if dependency not in target_set
        }
    )
    dependents = sorted(
        {
            dependent
            for target in group
            for dependent in target_results[target]["dependents"]
            if dependent not in target_set
        }
    )
    target_modules = sorted({module_prefix(target) for target in group})
    dependent_modules = sorted({module_prefix(path) for path in dependents})

    if not dependents:
        parallel_hint = "isolated"
        safe_parallel = True
    elif len(dependent_modules) > 1:
        parallel_hint = "cross_module_boundary"
        safe_parallel = False
    elif len(target_modules) > 1:
        parallel_hint = "multi_module_internal"
        safe_parallel = False
    else:
        parallel_hint = "module_local"
        safe_parallel = True

    return {
        "targets": group,
        "modules": target_modules,
        "dependencies": dependencies,
        "dependents": dependents,
        "dependentModules": dependent_modules,
        "parallelHint": parallel_hint,
        "safeParallel": safe_parallel,
    }


def sort_groups(groups: list[dict[str, Any]]) -> list[dict[str, Any]]:
    def risk_score(group: dict[str, Any]) -> tuple[int, int, int, str]:
        hint = group["parallelHint"]
        hint_priority = {
            "cross_module_boundary": 0,
            "multi_module_internal": 1,
            "module_local": 2,
            "isolated": 3,
        }[hint]
        return (
            hint_priority,
            -len(group["dependents"]),
            -len(group["targets"]),
            ",".join(group["targets"]),
        )

    ordered = []
    for index, group in enumerate(sorted(groups, key=risk_score), start=1):
        payload = dict(group)
        payload["groupId"] = f"group-{index}"
        payload["suggestedOrder"] = index
        ordered.append(payload)
    return ordered


def compute_shared_boundaries(groups: list[dict[str, Any]]) -> list[dict[str, Any]]:
    owners: dict[str, set[str]] = defaultdict(set)
    boundary_kind: dict[tuple[str, str], str] = {}

    for group in groups:
        group_id = group["groupId"]
        for dependency in group["dependencies"]:
            owners[dependency].add(group_id)
            boundary_kind[(dependency, group_id)] = "dependency"
        for dependent in group["dependents"]:
            owners[dependent].add(group_id)
            boundary_kind[(dependent, group_id)] = "dependent"

    shared = []
    for path, group_ids in sorted(owners.items()):
        if len(group_ids) < 2:
            continue
        kinds = sorted({boundary_kind[(path, group_id)] for group_id in group_ids})
        shared.append(
            {
                "file": path,
                "groups": sorted(group_ids),
                "kinds": kinds,
                "modules": sorted({module_prefix(path)}),
            }
        )
    return shared


def build_partition(project_root: str, raw_targets: list[str]) -> dict[str, Any]:
    targets = sorted({normalize_target(project_root, path) for path in raw_targets})
    config = read_config(project_root)
    dep_maps = config.get("dep_maps", {})
    deps_dir = os.path.join(project_root, dep_maps.get("dir", ".claude/deps"))
    all_maps = load_all_dep_maps(deps_dir)

    target_results = {
        target: query_file(target, all_maps)
        for target in targets
    }
    grouped_targets, direct_links = group_targets(targets, target_results)
    groups = [classify_group(group, target_results) for group in grouped_targets]
    ordered_groups = sort_groups(groups)
    shared_boundaries = compute_shared_boundaries(ordered_groups)

    return {
        "projectRoot": project_root,
        "targets": targets,
        "groups": ordered_groups,
        "sharedBoundaries": shared_boundaries,
        "directLinks": direct_links,
    }


def main() -> None:
    if len(sys.argv) < 3:
        print("Usage: dep_partition.py <project_root> <file> [<file> ...]", file=sys.stderr)
        sys.exit(1)

    project_root = os.path.abspath(sys.argv[1])
    config = read_config(project_root)
    dep_maps = config.get("dep_maps", {})
    modules = dep_maps.get("modules", [])

    if not modules:
        print("Error: No dep_maps.modules configured in .claude/look-before-you-leap.local.md", file=sys.stderr)
        sys.exit(1)

    result = build_partition(project_root, sys.argv[2:])
    json.dump(result, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
