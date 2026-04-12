#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$HOME/.config/stacks"
CONFIG_FILE="$CONFIG_DIR/config.json"

usage() {
  echo "Usage: bash init.sh <path>"
  echo ""
  echo "Creates a new knowledge library at <path>."
  echo "Copies templates, runs git init, and updates stacks config."
  echo ""
  echo "Example: bash init.sh ~/my-library"
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" || -z "${1:-}" ]] && { usage; exit 0; }

TARGET="$1"
# Expand tilde to absolute path
TARGET="${TARGET/#\~/$HOME}"

if [[ -d "$TARGET" ]]; then
  echo "ERROR: $TARGET already exists."
  exit 1
fi

echo "=== Creating Knowledge Library ==="
echo "Location: $TARGET"

# Create and populate from template (cp -r copies all files including .gitignore)
mkdir -p "$TARGET"
cp -r "$REPO_DIR/templates/library/." "$TARGET/"

# Git init
cd "$TARGET"
git init
git add -A
git commit -m "feat: initialize knowledge library"

# Update stacks config with absolute path
mkdir -p "$CONFIG_DIR"
jq -n --arg lib "$TARGET" '{"library": $lib}' > "$CONFIG_FILE"

echo ""
echo "Done. Library created at: $TARGET"
echo "Config updated: $CONFIG_FILE"
echo ""
echo "Next: cd $TARGET && run /stacks:new {name} to create your first stack"
