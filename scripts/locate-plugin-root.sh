#!/usr/bin/env bash
set -euo pipefail

# Resolve STACKS_ROOT (the absolute path of the installed stacks plugin).
# Echoes the path to stdout. Usage:
#
#   STACKS_ROOT=$(bash "$SCRIPTS_DIR/locate-plugin-root.sh")
#   STACKS_ROOT=$(bash /known/path/to/locate-plugin-root.sh)  # bootstrap from any caller
#
# Authoritative source: known_marketplaces.json `installLocation` (set on
# directory-source installs). Falls back to scanning ~/.claude/plugins/cache
# when installLocation is absent (registry-style installs). Cache scan
# returns the highest-versioned match by `sort -V | tail -1`.

STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null || true)
if [[ -z "$STACKS_ROOT" ]]; then
  CACHE_SCRIPTS=$(find ~/.claude/plugins/cache -type d -name "scripts" -path "*/stacks/*" 2>/dev/null | sort -V | tail -1)
  STACKS_ROOT="${CACHE_SCRIPTS%/scripts}"
fi

if [[ -z "$STACKS_ROOT" ]] || [[ ! -d "$STACKS_ROOT" ]]; then
  echo "ERROR: locate-plugin-root: STACKS_ROOT could not be resolved" >&2
  exit 1
fi

echo "$STACKS_ROOT"
