#!/usr/bin/env bash
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
KNOWN_MARKETPLACES="$HOME/.claude/plugins/known_marketplaces.json"
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
CONFIG_DIR="$HOME/.config/stacks"
PLUGIN_KEY="stacks@stacks"
MARKETPLACE_NAME="stacks"

usage() {
  echo "Usage: bash uninstall.sh"
  echo ""
  echo "Removes the stacks plugin from Claude Code."
  echo "Does NOT delete your library repo or its content."
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { usage; exit 0; }

echo "=== Stacks Plugin Uninstaller ==="

# Remove from settings.json: enabledPlugins + extraKnownMarketplaces
if [[ -f "$SETTINGS" ]]; then
  jq --arg k "$PLUGIN_KEY" --arg m "$MARKETPLACE_NAME" \
    'del(.enabledPlugins[$k]) | del(.extraKnownMarketplaces[$m])' \
    "$SETTINGS" > "$SETTINGS.tmp"
  mv "$SETTINGS.tmp" "$SETTINGS"
  echo "Removed from settings.json."
fi

# Remove from known_marketplaces.json (written by Claude Code when it resolves the marketplace)
if [[ -f "$KNOWN_MARKETPLACES" ]]; then
  jq --arg m "$MARKETPLACE_NAME" 'del(.[$m])' \
    "$KNOWN_MARKETPLACES" > "$KNOWN_MARKETPLACES.tmp"
  mv "$KNOWN_MARKETPLACES.tmp" "$KNOWN_MARKETPLACES"
  echo "Removed from known_marketplaces.json."
fi

# Remove from installed_plugins.json (written by Claude Code when it caches the plugin)
if [[ -f "$INSTALLED_PLUGINS" ]]; then
  jq --arg k "$PLUGIN_KEY" 'del(.plugins[$k])' \
    "$INSTALLED_PLUGINS" > "$INSTALLED_PLUGINS.tmp"
  mv "$INSTALLED_PLUGINS.tmp" "$INSTALLED_PLUGINS"
  echo "Removed from installed_plugins.json."
fi

# Note: config.json is preserved so reinstall can find existing library
echo ""
echo "Done. Restart Claude Code to unload the plugin."
echo "Your library repo and config ($CONFIG_DIR/config.json) were NOT deleted."
echo "To fully remove config: rm -rf $CONFIG_DIR"
