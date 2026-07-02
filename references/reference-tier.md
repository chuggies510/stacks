# Deep-reference tier

Handbook chapters converted by doc-tools `extract-pdf` faithful mode (reference-grade
Markdown: dual converter + patch agent + `verify-merge.py` gate) have no home in the
`sources → articles` schema. They are not **sources** (inputs already cataloged into
articles) and not **articles** (LLM-synthesized guides). The deep-reference tier is the
shelf for them: tier-1 handbook text, cited to the printed page, that `/stacks:lookup`
can read behind the articles.

Producer: `/stacks:ingest-book`. Consumer: `/stacks:lookup`. Index generator:
`scripts/regenerate-reference-index.sh`.

## Layout

```
{stack}/reference/{book-slug}/
  index.md                              <- generated; what lookup greps
  vol2-ch06-domestic-water-heating.md   <- one gated chapter, provenance frontmatter
  vol2-ch07-...md
  aspe-pedh-vol2.pdf                     <- raw source PDF, gitignored (stays local)
```

- The tier is created lazily on first ingest — `new-stack` does not scaffold an empty
  `reference/`, and `lookup` tolerates its absence (a stack with no books just has no
  `reference/` dir).
- Raw PDFs are gitignored (`reference/**/*.pdf`): the book stays out of git history, a
  local re-pull of any page stays possible. The gated chapter `.md` files ARE tracked.
- `{book-slug}` is a short kebab identifier for the whole book (e.g. `aspe-pedh`); one
  dir per book, chapters as files inside it.

## Chapter frontmatter

Every chapter file carries provenance so a citation traces back to the printed book:

```yaml
---
book: ASPE Plumbing Engineering Design Handbook
book_slug: aspe-pedh
volume: 2
chapter: 6
title: Domestic Water Heating
topics: water heater sizing, recirculation, storage vs instantaneous, legionella, mixing valves
edition: 4th (2018)
printed_pages: "155-198"
pdf_pages: "175-218"
converters: pymupdf4llm layout-on + layout-off + pdfplumber
merge_model: haiku/low
gate: PASS
last_ingested: 2026-07-02
---
```

- `topics` — a short keyword phrase (asker's words) describing what the chapter covers.
  It is the routing line the index generator emits and `lookup` recognizes against, the
  same role `routing:` plays for an article. Falls back to `title` if absent.
- `volume` / `chapter` — sort keys for the index (numeric ascending). A single-volume
  book omits `volume`; the generator treats a missing volume as 0.
- `gate` — `PASS` is the invariant. `ingest-book` never files a chapter the gate failed.

## Index format

`index.md` is regenerated from chapter frontmatter and is the recognition surface
`lookup` greps (mirrors an article `index.md`'s `## Articles` map):

```markdown
# {Book Name} — Reference Index

*Auto-generated from chapter frontmatter. Deep-reference tier: gated handbook chapters,
not synthesized articles. Do not edit; run scripts/regenerate-reference-index.sh.*

## Chapters

- [[vol2-ch06-domestic-water-heating|Vol 2 Ch 6: Domestic Water Heating]] — water heater sizing, recirculation, storage vs instantaneous, legionella, mixing valves (printed pp. 155-198)
```

## Cataloging a chapter into articles later

Deep reference is **upstream** of articles, not instead of them. To promote a chapter
into first-class synthesized articles, copy it into `{stack}/sources/incoming/` and run
`/stacks:catalog-sources {stack}` — it ingests any `.md` there like any other source. No
special path is needed; the chapter file is already reference-grade text.
