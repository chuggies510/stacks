# Library CLAUDE.md

## What This Is

This is a knowledge library managed by the stacks plugin. It contains one or more
knowledge collections ("stacks"), each with curated sources and LLM-synthesized
topic guides.

## Session Start

After `/workspace-toolkit:start` runs, always do the following before asking what to work on:

**1. Enumerate stacks:**
```bash
find . -maxdepth 1 -name "*.md" -path "./*" 2>/dev/null | head -0  # dummy
STACKS=$(find . -maxdepth 1 -type d ! -name ".*" ! -name "dev" | sort | xargs -I{} sh -c '[ -f "{}/STACK.md" ] && echo "{}"' 2>/dev/null)
for STACK in $STACKS; do
  NAME=$(basename "$STACK")
  ARTICLES=$(find "$STACK/articles" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  SOURCES=$(find "$STACK/sources" -type f ! -name ".gitkeep" ! -path "*/incoming/*" 2>/dev/null | wc -l | tr -d ' ')
  INCOMING=$(find "$STACK/sources/incoming" -type f ! -name ".gitkeep" 2>/dev/null | wc -l | tr -d ' ')
  echo "stack=$NAME articles=$ARTICLES sources=$SOURCES incoming=$INCOMING"
done
```

**2. Display a stacks summary block:**

```
Stacks in this library:
  {name}  —  {N} articles, {N} sources filed  [INCOMING: N] if incoming > 0

Available commands:
  /stacks:new-stack {name}          scaffold a new stack
  /stacks:catalog-sources {stack}  process sources into article-per-concept wiki entries
  /stacks:audit-stack {stack}      validate articles, find gaps, suggest research
  /stacks:ask "{query}"            query this library from any repo

Next: {derive from state}
```

Derive "Next" from state:
- No stacks: "Run `/stacks:new-stack {name}` to create your first stack."
- Stack exists, no articles, no incoming: "Drop sources in `{stack}/sources/incoming/`, then run `/stacks:catalog-sources {stack}`."
- Stack has incoming sources: "Run `/stacks:catalog-sources {stack}` to process {N} queued source(s)."
- Stack has articles, no incoming: "Run `/stacks:audit-stack {stack}` to check coverage and find gaps."

## Conventions

- **Sources are immutable.** Drop raw material in `{stack}/sources/incoming/`.
  The catalog process files them by origin and synthesizes knowledge into article-per-concept wiki entries.
- **Articles are LLM-maintained.** Do not hand-edit article files. Use `/stacks:catalog-sources`
  to update them from sources.
- **index.md is the stack index.** Each stack's index.md lists all sources and articles
  for that stack. catalog-sources regenerates it. Do not edit manually.
- **log.md is append-only.** Records what operations happened and when.
- **STACK.md is the schema.** Defines source hierarchy, topic template, and filing
  rules for that stack. Edit this to change how the stack is curated.
