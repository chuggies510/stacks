---
name: lookup
description: |
  Use when the user needs to look up domain knowledge from their knowledge
  library. Works from any repo. Reads the stacks config to find the library,
  searches the catalog and indexes, and synthesizes an answer from articles.
  Examples: "/stacks:lookup how do VAV systems work", "/stacks:lookup mep chilled water sizing".
---

# Lookup

Query knowledge stacks from any repo.

## Step 0: Telemetry

```bash
STACKS_ROOT="$CLAUDE_PLUGIN_ROOT"
SKILL_NAME="stacks:lookup" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
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

```bash
QUERY=$(echo "$ARGUMENTS" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
```

Resolve `STACKS_TO_SEARCH` from catalog.md:

```bash
mapfile -t STACKS_TO_SEARCH < <(
  grep '^- \[' "$LIBRARY/catalog.md" \
  | sed 's|.*\[\([^]]*\)\](\([^/]*\)/).*|\2|'
)
[[ ${#STACKS_TO_SEARCH[@]} -gt 0 ]] \
  || { echo "No stacks found in catalog.md — run /stacks:new-stack first."; exit 1; }
```

## Step 4: Hop-1 — narrow to matching stacks

<!-- Retrieval contract: input = (QUERY, catalog.md descriptions loaded in Step 2,
     STACKS_TO_SEARCH from Step 3).
     Output = STACKS_TO_SEARCH narrowed to 1-3 stacks whose domain matches the query. -->

Do the Hop-1 recognition pass now:

Read the catalog.md descriptions you already loaded in Step 2. Each stack entry has a name and a description of its domain (what topics, questions, and concepts it covers). Match the **query's meaning** against those descriptions — not keyword overlap, but whether the stack's domain is the right place to answer this question.

Decision rules:
- **Single-domain query**: pick 1 stack. Default narrow: if one stack clearly owns the domain, select only that one.
- **Cross-domain query** (the query genuinely spans two or more distinct domains, e.g. "how does AI apply to building controls"): widen to 2-3 stacks.
- Do not open stacks whose domain is unrelated to the query even if they share incidental words (e.g. a query about LLM tuning should not pull in HVAC stacks because HVAC sources mention "controls").

Rewrite `STACKS_TO_SEARCH` to contain only the selected stack name(s) before proceeding.

## Step 5: Read the routing map for all stacks in scope

For each stack in `STACKS_TO_SEARCH`:
- Read `$LIBRARY/{stack}/index.md`. If it does not exist, note the stack as "no index yet" and skip it.
- The `## Articles` section is the routing map: `- [[slug|title]] — {routing line}`, where the routing line says what the article covers and the questions it answers (#59). This is the recognition surface for Step 6.
- Capture any `## Reading Paths` section as supplementary retrieval context.

If all stacks were skipped (none had an index), tell the user to run `/stacks:catalog-sources` in the library repo.

## Step 6: Recognize matching articles across stacks

<!-- Retrieval contract: input = (QUERY, the routing maps read in Step 5).
     Output = the article paths whose routing line matches the query; Step 7
     synthesis depends only on those. -->

From the `## Articles` routing lines you read in Step 5, select every article whose routing line (or title) matches the query's intent. The routing line is written in an asker's words, so match on meaning, not just shared tokens. Take as many as genuinely match — do not pad to a fixed count, and do not cap a broad question at a few when more are on-topic.

Read the selected article files. If recognition found nothing, tell the user: "No matching content found in stacks: {STACKS_TO_SEARCH[*]}." and stop — do not synthesize from nothing.

## Step 7: Synthesize answer

Using the article content, synthesize an answer to the user's query.

Requirements:
- Cite which article(s) the answer comes from (by title, not path)
- Include specific data points, formulas, rules of thumb, and field notes from the articles
- If the articles don't fully answer the question, say what's missing
- Do not invent information beyond what the articles contain

**Collect primary sources.** Before formatting the response, gather the vera base sources from every article read. Each article has a `sources:` frontmatter list of relative paths (e.g. `swe/sources/fowler-bliki/fowler-harness-engineering.md`). For each unique path, read the first 8 lines of `$LIBRARY/{path}` and extract:
- The H1 heading (title of the original publication)
- `Source:` line (URL)
- `Author:` line (if present)
- `Date:` line (if present)

Deduplicate across articles. Skip sources whose path contains `liminal`, `field-notes`, or `internal` — those are private session notes, not citable publications. Include everything else regardless of tier, as long as a URL exists.

Format the response as:
```
## Answer

{synthesized answer with specific citations inline}

**Library articles**: {article titles that contributed}
**Stack**: {stack name(s) that contributed — use singular "Stack" if only one}

**Primary sources:**
- {Author}, "{Title}", {date} — {URL}
- {repeat per unique citable source}
```

If no relevant articles are found: "No matching articles found in {stack}. The stack covers: {list article titles from index.md}. Consider adding sources and running /stacks:catalog-sources {stack}."

## Step 8: Offer to file the result back (opt-in)

Valuable answers can compound into the library rather than disappearing into chat history. Filing is **opt-in**: never write or commit an article without the user's go-ahead. After delivering the answer, assess whether filing is worth offering:

**Worth offering if the answer:**
- Synthesized something non-obvious across multiple topics (the synthesis didn't exist as a single place before)
- Resolved a contradiction or ambiguity between articles
- Produced a comparison or decision table that would be useful again
- Revealed a gap that is now partially answered by the synthesis itself

**Not worth offering if the answer:**
- Simply restated what one existing article already says clearly
- Was a lookup that required no synthesis
- Is ephemeral context specific to the current task

If it's worth offering, ask the user once — name the target stack(s) and whether it would extend an existing article or create a new one, e.g.: *"This synthesizes X across {stacks}. File it? (extend `{slug}` / new article `{slug}` / skip)"*. Do nothing further unless the user opts in. On skip (or no response), stop here — the answer was already delivered.

If the user opts in, file to the chosen stack(s):

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
   routing: <one line — what this article covers and the questions it answers, in an asker's words>
   tags:
     - <tag>
   ---
   ```
   Body follows the 300-800 word target with inline `[source-slug]` citations. Do not add `[VERIFIED]` / `[DRIFT]` / `[UNSOURCED]` / `[STALE]` marks. Add the new entry to `$LIBRARY/{stack}/index.md` under the Articles list as `- [[slug|title]] — {routing}` (keep alphabetical).

**After each stack filed:**

Update `$LIBRARY/{stack}/log.md`, prepending:
```
## [YYYY-MM-DD] query | "{short query summary}" → filed to {target}
Synthesized answer filed. {new | updated} article: {slug}.
```

**After all chosen stacks are filed** (only reached because the user opted in above):

```bash
cd "$LIBRARY" && git add . && git commit -m "feat: file query result — {short description}"
```
