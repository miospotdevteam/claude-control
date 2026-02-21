#!/usr/bin/env python3
"""Auto-detect project stack and generate .claude/software-discipline.local.md.

Usage: python3 detect-stack.py <project_root>

Scans known paths (no directory walks) and outputs the full config file
content to stdout. The caller writes it to disk.
"""

import json
import os
import sys


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def file_exists(path):
    return os.path.isfile(path)


def dir_exists(path):
    return os.path.isdir(path)


def detect_language(root):
    """Detect primary language."""
    if file_exists(f"{root}/tsconfig.json") or file_exists(f"{root}/tsconfig.base.json"):
        return "typescript"
    # Check workspace subdirectories for tsconfig (monorepos often skip root tsconfig)
    for parent in ("apps", "packages", "services", "libs"):
        parent_dir = f"{root}/{parent}"
        if dir_exists(parent_dir):
            try:
                for entry in os.listdir(parent_dir):
                    if file_exists(f"{parent_dir}/{entry}/tsconfig.json"):
                        return "typescript"
            except OSError:
                pass
    if file_exists(f"{root}/package.json"):
        return "javascript"
    if file_exists(f"{root}/Cargo.toml"):
        return "rust"
    if file_exists(f"{root}/pyproject.toml") or file_exists(f"{root}/setup.py"):
        return "python"
    if file_exists(f"{root}/go.mod"):
        return "go"
    return ""


def detect_runtime(language, package_manager):
    if package_manager == "bun":
        return "bun"
    if language in ("typescript", "javascript"):
        return "node"
    return ""


def detect_package_manager(root):
    if file_exists(f"{root}/pnpm-lock.yaml"):
        return "pnpm"
    if file_exists(f"{root}/bun.lockb") or file_exists(f"{root}/bun.lock"):
        return "bun"
    if file_exists(f"{root}/yarn.lock"):
        return "yarn"
    if file_exists(f"{root}/package-lock.json"):
        return "npm"
    return ""


def detect_monorepo(root):
    indicators = [
        f"{root}/pnpm-workspace.yaml",
        f"{root}/turbo.json",
        f"{root}/lerna.json",
        f"{root}/nx.json",
    ]
    for path in indicators:
        if file_exists(path):
            return True
    # Check package.json workspaces field
    pkg = read_json(f"{root}/package.json")
    if pkg and "workspaces" in pkg:
        return True
    return False


def collect_all_deps(root):
    """Collect all dependency names from package.json (and workspace package.jsons)."""
    all_deps = set()

    def add_deps_from(pkg):
        if not pkg:
            return
        for key in ("dependencies", "devDependencies", "peerDependencies"):
            deps = pkg.get(key, {})
            if isinstance(deps, dict):
                all_deps.update(deps.keys())

    # Root package.json
    add_deps_from(read_json(f"{root}/package.json"))

    # Scan workspace dirs one level deep
    for workspace_parent in ("apps", "packages", "services", "libs"):
        parent = f"{root}/{workspace_parent}"
        if not dir_exists(parent):
            continue
        try:
            for entry in os.listdir(parent):
                pkg_path = f"{parent}/{entry}/package.json"
                add_deps_from(read_json(pkg_path))
        except OSError:
            pass

    return all_deps


def detect_from_deps(deps, root_scripts=None, package_manager=""):
    """Detect frameworks/tools from dependency names."""
    result = {}
    scripts = root_scripts or {}

    # Frontend
    frontend_map = {
        "react": "react", "react-dom": "react",
        "next": "next",
        "vue": "vue", "nuxt": "nuxt",
        "svelte": "svelte", "@sveltejs/kit": "sveltekit",
        "solid-js": "solid",
        "@angular/core": "angular",
    }
    for dep, name in frontend_map.items():
        if dep in deps:
            result["frontend"] = name
            break

    # Backend
    backend_map = {
        "hono": "hono",
        "express": "express",
        "fastify": "fastify",
        "@nestjs/core": "nestjs",
        "koa": "koa",
    }
    # next is both frontend and backend
    if "next" in deps and "frontend" not in result:
        result["backend"] = "next"
    for dep, name in backend_map.items():
        if dep in deps:
            result["backend"] = name
            break

    # Validation
    validation_map = {
        "zod": "zod",
        "valibot": "valibot",
        "joi": "joi",
        "yup": "yup",
        "ajv": "ajv",
    }
    for dep, name in validation_map.items():
        if dep in deps:
            result["validation"] = name
            break

    # Styling
    styling_map = {
        "tailwindcss": "tailwind",
        "@tailwindcss/postcss": "tailwind",
        "styled-components": "styled-components",
        "@emotion/react": "emotion",
    }
    for dep, name in styling_map.items():
        if dep in deps:
            result["styling"] = name
            break

    # Testing — check deps first, then fall back to script patterns
    testing_map = {
        "vitest": "vitest",
        "jest": "jest",
        "@playwright/test": "playwright",
        "cypress": "cypress",
        "mocha": "mocha",
    }
    for dep, name in testing_map.items():
        if dep in deps:
            result["testing"] = name
            break
    # If no testing dep found, check if scripts use bun test
    if "testing" not in result and package_manager == "bun":
        test_script = scripts.get("test", "")
        if "bun test" in test_script or "bun run test" in test_script:
            result["testing"] = "bun-test"

    # ORM / DB
    orm_map = {
        "drizzle-orm": "drizzle",
        "prisma": "prisma",
        "@prisma/client": "prisma",
        "convex": "convex",
        "typeorm": "typeorm",
        "sequelize": "sequelize",
        "kysely": "kysely",
        "mongoose": "mongoose",
    }
    for dep, name in orm_map.items():
        if dep in deps:
            result["orm"] = name
            break

    return result


