---
name: lookup
description: Use when answering a domain question from the configured knowledge library or searching its articles and deep-reference chapters.
---

# Lookup

Query knowledge stacks from any repo. Step 8 records the lookup once the answer is delivered.

## Step 1: Find the library

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
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
STACKS_TO_SEARCH=$(grep '^- \[' "$LIBRARY/catalog.md" \
  | sed 's|.*\[\([^]]*\)\](\([^/]*\)/).*|\2|')
[ -n "$STACKS_TO_SEARCH" ] \
  || { echo "No stacks found in catalog.md; run /stacks:new-stack first."; exit 1; }
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
- **Deep-reference tier** (stacks#85): enumerate with `find "$LIBRARY/{stack}/reference" -mindepth 2 -maxdepth 2 -type f -name index.md -print 2>/dev/null`, then read every returned index (one per ingested handbook; most stacks return none). Each `## Chapters` map is a recognition surface for Step 6.5. Its generated row format is owned by the plugin's `references/reference-tier.md`.

If a stack has neither an article index nor any reference index, note it as "no index yet" and skip it. If ALL stacks were skipped (no index of either kind anywhere), tell the user that this Hermes release cannot catalog sources and that cataloging needs a compatible Stacks harness.

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

**Miss decision (both surfaces now checked).** A **miss** is: Step 6 found no article AND Step 6.5 found no chapter. On a miss, do not synthesize from nothing. Run Step 8 to record it, then report the unresolved gap through Step 9. If Step 6.5 found chapters even though Step 6 found no article, that is a **hit**: synthesize from the chapters in Step 7. Do not treat it as a miss.

**Anti-pattern: never freelance a web search mid-lookup.** Do not call WebSearch/WebFetch to answer a lookup. On a **true miss** (no article and no chapter, above), record the gap and report it through Step 9. On a **partial hit** (an article or chapter matched but does not fully answer), answer from what is grounded and state what is missing in Step 7. Reaching outside the library to answer is off-limits.

## Step 7: Synthesize answer

Using the article content — and any reference chapters recognized in Step 6.5 — synthesize an answer to the user's query.

Requirements:
- Cite which article(s) the answer comes from (by title, not path)
- Include specific data points, formulas, rules of thumb, and field notes from the articles
- For any content drawn from a **reference chapter** (Step 6.5), cite it to the printed book: book name, volume/chapter, and the printed page range from its frontmatter (`book`, `volume`, `chapter`, `printed_pages`). A handbook chapter IS a citable primary source.
- If the articles and chapters don't fully answer the question, say what's missing
- Do not invent information beyond what the articles and chapters contain
- Do not call WebSearch/WebFetch to fill a gap here. Answer from the grounded content and state what is missing. A true miss never reaches Step 7: it is recorded in Step 8 and reported in Step 9.

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

If no article matched but reference chapters did (an article-less hit), synthesize from the chapters and note that no firm article covers this topic yet. A **true miss** (neither article nor chapter matched) is handled in Step 6.5, then Step 8 and Step 9. Do not reach Step 7 on a true miss.

## Step 8: Record the lookup

Log this lookup to telemetry — what was asked and which articles answered it. This single record is both the usage count and the query log, so it replaces the old bare counter. Run it after delivering the answer, **whether or not articles were found** (a miss is signal: it flags a gap to fill).

Substitute the placeholders below (comma-separated). The query comes from `$ARGUMENTS`:

- `stacks` — the stack(s) you searched after Hop-1 narrowing (Step 4). **Populate this even on a miss**: it records the domain that lacked grounded content. Leave empty only when Hop-1 matched no stack at all.
- `articles` — the title(s) that contributed to the answer: article titles AND any reference-chapter titles recognized in Step 6.5. **Empty only on a true miss**: no article and no chapter matched.
```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
# Re-derive the library here because shell variables do not survive between
# blocks. Recording it scopes the usage log per library.
LIBRARY=$(bash "$STACKS_ROOT/scripts/resolve-library.sh" 2>/dev/null)
TELEMETRY_EXTRA="$(jq -cn \
  --arg query "$ARGUMENTS" \
  --arg stacks '<stack(s) searched after Hop-1, comma-separated; empty only if no stack matched>' \
  --arg articles '<contributing article AND reference-chapter title(s), comma-separated; empty only on a true miss (no article and no chapter)>' \
  --arg library "$LIBRARY" \
  '{query: $query, stacks: $stacks, articles: $articles, library: $library}')" \
SKILL_NAME="stacks:lookup" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

<!-- ponytail: one telemetry line per lookup = the usage count AND the query log.
     A run that ends early can still skip this step; guaranteed capture would need a
     PreToolUse/UserPromptSubmit hook, which is overkill for usage stats. Add the hook
     only if skipped lookups become a real gap. -->

## Step 9: Report an unresolved gap

**Only on a true miss**: no article and no reference chapter matched. On a hit,
including a reference-only hit, lookup is done once the answer is delivered.

The safe Hermes release does not include `enrich-stack`, `catalog-sources`, or
`audit-stack`, because they require Stacks worker agents. Tell the user:

```
No matching grounded content found in stacks: {STACKS_TO_SEARCH[*]}.
This Hermes Stacks release recorded the gap but cannot research or catalog it.
Use a compatible Stacks harness to enrich and catalog the source material.
```

Do not web-search or synthesize an answer outside the library. Then stop.
