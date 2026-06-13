# stacks Tech Context

## Project Structure

| Directory/File | Purpose |
|----------------|---------|
| `.claude-plugin/plugin.json` | Plugin identity and version |
| `.claude-plugin/marketplace.json` | Single-plugin marketplace descriptor (source: "./") |
| `agents/` | 3 worker subagent definitions: source-extractor, article-synthesizer, validator |
| `skills/{name}/SKILL.md` | User-invocable skills: ask, audit-stack, catalog-sources, init-library, new-stack, process-inbox |
| `scripts/` | Lifecycle scripts (install.sh, uninstall.sh, update.sh, init.sh, locate-plugin-root.sh, loop.sh) plus pipeline helpers (assert-structure.sh, gate-batch.sh, collision-dest.sh, dedup-extractions.py, normalize-tags.sh, regenerate-moc.sh, telemetry.sh) |
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
| `scripts/assert-structure.sh {path} {kind} {label}` | Content-shape gate. Kinds: `concept-batch`/`dedup-md` (`## Concept:` header), `dedup-meta` (`ALL_SLUGS=`), `article-md` (`title:` + `last_verified:`), `article-validated` (a `[VERIFIED\|DRIFT\|UNSOURCED\|STALE]` mark). Covered by `tests/assert-structure.bats`. |
| `scripts/dedup-extractions.py {extr_dir} {dedup_path}` | W1b dedup: merges concept blocks across `batch-*-concepts.md` by slug (union of `source_paths[]`, first-seen order), writes `_dedup.md`, one `_dedup-{slug}.md` per slug, and `_dedup-meta.txt` (`ALL_SLUGS`/`UPDATED_SLUGS`/`N_NEW`/`N_UPDATED`/`N_UNIQUE_CONCEPTS`/`INPUT_BLOCKS` for the caller to source). |
| `scripts/normalize-tags.sh {stack_root}` | Reads `allowed_tags:` block-list from `{stack_root}/STACK.md`, greps every `articles/*.md` frontmatter `tags:` against it, halts with `TAG_DRIFT: {slug}: {tag}` on stderr per offender (exit 1). Exits 0 with backward-compat warning when `allowed_tags:` absent/empty. Runs as the W2 tag-drift check in catalog. |
| `scripts/regenerate-moc.sh {stack_root}` | Rebuilds `index.md` (Map of Contents) from article frontmatter, grouping by `tags[0]`; preserves the `## Reading Paths` section verbatim. W4 in catalog. |
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
/stacks:ask some question
```

## Dependencies

Pure markdown + bash plugin. No package manager, no build step. No `package.json`, `pyproject.toml`, `Cargo.toml`.

Runtime dependencies:
- `jq` (version file parsing, known_marketplaces.json fallback)
- `python3` (W1b dedup: `dedup-extractions.py`)
- `awk` (W4 MoC `regenerate-moc.sh`, tag parse in `normalize-tags.sh`)
- `uv` + `pdfplumber` (PDF→text in `convert-sources.sh`; pdfplumber fetched ephemerally via `uv run --no-project --with`, no install)
- `pandoc` (`.docx`→text in `convert-sources.sh`)
- `libreoffice` (spreadsheets/slides/legacy Office→text in `convert-sources.sh`, headless with an isolated profile)
- document-ingest tools degrade gracefully: a missing tool skips that file with a report, never crashes the pipeline
- Linux `stat -c %Y` (mtime extraction in `gate-batch.sh`; macOS/BSD not supported)

Consumers of this plugin:
- `~/.claude/settings.json` — `extraKnownMarketplaces` + `enabledPlugins` entries written by install.sh
- `~/.config/stacks/config.json` — written by `/stacks:init-library` to point `ask` and `process-inbox` at the active library

## Version Sync

Two files must match on every version change:
- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → plugin entry `version`

Mismatches cause the launcher to show stale versions.
