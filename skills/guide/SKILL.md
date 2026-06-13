---
name: guide
description: |
  Use when the user wants a long-form synthesized guide on a topic from their
  knowledge library. Retrieves relevant articles across stacks and writes a
  structured guide to library/guides/{slug}.md. Supports --stacks to scope to
  specific stacks and --regenerate to rebuild an existing guide.
  Examples: "/stacks:guide 'HVAC building electrification'",
  "/stacks:guide 'Svelte runes' --stacks svelte",
  "/stacks:guide 'schema migration' --regenerate".
---

# Guide Synthesis

Generate a long-form guide from library articles.

## Step 0: Telemetry

```bash
LOCATE=$(find ~/.claude/plugins/cache -name locate-plugin-root.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
[[ -z "$LOCATE" ]] && LOCATE="$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)/scripts/locate-plugin-root.sh"
STACKS_ROOT=$(bash "$LOCATE" 2>/dev/null)
SKILL_NAME="stacks:guide" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

## Step 1: Find the library

```bash
CONFIG="$HOME/.config/stacks/config.json"
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: No stacks config found at $CONFIG. Run /stacks:init-library first."
  exit 1
fi
LIBRARY=$(jq -r '.library // empty' "$CONFIG")
LIBRARY="${LIBRARY/#\~/$HOME}"
if [[ -z "$LIBRARY" || ! -d "$LIBRARY" ]]; then
  echo "ERROR: Library not found at '$LIBRARY'."
  exit 1
fi
```

## Step 2: Parse arguments

`$ARGUMENTS` contains the full argument string. Parse flags before extracting the topic:

```bash
RAW="$ARGUMENTS"
STACKS_FILTER=""
REGENERATE=0

if [[ "$RAW" == *"--regenerate"* ]]; then
  REGENERATE=1
  RAW="${RAW//--regenerate/}"
fi

if [[ "$RAW" == *"--stacks "* ]]; then
  STACKS_FILTER=$(echo "$RAW" | sed 's/.*--stacks[[:space:]]*//' | awk '{print $1}')
  RAW=$(echo "$RAW" | sed "s/--stacks[[:space:]]*${STACKS_FILTER}//")
fi

# Strip surrounding quotes from topic
TOPIC=$(echo "$RAW" | sed "s/^['\"]//;s/['\"]$//" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

if [[ -z "$TOPIC" ]]; then
  echo "ERROR: Topic required. Example: /stacks:guide 'HVAC building electrification'"
  exit 1
fi

# Compute slug from topic
SLUG=$(echo "$TOPIC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
```

## Step 3: Check for existing guide

```bash
GUIDE_PATH="$LIBRARY/guides/${SLUG}.md"
mkdir -p "$LIBRARY/guides"
```

If `$GUIDE_PATH` exists and `REGENERATE=0`:
- Read the guide and display its content to the user
- Tell the user: "Existing guide found (generated: {date from frontmatter}). Displaying it below. Use `/stacks:guide --regenerate '{TOPIC}'` to rebuild from current articles."
- Stop.

If `$GUIDE_PATH` exists and `REGENERATE=1`: continue to Step 4 (will overwrite).

## Step 4: Resolve stack scope

Read `$LIBRARY/catalog.md`. Resolve `STACKS_TO_SEARCH`:

```bash
if [[ -n "$STACKS_FILTER" ]]; then
  IFS=',' read -ra _RAW <<< "$STACKS_FILTER"
  STACKS_TO_SEARCH=()
  for s in "${_RAW[@]}"; do
    s="${s//[[:space:]]/}"
    [[ -n "$s" ]] || continue
    [[ -d "$LIBRARY/$s" ]] || { echo "ERROR: stack '$s' not found"; exit 1; }
    STACKS_TO_SEARCH+=("$s")
  done
else
  mapfile -t STACKS_TO_SEARCH < <(
    grep '^- \[' "$LIBRARY/catalog.md" \
    | sed 's|.*\[\([^]]*\)\](\([^/]*\)/).*|\2|'
  )
  [[ ${#STACKS_TO_SEARCH[@]} -gt 0 ]] \
    || { echo "No stacks in catalog.md — run /stacks:new-stack first."; exit 1; }
fi
```

## Step 5: Load indexes and score articles

For each stack in `STACKS_TO_SEARCH`:
- Read `$LIBRARY/{stack}/index.md`. If it doesn't exist, note "no index yet" and skip.
- Capture any Reading Paths or Topics section as retrieval context.

Score articles across all stacks by topic relevance:
1. `title` frontmatter — highest weight
2. `tags[]` — high weight
3. Slug (filename without `.md`) — medium weight
4. Reading Paths / Topics sections from index — contextual aid

For guide synthesis, collect the top **10** articles globally (not capped at 3 like /stacks:ask — guides benefit from more source material). Track stack attribution for each. Note articles that were candidates but below threshold in an EXCLUDED list.

Read each selected article file.

If no relevant articles found: "No articles matched '{TOPIC}' in stacks: {STACKS_TO_SEARCH[*]}. Run /stacks:catalog-sources to process pending sources."

## Step 6: Record article commit SHAs

For each included article, capture its current commit SHA:

```bash
for article_path in "${INCLUDED_ARTICLES[@]}"; do
  sha=$(git -C "$LIBRARY" log -1 --format="%H" -- "$article_path" 2>/dev/null || echo "")
  # store (stack_name, relative_path, sha) as a tuple
done
```

## Step 7: Synthesize guide

Using all selected article content, synthesize a structured guide. Requirements:
- Open with an Overview that defines the topic and states its scope
- Sections appropriate to the topic; for technical topics use: Overview, Key Concepts, Patterns, Pitfalls, Field Notes, Sources
- Specific data points, formulas, rules of thumb, and failure modes drawn from articles
- Inline `[article-slug]` citations on every non-obvious claim
- 800-2000 words (longer than an article, shorter than a book chapter)

## Step 8: Write guide to library

Write `$LIBRARY/guides/${SLUG}.md`:

Frontmatter:
```yaml
---
topic: "{TOPIC}"
generated: {YYYY-MM-DD today}
stacks:
  - {contributing stack name}
articles:
  - stack: {stack-name}
    path: {relative path from library root}
    sha: {commit sha}
excluded:
  - path: {relative path}
    reason: {reason for exclusion}
---
```

Body: the synthesized guide from Step 7.

## Step 9: Update log.md for contributing stacks

For each stack that contributed articles, prepend to `$LIBRARY/{stack}/log.md`:

```
## [YYYY-MM-DD] guide | "{TOPIC}" → guides/{SLUG}.md
Contributed {N} article(s) to guide synthesis.
```

## Step 10: Commit and report

```bash
cd "$LIBRARY"
git add guides/ {each contributing stack}/log.md
git commit -m "feat: synthesize guide — {SLUG}"
```

Report to user:
```
## Guide Complete

Topic: {TOPIC}
Written to: guides/{SLUG}.md
Sources: {N} articles from {stacks}

Run /stacks:guide --regenerate '{TOPIC}' to refresh after new sources are cataloged.
```
