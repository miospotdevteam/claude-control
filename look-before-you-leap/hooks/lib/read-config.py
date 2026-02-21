#!/usr/bin/env python3
"""Read .claude/look-before-you-leap.local.md and output config as JSON.

Usage: python3 read-config.py <project_root>

Parses YAML frontmatter (regex-based, no PyYAML dependency).
Supports 2-level nesting with scalar values only.
Outputs {} on missing file or parse error.
"""

import json
import re
import sys


def parse_frontmatter(text):
    """Extract YAML frontmatter from markdown text.

    Supports:
      key: value           -> {"key": "value"}
      parent:
        child: value       -> {"parent": {"child": "value"}}

    Values are coerced: true/false -> bool, digits -> int.
    """
    match = re.match(r'^---\s*\n(.*?)\n---', text, re.DOTALL)
    if not match:
        return {}

    lines = match.group(1).split('\n')
    result = {}
    current_parent = None
    current_child_list = None  # (parent_key, child_key) when collecting list items

    for line in lines:
        # Skip blank lines and comments
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            current_child_list = None
            current_parent = None if not stripped else current_parent
            continue

        # List item (e.g. "    - packages/i18n")
        list_match = re.match(r'^\s+-\s+(.+)', line)
        if list_match and current_child_list:
            parent_key, child_key = current_child_list
            result[parent_key][child_key].append(_coerce(list_match.group(1).strip()))
            continue

        # End any active list collection when we hit a non-list line
        current_child_list = None

        # Indented line (child of current parent)
        if line.startswith('  ') and current_parent is not None:
            child_match = re.match(r'^\s+([\w_]+)\s*:\s*(.*)', line)
            if child_match:
                key, val = child_match.group(1), child_match.group(2).strip()
                if val:
                    result[current_parent][key] = _coerce(val)
                else:
                    # Child key with no value — start collecting list items
                    result[current_parent][key] = []
                    current_child_list = (current_parent, key)
            continue

        # Top-level key
        top_match = re.match(r'^([\w_]+)\s*:\s*(.*)', line)
        if top_match:
            key, val = top_match.group(1), top_match.group(2).strip()
            if val:
                # Scalar value
                result[key] = _coerce(val)
                current_parent = None
            else:
                # Start of a nested block
                result[key] = {}
                current_parent = key


    return result


def _coerce(val):
    """Coerce string values to bool/int where appropriate."""
    if val.lower() == 'true':
        return True
    if val.lower() == 'false':
        return False
    if val.isdigit():
        return int(val)
    # Strip surrounding quotes
    if (val.startswith('"') and val.endswith('"')) or \
       (val.startswith("'") and val.endswith("'")):
        return val[1:-1]
    return val


def main():
    if len(sys.argv) < 2:
        json.dump({}, sys.stdout)
        return

    project_root = sys.argv[1]
    config_path = f"{project_root}/.claude/look-before-you-leap.local.md"

    try:
        with open(config_path) as f:
            content = f.read()
        config = parse_frontmatter(content)
        json.dump(config, sys.stdout)
    except (FileNotFoundError, PermissionError, OSError):
        json.dump({}, sys.stdout)


if __name__ == '__main__':
    main()