def detect_structure(root, is_monorepo):
    """Detect project structure for monorepos."""
    if not is_monorepo:
        return {}

    structure = {}
    shared_packages = []

    # Scan apps/ and packages/ for package names
    for workspace_parent in ("apps", "packages", "services", "libs"):
        parent = f"{root}/{workspace_parent}"
        if not dir_exists(parent):
            continue
        try:
            for entry in sorted(os.listdir(parent)):
                pkg = read_json(f"{parent}/{entry}/package.json")
                if not pkg:
                    continue
                name = pkg.get("name", "")
                entry_path = f"{workspace_parent}/{entry}"

                if workspace_parent == "packages":
                    # Heuristic: if the package looks like a shared API package
                    if "api" in entry.lower():
                        structure["shared_api_package"] = name
                    # Collect all shared packages
                    if name:
                        shared_packages.append(entry_path)

                elif workspace_parent == "apps":
                    if entry.lower() in ("api", "server", "backend"):
                        structure["api_dir"] = entry_path
                    elif entry.lower() in ("web", "app", "client", "frontend"):
                        structure["web_dir"] = entry_path
        except OSError:
            pass

    if shared_packages:
        structure["shared_packages"] = shared_packages

    return structure


def should_enable_api_contracts(detected):
    """Enable api_contracts discipline if the project has a backend framework."""
    return bool(detected.get("backend"))


def detect_verification_commands(root):
    """Extract verification commands from root package.json scripts."""
    pkg = read_json(f"{root}/package.json")
    if not pkg:
        return {}

    scripts = pkg.get("scripts", {})
    if not scripts:
        return {}

    commands = {}

    # Map well-known script names to verification categories
    script_map = {
        "typecheck": "typecheck", "type-check": "typecheck", "tsc": "typecheck",
        "tsgo": "typecheck", "check-types": "typecheck",
        "lint": "lint", "eslint": "lint",
        "test": "test", "test:unit": "test",
        "build": "build",
    }

    for script_name, category in script_map.items():
        if script_name in scripts and category not in commands:
            commands[category] = f"{script_name}"

    return commands


def build_config(root):
    language = detect_language(root)
    package_manager = detect_package_manager(root)
    runtime = detect_runtime(language, package_manager)
    is_monorepo = detect_monorepo(root)

    root_pkg = read_json(f"{root}/package.json")
    root_scripts = root_pkg.get("scripts", {}) if root_pkg else {}

    deps = collect_all_deps(root) if language in ("typescript", "javascript") else set()
    from_deps = detect_from_deps(deps, root_scripts, package_manager)

    structure = detect_structure(root, is_monorepo)
    verification = detect_verification_commands(root)

    stack = {}
    if language:
        stack["language"] = language
    if runtime:
        stack["runtime"] = runtime
    if package_manager:
        stack["package_manager"] = package_manager
    stack["monorepo"] = is_monorepo
    stack.update(from_deps)

    disciplines = {
        "api_contracts": should_enable_api_contracts(from_deps),
        "plan_enforcement": True,
    }

    return stack, structure, disciplines, verification


def render_config(stack, structure, disciplines, verification):
    """Render the full .local.md file content."""
    lines = ["---"]

    if stack:
        lines.append("stack:")
        for k, v in stack.items():
            lines.append(f"  {k}: {_yaml_val(v)}")

    if structure:
        lines.append("structure:")
        for k, v in structure.items():
            if isinstance(v, list):
                lines.append(f"  {k}:")
                for item in v:
                    lines.append(f"    - {item}")
            else:
                lines.append(f"  {k}: {_yaml_val(v)}")

    if verification:
        lines.append("verification:")
        for k, v in verification.items():
            lines.append(f"  {k}: {_yaml_val(v)}")

    if disciplines:
        lines.append("disciplines:")
        for k, v in disciplines.items():
            lines.append(f"  {k}: {_yaml_val(v)}")

    lines.append("---")
    lines.append("")
    lines.append("# Project Notes")
    lines.append("")
    lines.append("Add project-specific context here (optional, free-form).")
    lines.append("")

    return "\n".join(lines)


def _yaml_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def main():
    if len(sys.argv) < 2:
        print("Usage: detect-stack.py <project_root>", file=sys.stderr)
        sys.exit(1)

    root = sys.argv[1].rstrip("/")
    stack, structure, disciplines, verification = build_config(root)
    print(render_config(stack, structure, disciplines, verification), end="")


if __name__ == "__main__":
    main()
