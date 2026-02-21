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
    if file_exists(f"{root}/package.json"):
        return "javascript"
    if file_exists(f"{root}/Cargo.toml"):
        return "rust"
    if file_exists(f"{root}/pyproject.toml") or file_exists(f"{root}/setup.py"):
        return "python"
    if file_exists(f"{root}/go.mod"):
        return "go"
    return ""


def detect_runtime(language):
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


def detect_from_deps(deps):
    """Detect frameworks/tools from dependency names."""
    result = {}

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

    # Testing
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

    # Scan apps/ and packages/ for package names
    for workspace_parent, config_key in [("apps", None), ("packages", None)]:
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

                # Heuristic: if the package looks like a shared API package
                if "api" in entry.lower() and workspace_parent == "packages":
                    structure["shared_api_package"] = name
                    structure["shared_dir"] = entry_path

                # Heuristic: api app
                if entry.lower() in ("api", "server", "backend") and workspace_parent == "apps":
                    structure["api_dir"] = entry_path

                # Heuristic: web app
                if entry.lower() in ("web", "app", "client", "frontend") and workspace_parent == "apps":
                    structure["web_dir"] = entry_path
        except OSError:
            pass

    return structure


def should_enable_api_contracts(detected):
    """Enable api_contracts discipline if the project has a backend framework."""
    return bool(detected.get("backend"))


def build_config(root):
    language = detect_language(root)
    runtime = detect_runtime(language)
    package_manager = detect_package_manager(root)
    is_monorepo = detect_monorepo(root)

    deps = collect_all_deps(root) if language in ("typescript", "javascript") else set()
    from_deps = detect_from_deps(deps)

    structure = detect_structure(root, is_monorepo)

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

    return stack, structure, disciplines


def render_config(stack, structure, disciplines):
    """Render the full .local.md file content."""
    lines = ["---"]

    if stack:
        lines.append("stack:")
        for k, v in stack.items():
            lines.append(f"  {k}: {_yaml_val(v)}")

    if structure:
        lines.append("structure:")
        for k, v in structure.items():
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
    stack, structure, disciplines = build_config(root)
    print(render_config(stack, structure, disciplines), end="")


if __name__ == "__main__":
    main()
