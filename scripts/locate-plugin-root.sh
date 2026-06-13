#!/usr/bin/env bash
set -euo pipefail

# Resolve STACKS_ROOT (the absolute path of the installed stacks plugin).
# Echoes the path to stdout. Usage:
#
#   STACKS_ROOT=$(bash "$SCRIPTS_DIR/locate-plugin-root.sh")
#   STACKS_ROOT=$(bash /known/path/to/locate-plugin-root.sh)  # bootstrap from any caller
#
# Source: known_marketplaces.json `installLocation` (directory-source installs).

STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null || true)

if [[ -z "$STACKS_ROOT" ]] || [[ ! -d "$STACKS_ROOT" ]]; then
  echo "ERROR: locate-plugin-root: STACKS_ROOT could not be resolved" >&2
  exit 1
fi

echo "$STACKS_ROOT"
