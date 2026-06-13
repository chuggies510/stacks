#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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
