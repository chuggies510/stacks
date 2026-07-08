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
- Read `$LIBRARY/{stack}/index.md`. If it does not exist, note the stack as "no article index yet".
- The `## Articles` section is the routing map: `- [[slug|title]] — {routing line}`, where the routing line says what the article covers and the questions it answers (#59). This is the recognition surface for Step 6.
- Capture any `## Reading Paths` section as supplementary retrieval context.
- **Deep-reference tier** (stacks#85): also read every `$LIBRARY/{stack}/reference/*/index.md` that exists (one per ingested handbook; most stacks have none — skip silently when the glob is empty). Each is a `## Chapters` map of gated handbook chapters: `- [[chapter-slug|Vol V Ch C: Title]] — {topics} (printed pp. N-M)`. This is the recognition surface for Step 6.5. Schema: the plugin's `references/reference-tier.md`.

If a stack has neither an article index nor any reference index, note it as "no index yet" and skip it. If ALL stacks were skipped (no index of either kind anywhere), tell the user to run `/stacks:catalog-sources` in the library repo.

## Step 6: Recognize matching articles across stacks

<!-- Retrieval contract: input = (QUERY, the routing maps read in Step 5).
     Output = the article paths whose routing line matches the query; Step 7
     synthesis depends only on those. -->

From the `## Articles` routing lines you read in Step 5, select every article whose routing line (or title) matches the query's intent. The routing line is written in an asker's words, so match on meaning, not just shared tokens. Take as many as genuinely match — do not pad to a fixed count, and do not cap a broad question at a few when more are on-topic.

Read the selected article files. If article recognition found nothing, do **not** conclude a miss yet — the deep-reference tier (Step 6.5) may still answer the query. Proceed to Step 6.5; the miss decision is made there, once both the article map and the reference map have been checked.

## Step 6.5: Recognize matching reference chapters (stacks#85)

<!-- Retrieval contract: input = (QUERY, the reference `## Chapters` maps read in Step 5).
     Output = the chapter file paths whose routing line matches the query; Step 7 reads
     them alongside the articles. -->

From the `## Chapters` routing lines in the reference indexes you read in Step 5, select every chapter whose line (topics + title) matches the query's intent — same recognition as Step 6, matching on meaning. Most queries match zero chapters (the stack has no book, or the book doesn't cover this); that is normal.

Read the selected chapter files (each is reference-grade handbook Markdown with provenance frontmatter). They feed Step 7 as **backing reference behind the articles** — articles stay the first-class answer (the firm's design guides); a chapter is the handbook page the answer traces to.

**Miss decision (both surfaces now checked).** A **miss** is: Step 6 found no article AND Step 6.5 found no chapter. On a miss, do not synthesize from nothing — run Step 8 to log it, then go to **Step 9 (auto-enrich on a miss)**. Only if Step 9 is not applicable (no stack matched in Hop-1, or it stages nothing) tell the user: "No matching content found in stacks: {STACKS_TO_SEARCH[*]}." If Step 6.5 found chapters even though Step 6 found no article, that is a **hit** — synthesize from the chapters in Step 7; do not auto-enrich.

## Step 7: Synthesize answer

Using the article content — and any reference chapters recognized in Step 6.5 — synthesize an answer to the user's query.

Requirements:
- Cite which article(s) the answer comes from (by title, not path)
- Include specific data points, formulas, rules of thumb, and field notes from the articles
- For any content drawn from a **reference chapter** (Step 6.5), cite it to the printed book: book name, volume/chapter, and the printed page range from its frontmatter (`book`, `volume`, `chapter`, `printed_pages`). A handbook chapter IS a citable primary source.
- If the articles and chapters don't fully answer the question, say what's missing
- Do not invent information beyond what the articles and chapters contain

**Collect primary sources.** Before formatting the response, gather the base sources from every article read. Each article has a `sources:` frontmatter list of relative paths in the canonical **bare** form — `sources/{publisher}/{file}.md` — per the article contract (`references/article-contract.md`, plugin root; the whole corpus was normalized to bare in stacks#88). Resolve each by prepending the stack the article belongs to: read `$LIBRARY/{stack}/{path}`. For each unique resolved path, read the first 8 lines and extract:
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
**Reference chapters**: {book — Vol V Ch C: Title (printed pp. N-M) for each chapter that contributed; omit this line if none}
**Stack**: {stack name(s) that contributed — use singular "Stack" if only one}

**Primary sources:**
- {Author}, "{Title}", {date} — {URL}
- {repeat per unique citable source}
```

Omit the `**Reference chapters**` line entirely when no chapter contributed (the common case). It appears only for stacks carrying an ingested handbook.

If no article matched but reference chapters did (an article-less hit), synthesize from the chapters and note that no firm article covers this topic yet — a candidate to catalog (copy the chapter into `sources/incoming/`). A **true miss** (neither article nor chapter matched) is handled in Step 6.5 → Step 8 → Step 9, not here — you do not reach Step 7 on a true miss.

## Step 8: Record the lookup

Log this lookup to telemetry — what was asked and which articles answered it. This single record is both the usage count and the query log, so it replaces the old bare counter. Run it after delivering the answer, **whether or not articles were found** (a miss is signal: it flags a gap to fill).

Substitute the placeholders below (comma-separated). The query comes from `$ARGUMENTS`:

- `stacks` — the stack(s) you searched after Hop-1 narrowing (Step 4). **Populate this even on a miss** — a miss in stack X means "X was the right domain but had no article", which is exactly the gap `lookup-misses.sh` mines and `enrich-stack` closes. Leave empty only when Hop-1 matched no stack at all.
- `articles` — the title(s) that contributed to the answer: article titles AND any reference-chapter titles recognized in Step 6.5 (a chapter answered the query, so it is not a miss). **Empty only on a true miss** — no article and no chapter matched. `articles == ""` (with `stacks` populated) is the miss signal `lookup-misses.sh` mines, so a reference-only hit must record its chapter title(s) here or it is falsely enriched later.

```bash
STACKS_ROOT="$CLAUDE_PLUGIN_ROOT"
TELEMETRY_EXTRA="$(jq -cn \
  --arg query "$ARGUMENTS" \
  --arg stacks '<stack(s) searched after Hop-1, comma-separated; empty only if no stack matched>' \
  --arg articles '<contributing article AND reference-chapter title(s), comma-separated; empty only on a true miss (no article and no chapter)>' \
  '{query: $query, stacks: $stacks, articles: $articles}')" \
SKILL_NAME="stacks:lookup" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

<!-- ponytail: one telemetry line per lookup = the usage count AND the query log.
     A run that ends early can still skip this step; guaranteed capture would need a
     PreToolUse/UserPromptSubmit hook, which is overkill for usage stats. Add the hook
     only if skipped lookups become a real gap. -->

## Step 9: Auto-enrich on a miss (hands-free, #69)

**Only on a true miss** (the Step 6.5 decision: no article AND no reference chapter matched). On a hit — including an article-less hit where only a reference chapter matched — lookup is done once the answer is delivered; do not enrich.

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

Then stop; enrich already committed whatever it filed.
