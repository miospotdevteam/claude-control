#!/usr/bin/env python3
"""Generate normalized dependency maps via madge + dynamic import scanning.

Usage:
    python3 deps-generate.py <project_root> --module "apps/api"
    python3 deps-generate.py <project_root> --all
    python3 deps-generate.py <project_root> --stale-only

Reads dep_maps config from .claude/look-before-you-leap.local.md.
Runs madge per module for static imports, then scans for dynamic imports
(import(), React.lazy, next/dynamic, etc.), normalizes all paths to
repo-relative, writes to .claude/deps/deps-{slug}.json.
"""

import json
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
READ_CONFIG = os.path.join(SCRIPT_DIR, "..", "hooks", "lib", "read-config.py")


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


def read_tsconfig_paths(project_root, module_path):
    """Read compilerOptions.paths and baseUrl from tsconfig.json.

    Returns (paths_dict, base_url) where paths_dict maps alias patterns
    to lists of target patterns, e.g. {"@/*": ["./src/*"]}.
    Follows a single level of 'extends' for monorepo base configs.
    """
    module_abs = os.path.join(project_root, module_path)
    tsconfig_path = os.path.join(module_abs, "tsconfig.json")
    if not os.path.exists(tsconfig_path):
        return {}, None

    try:
        with open(tsconfig_path) as f:
            # Strip JS-style comments (// and /* */) before parsing
            content = f.read()
            content = re.sub(r'//.*?$', '', content, flags=re.MULTILINE)
            content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
            tsconfig = json.loads(content)
    except (json.JSONDecodeError, FileNotFoundError):
        return {}, None

    compiler_opts = tsconfig.get("compilerOptions", {})
    paths = compiler_opts.get("paths", {})
    base_url = compiler_opts.get("baseUrl")

    # Follow one level of extends to pick up paths from a base tsconfig
    if not paths and "extends" in tsconfig:
        extends_path = tsconfig["extends"]
        if not os.path.isabs(extends_path):
            extends_path = os.path.normpath(os.path.join(module_abs, extends_path))
        # Handle extensionless references (e.g., "./tsconfig.base")
        if not extends_path.endswith(".json"):
            extends_path += ".json"
        if os.path.exists(extends_path):
            try:
                with open(extends_path) as f:
                    content = f.read()
                    content = re.sub(r'//.*?$', '', content, flags=re.MULTILINE)
                    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
                    base = json.loads(content)
                base_opts = base.get("compilerOptions", {})
                paths = paths or base_opts.get("paths", {})
                base_url = base_url or base_opts.get("baseUrl")
            except (json.JSONDecodeError, FileNotFoundError):
                pass

    return paths, base_url


# Extensions to probe when resolving dynamic import specifiers
_EXTENSIONS = [".ts", ".tsx", ".js", ".jsx"]
_INDEX_FILES = ["/index.ts", "/index.tsx", "/index.js", "/index.jsx"]


def resolve_import_path(specifier, importing_file, project_root, module_path,
                        tsconfig_paths, base_url):
    """Resolve a dynamic import specifier to a repo-relative path.

    Returns the resolved repo-relative path, or None if unresolvable.
    """
    module_abs = os.path.join(project_root, module_path)

    # Determine the base directory for relative resolution
    importing_abs = os.path.join(project_root, importing_file)
    importing_dir = os.path.dirname(importing_abs)

    resolved_abs = None

    if specifier.startswith("."):
        # Relative import: resolve against importing file's directory
        resolved_abs = _probe_path(os.path.join(importing_dir, specifier))

    elif tsconfig_paths:
        # Try tsconfig path aliases
        resolved_abs = _resolve_alias(specifier, tsconfig_paths, module_abs,
                                      base_url, project_root)

    elif base_url:
        # No paths but baseUrl set: resolve relative to baseUrl
        base_abs = os.path.normpath(os.path.join(module_abs, base_url))
        resolved_abs = _probe_path(os.path.join(base_abs, specifier))

    if resolved_abs is None:
        return None

    repo_rel = os.path.relpath(resolved_abs, project_root)
    if repo_rel.startswith(".."):
        return None  # Outside the repo
    return repo_rel


def _probe_path(candidate):
    """Try a candidate path with common extensions. Return absolute path or None."""
    candidate = os.path.normpath(candidate)

    # Exact match (already has extension)
    if os.path.isfile(candidate):
        return candidate

    # Try adding extensions
    for ext in _EXTENSIONS:
        p = candidate + ext
        if os.path.isfile(p):
            return p

    # Try as directory with index file
    for idx in _INDEX_FILES:
        p = candidate + idx
        if os.path.isfile(p):
            return p

    return None


