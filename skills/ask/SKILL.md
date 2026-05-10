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
# -- REPLACE-WITH-QMD when #10 lands: this bash enumeration is the stub.
# The qmd implementation accepts (query, stacks_to_search[]) and returns
# (article_path, stack_name)[] ranked by score — replace Step 5 article-mode body only.
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

<!-- STACKS-SEARCH STUB — replace this block when #10 (qmd) lands.
     Contract: input = (QUERY, STACKS_TO_SEARCH[], per-stack article dirs)
     Output = up to 3 (article_path, stack_name) pairs ranked by relevance.
     The answer synthesis in Step 6 depends only on these pairs. -->

Check whether each stack in `STACKS_TO_SEARCH` is in article mode or guide mode:

```bash
for stack in "${STACKS_TO_SEARCH[@]}"; do
  if find "$LIBRARY/$stack/articles" -maxdepth 1 -name '*.md' 2>/dev/null | grep -q .; then
    echo "article $stack"
  else
    echo "guide $stack"
  fi
done
```

**Article mode stacks** (those where `articles/` exists and has `.md` files):

Score articles across ALL article-mode stacks together. For each article, weight matches in this order:
1. `title` frontmatter field — highest weight
2. `tags[]` frontmatter field — high weight
3. Article slug (filename without `.md`) — medium weight
4. Reading Paths context from Step 4 — contextual aid

Select the top 3 articles globally (across all stacks). Read each article file. Track which stack each article came from.

**Guide mode stacks** (those without `articles/`):

Score guides from all guide-mode stacks together using the same weighting. Select top 3 guides globally. Track which stack each guide came from.

**Mixed case** (some stacks article mode, some guide mode):

Score article-mode and guide-mode results separately, then interleave by relevance score. Cap at 3 total.

If no matches found across any stack in scope: "No matching content found in stacks: {STACKS_TO_SEARCH[*]}."

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
**Stacks**: {stack name(s) that contributed — use singular "Stack" if only one}
```

If no relevant topics are found: "No matching topics found in {stack}. The stack covers: {list topic names from index.md}. Consider adding sources and running /stacks:catalog-sources {stack}."

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

If the answer warrants filing, proceed as follows:

**Determine the filing target.** If results came from a single stack, file there. If results came from multiple stacks, ask: "File this answer to: {list of contributing stacks}, all of them, or skip?"

For each chosen stack, run the filing branch for that stack independently using that stack's mode (article or guide — determined in Step 5 by whether `$LIBRARY/{stack}/articles/` exists and has files).

For each chosen stack:

**Article mode** (stack has `articles/` with files):

1. Determine whether the answer extends an existing article (a concept already covered, but the synthesis adds material the article does not have) or is a new concept that needs its own article.

2. **Extends existing article:** read `$LIBRARY/{stack}/articles/{slug}.md`, append the synthesized material under an appropriate heading, merge any new source paths into the `sources:` frontmatter list, set `updated: <today>` and `last_verified: ""` (forces revalidation on the next audit). Use inline `[source-slug]` citations to match the article convention. Do not write `[[wikilinks]]` — the next `/stacks:audit-stack` wikilink pass handles those.

3. **New article:** create `$LIBRARY/{stack}/articles/{slug}.md` with this frontmatter:
   ```yaml
   ---
   extraction_hash: ""
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

**Guide mode** (stack has no `articles/`):

1. Determine whether it fits an existing topic (extends a guide) or is genuinely new.

2. **Extends existing topic:** append the synthesized content to `$LIBRARY/{stack}/topics/{topic}/guide.md` under the appropriate section.

3. **New topic:** create `$LIBRARY/{stack}/topics/{slug}/guide.md` using the topic template from `$LIBRARY/{stack}/STACK.md`. Add to `$LIBRARY/{stack}/index.md` Topics table.

**After each stack filed:**

Update `$LIBRARY/{stack}/log.md`, prepending:
```
## [YYYY-MM-DD] query | "{short query summary}" → filed to {target}
Synthesized answer filed. {new | updated} {article|topic}: {slug}.
```

**After all chosen stacks are filed:**

```bash
cd "$LIBRARY" && git add . && git commit -m "feat: file query result — {short description}"
```
