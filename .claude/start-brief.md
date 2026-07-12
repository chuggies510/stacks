<!--
Start-brief: distilled orientation loaded by /start.
Distilled 2026-07-11 from:
  tech-context.md @ cb8be4f8a32c35b5910de9ad419626ecffa5b07c
  system-patterns.md @ c56e1d058a8f7352b61a66ec2463095469dbea39
Run /workspace-toolkit:refresh-start-brief when source files have drifted substantively.
-->

# stacks Start Brief

Claude Code plugin for building and maintaining curated domain knowledge libraries. Sources are cataloged into flat article-per-concept wiki entries queryable with `/stacks:lookup` from any repo; an audit pass validates each article against its cited sources. This repo is the tool, NOT a library: no knowledge content lives here.

## Tech context

### Deployment

- Directory-source plugin: loads directly from this repo via `extraKnownMarketplaces` in `~/.claude/settings.json`. Updates via `git pull`, no cache refresh.
- `bash scripts/install.sh` registers the marketplace + `enabledPlugins` entry, then restart Claude Code.
- `~/.config/stacks/config.json` (written by `/stacks:init-library`) points `lookup`/`process-inbox` at the active library.
- GitHub: `git@github.com:chuggies510/stacks.git`. Issues: `gh issue list --state open`.

### Version sync (every change)

Two files must match on every bump, or the launcher shows stale versions:
- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → plugin entry `version`
Plus a CHANGELOG entry.

### Tooling

- Pure markdown + bash. No package manager, no build step, no `package.json`.
- Runtime deps: `jq`, `python3` (W1b dedup), `awk` (MoC/tag parse), `uv`+`pdfplumber`/`pandoc`/`openpyxl`/`libreoffice` (source conversion, degrade gracefully on missing tool), Linux `stat -c %Y` (macOS/BSD not supported).

### Layout

- `.claude-plugin/` — plugin.json + marketplace.json (`source: "./"`).
- `agents/` — 4 worker subagent defs. `skills/{name}/SKILL.md` — user-invocable skills.
- `scripts/` — lifecycle (install/uninstall/update/init) + pipeline helpers (`gate-batch.sh`, `check-coverage.sh`, `dedup-extractions.py`, `normalize-tags.sh`, `regenerate-moc.sh`, `convert-sources.sh`, `resolve-library.sh`, `rank-articles.sh`, `lookup-misses.sh`); `scripts/pipeline/` holds the per-pipeline orchestration.
- `templates/{library,stack}/` — scaffold copied into user repos. `references/` — `article-contract.md`, `reference-tier.md`, `default-topic-template.md`. `dev/` — planning artifacts, not shipped.

### Test cycle

```bash
bash scripts/install.sh            # register plugin, then restart Claude Code
/stacks:init-library ~/tmp/test-library
/stacks:new-stack test-stack
/stacks:catalog-sources test-stack
/stacks:audit-stack test-stack
/stacks:lookup some question
```

## System patterns

### Core architecture

Three-layer plugin; the plugin holds no knowledge, it manipulates user-owned library repos:
1. Skills (user-facing SKILL.md): init-library, new-stack, catalog-sources, audit-stack, enrich-stack, process-inbox, lookup.
2. Agents (4 workers): source-extractor, article-synthesizer, validator, enrichment. No orchestrator agents.
3. Templates: `templates/library/` and `templates/stack/` scaffold user repos.

