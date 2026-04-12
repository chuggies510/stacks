#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  echo "Usage: bash update.sh"
  echo ""
  echo "Pulls latest stacks code and refreshes the plugin cache."
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { usage; exit 0; }

echo "=== Stacks Plugin Updater ==="

cd "$REPO_DIR"
git pull
echo "Pulled latest."

if command -v claude &> /dev/null; then
  claude plugin update stacks 2>/dev/null || echo "Plugin cache refresh skipped (run manually if needed)."
else
  echo "Claude CLI not found. Restart Claude Code to pick up changes."
fi

VERSION=$(jq -r .version .claude-plugin/plugin.json)
echo "Done. Stacks version: $VERSION"
