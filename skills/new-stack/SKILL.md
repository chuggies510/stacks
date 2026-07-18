---
name: new-stack
description: |
  Use when the user wants to create a new knowledge stack in their library.
  Scaffolds the directory structure, STACK.md schema, index, and log from
  templates. Runs from any repo; targets the library configured in
  ~/.config/stacks/config.json, or the current directory when it is itself a library.
---

# New Stack

Create a new empty knowledge stack in this library.

The harness re-initializes the shell between every ```bash``` block (env vars
are lost; the working directory is kept). So each block below re-derives what it
needs from `$CLAUDE_PLUGIN_ROOT` (present in every block) and the concrete stack
name — nothing is carried in a shell variable across blocks. The one piece of
state that survives is the `cd` into the library in Step 1.

## Step 0: Telemetry

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
SKILL_NAME="stacks:new-stack" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

## Step 1: Resolve the library and scaffold the stack

This is the deterministic scaffold — resolve the library, `cd` into it (the `cd`
persists to later blocks; the vars do not), validate the name, copy the
template, and substitute placeholders. It all lives in ONE shell so the derived
names stay coherent.

Substitute `STACK_NAME` with the stack name from `$ARGUMENTS`. If `$ARGUMENTS`
is empty, ask the user what to call the stack, then replace `$ARGUMENTS` below
with the literal name they gave. The name must be lowercase alphanumeric with
hyphens only (no spaces, no special characters); if it fails that rule, tell the
user and ask again before running this block.

```bash
set -euo pipefail
STACK_NAME="$ARGUMENTS"
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"

LIBRARY=$(bash "$STACKS_ROOT/scripts/resolve-library.sh") && cd "$LIBRARY" || exit 1
# resolve-library.sh prints a fix hint and exits non-zero when no library is
# configured or reachable; if it failed, stop and relay that message.

if ! [[ "$STACK_NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "ERROR: stack name '$STACK_NAME' must be lowercase alphanumeric with hyphens only."
  exit 1
fi
if [[ -d "$STACK_NAME" ]]; then
  echo "ERROR: Directory '$STACK_NAME' already exists."
  exit 1
fi

TEMPLATE_DIR="$STACKS_ROOT/templates/stack"
if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "ERROR: Stack template not found. Is the stacks plugin installed?"
  exit 1
fi

mkdir -p "$STACK_NAME"
cp -r "$TEMPLATE_DIR/." "$STACK_NAME/"
find "$STACK_NAME" -name '.gitkeep' -delete

DISPLAY_NAME=$(echo "$STACK_NAME" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}')
perl -pi -e "s/\{Stack Name\}/\Q$DISPLAY_NAME\E/g" "$STACK_NAME/STACK.md" "$STACK_NAME/index.md" "$STACK_NAME/log.md"

echo "SCAFFOLDED $STACK_NAME ($DISPLAY_NAME) in $LIBRARY"
```

## Step 2: Guide STACK.md setup

Tell the user: "Stack '$STACK_NAME' scaffolded at $STACK_NAME/. Edit $STACK_NAME/STACK.md to define your scope, source hierarchy, topic template, and filing rules before running /stacks:catalog-sources."

Read `$STACK_NAME/STACK.md` and show the user the placeholder sections.

Ask: "Would you like to fill in the STACK.md sections now, or do it later?"

- If **now**: walk through each section conversationally. Ask about scope, source hierarchy, filing rules, and any custom topic template sections. Update STACK.md with their answers using the Edit tool. Keep the one-sentence scope description they give — you will pass it as `SCOPE` in Step 3.
- If **later**: leave STACK.md as-is; Step 3 uses the placeholder scope.

## Step 3: Update catalog and commit

Re-derive the names here (the previous block's shell is gone; the `cd` into the
library is not). Substitute `STACK_NAME` with the same concrete name used in
Step 1, and `SCOPE` with the one-sentence scope from Step 2 if the user filled
it in — otherwise leave the `SCOPE=` line as the placeholder default below.

```bash
set -euo pipefail
STACK_NAME="$ARGUMENTS"
SCOPE="edit this description in catalog.md"

DISPLAY_NAME=$(echo "$STACK_NAME" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}')
echo "- [$DISPLAY_NAME]($STACK_NAME/) — $SCOPE (0 topics, 0 sources)" >> catalog.md

git add "$STACK_NAME/" catalog.md
git commit -m "feat: create $STACK_NAME stack"
```

Report: "Stack '$STACK_NAME' created. Drop sources in $STACK_NAME/sources/incoming/ and run /stacks:catalog-sources $STACK_NAME to build article-per-concept wiki entries. Note: sources/incoming/ is gitignored staging — those files are not tracked and don't sync across machines; cataloging is what makes them durable."
