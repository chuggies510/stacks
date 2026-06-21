---
name: lookup
description: |
  Use when the user needs to look up domain knowledge from their knowledge
  library. Works from any repo. Reads the stacks config to find the library,
  searches the catalog and indexes, and synthesizes an answer from articles.
  Examples: "/stacks:lookup how do VAV systems work", "/stacks:lookup mep chilled water sizing".
---

# Lookup

Query knowledge stacks from any repo. Step 8 records the lookup once the answer is delivered.

## Step 1: Find the library

```bash
STACKS_ROOT="$CLAUDE_PLUGIN_ROOT"
LIBRARY=$(bash "$STACKS_ROOT/scripts/resolve-library.sh") || exit 1
echo "Library: $LIBRARY"
```

`resolve-library.sh` reads `$STACKS_CONFIG` (or `~/.config/stacks/config.json`)
for `.library`, and falls back to the current directory when it is itself a
library (has `catalog.md`). It prints a fix hint and exits non-zero when no
library can be found.

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

Read the selected article files. If recognition found nothing (a **miss**), do not synthesize from nothing here — instead run Step 8 to log the miss, then go to **Step 9 (auto-enrich on a miss)**, which researches the gap and retries. Only if Step 9 is not applicable (no stack matched in Hop-1, or it stages nothing) do you tell the user: "No matching content found in stacks: {STACKS_TO_SEARCH[*]}."

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

## Step 8: Record the lookup

Log this lookup to telemetry — what was asked and which articles answered it. This single record is both the usage count and the query log, so it replaces the old bare counter. Run it after delivering the answer, **whether or not articles were found** (a miss is signal: it flags a gap to fill).

Substitute the placeholders below (comma-separated). The query comes from `$ARGUMENTS`:

- `stacks` — the stack(s) you searched after Hop-1 narrowing (Step 4). **Populate this even on a miss** — a miss in stack X means "X was the right domain but had no article", which is exactly the gap `lookup-misses.sh` mines and `enrich-stack` closes. Leave empty only when Hop-1 matched no stack at all.
- `articles` — the article title(s) that contributed to the answer; **empty on a miss**. `articles == ""` (with `stacks` populated) is the miss signal downstream.

```bash
STACKS_ROOT="$CLAUDE_PLUGIN_ROOT"
TELEMETRY_EXTRA="$(jq -cn \
  --arg query "$ARGUMENTS" \
  --arg stacks '<stack(s) searched after Hop-1, comma-separated; empty only if no stack matched>' \
  --arg articles '<contributing article title(s), comma-separated; empty on a miss>' \
  '{query: $query, stacks: $stacks, articles: $articles}')" \
SKILL_NAME="stacks:lookup" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

<!-- ponytail: one telemetry line per lookup = the usage count AND the query log.
     A run that ends early can still skip this step; guaranteed capture would need a
     PreToolUse/UserPromptSubmit hook, which is overkill for usage stats. Add the hook
     only if skipped lookups become a real gap. -->

## Step 9: Auto-enrich on a miss (hands-free, #69)

**Only on a miss** (Step 6 found no matching article). On a hit, skip to Step 10.

A miss is live demand the library could not meet. Instead of stopping, lookup
researches the gap and retries — in one command, no second invocation. The miss
was just logged in Step 8, so the enrich pass picks it up from telemetry.

**Applicability gate.** This needs a stack to enrich. If Hop-1 (Step 4) narrowed
to at least one stack, proceed. If Hop-1 matched **no** stack (the query is
outside every stack's domain), there is nothing to enrich against: tell the user
"No matching content found in stacks: {STACKS_TO_SEARCH[*]}." and stop.

For each in-scope stack (usually one):

1. Tell the user: `Gap detected in {stack} — researching now…`
2. Move into the library and run the enrichment loop hands-free. `enrich-stack`
   is library-local, so `cd` there first — working directory persists into the
   skill invocation that follows. Re-resolve the library path here rather than
   reusing `$LIBRARY` from Step 1: shell variables do not survive between bash
   blocks, so the bare variable would be empty. `--auto` makes enrich-stack
   auto-stage the agent's `CANDIDATE` sources (tier 1-3, quote-verified) without
   an operator prompt, then catalog + audit:

   ```bash
   cd "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/resolve-library.sh")"
   ```

   Then invoke `/stacks:enrich-stack {stack} --auto --query "{the user's query}"`.
   The `--query` scopes the run to **this one gap**: enrich-stack web-searches a
   grounding source for exactly this query, stages it if `CANDIDATE` (tier 1-3,
   quote re-verified), catalogs it into an article, and re-audits — committing the
   result in the library. It does **not** touch the stack's other soft spots or
   historical misses; one miss authorizes researching only the query that missed.
   (Pass the query as the literal last argument; `--query` consumes the rest of
   the string, so it needs no quoting gymnastics on the enrich side.)

3. After it returns, **retry the lookup for the original query**: redo Steps 5–7
   against the now-updated `{stack}/index.md` (re-read the routing map, re-recognize,
   re-synthesize) and deliver the enriched answer.

**Fallback (#69).** Report enrich-stack's actual outcome — it already catalogs
and commits, so do not say "queued for the next audit" (the sources are already
ingested or were never staged). If it staged nothing (`NOSOURCE` — nothing on the
web grounds the query) say so: "No groundable source found for this query;
nothing was added." If it staged and cataloged a source but the retry still finds
no confident article, say: "Researched and filed a source on this, but it didn't
synthesize into a confident answer — see the new article in `{stack}`." Do not
fabricate an answer from thin sources.

Then stop (a miss does not also run Step 10 — there is no synthesized answer to
file back beyond what enrich already committed).

## Step 10: Offer to file the result back (opt-in)

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
