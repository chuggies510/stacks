#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  echo "Usage: bash update.sh"
  echo ""
  echo "Pulls latest stacks code. Since stacks uses a directory-source"
  echo "marketplace, git pull IS the update — no cache refresh needed."
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { usage; exit 0; }

echo "=== Stacks Plugin Updater ==="

cd "$REPO_DIR"

OLD_VERSION=$(jq -r .version .claude-plugin/plugin.json)
git pull
NEW_VERSION=$(jq -r .version .claude-plugin/plugin.json)

if [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
  echo "Already up to date. Stacks version: $NEW_VERSION"
else
  echo "Updated: $OLD_VERSION → $NEW_VERSION"
  echo "Restart Claude Code to pick up changes."
fi
