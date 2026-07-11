# stacks Tech Context

## Project Structure

| Directory/File | Purpose |
|----------------|---------|
| `.claude-plugin/plugin.json` | Plugin identity and version |
| `.claude-plugin/marketplace.json` | Single-plugin marketplace descriptor (source: "./") |
| `agents/` | 4 worker subagent definitions: source-extractor, article-synthesizer, validator, enrichment |
| `skills/{name}/SKILL.md` | User-invocable skills: lookup, audit-stack, catalog-sources, enrich-stack, init-library, new-stack, process-inbox |
| `scripts/` | Lifecycle scripts (install.sh, uninstall.sh, update.sh, init.sh, loop.sh) plus pipeline helpers (assert-structure.sh, gate-batch.sh, check-coverage.sh, collision-dest.sh, dedup-extractions.py, normalize-tags.sh, regenerate-moc.sh, convert-sources.sh, rank-articles.sh, rewrite-source-refs.sh, resolve-library.sh, lookup-misses.sh, telemetry.sh). `scripts/pipeline/` holds the per-pipeline orchestration scripts (enrich.sh, audit.sh, catalog.sh all shipped — epic #87 pipelines migrated; each has an inline `--self-check`, no bats file). `locate-plugin-root.sh` was deleted (#63) — skills use `$CLAUDE_PLUGIN_ROOT`. |
| `templates/library/` | Files copied when `/stacks:init-library` creates a library |
| `templates/stack/` | Files copied when `/stacks:new-stack` scaffolds a stack; includes `dev/audit/` and `dev/extractions/` skeletons |
| `references/` | `default-topic-template.md` (the only reference doc; wave-engine/refresh-procedure/obsidian were removed in 0.21.0) |
| `dev/` | Planning and feature-dev artifacts (not shipped with plugin) |
| `CHANGELOG.md` | Version history |
| `README.md` | User-facing readme |

## Pipeline helpers

| Script | Purpose |
|--------|---------|
| `scripts/gate-batch.sh {epoch} {label} {kind} {path}...` | Shared write-or-fail + structure gate loop. Each path must be non-empty AND mtime strictly newer than `{epoch}` (the size+mtime check, folded in 0.21.0 from the former assert-written.sh), then `assert-structure.sh {path} {kind}`; aggregates failures, exits 1 with `AGENT_WRITE_FAILURE: {label} batches ungated:`. Pass `-` as `{kind}` to skip the structure check. Call sites: catalog W1/W2, audit A1. Covered by `tests/gate-batch.bats`. |
| `scripts/check-coverage.sh [--field N] [--verdict TAG] [--batched] {dispatch.tsv} {output-file\|tag=file}...` | Per-item coverage gate (0.45.0, hardened 0.45.1; `--batched` 0.49.0). Reconciles the dispatch manifest (`batch_tag<TAB>item_id[<TAB>metadata]`) against receipt rows (item_id in col N, default 2); fails by name on omission, duplicate, unknown id, or missing/empty output file. `--batched` reconciles per batch (each `tag=file` pair vs only that batch's ids + its own file), catching a cross-batch misattribution and an unpaired manifest tag (#92). Exit 0 only on exact set equality. Inline `--self-check` (18 red-when-broken cases). Wired into the audit + enrich gates (`--batched`); catalog uses per-path `gate-batch.sh` instead. |
| `scripts/pipeline/enrich.sh {prep\|gate\|finish} {stack} [--auto] [--query <text>]` | Enrich pipeline orchestration (0.46.0). `prep` = args + gap assembly + stale-check + CAP=5 shard → `dev/enrich/{run.env,dispatch.tsv}`; `gate` = gate-batch + check-coverage over gap_ids; `finish` = URL-dedup + cleanup. State via files, never shell env (#72). `--self-check` (6 cases; the seeded URL-less filed source exercises the grep-no-match path that killed prep under set -e until the 0.48.0 `\|\| true`). |
| `scripts/pipeline/audit.sh {prep\|gate\|finish} {stack} [--full]` | Audit pipeline orchestration (0.47.0, #87 T7; incremental 0.52.0). `prep` = article enum + **incremental skip** (hash vs `dev/audit/verified.tsv`, `--full` bypasses) + CAP=5 shard → `dev/audit/{run.env,dispatch.tsv}`; emits `NOTHING_TO_AUDIT` when all unchanged. `gate` = gate-batch (`audit-findings`) + per-row RUN_ID check + `check-coverage.sh --verdict VALIDATED` (no-ops on empty dispatch). `finish` = report.md + **merged** soft-spots.tsv (carries skipped articles' soft spots forward) + `verified.tsv` re-stamp (`git hash-object` per article) + cleanup. Per-article `VALIDATED` receipt replaced the `last_verified==today` date-gate (#71). gate+finish assert dispatch-rows==N_ARTICLES (a truncated dispatch dies, never stamps unaudited articles verified). `--self-check` (18 cases). |
| `scripts/pipeline/catalog.sh {queue\|prep\|gate-w1\|dedup\|gate-w2\|finish} {stack} [--from P]` | Catalog pipeline orchestration (0.48.0, #87 T8). `queue` = stacks with incoming, largest first; `prep` = `--from` stage + convert + W0 enum/paren-gate + W1 manifest; `gate-w1`/`gate-w2` = gate-batch over the 1:1 per-source/per-slug output files (path presence = coverage, so no check-coverage); `dedup` = W1b merge + W2 manifest + near-dup report; `finish` = tag-drift + W3 filing + W4 MoC + cleanup. RUN_ID_W2 captured at `dedup` is the single freshness floor for all W2 waves. State via files under `dev/extractions/`, never shell env (#72). Phases are manifest-authoritative (finish files/gates the dispatched set, not a live `find`; dedup rejects off-manifest batch files) — codex-hardened. `--self-check` (20 cases). |
| `scripts/assert-structure.sh {path} {kind} {label}` | Content-shape gate. Kinds: `concept-batch`/`dedup-md` (`## Concept:` header), `dedup-meta` (`ALL_SLUGS=`), `article-md` (`title:` + `last_verified:`), `audit-findings` (a `VALIDATED` receipt row — the #87 T7 per-article coverage signal that replaced the `article-validated` date-gate), `enrichment-findings` (8-field verdict rows). Covered by `tests/assert-structure.bats`. |
| `scripts/dedup-extractions.py {extr_dir} {dedup_path}` | W1b dedup: merges concept blocks across `batch-*-concepts.md` by slug (union of `source_paths[]`, first-seen order), writes `_dedup.md`, one `_dedup-{slug}.md` per slug, and `_dedup-meta.txt` (`ALL_SLUGS`/`UPDATED_SLUGS`/`N_NEW`/`N_UPDATED`/`N_UNIQUE_CONCEPTS`/`INPUT_BLOCKS` for the caller to source). |
| `scripts/normalize-tags.sh {stack_root}` | Reads `allowed_tags:` block-list from `{stack_root}/STACK.md`, greps every `articles/*.md` frontmatter `tags:` against it, halts with `TAG_DRIFT: {slug}: {tag}` on stderr per offender (exit 1). Exits 0 with backward-compat warning when `allowed_tags:` absent/empty. Runs as the W2 tag-drift check in catalog. |
| `scripts/regenerate-moc.sh {stack_root}` | Rebuilds `index.md` (Map of Contents) from article frontmatter, grouping by `tags[0]`; appends each article's `routing:` line (`- [[slug\|title]] — {routing}`) to make it a recognition map (#59), bare link if absent; preserves the `## Reading Paths` section verbatim. W4 in catalog. |
| `scripts/rewrite-source-refs.sh {articles_dir} {fname} {publisher}` | After W3 files a source out of `incoming/`, rewrites `sources/incoming/{fname}` → `sources/{publisher}/{fname}` across the stack's articles so citations don't dangle (#56). Also the one-shot fixer for pre-fix libraries. |
| `scripts/collision-dest.sh {dir} {filename}` | Echoes a non-colliding path in `{dir}` for `{filename}`, appending `-1`, `-2`, ... before the extension until free. Shared by catalog source filing and process-inbox routing. |

## CLI Commands

```bash
# Git
git remote -v                        # git@github.com:chuggies510/stacks.git
git log --oneline -10

# Issues
gh issue list --state open
gh issue view {N}

# Install / test cycle
bash scripts/install.sh              # registers plugin in ~/.claude/settings.json
# restart Claude Code, then:
/stacks:init-library ~/tmp/test-library
/stacks:new-stack test-stack
/stacks:catalog-sources test-stack
/stacks:audit-stack test-stack
/stacks:lookup some question
```

## Dependencies

Pure markdown + bash plugin. No package manager, no build step. No `package.json`, `pyproject.toml`, `Cargo.toml`.

Runtime dependencies:
- `jq` (version file parsing, known_marketplaces.json fallback)
- `python3` (W1b dedup: `dedup-extractions.py`)
- `awk` (W4 MoC `regenerate-moc.sh`, tag parse in `normalize-tags.sh`)
- `uv` + `pdfplumber` (PDF→text in `convert-sources.sh`; pdfplumber fetched ephemerally via `uv run --no-project --with`, no install)
- `pandoc` (`.docx`→text in `convert-sources.sh`)
- `openpyxl` (multi-sheet `.xlsx`→one CSV sidecar per sheet in `convert-sources.sh`, via `uv run --no-project --with`; 0.51.0)
- `libreoffice` (slides/legacy Office + `.xls`/`.ods` spreadsheets→text in `convert-sources.sh`, headless with an isolated profile; the single-sheet fallback when openpyxl is unavailable)
- document-ingest tools degrade gracefully: a missing tool skips that file with a report, never crashes the pipeline
- Linux `stat -c %Y` (mtime extraction in `gate-batch.sh`; macOS/BSD not supported)

Consumers of this plugin:
- `~/.claude/settings.json` — `extraKnownMarketplaces` + `enabledPlugins` entries written by install.sh
- `~/.config/stacks/config.json` — written by `/stacks:init-library` to point `lookup` and `process-inbox` at the active library

## Version Sync

Two files must match on every version change:
- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → plugin entry `version`

Mismatches cause the launcher to show stale versions.
