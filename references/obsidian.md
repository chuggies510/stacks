# Obsidian as a stacks library IDE

A stacks library is a directory of markdown files with YAML frontmatter and `[[wikilink]]` cross-references. That is exactly the shape [Obsidian](https://obsidian.md) is built for. Opening your library as a vault gives you graph view, backlinks, Dataview queries against frontmatter, and one-click source capture via the Web Clipper extension — no tooling changes on the stacks side, the library already produces the right files.

This guide documents the integration. It is not required for using stacks. If you read articles in VS Code and drop sources in `sources/incoming/` by hand, nothing breaks.

## Opening a library as a vault

1. Install Obsidian.
2. Choose **Open folder as vault** and pick your library root (e.g., `~/knowledge`).
3. Ignore the prompt about `.obsidian/` — it is already in the library `.gitignore`.

The vault picks up every stack as a top-level folder. `catalog.md` is a good place to pin as the home note.

## Graph view

`[[wikilinks]]` between articles (added deterministically by `scripts/wikilink-pass.sh` during catalog and audit) materialize as edges in Obsidian's graph view. Clusters in the graph are a fast visual signal for topic density: thin clusters suggest a stack is under-articled, dense clusters suggest natural sub-topics to consolidate.

Enable **Settings → Core plugins → Graph view**, then:

- Filter to one stack via path prefix (`path:rust-async/`) to see just that stack's structure.
- Use **local graph** when reading an article to see its one-hop neighborhood.

## Source capture with Web Clipper

The [Obsidian Web Clipper](https://obsidian.md/clipper) browser extension converts any article page to markdown and saves it to a vault folder. Configure it once and source capture becomes a single-click operation.

**Configure:**

1. Open the Web Clipper extension settings.
2. Under **Vault**, select your stacks library.
3. Under **Path**, set `{{vault}}/<stack-name>/sources/incoming/`. Repeat for each stack you capture to, or leave a default on the stack you most commonly feed.
4. Under **Template**, include title and URL in frontmatter so `catalog-sources` has usable provenance:

```markdown
---
title: {{title}}
url: {{url}}
author: {{author}}
captured: {{date}}
---

{{content}}
```

After capture, the file lands ready for `/stacks:catalog-sources {stack}`. No manual copy-paste.

## Dataview queries against frontmatter

The [Dataview community plugin](https://github.com/blacksmithgu/obsidian-dataview) queries frontmatter fields across the vault. Articles written by `article-synthesizer` have a consistent schema, which makes Dataview queries cheap to write and reliable to run.

Article frontmatter fields available:

- `title` — human-readable
- `tags[]` — topical tags
- `sources[]` — source paths backing the article
- `updated` — YYYY-MM-DD of last synthesis
- `last_verified` — YYYY-MM-DD of last validator pass, or empty
- `extraction_hash` — hash of the source extraction (empty for query-filed articles)

**Example queries:**

Find articles that have never been validated (post-catalog, pre-first-audit):

````markdown
```dataview
TABLE title, updated, last_verified
FROM "rust-async/articles"
WHERE last_verified = ""
SORT updated DESC
```
````

Find articles with only one source backing (single-source fragility candidates for audit-stack's research-questions pass):

````markdown
```dataview
TABLE title, length(sources) AS "source_count"
FROM "rust-async/articles"
WHERE length(sources) <= 1
SORT source_count ASC
```
````

Find articles whose last validation is older than 90 days (staleness candidates):

````markdown
```dataview
TABLE title, last_verified
FROM "rust-async/articles"
WHERE last_verified != "" AND date(last_verified) < date(today) - dur(90 days)
SORT last_verified ASC
```
````

Coverage dashboard — article count per tag across a stack:

````markdown
```dataview
TABLE length(rows) AS "articles"
FROM "rust-async/articles"
FLATTEN tags
GROUP BY tags
SORT length(rows) DESC
```
````

A dashboard note that collects these queries is a useful home page; pin it and run `audit-stack` when the staleness table grows.

## Linking conventions inside Obsidian

Stacks uses `[[slug]]` wikilinks with the article slug (not title) as the target. Obsidian resolves these to `articles/{slug}.md` because Obsidian's default resolution walks the vault looking for any `{slug}.md` file. If two stacks ship the same slug, Obsidian resolves to whichever it finds first — not an error, but something to be aware of. `wikilink-pass.sh` excludes self-links; cross-stack links are not auto-generated.

Do not hand-author new wikilinks in article bodies. The wikilink pass is run after every catalog and audit and will either leave your link alone (if the term is in the glossary) or miss it entirely (if not). Add the term to `glossary.md` via the synthesizer pass instead.

## What not to do

- Do not hand-edit `articles/*.md`. The next `catalog-sources` run may rewrite the file; your changes are lost. Use `/stacks:ask` with Step 7 filing to add content.
- Do not rearrange `articles/` into subfolders. The pipeline assumes a flat directory and indexing breaks if you nest.
- Do not commit `sources/incoming/` or `sources/trash/` — already gitignored by the stack template. If you see either in `git status`, your `.gitignore` is stale (pre-0.9.1 libraries); add the two lines from `templates/stack/.gitignore`.

## Marp slides

The [Marp community plugin](https://github.com/rcsaquino/obsidian-marp) renders any markdown file with `marp: true` in frontmatter as a slide deck. Useful for turning an article (or glossary, or invariants) into a briefing without leaving the vault. This is presentation only — Marp frontmatter does not interfere with validator or synthesizer reads.
