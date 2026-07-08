<!--
Start-brief: distilled orientation loaded by /start.
Distilled 2026-07-07 from:
  tech-context.md @ ed982d8c1eb2df38b25b57ea5ae278f529ca05c9
  system-patterns.md @ c1c7bb567c1561c05697f0ff02dad02ddffa7f58
Run /workspace-toolkit:refresh-start-brief when source files have drifted substantively.
-->

# stacks Start Brief

Claude Code plugin for building and maintaining curated domain knowledge libraries. Sources are cataloged into article-per-concept wiki entries (flat `articles/` directory) queryable with `/stacks:lookup` from any repo; an audit pass validates each article against its cited sources and writes a fresh drift report. This repo is the tool, not a library: no knowledge content lives here.

## Tech context

### Deployment and registration

- Directory-source plugin: `marketplace.json` declares `"source": "./"`, so it loads directly from this repo root. No build step, no cache refresh; `git pull` is the update mechanism. Restart Claude Code to pick up changes.
- `bash scripts/install.sh` writes `extraKnownMarketplaces` + `enabledPlugins` entries into `~/.claude/settings.json` (mirrors ChuggiesMart).
- `~/.config/stacks/config.json` (written by `/stacks:init-library`) points `lookup` + `process-inbox` at the active library. Current library: `/Users/chris/chungus/dev/library-stack` (repo `git@github.com:chuggies510/library-stack.git`, branch `main`).
- Version sync: `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (`.plugins[0].version`) must match every change, else the launcher shows stale. Bump both plus a CHANGELOG entry per change.
- Repo: `git@github.com:chuggies510/stacks.git` (HTTPS remote, no SSH socket needed to push). Commits go direct to master. Issues: `gh issue list --state open`.

### Tooling and dependencies

- Pure markdown + bash plugin. No package manager, no build step, no `package.json`/`pyproject.toml`.
- Core runtime deps: `jq` (version/marketplace parse), `python3` (W1b dedup, `dedup-extractions.py`), `awk` (W4 MoC + tag parse), Linux `stat -c %Y` for mtime (macOS/BSD unsupported).
- Document-ingest deps (convert stage only): `uv` + `pdfplumber` (PDF), `openpyxl` (multi-sheet `.xlsx` → one CSV sidecar per sheet, 0.51.0), `pandoc` (.docx), `libreoffice` (slides/legacy Office + `.xls`/`.ods`, headless; the single-sheet fallback when openpyxl is absent). All fetched ephemerally via `uv run --no-project --with`; a missing tool skips that file with a report, never crashes the pipeline. A failed input is named in the run summary (0.51.0).
- Tests: `bats` (`tests/gate-batch.bats`, `tests/assert-structure.bats`, `tests/dedup-extractions.bats`). Pipeline + gate scripts carry inline `--self-check` harnesses (red-when-broken).
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

1. Skills (user-facing `skills/{name}/SKILL.md`): `init-library`, `new-stack`, `catalog-sources`, `audit-stack`, `enrich-stack`, `process-inbox`, `lookup`, `ingest-book`, `using-stacks`.
2. Agents (workers): `source-extractor`, `article-synthesizer`, `validator`, `enrichment`. No orchestrator agents.
3. Templates: `templates/library/` and `templates/stack/` copied into user repos to scaffold.

### File conventions

- `agents/` definitions; `scripts/` lifecycle (install/uninstall/update/init/locate-plugin-root/loop) plus pipeline helpers; `references/` reference docs; `dev/` planning artifacts (not shipped).
- Articles are flat (no typed subdirs), 300-800 words (stretch 1200), plain markdown with inline `[source-slug]` citations.
- Pipeline helpers: `gate-batch.sh` (write-or-fail size+mtime + `assert-structure.sh` shape), `convert-sources.sh`, `dedup-extractions.py` (W1b slug merge), `normalize-tags.sh`, `regenerate-moc.sh` (W4 MoC), `rewrite-source-refs.sh` (incoming→publisher after filing), `collision-dest.sh`, `check-coverage.sh` (per-item + per-batch coverage reconciliation).

### Article contract SSOT (`references/article-contract.md`)

One checked-in definition of the article frontmatter schema, bare source-ref form, per-source tier semantics, and the W1 concept-block shape, `assert-structure.sh` named as enforcement. Six stages point at it instead of restating (STACK.md template, the four agent defs, catalog-sources, lookup). The #77 schema-drift cluster is closed (0.49.0): `extraction_hash` and `updated` are both dead and stripped from the corpus; source-refs are bare-only (`sources/{publisher}/{file}.md`, no `{stack}/` prefix); tier attaches per `source_path` — `dedup-extractions.py` carries a `source_path → tier` map and emits it inline per source (`- {path} (tier N)`), the synthesizer reads it for hierarchy weighting and writes bare paths into `sources:`.

### Catalog pipeline (convert → W0 to W4)

`/stacks:catalog-sources [stack]`: Step 3.5 `convert-sources.sh` (images/scanned-PDFs/unknown-binaries skipped + reported; originals archived to gitignored `sources/.raw/`) → W0 enumerate `sources/incoming/` → W1 `source-extractor` parallel, 1 source per agent, writes `dev/extractions/{batch_id}-concepts.md` → W1b `dedup-extractions.py` merges `source_paths[]` (each keeping its emitting block's tier inline) → W2 `article-synthesizer` parallel per unique concept, 25-agent wave cap → W2 tag-drift check → W3 source filing → W4 MoC regen.

### Audit and enrich pipeline (stateless)

`/stacks:audit-stack {stack}`: dispatch `validator` over articles; each fixes claims contradicting their cited source in place, records corrections + soft spots + a per-article `VALIDATED` receipt row, sets `last_verified`. Each run is independent (no carry-forward ledger). `/stacks:enrich-stack {stack}` acquires sources for **gaps** = audit soft spots + lookup misses; the `enrichment` agent web-searches one grounding source per gap. Two staging modes: interactive (operator-approved) and `--auto` (lookup's hands-free path, CANDIDATE verdicts only). Lookup misses are scoped per-library + a 30-day recency window (0.51.0/#73): each lookup records its resolved library in telemetry, `lookup-misses.sh` filters to the enriching library and drops stale misses.

### Pipeline orchestration (epic #87 + #77 cluster, both closed)

Deterministic control flow lives in one checked-in script per pipeline (`scripts/pipeline/{catalog,audit,enrich}.sh`) with `prep|gate|finish` phases (catalog adds `queue|dedup|gate-w1|gate-w2`); state crosses phases via `dev/<phase>/{run.env,dispatch.tsv}` files, never shell env (#72). `scripts/check-coverage.sh` reconciles the dispatch manifest against per-item receipt rows, failing by name on omission/duplicate/unknown/missing (#71). Its `--batched` mode (0.49.0, #92) reconciles each batch's dispatched ids against only its own receipt file — catching a cross-batch misattribution the global union missed, and failing on a manifest tag with no receipt-file pair; the audit + enrich gates wire it in, catalog uses per-path `gate-batch.sh` instead. **Both epics shipped: #87 (enrich 0.46.0, audit 0.47.0, catalog 0.48.0 + SSOT + gate 0.45.x); #77 schema-drift cluster (0.49.0, #88/#89/#90/#92).**

### Other flows

- `/stacks:init-library {path}` / `/stacks:new-stack {name}` (like every stacks skill, runs from any repo — resolves the library from config, not cwd; the field-usage model, 0.50.0/#54) / `/stacks:process-inbox` (routing only) / `/stacks:ingest-book {stack} {pdf}` (handbook PDF → deep-reference tier `{stack}/reference/{book}/`, schema in `references/reference-tier.md`).
- `/stacks:lookup {question}` (north star): read config → open catalog + per-stack `index.md` → recognize matching articles over the `## Articles` routing map + reference chapters → synthesize cited answer → optional Karpathy-loop file-back. **On a miss**, logs it then auto-enriches hands-free (`enrich-stack {stack} --auto --query`), catalogs + re-audits, retries (#69). Optimizes two axes: retrieval friction (per-article `routing:` lines) and per-article truthfulness (article matches its sources).

