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

GH_USER=$(gh api user -q .login)

echo "=== Creating Knowledge Library ==="
echo "Location: $TARGET"
echo "GitHub repo: $GH_USER/$REPO_NAME ($VISIBILITY)"

# Phase 1: local setup — trap cleans up on failure
trap 'echo "ERROR: Setup failed, cleaning up local directory."; rm -rf "$TARGET"' ERR

mkdir -p "$TARGET"
cp -r "$REPO_DIR/templates/library/." "$TARGET/"
cd "$TARGET"
git init -b main
git add -A
git commit -m "feat: initialize knowledge library"

# Phase 2: GitHub — after this point, don't delete local dir on failure
trap - ERR

# Create repo on GitHub (no --source, no --push — those are unreliable)
if ! gh repo create "$REPO_NAME" "$VISIBILITY" 2>&1; then
  echo ""
  echo "WARNING: GitHub repo creation failed. Local library is intact at: $TARGET"
  echo "Create the repo manually and run: git -C \"$TARGET\" remote add origin git@github.com:$GH_USER/$REPO_NAME.git && git -C \"$TARGET\" push -u origin main"
  exit 1
fi

# Set remote and push
git remote add origin "git@github.com:$GH_USER/$REPO_NAME.git"
if ! git push -u origin main; then
  echo ""
  echo "WARNING: Push failed. Local library and GitHub repo both exist."
  echo "Push manually: git -C \"$TARGET\" push -u origin main"
  exit 1
fi

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
echo "GitHub: https://github.com/$GH_USER/$REPO_NAME"
echo "Config updated: $CONFIG_FILE"
echo ""
echo "Next: open a Claude Code session in $TARGET, then run /stacks:new {name}"
