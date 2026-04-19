# Refresh Procedure — Incremental Knowledge Synthesis

Triggered by `/stacks:catalog-sources` when existing articles are present. Detects new/changed sources and selectively re-runs affected waves.

## Step 1: Detect Changes

Diff `sources/incoming/` listing against the Sources section of `index.md`:

```bash
# List files in sources/incoming/ (sorted)
ls {stack}/sources/incoming/ | sort > /tmp/sources-actual.txt

# Extract source filenames from index.md Sources section
grep -E '^\- |^  - ' {stack}/index.md | sed 's/.*sources\///' | sed 's/[) ].*//' | sort > /tmp/sources-indexed.txt

# New sources = in actual but not indexed
comm -23 /tmp/sources-actual.txt /tmp/sources-indexed.txt > /tmp/new-sources.txt
cat /tmp/new-sources.txt
```

If diff is empty: "All sources indexed. Nothing to refresh." Stop.
If diff is non-empty: proceed with changed file list.

## Step 2: Concept Identification (W1)

Dispatch `concept-identifier` agent for each new source:

```
Prompt: "Identify all concepts and extract claims from this source.

Source: {source path}
Source hierarchy and template: STACK.md
Prior findings (if any): dev/audit/findings.md

Extraction hash: {source_sha256}
Output directory: dev/extractions/
Project root: {pwd}"
```

The concept-identifier produces one extraction file per source in `dev/extractions/`. Each extraction lists concept slugs and raw claim blocks.

Run W1b slug-collision dedup after all W1 agents complete:

```bash
# Normalize slugs: lowercase, replace spaces with hyphens, strip non-alnum
# If a new slug matches an existing articles/{slug}.md, treat as update to that article
```

## Step 3: Article Synthesis (W2)

For each unique concept slug identified in Step 2:

- If `articles/{slug}.md` exists: update it, merging new claims while preserving existing content
- If `articles/{slug}.md` does not exist: create it from scratch

Dispatch `article-synthesizer` agent per concept:

```
Prompt: "Write or update the article for concept '{slug}'.

Extractions: dev/extractions/{source}-concepts.md (all files referencing this slug)
Existing article (if any): articles/{slug}.md
Source hierarchy: STACK.md
Extraction hash: {hash}
Project root: {pwd}"
```

Each article is 300-800 words, uses inline `[source-slug]` citations, and includes `extraction_hash` frontmatter.

Run W2b wikilink pass after all W2 agents complete (see `scripts/wikilink-pass.sh`).

## Step 4: Source Filing (W3)

Move processed sources from `sources/incoming/` to the appropriate tier directory under `sources/` based on STACK.md source hierarchy:

```bash
# Example: sources/incoming/paper.pdf → sources/tier1/paper.pdf
```

Update index.md Sources section to reflect filed locations.

## Step 5: Index Regeneration (W4)

Regenerate `index.md` from the current state of `articles/` and `sources/`:

- Topics/Articles section: one row per `articles/{slug}.md`, using frontmatter title and tags
- Sources section: one row per filed source, with tier and ingestion date
- Preserve any `## Reading Paths` section authored by the user

## State Files

| file | purpose |
|------|---------|
| `dev/extractions/{source}-concepts.md` | W1 output, ephemeral (per-run) |
| `articles/{slug}.md` | W2 output, persistent |
| `dev/audit/findings.md` | audit-stack output, read by W0b skip-list |
| `dev/audit/closed/{date}-findings.md` | archived findings per audit cycle |
