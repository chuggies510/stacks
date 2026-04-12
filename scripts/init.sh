#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$HOME/.config/stacks"
CONFIG_FILE="$CONFIG_DIR/config.json"

usage() {
  echo "Usage: bash init.sh <path> [--public]"
  echo ""
  echo "Creates a new knowledge library at <path>."
  echo "Scaffolds from template, creates a private GitHub repo, and pushes."
  echo ""
  echo "Options:"
  echo "  --public    Create a public GitHub repo (default: private)"
  echo ""
  echo "Example: bash init.sh ~/my-library"
}

VISIBILITY="--private"
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
    --public) VISIBILITY="--public" ;;
    *) TARGET="$arg" ;;
  esac
done

[[ -z "$TARGET" ]] && { usage; exit 0; }

# Expand tilde to absolute path
TARGET="${TARGET/#\~/$HOME}"
REPO_NAME="$(basename "$TARGET")"

if [[ -d "$TARGET" ]]; then
  echo "ERROR: $TARGET already exists."
  exit 1
fi

# Check gh is available
if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI not found. Install from https://cli.github.com"
  exit 1
fi

# Check gh auth
if ! gh auth status &>/dev/null; then
  echo "ERROR: Not authenticated with gh. Run 'gh auth login' first."
  exit 1
fi

trap 'rm -rf "$TARGET"' ERR

echo "=== Creating Knowledge Library ==="
echo "Location: $TARGET"
echo "GitHub repo: $REPO_NAME ($VISIBILITY)"

# Create and populate from template
mkdir -p "$TARGET"
cp -r "$REPO_DIR/templates/library/." "$TARGET/"

# Git init + initial commit
cd "$TARGET"
git init -b main
git add -A
git commit -m "feat: initialize knowledge library"

# Create GitHub repo and push
gh repo create "$REPO_NAME" "$VISIBILITY" --source . --push
echo "GitHub repo created and pushed."

# Update stacks config with absolute path
mkdir -p "$CONFIG_DIR"
if [[ -f "$CONFIG_FILE" ]]; then
  jq --arg lib "$TARGET" '.library = $lib' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
else
  jq -n --arg lib "$TARGET" '{"library": $lib}' > "$CONFIG_FILE"
fi

echo ""
echo "Done. Library created at: $TARGET"
echo "GitHub: https://github.com/$(gh api user -q .login)/$REPO_NAME"
echo "Config updated: $CONFIG_FILE"
echo ""
echo "Next: cd $TARGET && run /stacks:new {name} to create your first stack"
