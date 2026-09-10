#!/usr/bin/env bash
# Resolve the active library path for the stacks skills.
#
# Resolution order:
#   1. $STACKS_CONFIG (or ~/.config/stacks/config.json) -> .library, if it points
#      at a real directory. Honors the same override the scripts already use.
#   2. The current directory, if it is itself a library (has catalog.md). Lets the
#      library-relative skills work before this machine has been registered with a
#      config, instead of telling you to init a library you are standing in.
#
# Echoes the resolved absolute path on success. On failure, prints a fix hint to
# stderr and exits 1.
set -euo pipefail

CONFIG="${STACKS_CONFIG:-$HOME/.config/stacks/config.json}"

LIBRARY=""
if [[ -f "$CONFIG" ]]; then
  LIBRARY=$(jq -r '.library // empty' "$CONFIG" 2>/dev/null || true)
  # Expand a leading ~ or ~/ to $HOME, but leave ~user/... untouched.
  if [[ "$LIBRARY" == "~" || "$LIBRARY" == "~/"* ]]; then
    LIBRARY="${HOME}${LIBRARY#\~}"
  fi
fi

if [[ -z "$LIBRARY" || ! -d "$LIBRARY" ]]; then
  if [[ -f "$PWD/catalog.md" ]]; then
    LIBRARY="$PWD"
  else
    echo "ERROR: No library found." >&2
    echo "No usable config at $CONFIG, and the current directory is not a library (no catalog.md)." >&2
    echo "Fix: run /stacks:init-library, or cd into your library and retry." >&2
    exit 1
  fi
fi

echo "$LIBRARY"
