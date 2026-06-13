---
name: ask
description: |
  Use when the user needs to look up domain knowledge from their knowledge
  library. Works from any repo. Reads the stacks config to find the library,
  searches the catalog and indexes, and synthesizes an answer from articles.
  Examples: "/stacks:ask how do VAV systems work", "/stacks:ask mep chilled water sizing".
---

# Lookup

Query knowledge stacks from any repo.

## Step 0: Telemetry

```bash
LOCATE=$(find ~/.claude/plugins/cache -name locate-plugin-root.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
[[ -z "$LOCATE" ]] && LOCATE="$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)/scripts/locate-plugin-root.sh"
STACKS_ROOT=$(bash "$LOCATE" 2>/dev/null)
SKILL_NAME="stacks:ask" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
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

## Step 3: Parse the query and resolve stack scope

`$ARGUMENTS` contains the full query text. Parse flags before extracting the query:

```bash
RAW="$ARGUMENTS"
STACK_SINGLE=""
STACKS_MULTI=""

# Extract --stack {name}
if [[ "$RAW" == *"--stack "* ]]; then
  STACK_SINGLE=$(echo "$RAW" | sed 's/.*--stack[[:space:]]*//' | awk '{print $1}')
  RAW=$(echo "$RAW" | sed "s/--stack[[:space:]]*${STACK_SINGLE}//")
fi

# Extract --stacks {a,b,c}
if [[ "$RAW" == *"--stacks "* ]]; then
  STACKS_MULTI=$(echo "$RAW" | sed 's/.*--stacks[[:space:]]*//' | awk '{print $1}')
  RAW=$(echo "$RAW" | sed "s/--stacks[[:space:]]*${STACKS_MULTI}//")
fi

