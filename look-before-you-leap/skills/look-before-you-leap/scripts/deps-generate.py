#!/usr/bin/env python3
"""Generate normalized dependency maps via madge.

Usage:
    python3 deps-generate.py <project_root> --module apps/api
    python3 deps-generate.py <project_root> --all
    python3 deps-generate.py <project_root> --stale-only

Reads dep_maps config from .claude/look-before-you-leap.local.md.
Runs madge per module, normalizes paths to repo-relative,
writes to .claude/deps/deps-{slug}.json.
"""

import json
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
READ_CONFIG = os.path.join(SCRIPT_DIR, "..", "..", "..", "hooks", "lib", "read-config.py")


def read_config(project_root):
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


def module_slug(module_path):
    """Convert module path to filename slug: apps/api -> apps-api"""
    return module_path.replace("/", "-")


def get_deps_dir(project_root, config):
    dep_maps = config.get("dep_maps", {})
    rel_dir = dep_maps.get("dir", ".claude/deps")
    return os.path.join(project_root, rel_dir)


def get_stale_modules(deps_dir):
    """Read .stale marker file and return set of stale module slugs."""
    stale_file = os.path.join(deps_dir, ".stale")
    if not os.path.exists(stale_file):
        return set()
    try:
        with open(stale_file) as f:
            return {line.strip() for line in f if line.strip()}
    except (FileNotFoundError, PermissionError):
        return set()


def clear_stale(deps_dir, slug):
    """Remove a slug from the .stale marker file."""
    stale_file = os.path.join(deps_dir, ".stale")
    if not os.path.exists(stale_file):
        return
    try:
        with open(stale_file) as f:
            lines = [line.strip() for line in f if line.strip()]
        remaining = [l for l in lines if l != slug]
        with open(stale_file, "w") as f:
            f.write("\n".join(remaining) + "\n" if remaining else "")
    except (FileNotFoundError, PermissionError):
        pass


def is_stale_by_mtime(project_root, deps_dir, module_path):
    """Check if any .ts/.tsx in module is newer than its dep file."""
    slug = module_slug(module_path)
    dep_file = os.path.join(deps_dir, f"deps-{slug}.json")
    if not os.path.exists(dep_file):
        return True

    dep_mtime = os.path.getmtime(dep_file)
    src_dir = os.path.join(project_root, module_path, "src")
    if not os.path.isdir(src_dir):
        src_dir = os.path.join(project_root, module_path)

    for root, _dirs, files in os.walk(src_dir):
        # Skip node_modules
        if "node_modules" in root:
            continue
        for fname in files:
            if fname.endswith((".ts", ".tsx")) and not fname.endswith((".test.ts", ".test.tsx", ".spec.ts", ".spec.tsx")):
                fpath = os.path.join(root, fname)
                if os.path.getmtime(fpath) > dep_mtime:
                    return True
    return False


