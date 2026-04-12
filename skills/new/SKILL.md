---
name: new
description: |
  Use when the user wants to create a new knowledge stack in their library.
  Scaffolds the directory structure, STACK.md schema, index, and log from
  templates. Must be run from within a library repo (one with catalog.md at root).
---

# New Stack

Create a new empty knowledge stack in this library.

## Step 0: Telemetry

```bash
TELEMETRY_SH=$(find ~/.claude/plugins/cache -name telemetry.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
if [[ -z "$TELEMETRY_SH" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  TELEMETRY_SH="$STACKS_ROOT/scripts/telemetry.sh"
fi
SKILL_NAME="stacks:new" bash "$TELEMETRY_SH" 2>/dev/null || true
```

## Step 1: Gate check

Verify this is a library repo:

```bash
if [[ ! -f "catalog.md" ]]; then
  echo "ERROR: catalog.md not found. This doesn't appear to be a library repo."
  echo "Run /stacks:init to create a library first."
  exit 1
fi
```

If gate fails, stop and tell the user.

## Step 2: Parse arguments

The stack name comes from `$ARGUMENTS`. If empty, ask the user what to call the stack.

Validate: name must be lowercase alphanumeric with hyphens only (no spaces, no special characters). If invalid, tell the user the naming rule and ask again.

```bash
STACK_NAME="$ARGUMENTS"
if [[ -d "$STACK_NAME" ]]; then
  echo "ERROR: Directory '$STACK_NAME' already exists."
  exit 1
fi
```

## Step 3: Scaffold from template

Find the stack template in the stacks plugin directory:

```bash
# Try plugin cache first
TEMPLATE_DIR=$(find ~/.claude/plugins/cache -type d -name "stack" -path "*/stacks/*/templates/stack" 2>/dev/null | sort -V | tail -1)
# Fallback: local install path from settings
if [[ -z "$TEMPLATE_DIR" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  [[ -n "$STACKS_ROOT" && -d "$STACKS_ROOT/templates/stack" ]] && TEMPLATE_DIR="$STACKS_ROOT/templates/stack"
fi
if [[ -z "$TEMPLATE_DIR" ]]; then
  echo "ERROR: Stack template not found. Is the stacks plugin installed?"
  exit 1
fi
mkdir -p "$STACK_NAME"
cp -r "$TEMPLATE_DIR/." "$STACK_NAME/"
# Remove .gitkeep files from copied template
find "$STACK_NAME" -name '.gitkeep' -delete
```

## Step 4: Replace placeholders

```bash
DISPLAY_NAME=$(echo "$STACK_NAME" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}')
perl -pi -e "s/\\{Stack Name\\}/$DISPLAY_NAME/g" "$STACK_NAME/STACK.md" "$STACK_NAME/index.md" "$STACK_NAME/log.md"
```

## Step 5: Guide STACK.md setup

Tell the user: "Stack '$STACK_NAME' scaffolded at $STACK_NAME/. Edit $STACK_NAME/STACK.md to define your scope, source hierarchy, topic template, and filing rules before running /stacks:ingest."

Read `$STACK_NAME/STACK.md` and show the user the placeholder sections.

Ask: "Would you like to fill in the STACK.md sections now, or do it later?"

- If **now**: walk through each section conversationally. Ask about scope, source hierarchy, filing rules, and any custom topic template sections. Update STACK.md with their answers using the Edit tool. After editing, extract the user's scope description from their answer and set SCOPE_DESCRIPTION to that text (a single sentence describing what the stack covers).
- If **later**: proceed to catalog update. Set SCOPE_DESCRIPTION="" (empty, so the catalog gets the placeholder).

Before running the Step 6 bash block, set `SCOPE_DESCRIPTION` to the scope text from Step 5 if the user provided it, otherwise leave it unset so the default placeholder applies.

## Step 6: Update catalog

Append a new entry to the library's `catalog.md`:

```bash
SCOPE="${SCOPE_DESCRIPTION:-edit this description in catalog.md}"
echo "- [$DISPLAY_NAME]($STACK_NAME/) — $SCOPE (0 topics, 0 sources)" >> catalog.md
```

Where `SCOPE_DESCRIPTION` is set from the user's answer in Step 5 if they filled it in, otherwise left as placeholder.

## Step 7: Commit

```bash
git add "$STACK_NAME/" catalog.md
git commit -m "feat: create $STACK_NAME stack"
```

Report: "Stack '$STACK_NAME' created. Drop sources in $STACK_NAME/sources/incoming/ and run /stacks:ingest $STACK_NAME to build topic guides."
