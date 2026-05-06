#!/usr/bin/env bash
# Refresh the installed plugin cache from the local source checkout.
#
# Usage: bash refresh-from-source.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_NAME="$(basename "$PLUGIN_ROOT")"

source "${PLUGIN_ROOT}/hooks/lib/find-root.sh"

fail() {
  echo "Refresh failed: $*" >&2
  exit 1
}

canonical_dir() {
  cd "$1" && pwd -P
}

mtime() {
  stat -f "%m" "$1" 2>/dev/null || stat -c "%Y" "$1" 2>/dev/null || echo 0
}

is_cache_path() {
  local path="$1"
  local cache_root
  cache_root="$(canonical_dir "$HOME/.claude/plugins/cache" 2>/dev/null || true)"

  [ -n "$cache_root" ] || return 1
  case "$path" in
    "$cache_root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

repo_name_from_cache_path() {
  local path="$1"
  local after_cache="${path#*plugins/cache/}"
  echo "${after_cache%%/*}"
}

find_source_plugin_root() {
  local current_root
  current_root="$(canonical_dir "$PLUGIN_ROOT")"

  if ! is_cache_path "$current_root" && [ -d "$current_root/.claude-plugin" ]; then
    echo "$current_root"
    return 0
  fi

  local repo_root=""
  repo_root="$(find_plugin_repo 2>/dev/null || true)"

  if [ -z "$repo_root" ] && is_cache_path "$current_root"; then
    local repo_name
    repo_name="$(repo_name_from_cache_path "$current_root")"
    local base
    for base in "$HOME/Projects" "$HOME/Code" "$HOME/Dev" "$HOME/src" "$HOME"; do
      if [ -d "$base/$repo_name/.git" ]; then
        repo_root="$base/$repo_name"
        break
      fi
    done
  fi

  if [ -n "$repo_root" ] && [ -d "$repo_root/$PLUGIN_NAME/.claude-plugin" ]; then
    canonical_dir "$repo_root/$PLUGIN_NAME"
    return 0
  fi

  return 1
}

find_cache_plugin_root() {
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT" ]; then
    local env_root
    env_root="$(canonical_dir "$CLAUDE_PLUGIN_ROOT")"
    if is_cache_path "$env_root"; then
      echo "$env_root"
      return 0
    fi
  fi

  local source_root="$1"
  local repo_name
  repo_name="$(basename "$(dirname "$source_root")")"

  local cache_parent="$HOME/.claude/plugins/cache/$repo_name/$PLUGIN_NAME"
  if [ ! -d "$cache_parent" ]; then
    return 1
  fi

  local newest=""
  local newest_mtime=0
  local candidate
  for candidate in "$cache_parent"/*; do
    [ -d "$candidate" ] || continue
    local candidate_mtime
    candidate_mtime="$(mtime "$candidate")"
    if [ "$candidate_mtime" -gt "$newest_mtime" ]; then
      newest="$candidate"
      newest_mtime="$candidate_mtime"
    fi
  done

  [ -n "$newest" ] || return 1
  canonical_dir "$newest"
}

copy_source_to_stage() {
  local source_root="$1"
  local stage_root="$2"

  rm -rf "$stage_root"

  if command -v rsync >/dev/null 2>&1; then
    mkdir -p "$stage_root"
    rsync -a --delete --exclude ".git/" "$source_root/" "$stage_root/"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$source_root" "$stage_root" <<'PY'
import shutil
import sys

source, target = sys.argv[1:3]
shutil.copytree(
    source,
    target,
    symlinks=True,
    ignore=shutil.ignore_patterns(".git"),
)
PY
    return 0
  fi

  fail "rsync is not installed and python3 fallback is unavailable."
}

SOURCE_PLUGIN_ROOT="$(find_source_plugin_root || true)"
[ -n "$SOURCE_PLUGIN_ROOT" ] || fail "could not locate local source checkout for $PLUGIN_NAME."

CACHE_PLUGIN_ROOT="$(find_cache_plugin_root "$SOURCE_PLUGIN_ROOT" || true)"
[ -n "$CACHE_PLUGIN_ROOT" ] || fail "could not locate installed cache directory. Set CLAUDE_PLUGIN_ROOT or install the plugin first."

SOURCE_PLUGIN_ROOT="$(canonical_dir "$SOURCE_PLUGIN_ROOT")"
CACHE_PLUGIN_ROOT="$(canonical_dir "$CACHE_PLUGIN_ROOT")"

if [ "$SOURCE_PLUGIN_ROOT" = "$CACHE_PLUGIN_ROOT" ]; then
  fail "source and cache directories are the same path: $SOURCE_PLUGIN_ROOT"
fi

CACHE_PARENT="$(dirname "$CACHE_PLUGIN_ROOT")"
STAGE_ROOT="$CACHE_PARENT/.refresh-stage-$$"
OLD_ROOT="$CACHE_PARENT/.refresh-old-$$"
SWAP_IN_PROGRESS=0

cleanup() {
  if [ "$SWAP_IN_PROGRESS" -eq 1 ] && [ ! -d "$CACHE_PLUGIN_ROOT" ] && [ -d "$OLD_ROOT" ]; then
    mv "$OLD_ROOT" "$CACHE_PLUGIN_ROOT" 2>/dev/null || true
  fi
  rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

copy_source_to_stage "$SOURCE_PLUGIN_ROOT" "$STAGE_ROOT"

rm -rf "$OLD_ROOT"
if ! mv "$CACHE_PLUGIN_ROOT" "$OLD_ROOT"; then
  fail "could not move existing cache directory aside: $CACHE_PLUGIN_ROOT"
fi
SWAP_IN_PROGRESS=1

if ! mv "$STAGE_ROOT" "$CACHE_PLUGIN_ROOT"; then
  mv "$OLD_ROOT" "$CACHE_PLUGIN_ROOT" 2>/dev/null || true
  fail "could not activate refreshed cache directory; restored previous cache if possible."
fi
SWAP_IN_PROGRESS=0

rm -rf "$OLD_ROOT"

echo "Refresh complete."
echo "  Source: $SOURCE_PLUGIN_ROOT"
echo "  Cache:  $CACHE_PLUGIN_ROOT"
