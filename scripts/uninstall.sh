#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
CONFIG_DIR="$HOME/.config/stacks"

usage() {
  echo "Usage: bash uninstall.sh"
  echo ""
  echo "Removes the stacks plugin from Claude Code."
  echo "Does NOT delete your library repo or its content."
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { usage; exit 0; }

echo "=== Stacks Plugin Uninstaller ==="

# Remove from enabledPlugins (object format)
PLUGIN_KEY="stacks@local"
if [[ -f "$SETTINGS" ]]; then
  jq --arg k "$PLUGIN_KEY" 'del(.enabledPlugins[$k]) | del(.pluginPaths[$k])' "$SETTINGS" > "$SETTINGS.tmp"
  mv "$SETTINGS.tmp" "$SETTINGS"
  echo "Removed from enabledPlugins."
fi

# Note: config.json is preserved so reinstall can find existing library
echo ""
echo "Done. Restart Claude Code to unload the plugin."
echo "Your library repo and config ($CONFIG_DIR/config.json) were NOT deleted."
echo "To fully remove config: rm -rf $CONFIG_DIR"
