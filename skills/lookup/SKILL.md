---
name: lookup
description: |
  Use when the user needs to look up domain knowledge from their knowledge
  library. Works from any repo. Reads the stacks config to find the library,
  searches the catalog and indexes, and synthesizes an answer from topic guides.
  Examples: "/stacks:lookup how do VAV systems work", "/stacks:lookup mep chilled water sizing".
---

# Lookup

Query knowledge stacks from any repo.

## Step 0: Telemetry

```bash
TELEMETRY_SH=$(find ~/.claude/plugins/cache -name telemetry.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
if [[ -z "$TELEMETRY_SH" ]]; then
  STACKS_ROOT=$(jq -r '.pluginPaths["stacks@local"] // empty' ~/.claude/settings.json 2>/dev/null)
  TELEMETRY_SH="$STACKS_ROOT/scripts/telemetry.sh"
fi
SKILL_NAME="stacks:lookup" bash "$TELEMETRY_SH" 2>/dev/null || true
```

## Step 1: Find the library

```bash
CONFIG="$HOME/.config/stacks/config.json"
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: No stacks config found at $CONFIG"
  echo "Run 'bash path/to/stacks/scripts/install.sh' first."
  exit 1
fi
LIBRARY=$(jq -r '.library // empty' "$CONFIG")
LIBRARY="${LIBRARY/#\~/$HOME}"
if [[ -z "$LIBRARY" || ! -d "$LIBRARY" ]]; then
  echo "ERROR: Library not found at '$LIBRARY'"
  echo "Update $CONFIG or run init.sh to create a library."
  exit 1
fi
echo "Library: $LIBRARY"
```

## Step 2: Read the catalog

Read `$LIBRARY/catalog.md`. This lists all available stacks with names, descriptions, and counts.

If the catalog has no stacks (only the placeholder text), tell the user: "No stacks in your library yet. Run /stacks:new from your library repo to create one."

## Step 3: Parse the query

`$ARGUMENTS` contains the full query text. Two formats:

- `{stack-name} {query}` — if the first word matches a directory in `$LIBRARY`, use that stack and the rest as the query
- `{query}` — treat the entire argument as a query; match against catalog descriptions to select the best stack

If no stack can be matched, list available stacks and ask the user which to search.

## Step 4: Read the stack index

Read `$LIBRARY/{stack}/index.md`. It has two sections:
- **Topics**: list of topic guides with descriptions
- **Sources**: list of ingested sources

Match the query against topic names and descriptions to identify the 1-3 most relevant topics.

If the index is empty (no topics yet), tell the user: "Stack '{stack}' has no topics yet. Run /stacks:ingest {stack} from your library repo first."

## Step 5: Read topic guides

Read the matched topic guide files at `$LIBRARY/{stack}/topics/{topic}/guide.md`.

Read up to 3 guides. If only one matches, read just that one. If more than 3 match, pick the 3 with the closest relevance to the query.

## Step 6: Synthesize answer

Using the topic guide content, synthesize an answer to the user's query.

Requirements:
- Cite which topic guide(s) the answer comes from (by name, not path)
- Include specific data points, formulas, rules of thumb, and field notes from the guides
- If the guides don't fully answer the question, say what's missing
- Do not invent information beyond what the guides contain

Format the response as:
```
## Answer

{synthesized answer with specific citations inline}

**Sources**: {topic guide names that contributed}
**Stack**: {stack name}
```

If no relevant topics are found: "No matching topics found in {stack}. The stack covers: {list topic names from index.md}. Consider adding sources and running /stacks:ingest {stack}."
