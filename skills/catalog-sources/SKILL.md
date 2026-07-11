---
name: catalog-sources
description: |
  Use when the user wants to process new sources into article-per-concept wiki
  entries for a knowledge stack. Enumerates new sources, identifies concepts per
  source (W1), deduplicates shared concept slugs (W1b), synthesizes one article
  per unique concept (W2), files sources to their publisher directory (W3), and
  regenerates the stack Map of Contents (W4). Runs from any repo; targets the
  library configured in ~/.config/stacks/config.json, or the current directory
  when it is itself a library. Accepts an optional --from {path} argument
  to stage source files from an existing directory before cataloging.
---

# Catalog Sources

Process new sources into article-per-concept wiki entries for a knowledge stack.

The deterministic control flow (arg parse, `--from` staging, convert, enum, sharding, dedup, gating, tag-drift, source filing, MoC, cleanup) lives in `scripts/pipeline/catalog.sh` as phase subcommands; state crosses phases through `dev/extractions/{run.env,dispatch-w1.tsv,dispatch-w2.tsv}` files, never shell env. This skill runs the two model dispatches (W1 source-extractor, W2 article-synthesizer) and the interactive near-dup review between the script phases, then does the log+commit.

## Step 0: Telemetry

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
SKILL_NAME="stacks:catalog-sources" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

## Step 1: Pick the stack(s)

Two modes, keyed on `$ARGUMENTS`:

- **A stack name is given** (with or without `--from {path}`): catalog that one stack. `--from` stages source files from an existing directory into the stack's `incoming/` before cataloging.
- **No argument**: catalog every stack that has queued sources in `incoming/`, largest batch first. Get the queue:

  ```bash
  STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
  bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" queue
  ```

  Empty output means nothing is queued — tell the user and stop. Otherwise **run Steps 2–9 once per stack in the printed order** (each stack is an independent cataloging run; commit per stack at Step 9 so a failure mid-queue leaves prior stacks clean). `--from` is not available in this mode (it needs an explicit stack).

For each stack to catalog, do Steps 2–9.

## Step 2: Prep — stage, convert, enumerate, shard (`catalog.sh prep`)

`prep` does everything deterministic before the first agent: resolve+cd the library, stage `--from` sources (collision-safe copy of the supported types), convert non-text sources (PDF/Office → text sidecars, images/scanned/unknown skipped-and-reported), enumerate `sources/incoming/` (the new-source set), fail early on `(`/`)` in a filename (breaks the index parser), and write the W1 manifest (`dev/extractions/dispatch-w1.tsv`) + `run.env` with `RUN_ID_W1`.

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" prep {stack}
# or, staging first:  ... prep {stack} --from {path}
```

Surface prep's output to the operator: the staging report (how many staged/skipped and why), the converter's `PASSTHROUGH`/`CONVERTED`/`SKIPPED` lines (a silently-skipped source reads as covered while being absent), and the new-source count. A `CATALOG_NOOP` line means `incoming/` is empty after staging — nothing to catalog for this stack; move to the next (or stop). A non-zero exit (bad `--from`, a paren filename, missing stack) prints the reason and stops.

## Step 3: Read STACK.md

Read `{stack}/STACK.md` for the source hierarchy (tier rankings for conflict resolution), the scope section (what belongs / the "What does not belong" discard test), and the filing rules. The W1 agents need the hierarchy and scope; you need the filing rules only if you later resolve an ambiguous publisher by hand.

## Step 4: W1 — Dispatch one source-extractor per source

`prep` sharded the sources one-per-agent — per-source isolation on purpose: bundling sources into one agent bleeds claims across them (a claim from source A attributed to a concept first seen in source B). Read the manifest `dev/extractions/dispatch-w1.tsv` — each row is `batch_tag<TAB>source_path`. **In a single message, emit one `Agent` tool call per manifest row**, `subagent_type` = `stacks:source-extractor`. Parallel dispatch — never sequential. Each agent prompt names:

- its **`batch_id`** = the string `batch-` followed by column 1's numeric tag (column 1 holds `1`, `2`, …, so `batch_id` is `batch-1`, `batch-2`, …), which fixes its output path `dev/extractions/{batch_id}-concepts.md`,
- its assigned **source path** (column 2),
- the path to `{stack}/STACK.md` (source hierarchy + scope),
- the existing `{stack}/articles/` listing (the authoritative slug set, for slug-immutability checks), **and** `{stack}/index.md`'s `## Articles` map — the `slug — scope` routing lines that say what each existing article already covers. The scope lines are the reuse-vs-mint decision surface: a concept that falls within an existing article's *described scope* reuses that slug instead of minting a new one, which is what stops a rich source fragmenting one article into several new sub-topic slugs (stacks#106). If `index.md` has no `## Articles` map yet (first catalog run, no articles), the bare listing stands.

## Step 5: Gate W1 (`catalog.sh gate-w1`)

