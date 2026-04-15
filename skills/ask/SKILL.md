---
name: ask
description: |
  Use when the user needs to look up domain knowledge from their knowledge
  library. Works from any repo. Reads the stacks config to find the library,
  searches the catalog and indexes, and synthesizes an answer from topic guides.
  Examples: "/stacks:ask how do VAV systems work", "/stacks:ask mep chilled water sizing".
---

# Lookup

Query knowledge stacks from any repo.

## Step 0: Telemetry

```bash
TELEMETRY_SH=$(find ~/.claude/plugins/cache -name telemetry.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
if [[ -z "$TELEMETRY_SH" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  TELEMETRY_SH="$STACKS_ROOT/scripts/telemetry.sh"
fi
SKILL_NAME="stacks:ask" bash "$TELEMETRY_SH" 2>/dev/null || true
```

## Step 1: Find the library

```bash
CONFIG="$HOME/.config/stacks/config.json"
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: No stacks config found at $CONFIG"
  echo "Run /stacks:init-library to create a library first."
  exit 1
fi
LIBRARY=$(jq -r '.library // empty' "$CONFIG")
LIBRARY="${LIBRARY/#\~/$HOME}"
if [[ -z "$LIBRARY" || ! -d "$LIBRARY" ]]; then
  echo "ERROR: Library not found at '$LIBRARY'"
  echo "Update $CONFIG or run /stacks:init-library to create a library."
  exit 1
fi
echo "Library: $LIBRARY"
```

## Step 2: Read the catalog

Read `$LIBRARY/catalog.md`. This lists all available stacks with names, descriptions, and counts.

If catalog.md contains no stack entries (no lines starting with `- [`), tell the user: "No stacks in your library yet. Run /stacks:new-stack from your library repo to create one."

## Step 3: Parse the query

`$ARGUMENTS` contains the full query text.

Check if the first word of `$ARGUMENTS` matches an existing stack directory:

```bash
FIRST_WORD=$(echo "$ARGUMENTS" | awk '{print $1}')
if [[ -d "$LIBRARY/$FIRST_WORD" ]]; then
  STACK="$FIRST_WORD"
  QUERY=$(echo "$ARGUMENTS" | cut -d' ' -f2-)
else
  STACK=""
  QUERY="$ARGUMENTS"
fi
```

If `STACK` is empty, read the catalog descriptions and use semantic reasoning to pick the best matching stack for the query. If no good match, list stacks and ask the user which to use.

## Step 4: Read the stack index

Read `$LIBRARY/{stack}/index.md`. It has two sections:
- **Topics**: list of topic guides with descriptions
- **Sources**: list of ingested sources

If `$LIBRARY/{stack}/index.md` does not exist, tell the user: "Stack `{stack}` has no index yet — it may be newly created. Run /stacks:ingest-sources {stack} from your library repo to populate it." Then stop.

Match the query against topic names and descriptions to identify the 1-3 most relevant topics. Use this preference order: (1) exact keyword match against topic names first, (2) keyword match against topic descriptions, (3) semantic reasoning when no exact matches exist. When multiple topics score similarly, prefer narrower topics over broad overview topics.

If the index is empty (no topics yet), tell the user: "Stack '{stack}' has no topics yet. Run /stacks:ingest-sources {stack} from your library repo first."

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

If no relevant topics are found: "No matching topics found in {stack}. The stack covers: {list topic names from index.md}. Consider adding sources and running /stacks:ingest-sources {stack}."

## Step 7: File result back (Karpathy loop)

Valuable answers compound into the library rather than disappearing into chat history. After delivering the answer, assess whether it should be filed:

**File the result if the answer:**
- Synthesized something non-obvious across multiple topics (the synthesis didn't exist as a single place before)
- Resolved a contradiction or ambiguity between guides
- Produced a comparison or decision table that would be useful again
- Revealed a gap that is now partially answered by the synthesis itself

**Do not file if the answer:**
- Simply restated what one existing guide already says clearly
- Was a lookup that required no synthesis
- Is ephemeral context specific to the current task

If the answer warrants filing, ask: "File this answer into the {stack} stack? (yes/no)"

If yes:

1. Determine whether it fits an existing topic (extends a guide) or is genuinely new (needs its own guide).

2. **Extends existing topic:** append the synthesized content to the relevant `$LIBRARY/{stack}/topics/{topic}/guide.md` under the appropriate section. Increment the `sources` frontmatter count if new source material was drawn in.

3. **New topic:** create `$LIBRARY/{stack}/topics/{slug}/guide.md` using the topic template from `$LIBRARY/{stack}/STACK.md`. Populate it from the synthesized answer. Add it to `$LIBRARY/{stack}/index.md` Topics table.

4. Update `$LIBRARY/{stack}/log.md`, prepending:
   ```
   ## [YYYY-MM-DD] query | "{short query summary}" → filed to {topic}
   Synthesized answer filed. {new | updated} topic: {topic-slug}.
   ```

5. Commit:
   ```bash
   cd "$LIBRARY" && git add "{stack}/" && git commit -m "feat({stack}): file query result — {short description}"
   ```
