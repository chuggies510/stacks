#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETTINGS="$HOME/.claude/settings.json"
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
CONFIG_DIR="$HOME/.config/stacks"
VERSION=$(jq -r '.version' "$REPO_DIR/.claude-plugin/plugin.json" 2>/dev/null || echo "0.1.0")
PLUGIN_KEY="stacks@local"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

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

# 1. Register in settings.json enabledPlugins (idempotent)
jq --arg k "$PLUGIN_KEY" \
  '.enabledPlugins //= {} | .enabledPlugins[$k] = true' \
  "$SETTINGS" > "$SETTINGS.tmp"
mv "$SETTINGS.tmp" "$SETTINGS"
echo "Registered in enabledPlugins as $PLUGIN_KEY"

# 2. Register in installed_plugins.json (the file Claude Code actually reads for paths)
if [[ ! -f "$INSTALLED_PLUGINS" ]]; then
  echo '{"version": 2, "plugins": {}}' > "$INSTALLED_PLUGINS"
fi

jq --arg k "$PLUGIN_KEY" --arg p "$REPO_DIR" --arg v "$VERSION" --arg now "$NOW" \
  '.plugins[$k] = [{
    "scope": "user",
    "installPath": $p,
    "version": $v,
    "installedAt": $now,
    "lastUpdated": $now,
    "gitCommitSha": ""
  }]' \
  "$INSTALLED_PLUGINS" > "$INSTALLED_PLUGINS.tmp"
mv "$INSTALLED_PLUGINS.tmp" "$INSTALLED_PLUGINS"
echo "Registered installPath in installed_plugins.json: $REPO_DIR"

# 3. Create stacks config directory
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