### Cross-cutting harness patterns

- Parent-side sharded dispatch: scale-sensitive waves (catalog W1/W2, audit A1) sharded and dispatched directly by the parent skill, not an orchestrator (nested Task dispatch silently fell back to inline). Bounds: 1 source/W1 agent, 25 agents/W2 wave, per-agent article caps.
- Write-or-fail gate: caller captures `DISPATCH_EPOCH` before dispatch; each expected file must be non-empty AND mtime strictly newer than the epoch, then pass `assert-structure.sh`. Sub-agents return only text, no exit code, so the file-based gate is the success signal.
- Shell env does NOT persist between a skill's Bash blocks (cwd does). Re-derive state per block, or pass via a nested skill's `$ARGUMENTS`; the three pipelines avoid this structurally via `dev/<phase>/` state files.

### Known weak spots

- `regenerate-moc.sh` / `normalize-tags.sh` use `awk`, not tested against mawk-only environments.
- Lookup-miss enrichment mines global telemetry; per-library + 30-day recency scoping shipped (0.51.0/#73, closed). Still deferred: a durable ledger that marks a miss *resolved* once its article lands — the recency window is the stand-in.

---

Full sources:
- .claude/memory-bank/tech-context.md (deployments, services, infrastructure)
- .claude/memory-bank/system-patterns.md (architecture, patterns, workflows)
- .claude/memory-bank/active-context-S*.md (current session focus + handoff)
- CLAUDE.md (project gotchas)
- ~/chungus/dev/CLAUDE.md (workspace gotchas, communication style)
