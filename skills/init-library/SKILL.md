---
name: init-library
description: Use when creating a new knowledge-library repository before any stacks exist.
---

# Init Library

Create a new knowledge library.

## Step 0: Telemetry

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
SKILL_NAME="stacks:init-library" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

## Step 1: Parse arguments

The library path comes from `$ARGUMENTS`. If empty, ask the user where they want the library created. Suggest `~/knowledge` as a sensible default.

Expand `~` to `$HOME` in the path.

## Step 2: Check prerequisites

```bash
TARGET="$ARGUMENTS"
TARGET="${TARGET/#\~/$HOME}"

if [[ -d "$TARGET" ]]; then
  echo "ERROR: $TARGET already exists."
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "ERROR: Not authenticated with gh."
  exit 1
fi
echo "Prerequisites OK."
```

If any check fails, stop and tell the user how to fix it.

## Step 3: Find and run init.sh

```bash
INIT_SH="$STACKS_ROOT/scripts/init.sh"
if [[ ! -f "$INIT_SH" ]]; then
  echo "ERROR: init.sh not found. Is the stacks plugin installed?"
  exit 1
fi
echo "INIT_SH=$INIT_SH"
```

## Step 4: Ask about visibility

Ask the user: "Private or public GitHub repo? (Private is default)"

- If **public**: set `VISIBILITY="--public"`
- Otherwise: set `VISIBILITY=""` (init.sh defaults to private)

## Step 5: Run init.sh

```bash
bash "$INIT_SH" "$TARGET" $VISIBILITY
```

If this fails, report the error and stop.

## Step 6: Report

Tell the user:
- Library created at the target path
- GitHub repo URL (from the init.sh output)
- Next step: `cd $TARGET` and open a Claude Code session there, then run `/stacks:new-stack {name}` to create their first stack