After all extractors return, gate the batch. One source maps 1:1 to one `batch-<tag>-concepts.md`, so a missing/empty/stale concept file fails **by path** — that presence check is the per-source coverage.

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" gate-w1 {stack}
```

A non-zero exit names the ungated batch file(s) — an extractor that wrote nothing or wrote a stale file. Surface it and stop.

## Step 6: Dedup + near-dup review (`catalog.sh dedup`)

`dedup` runs the deterministic W1b merge (union `source_paths` per slug, classify each unique slug new/updated, flag near-duplicate titles), asserts the merged output's shape, and writes the W2 manifest (`dev/extractions/dispatch-w2.tsv`, one slug per row) + `run.env` with `RUN_ID_W2`.

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" dedup {stack}
```

Read its output: the unique-concept count (new/updated split), the wave plan, and `NEAR_DUP_PAIRS`.

**Near-dup review (stacks#78) — do this before W2 dispatch.** Exact-slug dedup cannot catch two NEW slugs that are the same concept under different names (parallel extractors are blind to each other). If `dedup` printed a non-empty `NEAR_DUP_PAIRS=` line, STOP: for each `slugA~slugB` pair, read the two `dev/extractions/_dedup-{slug}.md` blocks and decide — **same concept** → merge them (fold one block's `source_paths` and claims into the other, `rm` the absorbed `_dedup-{slug}.md`, and delete the absorbed slug's row from `dev/extractions/dispatch-w2.tsv`) so W2 emits one article, not two stubs; **genuinely distinct** → leave both. Report-and-decide, never auto-merge: a wrong merge buries a lower-tier claim under a higher-tier block.

## Step 7: W2 — Dispatch one article-synthesizer per slug

Read `dev/extractions/dispatch-w2.tsv` — each row is `wave_tag<TAB>slug`. Article-synthesizer is 1-per-slug. Dispatch in waves grouped by `wave_tag` (the cap keeps any one message from overwhelming the harness): **for each wave, in a single message emit one `Agent` call per slug in that wave**, `subagent_type` = `stacks:article-synthesizer`; run waves sequentially. Each agent prompt names:

- `{stack}/dev/extractions/_dedup-{slug}.md` (the self-contained concept block),
- `{stack}/articles/{slug}.md` **only if** the slug is in `dedup`'s `Updated slugs` list (an update — the agent reads the existing article and revises it; new slugs have no such file),
- `{stack}/STACK.md` (source hierarchy + `allowed_tags`).

## Step 8: Gate W2 (`catalog.sh gate-w2`)

After all waves return, gate the articles. 1 slug maps 1:1 to `articles/{slug}.md`, so a missing article (a synthesizer that skipped its slug) or an unrewritten update (mtime older than this run) fails **by path**.

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" gate-w2 {stack}
```

A non-zero exit names the ungated article(s). Surface it and stop; the sources stay in `incoming/` (finish is not reached) and the next run retries.

## Step 9: Finish, log, commit (`catalog.sh finish`)

`finish` runs the post-synthesis deterministic tail: tag-drift enforcement (halts before filing if any article carries an out-of-vocabulary tag, so its source stays in `incoming/` for the next run), W3 source filing (each `incoming/` source moved to its publisher dir with citations rewritten; a source with no `publisher:` field files under `sources/unknown/` and is reported), W4 MoC regeneration, then cleanup of the transient run files. It prints a `CATALOG_SUMMARY: sources=… new=… updated=… unfiled=…` line.

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" finish {stack}
```

A non-zero exit with `TAG_DRIFT:` lines means an article's tags left the `allowed_tags:` vocabulary — surface it, and tell the operator to fix the article tag or the vocabulary list before re-running (the source stayed in `incoming/`). Otherwise read the `CATALOG_SUMMARY` counts for the log+commit.

Prepend a log entry and commit. Shell state does not survive between these blocks, so re-resolve the library here — substitute `{stack}` and the counts from `CATALOG_SUMMARY`:

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
LIBRARY=$(bash "$STACKS_ROOT/scripts/resolve-library.sh") && cd "$LIBRARY" || exit 1
NEW_ENTRY="## [$(date +%Y-%m-%d)] catalog | {sources} new sources, {new} articles created, {updated} updated
Sources processed: {sources}. New articles: {new}. Updated articles: {updated}."
{ printf '%s\n\n' "$NEW_ENTRY"; cat "{stack}/log.md"; } > /tmp/stacks-log.tmp
mv /tmp/stacks-log.tmp "{stack}/log.md"
git add "{stack}/"
git commit -m "feat({stack}): catalog {sources} sources, {new} new articles, {updated} updated"
```

Report to the user: sources processed, articles created vs updated, any sources filed under `sources/unknown/` (no publisher field) or left in `incoming/` (failed a gate), and suggest `/stacks:audit-stack {stack}` next if 2+ articles exist.
