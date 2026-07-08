<!--
Start-brief: distilled orientation loaded by /start.
Distilled 2026-07-07 from:
  tech-context.md @ 16cc60cff0a612acbd95cf2e1cd119da13d18fbf
  system-patterns.md @ b27153e7f555b7b030e94c19957270099d7ba7f4
Run /workspace-toolkit:refresh-start-brief when source files have drifted substantively.
-->

# stacks Start Brief

Claude Code plugin for building and maintaining curated domain knowledge libraries. Sources are cataloged into article-per-concept wiki entries (flat `articles/` directory) queryable with `/stacks:lookup` from any repo; an audit pass validates each article against its cited sources and writes a fresh drift report. This repo is the tool, not a library: no knowledge content lives here.

## Tech context

### Deployment and registration

- Directory-source plugin: `marketplace.json` declares `"source": "./"`, so it loads directly from this repo root. No build step, no cache refresh; `git pull` is the update mechanism. Restart Claude Code to pick up changes.
- `bash scripts/install.sh` writes `extraKnownMarketplaces` + `enabledPlugins` entries into `~/.claude/settings.json` (mirrors ChuggiesMart).
- `~/.config/stacks/config.json` (written by `/stacks:init-library`) points `lookup` + `process-inbox` at the active library.
- Version sync: `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions must match every change, else the launcher shows stale. Bump both plus a CHANGELOG entry per change.
- Repo: `git@github.com:chuggies510/stacks.git`. Commits go direct to master. Issues: `gh issue list --state open`.

### Tooling and dependencies

- Pure markdown + bash plugin. No package manager, no build step, no `package.json`/`pyproject.toml`.
- Core runtime deps: `jq` (version/marketplace parse), `python3` (W1b dedup, `dedup-extractions.py`), `awk` (W4 MoC + tag parse), Linux `stat -c %Y` for mtime (macOS/BSD unsupported).
- Document-ingest deps (convert stage only): `uv` + `pdfplumber` (PDF, fetched ephemerally via `uv run --no-project --with`), `pandoc` (.docx), `libreoffice` (spreadsheets/slides/legacy Office, headless). A missing tool skips that file with a report, never crashes the pipeline.
- Tests: `bats` (`tests/gate-batch.bats`, `tests/assert-structure.bats`).
- Skill frontmatter is only `name` + `description` (description starts "Use when..."). No `version`/`allowed-tools`/`thinking`. Agent frontmatter: `tools`, `model`, `description`, 3+ worked examples in the prompt.

### Test cycle

```bash
bash scripts/install.sh        # register plugin; restart Claude Code, then:
/stacks:init-library ~/tmp/test-library
/stacks:new-stack test-stack
/stacks:catalog-sources test-stack
/stacks:audit-stack test-stack
/stacks:lookup some question
rm -rf ~/tmp/test-library      # do not commit test library content
```

## System patterns

### Core architecture

Three-layer plugin; holds no knowledge, manipulates user-owned library repos.

1. Skills (user-facing `skills/{name}/SKILL.md`): `init-library`, `new-stack`, `catalog-sources`, `audit-stack`, `enrich-stack`, `process-inbox`, `lookup`.
2. Agents (workers): `source-extractor`, `article-synthesizer`, `validator`, `enrichment`. No orchestrator agents.
3. Templates: `templates/library/` and `templates/stack/` copied into user repos to scaffold.

### File conventions

- `agents/` definitions; `scripts/` lifecycle (install/uninstall/update/init/locate-plugin-root/loop) plus pipeline helpers; `references/` holds only `default-topic-template.md`; `dev/` planning artifacts (not shipped).
- Articles are flat (no typed subdirs), 300-800 words (stretch 1200), plain markdown with inline `[source-slug]` citations.
- Pipeline helpers: `gate-batch.sh {epoch} {label} {kind} {path}...` (write-or-fail size+mtime + `assert-structure.sh` shape, `-` skips); `convert-sources.sh` (non-text to text); `dedup-extractions.py` (W1b slug merge); `normalize-tags.sh {root}` (halts on out-of-vocab tags vs `STACK.md allowed_tags:`); `regenerate-moc.sh {root}` (W4 MoC, preserves `## Reading Paths`, appends each article's `routing:` line); `rewrite-source-refs.sh` (fix citations after source filing); `collision-dest.sh` (non-colliding filename).

