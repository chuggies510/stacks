#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETTINGS="$HOME/.claude/settings.json"
CONFIG_DIR="$HOME/.config/stacks"
MARKETPLACE_NAME="stacks"
PLUGIN_KEY="stacks@stacks"

usage() {
  echo "Usage: bash install.sh"
  echo ""
  echo "Registers the stacks plugin with Claude Code."
  echo "Run from the stacks repo root or scripts/ directory."
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { usage; exit 0; }

echo "=== Stacks Plugin Installer ==="

# Ensure settings file exists
if [[ ! -f "$SETTINGS" ]]; then
  echo "ERROR: $SETTINGS not found. Is Claude Code installed?"
  exit 1
fi

# 1. Register as a directory-type marketplace in settings.json
#    This is how ChuggiesMart registers itself — Claude Code reads
#    extraKnownMarketplaces and discovers plugins from marketplace.json.
jq --arg k "$PLUGIN_KEY" --arg name "$MARKETPLACE_NAME" --arg path "$REPO_DIR" \
  '.enabledPlugins //= {} | .extraKnownMarketplaces //= {} |
   .enabledPlugins[$k] = true |
   .extraKnownMarketplaces[$name] = {"source": {"source": "directory", "path": $path}}' \
  "$SETTINGS" > "$SETTINGS.tmp"
mv "$SETTINGS.tmp" "$SETTINGS"
echo "Registered marketplace: $MARKETPLACE_NAME (directory: $REPO_DIR)"
echo "Enabled plugin: $PLUGIN_KEY"

# 2. Create stacks config directory
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
  echo '{}' > "$CONFIG_DIR/config.json"
  echo "Created $CONFIG_DIR/config.json (set library path with init.sh)"
else
  echo "Config already exists at $CONFIG_DIR/config.json"
fi

echo ""
echo "Done. Restart Claude Code to load the stacks plugin."
echo "Next: run 'bash scripts/init.sh ~/path/to/my-library' to create your library."
