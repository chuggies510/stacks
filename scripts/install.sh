#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETTINGS="$HOME/.claude/settings.json"
CONFIG_DIR="$HOME/.config/stacks"

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

# enabledPlugins is a JSON object with "name@source": true entries
PLUGIN_KEY="stacks@local"
if jq -e --arg k "$PLUGIN_KEY" '.enabledPlugins[$k] // false' "$SETTINGS" 2>/dev/null | grep -q true; then
  echo "Already registered in enabledPlugins."
else
  jq --arg k "$PLUGIN_KEY" --arg p "$REPO_DIR" '.enabledPlugins[$k] = true | .pluginPaths[$k] = $p' "$SETTINGS" > "$SETTINGS.tmp"
  mv "$SETTINGS.tmp" "$SETTINGS"
  echo "Registered in enabledPlugins as $PLUGIN_KEY"
fi

# Create config directory
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
