---
name: init
description: |
  Use when the user wants to create a new knowledge library. Scaffolds the
  directory from templates, creates a private GitHub repo, and updates stacks
  config. Run this before /stacks:new.
---

# Init Library

Create a new knowledge library.

## Step 0: Telemetry

```bash
TELEMETRY_SH=$(find ~/.claude/plugins/cache -name telemetry.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
if [[ -z "$TELEMETRY_SH" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  TELEMETRY_SH="$STACKS_ROOT/scripts/telemetry.sh"
fi
SKILL_NAME="stacks:init" bash "$TELEMETRY_SH" 2>/dev/null || true
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

if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI not found."
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
INIT_SH=$(find ~/.claude/plugins/cache -name init.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
if [[ -z "$INIT_SH" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  INIT_SH="$STACKS_ROOT/scripts/init.sh"
fi
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
- Next step: `cd $TARGET` and open a Claude Code session there, then run `/stacks:new {name}` to create their first stack