### Catalog pipeline (convert → W0 to W4)

`/stacks:catalog-sources [stack]`: Step 3.5 `convert-sources.sh` (runs BEFORE enumeration; images/scanned-PDFs/unknown-binaries skipped + reported; converted originals archived to gitignored `sources/.raw/`; the source-extractor only ever sees readable text) → W0 enumerate `sources/incoming/` (new-source set; paren-in-filename gate fails early) → W1 `source-extractor` parallel, 1 source per agent for isolation, slug immutability, writes `dev/extractions/{batch_id}-concepts.md` → W1b `dedup-extractions.py` merges `source_paths[]` across shared slugs, writes one `_dedup-{slug}.md` per slug plus `_dedup-meta.txt` → W2 `article-synthesizer` parallel per unique concept, strip-on-rewrite, 25-agent wave cap → W2 tag-drift check (`normalize-tags.sh`, skipped if `allowed_tags:` absent) → W3 source filing to publisher dirs → W4 MoC regen (`regenerate-moc.sh`).

### Audit and enrich pipeline (stateless)

`/stacks:audit-stack {stack}`: A1 dispatch `validator` over articles (one agent unless count exceeds the 25 cap, then inline `${ARRAY[@]:i:CAP}` slices in parallel, each with a `BATCH_TAG`). Each validator fixes claims that contradict their cited source in place (excludes `sources/incoming/` + `sources/trash/`), records corrections + soft spots to `dev/audit/_audit-${BATCH_TAG}.md`, sets `last_verified`, no inline body marks. Parent re-gates each article (`article-validated` = populated `last_verified` date) → aggregate into `dev/audit/report.md` → commit. Each run is independent: re-checks from scratch, no findings ledger, no carry-forward, no convergence loop, no glossary synthesis. `/stacks:enrich-stack {stack}` acquires sources for **gaps** = audit soft spots (`dev/audit/soft-spots.tsv`) + lookup misses (mined from telemetry by `lookup-misses.sh`, sentinel slug `lookup-miss`). The `enrichment` agent web-searches one grounding source per gap, verifies it grounds the specific claim, tiers + dedups it. Two staging modes: interactive (default) stages only operator-approved sources; `--auto` (lookup's hands-free path) auto-stages `CANDIDATE` verdicts only (tier 1-3, quote re-verified). `--query <text>` scopes a run to one gap. Then it closes the loop (catalog + audit). Slots between audit and catalog.

### Other flows

- `/stacks:init-library {path}`: copy `templates/library/` → create private GitHub repo → write config.
- `/stacks:new-stack {name}`: copy `templates/stack/` to `{name}/` → register in library `catalog.md`.
- `/stacks:process-inbox`: read library `inbox/*.md` → classify against existing stacks via content + source metadata → move matched to target stack's `sources/incoming/` → report unmatched. Routing only.
- `/stacks:ingest-book {stack} {pdf}` (0.42–0.43): converts a handbook PDF chapter-by-chapter (doc-tools faithful mode) into the **deep-reference tier** `{stack}/reference/{book}/` (gated `.md` with printed-page provenance + generated `index.md`); lookup reads it behind the articles. Serial for 1–3 chapters; a `Workflow`-batch run mode fans a whole volume out in parallel (needs operator multi-agent opt-in). Schema in `references/reference-tier.md`.
- `/stacks:lookup {question}` (north star): read config → open catalog + per-stack `index.md` (resolve `--stack {name|a,b,c}`, else all) → recognize matching articles over the `## Articles` routing map (each entry `- [[slug|title]] — {routing line}`, LLM matches on meaning), supplemented by `rank-articles.sh` keyword rank → load matches → synthesize cited answer → optional Karpathy-loop file-back (extend or write an article, then commit). **On a miss** (no article recognized), lookup logs it (with the searched stack) then auto-enriches hands-free: `enrich-stack {stack} --auto --query "{query}"` researches just that query, auto-stages a CANDIDATE source, catalogs + re-audits, then retries and answers (#69). The system optimizes two axes: retrieval friction (the path to the right article via per-article `routing:` lines) and per-article truthfulness (article matches its sources).

### Cross-cutting harness patterns

- Parent-side sharded dispatch: scale-sensitive waves (catalog W1/W2, audit A1) are sharded and dispatched directly by the parent skill, not an orchestrator. Orchestrators were removed because nested Task dispatch silently fell back to inline and hit "Prompt is too long". Bounds: 1 source per W1 agent, 25 agents per W2 wave, 25 articles per validator. Sharding uses inline `${ARRAY[@]:i:CAP}`.
- Write-or-fail gate: caller captures `DISPATCH_EPOCH=$(date +%s)` before dispatch; each expected file must be non-empty AND mtime strictly newer than the epoch (size alone misses a stale file, mtime alone misses an empty write), then pass `assert-structure.sh`. `gate-batch.sh` mtime is portable (GNU `stat -c %Y` + BSD `-f %m` fallback). Sub-agents return only text, no exit code, so the file-based gate is the success signal. The gate enumerates file paths, never a directory.
- Slug immutability: W1 cannot rename an existing article's slug — it matches by claim overlap and reuses the slug. With W1b dedup this eliminates silent overwrite by parallel W2 writes to the same filename.
- Shell env does NOT persist between a skill's Bash blocks (cwd does). Re-derive state in the block that needs it, or pass it via a nested skill's `$ARGUMENTS` (never an env var). Bit the lookup auto-path twice; structural fix is **epic #87**.

### Pipeline orchestration migration (epic #87, in progress)

Deterministic pipeline control flow lives in one checked-in script per pipeline (`scripts/pipeline/{catalog,audit,enrich}.sh`) with `prep|gate|finish` phases (catalog adds `queue|dedup|gate-w1|gate-w2`); state crosses phases via `dev/<phase>/{run.env,dispatch.tsv}` files, never shell env (#72). A shared `scripts/check-coverage.sh` reconciles the dispatch manifest against per-item receipt rows, failing by name on omission/duplicate/unknown/missing (#71). `references/article-contract.md` is the one SSOT for the article schema (five stages point at it instead of restating). **Epic #87 complete: all three pipelines shipped (enrich 0.46.0, audit 0.47.0, catalog 0.48.0) + the SSOT + the gate (0.45.x).** The Workflow-tool fan-out substrate was measured against Agent-calls (T6) and deferred — record in `dev/t6-measurement/decision.md`.

### Known weak spots

- `regenerate-moc.sh` / `normalize-tags.sh` use `awk`, not tested against mawk-only environments (both now parse inline + block tag forms).
- Per-item coverage now enforced across all three pipelines (enrich gap_ids, audit `VALIDATED` receipts, catalog 1:1 per-file presence); the `last_verified == today` date-gate is retired (#71 / #87 done). Remaining: global-not-per-batch reconciliation gap: #92.
- Lookup-miss enrichment runs off global telemetry that can't tell libraries apart or mark a miss resolved — batch path only (#73).

---

Full sources:
- .claude/memory-bank/tech-context.md (deployments, services, infrastructure)
- .claude/memory-bank/system-patterns.md (architecture, patterns, workflows)
- .claude/memory-bank/active-context-S*.md (current session focus + handoff)
- CLAUDE.md (project gotchas)
- ~/chungus/dev/CLAUDE.md (workspace gotchas, communication style)