QUERY=$(echo "$RAW" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
```

Resolve `STACKS_TO_SEARCH` — the list of stack names to search:

```bash
if [[ -n "$STACK_SINGLE" ]]; then
  [[ -d "$LIBRARY/$STACK_SINGLE" ]] || { echo "ERROR: stack '$STACK_SINGLE' not found"; exit 1; }
  STACKS_TO_SEARCH=("$STACK_SINGLE")
elif [[ -n "$STACKS_MULTI" ]]; then
  IFS=',' read -ra _RAW_STACKS <<< "$STACKS_MULTI"
  STACKS_TO_SEARCH=()
  for s in "${_RAW_STACKS[@]}"; do
    s="${s//[[:space:]]/}"
    [[ -n "$s" ]] || continue
    [[ -d "$LIBRARY/$s" ]] || { echo "ERROR: stack '$s' not found"; exit 1; }
    STACKS_TO_SEARCH+=("$s")
  done
else
  # Default: all stacks from catalog.md
  mapfile -t STACKS_TO_SEARCH < <(
    grep '^- \[' "$LIBRARY/catalog.md" \
    | sed 's|.*\[\([^]]*\)\](\([^/]*\)/).*|\2|'
  )
  [[ ${#STACKS_TO_SEARCH[@]} -gt 0 ]] \
    || { echo "No stacks found in catalog.md — run /stacks:new-stack first."; exit 1; }
fi
```

## Step 4: Read indexes for all stacks in scope

For each stack in `STACKS_TO_SEARCH`:
- Read `$LIBRARY/{stack}/index.md`. If it does not exist, note the stack as "no index yet" and skip it.
- Capture any `## Reading Paths` section as retrieval context for that stack.

If all stacks were skipped (none had an index), tell the user to run `/stacks:catalog-sources` in the library repo.

## Step 5: Retrieve matching articles across stacks

<!-- Retrieval contract: input = (QUERY, STACKS_TO_SEARCH[], per-stack article dirs)
     Output = up to 3 article paths ranked by relevance; Step 6 synthesis depends
     only on those. rank-articles.sh searches whole article BODIES, not just
     frontmatter — title-only matching missed body content, the wall past a few
     dozen articles (#10). qmd's vector search is the future escalation, for
     queries that miss on pure semantic synonyms keyword grep can't catch. -->

Rank articles across all stacks in scope by keyword match over the whole file (body included), highest score first. Pass one `articles/` dir per stack:

```bash
ARTICLE_DIRS=()
for s in "${STACKS_TO_SEARCH[@]}"; do
  [[ -d "$LIBRARY/$s/articles" ]] && ARTICLE_DIRS+=("$LIBRARY/$s/articles")
done
RANKED=$(bash "$STACKS_ROOT/scripts/rank-articles.sh" 3 "$QUERY" "${ARTICLE_DIRS[@]}")
echo "$RANKED"
```

Each output line is `<score><TAB><path>`. Read each ranked article file (top 3); the stack name is the directory two levels above the file (`{stack}/articles/{slug}.md`). Use the `## Reading Paths` context from Step 4 as a tie-breaker / supplementary pointer when scores are close.

If `RANKED` is empty (no article scored), tell the user: "No matching content found in stacks: {STACKS_TO_SEARCH[*]}." and stop — do not synthesize from nothing.

## Step 6: Synthesize answer

Using the article content, synthesize an answer to the user's query.

Requirements:
- Cite which article(s) the answer comes from (by title, not path)
- Include specific data points, formulas, rules of thumb, and field notes from the articles
- If the articles don't fully answer the question, say what's missing
- Do not invent information beyond what the articles contain

Format the response as:
```
## Answer

{synthesized answer with specific citations inline}

**Sources**: {article titles that contributed}
**Stacks**: {stack name(s) that contributed — use singular "Stack" if only one}
```

If no relevant articles are found: "No matching articles found in {stack}. The stack covers: {list article titles from index.md}. Consider adding sources and running /stacks:catalog-sources {stack}."

## Step 7: File result back (Karpathy loop)

Valuable answers compound into the library rather than disappearing into chat history. After delivering the answer, assess whether it should be filed:

**File the result if the answer:**
- Synthesized something non-obvious across multiple topics (the synthesis didn't exist as a single place before)
- Resolved a contradiction or ambiguity between articles
- Produced a comparison or decision table that would be useful again
- Revealed a gap that is now partially answered by the synthesis itself

**Do not file if the answer:**
- Simply restated what one existing article already says clearly
- Was a lookup that required no synthesis
- Is ephemeral context specific to the current task

If the answer warrants filing, proceed as follows:

**Determine the filing target.** If results came from a single stack, file there. If results came from multiple stacks, ask: "File this answer to: {list of contributing stacks}, all of them, or skip?"

For each chosen stack:

1. Determine whether the answer extends an existing article (a concept already covered, but the synthesis adds material the article does not have) or is a new concept that needs its own article.

2. **Extends existing article:** read `$LIBRARY/{stack}/articles/{slug}.md`, append the synthesized material under an appropriate heading, merge any new source paths into the `sources:` frontmatter list, set `updated: <today>` and `last_verified: ""` (forces revalidation on the next audit). Use inline `[source-slug]` citations to match the article convention.

3. **New article:** create `$LIBRARY/{stack}/articles/{slug}.md` with this frontmatter:
   ```yaml
   ---
   last_verified: ""
   updated: <YYYY-MM-DD today>
   sources:
     - <path/to/source1.md>
   title: <human-readable title>
   tags:
     - <tag>
   ---
   ```
   Body follows the 300-800 word target with inline `[source-slug]` citations. Do not add `[VERIFIED]` / `[DRIFT]` / `[UNSOURCED]` / `[STALE]` marks. Add the new entry to `$LIBRARY/{stack}/index.md` under the Articles list (keep alphabetical).

**After each stack filed:**

Update `$LIBRARY/{stack}/log.md`, prepending:
```
## [YYYY-MM-DD] query | "{short query summary}" → filed to {target}
Synthesized answer filed. {new | updated} article: {slug}.
```

**After all chosen stacks are filed:**

```bash
cd "$LIBRARY" && git add . && git commit -m "feat: file query result — {short description}"
```