def run_madge(project_root, module_path, tool_cmd):
    """Run madge for a module and return raw JSON output."""
    module_abs = os.path.join(project_root, module_path)
    src_dir = os.path.join(module_abs, "src")
    if not os.path.isdir(src_dir):
        src_dir = module_abs

    tsconfig = os.path.join(module_abs, "tsconfig.json")

    # Build madge command
    cmd_parts = tool_cmd.split()
    cmd = list(cmd_parts)
    if os.path.exists(tsconfig):
        cmd.extend(["--ts-config", tsconfig])
    cmd.append(src_dir)

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=project_root,
            timeout=120,
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # Fallback: try npx madge
    npx_cmd = ["npx", "--yes"] + cmd_parts + (["--ts-config", tsconfig] if os.path.exists(tsconfig) else []) + [src_dir]
    try:
        result = subprocess.run(
            npx_cmd,
            capture_output=True,
            text=True,
            cwd=project_root,
            timeout=180,
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            print(f"  madge stderr: {result.stderr[:500]}", file=sys.stderr)
            return None
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        print(f"  madge failed: {e}", file=sys.stderr)
        return None


def normalize_paths(raw_deps, project_root, module_path):
    """Normalize madge-relative paths to repo-relative paths.

    Madge outputs paths relative to the entry point dir (e.g., src/).
    We resolve them to repo-relative paths (e.g., packages/shared/src/types.ts).
    """
    module_abs = os.path.join(project_root, module_path)
    src_dir = os.path.join(module_abs, "src")
    if not os.path.isdir(src_dir):
        src_dir = module_abs

    normalized = {}
    for file_key, deps in raw_deps.items():
        # Resolve the file key
        abs_key = os.path.normpath(os.path.join(src_dir, file_key))
        repo_key = os.path.relpath(abs_key, project_root)

        # Resolve each dependency
        repo_deps = []
        for dep in deps:
            abs_dep = os.path.normpath(os.path.join(src_dir, dep))
            repo_dep = os.path.relpath(abs_dep, project_root)
            # Filter out paths that escape the repo (node_modules, etc.)
            if not repo_dep.startswith(".."):
                repo_deps.append(repo_dep)

        normalized[repo_key] = repo_deps

    return normalized


def generate_module(project_root, module_path, config):
    """Generate dep map for a single module."""
    dep_maps = config.get("dep_maps", {})
    tool_cmd = dep_maps.get("tool_cmd", "madge --json --extensions ts,tsx")
    deps_dir = get_deps_dir(project_root, config)
    slug = module_slug(module_path)

    os.makedirs(deps_dir, exist_ok=True)

    print(f"Generating deps for {module_path}...", file=sys.stderr)
    raw = run_madge(project_root, module_path, tool_cmd)
    if raw is None:
        print(f"  FAILED: could not run madge for {module_path}", file=sys.stderr)
        return False

    normalized = normalize_paths(raw, project_root, module_path)
    out_path = os.path.join(deps_dir, f"deps-{slug}.json")
    with open(out_path, "w") as f:
        json.dump(normalized, f, indent=2, sort_keys=True)

    clear_stale(deps_dir, slug)
    file_count = len(normalized)
    print(f"  OK: {file_count} files -> {out_path}", file=sys.stderr)
    return True


def main():
    if len(sys.argv) < 3:
        print("Usage: deps-generate.py <project_root> (--module <path> | --all | --stale-only)", file=sys.stderr)
        sys.exit(1)

    project_root = os.path.abspath(sys.argv[1])
    config = read_config(project_root)
    dep_maps = config.get("dep_maps", {})
    modules = dep_maps.get("modules", [])

    if not modules:
        print("No dep_maps.modules configured in .claude/look-before-you-leap.local.md", file=sys.stderr)
        sys.exit(1)

    mode = sys.argv[2]

    if mode == "--module":
        if len(sys.argv) < 4:
            print("--module requires a module path", file=sys.stderr)
            sys.exit(1)
        target = sys.argv[3]
        if target not in modules:
            print(f"Module '{target}' not in configured modules: {modules}", file=sys.stderr)
            sys.exit(1)
        success = generate_module(project_root, target, config)
        sys.exit(0 if success else 1)

    elif mode == "--all":
        failed = []
        for mod in modules:
            if not generate_module(project_root, mod, config):
                failed.append(mod)
        if failed:
            print(f"\nFailed modules: {failed}", file=sys.stderr)
            sys.exit(1)
        print(f"\nAll {len(modules)} modules generated successfully.", file=sys.stderr)

    elif mode == "--stale-only":
        deps_dir = get_deps_dir(project_root, config)
        stale_slugs = get_stale_modules(deps_dir)
        generated = 0
        for mod in modules:
            slug = module_slug(mod)
            if slug in stale_slugs or is_stale_by_mtime(project_root, deps_dir, mod):
                generate_module(project_root, mod, config)
                generated += 1
        if generated == 0:
            print("All dep maps are up to date.", file=sys.stderr)
        else:
            print(f"Regenerated {generated} stale module(s).", file=sys.stderr)

    else:
        print(f"Unknown mode: {mode}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