def _resolve_alias(specifier, tsconfig_paths, module_abs, base_url, project_root):
    """Resolve a specifier against tsconfig paths aliases.

    Handles patterns like {"@/*": ["./src/*"], "@components/*": ["./src/components/*"]}.
    """
    base_dir = module_abs
    if base_url:
        base_dir = os.path.normpath(os.path.join(module_abs, base_url))

    for pattern, targets in tsconfig_paths.items():
        if not isinstance(targets, list) or not targets:
            continue

        if pattern.endswith("/*"):
            prefix = pattern[:-2]  # "@" or "@components"
            if specifier.startswith(prefix + "/"):
                rest = specifier[len(prefix) + 1:]
                for target in targets:
                    if target.endswith("/*"):
                        target_base = target[:-2]  # "./src" or "./src/components"
                        abs_target = os.path.normpath(os.path.join(base_dir, target_base, rest))
                        result = _probe_path(abs_target)
                        if result:
                            return result
        elif pattern == specifier:
            # Exact alias match (no wildcard)
            for target in targets:
                abs_target = os.path.normpath(os.path.join(base_dir, target))
                result = _probe_path(abs_target)
                if result:
                    return result

    return None


# Regex for dynamic imports: import('path') or import("path")
# Matches inside React.lazy(), next/dynamic(), defineAsyncComponent(), or bare
_DYNAMIC_IMPORT_RE = re.compile(r'''import\s*\(\s*['"]([^'"]+)['"]\s*\)''')


def scan_dynamic_imports(project_root, module_path, existing_deps):
    """Scan source files for dynamic import() patterns.

    Walks .ts/.tsx files in the module, finds import('...') patterns via regex,
    resolves paths, and returns additional dependency edges not already in
    existing_deps (the madge output).

    Returns dict: {repo_relative_file: [repo_relative_dep, ...]}
    """
    module_abs = os.path.join(project_root, module_path)
    src_dir = os.path.join(module_abs, "src")
    if not os.path.isdir(src_dir):
        src_dir = module_abs

    tsconfig_paths, base_url = read_tsconfig_paths(project_root, module_path)

    additional = {}
    dynamic_count = 0

    for root, _dirs, files in os.walk(src_dir):
        if "node_modules" in root:
            continue
        for fname in files:
            if not fname.endswith((".ts", ".tsx")):
                continue
            if fname.endswith((".test.ts", ".test.tsx", ".spec.ts", ".spec.tsx")):
                continue

            fpath = os.path.join(root, fname)
            repo_rel = os.path.relpath(fpath, project_root)

            try:
                with open(fpath) as f:
                    content = f.read()
            except (FileNotFoundError, PermissionError, UnicodeDecodeError):
                continue

            matches = _DYNAMIC_IMPORT_RE.findall(content)
            if not matches:
                continue

            existing_for_file = set(existing_deps.get(repo_rel, []))
            new_deps = []

            for specifier in matches:
                resolved = resolve_import_path(
                    specifier, repo_rel, project_root, module_path,
                    tsconfig_paths, base_url,
                )
                if resolved and resolved != repo_rel and resolved not in existing_for_file:
                    new_deps.append(resolved)
                    existing_for_file.add(resolved)

            if new_deps:
                additional[repo_rel] = new_deps
                dynamic_count += len(new_deps)

    if dynamic_count:
        print(f"  dynamic imports: found {dynamic_count} additional edge(s)", file=sys.stderr)

    return additional


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

    # Scan for dynamic imports and merge additional edges
    dynamic_edges = scan_dynamic_imports(project_root, module_path, normalized)
    for file_key, new_deps in dynamic_edges.items():
        if file_key in normalized:
            existing = set(normalized[file_key])
            normalized[file_key] = sorted(existing | set(new_deps))
        else:
            normalized[file_key] = sorted(new_deps)

    out_path = os.path.join(deps_dir, f"deps-{slug}.json")
    with open(out_path, "w") as f:
        json.dump(normalized, f, indent=2, sort_keys=True)

    clear_stale(deps_dir, slug)
    file_count = len(normalized)
    print(f"  OK: {file_count} files -> {out_path}", file=sys.stderr)
    return True


def main():
    if len(sys.argv) < 3:
        print('Usage: deps-generate.py <project_root> (--module "<path>" | --all | --stale-only)', file=sys.stderr)
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
