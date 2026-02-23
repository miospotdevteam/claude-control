#!/usr/bin/env python3
"""Query dependency maps for a file's dependencies and dependents.

Usage:
    python3 deps-query.py <project_root> <file_path>
    python3 deps-query.py <project_root> <file_path> --json

Auto-regenerates stale modules before querying. Scans ALL dep maps
for cross-module dependents.
"""

import json
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GENERATE_SCRIPT = os.path.join(SCRIPT_DIR, "deps-generate.py")
READ_CONFIG = os.path.join(SCRIPT_DIR, "..", "..", "..", "hooks", "lib", "read-config.py")


def read_config(project_root):
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


def module_slug(module_path):
    return module_path.replace("/", "-")


def find_module_for_file(file_path, modules):
    """Find which configured module a file belongs to (longest prefix match)."""
    best = None
    for mod in modules:
        if file_path.startswith(mod + "/") or file_path == mod:
            if best is None or len(mod) > len(best):
                best = mod
    return best


def regen_if_stale(project_root, module_path):
    """Regenerate a module's dep map if stale."""
    try:
        subprocess.run(
            [sys.executable, GENERATE_SCRIPT, project_root, "--module", module_path],
            capture_output=True, text=True, timeout=120,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass


def get_stale_modules(deps_dir):
    stale_file = os.path.join(deps_dir, ".stale")
    if not os.path.exists(stale_file):
        return set()
    try:
        with open(stale_file) as f:
            return {line.strip() for line in f if line.strip()}
    except (FileNotFoundError, PermissionError):
        return set()


def load_all_dep_maps(deps_dir):
    """Load all deps-*.json files from deps_dir."""
    maps = {}
    if not os.path.isdir(deps_dir):
        return maps
    for fname in os.listdir(deps_dir):
        if fname.startswith("deps-") and fname.endswith(".json"):
            fpath = os.path.join(deps_dir, fname)
            try:
                with open(fpath) as f:
                    maps[fname] = json.load(f)
            except (json.JSONDecodeError, FileNotFoundError):
                pass
    return maps


def query_file(file_path, all_maps):
    """Find dependencies and dependents for a file across all dep maps."""
    dependencies = []
    dependents = []
    found_in_module = None

    for map_name, dep_map in all_maps.items():
        # Check if file is a key (has dependencies listed)
        if file_path in dep_map:
            found_in_module = map_name
            dependencies = dep_map[file_path]

        # Check all entries for dependents (who imports this file)
        for source, deps in dep_map.items():
            if file_path in deps:
                dependents.append(source)

    return {
        "file": file_path,
        "found_in": found_in_module,
        "dependencies": sorted(set(dependencies)),
        "dependents": sorted(set(dependents)),
    }


def format_human(result):
    """Format query result for human consumption."""
    lines = []
    lines.append(f"FILE: {result['file']}")
    if result["found_in"]:
        lines.append(f"MODULE: {result['found_in'].replace('deps-', '').replace('.json', '').replace('-', '/')}")
    lines.append("")

    deps = result["dependencies"]
    lines.append(f"DEPENDENCIES ({len(deps)}):")
    if deps:
        for d in deps:
            lines.append(f"  {d}")
    else:
        lines.append("  (none)")

    lines.append("")
    dependents = result["dependents"]
    lines.append(f"DEPENDENTS ({len(dependents)}):")
    if dependents:
        # Group by top-level dir for readability
        by_prefix = {}
        for d in dependents:
            prefix = d.split("/")[0] + "/" + d.split("/")[1] if "/" in d else d
            by_prefix.setdefault(prefix, []).append(d)
        for prefix in sorted(by_prefix):
            for d in by_prefix[prefix]:
                lines.append(f"  {d}")
    else:
        lines.append("  (none)")

    lines.append("")
    lines.append(f"BLAST RADIUS: {len(dependents)} direct consumer(s)")
    if dependents:
        # Count unique top-level modules
        top_modules = {"/".join(d.split("/")[:2]) for d in dependents}
        lines.append(f"  Across {len(top_modules)} module(s): {', '.join(sorted(top_modules))}")

    return "\n".join(lines)


def main():
    if len(sys.argv) < 3:
        print("Usage: deps-query.py <project_root> <file_path> [--json]", file=sys.stderr)
        sys.exit(1)

    project_root = os.path.abspath(sys.argv[1])
    raw_file_path = sys.argv[2]
    json_mode = "--json" in sys.argv

    # Normalize file path to repo-relative
    if os.path.isabs(raw_file_path):
        file_path = os.path.relpath(raw_file_path, project_root)
    else:
        file_path = raw_file_path

    config = read_config(project_root)
    dep_maps_config = config.get("dep_maps", {})
    modules = dep_maps_config.get("modules", [])

    if not modules:
        print("Error: No dep_maps.modules configured in .claude/look-before-you-leap.local.md", file=sys.stderr)
        sys.exit(1)

    deps_dir_rel = dep_maps_config.get("dir", ".claude/deps")
    deps_dir = os.path.join(project_root, deps_dir_rel)

    # Auto-regenerate stale modules
    stale_slugs = get_stale_modules(deps_dir)
    file_module = find_module_for_file(file_path, modules)

    if file_module:
        slug = module_slug(file_module)
        dep_file = os.path.join(deps_dir, f"deps-{slug}.json")
        if slug in stale_slugs or not os.path.exists(dep_file):
            print(f"Regenerating stale dep map for {file_module}...", file=sys.stderr)
            regen_if_stale(project_root, file_module)

    # Also regen any other stale modules (they might have dependents)
    for mod in modules:
        slug = module_slug(mod)
        if slug in stale_slugs and mod != file_module:
            print(f"Regenerating stale dep map for {mod}...", file=sys.stderr)
            regen_if_stale(project_root, mod)

    # Load and query
    all_maps = load_all_dep_maps(deps_dir)
    if not all_maps:
        print("Error: No dep maps found. Run deps-generate.py --all first.", file=sys.stderr)
        sys.exit(1)

    result = query_file(file_path, all_maps)

    if json_mode:
        json.dump(result, sys.stdout, indent=2)
        print()
    else:
        print(format_human(result))


if __name__ == "__main__":
    main()