Field-usage model (#54): build/maintain skills are NOT library-cwd-bound. They resolve the library from config (or cwd if it is itself a library) and operate in place, since most stack work happens in a consuming field repo.

### Pipelines

- **Catalog (W0→W4):** convert non-text sources → enumerate `sources/incoming/` → W1 source-extractor (1 source/agent, slug immutability) → W1b `dedup-extractions.py` slug-collision merge → W2 article-synthesizer (per concept) → tag-drift check → W3 file sources to publisher dirs → W4 regenerate MoC.
- **Audit (drift report):** validator agents fix claims that contradict their cited source in place, record soft spots (claims with no source), stamp `last_verified`, rebuild `dev/audit/report.md`. Incremental by default (hash vs `verified.tsv`); `--full` re-checks all. Stateless: no findings ledger, no carry-forward.
- **Enrich (gap → source):** slots audit→enrich→catalog. Reads `dev/audit/soft-spots.tsv` + lookup misses, enrichment agent web-searches one source per gap. Interactive staging by default; `--auto` (lookup's hands-free miss path) auto-stages CANDIDATE verdicts only.
- **Lookup:** resolve config → open catalog + per-stack `index.md` → recognize matching articles over the `## Articles` routing map → synthesize a cited answer. On a miss (#69), logs it and invokes enrich-stack `--auto --query` scoped to the one query.

### Parent-side sharded dispatch

Scale-sensitive waves (catalog W1/W2, audit A1) are sharded and dispatched by the parent skill, not an orchestrator agent (nested Task dispatch was unreliable). Each pipeline's deterministic flow lives in `scripts/pipeline/{catalog,audit,enrich}.sh` with `prep|gate|finish` phases; each has an inline `--self-check`. Per-wave bounds: 1 source/source-extractor, enrich CAP=5/agent, catalog W2 + audit A1 slice at 25/agent.

### Key cross-cutting patterns

- **State crosses phases through files, never shell env.** Shell env/functions are LOST between a skill's Bash blocks (cwd persists). Pipelines carry `RUN_ID`/manifests in `dev/<phase>/{run.env,dispatch.tsv}` (#72). Live caution for any NEW SKILL.md Bash-block prose: re-derive per block or pass via `$ARGUMENTS`.
- **Write-or-fail gate:** sub-agents return only text, no exit code, so `gate-batch.sh {epoch} {label} {kind} {path}...` confirms output: each path non-empty AND mtime newer than the captured dispatch epoch, then `assert-structure.sh` content-shape check. Both halves matter (size alone passes a stale file, mtime alone passes an empty write).
- **Per-item coverage gate:** `check-coverage.sh` reconciles a dispatch manifest against per-item receipt rows, failing by name on omission/duplicate/unknown-id/missing file. `--batched` reconciles per batch.
- **Article contract SSOT:** `references/article-contract.md` is the one frontmatter/source-ref/tier/concept-block schema definition; five stages point at it instead of restating. `extraction_hash`/`updated` are dead and stripped.
- **Slug immutability:** W1 cannot rename an existing article's slug; combined with W1b dedup, prevents silent overwrite by parallel W2 dispatches.
- **Corpus scope map to all 4 worker agents (0.57.0–0.58.0):** each worker (extractor/synthesizer/enrich/validator) now receives the `index.md ## Articles` scope map for its corpus-relative judgment (reuse-vs-mint, what-to-cross-link, is-this-already-sourced, does-this-belong), not just a bare listing. The lever generalized from extraction to all stages. Model-tier eval (#95 / epic #109): sonnet stays the reliable tier; whether a cheaper or local model holds each stage's floor is the open question. All four stages now have an offline gold-set benchmark in `dev/experiments/model-tier/` (extraction, synthesis, validation, enrichment), each scored on its own discrimination axis (over-claim, poison-recall + false-correction, false-CANDIDATE), adversarially reviewed by two codex passes — the recurring failure is restraint under surface similarity, not transcription. Design half done; local scoring by liminal + the live layers (enrich search-recall, validator shadow test) remain.

---

Full sources:
- .claude/memory-bank/tech-context.md (deployments, services, infrastructure)
- .claude/memory-bank/system-patterns.md (architecture, patterns, workflows)
- .claude/memory-bank/active-context-S*.md (current session focus + handoff)
- CLAUDE.md (project gotchas)
- ~/chungus/dev/CLAUDE.md (workspace gotchas, communication style)
