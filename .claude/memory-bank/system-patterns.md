# stacks System Patterns

## Architecture

Three-layer plugin:

1. **Skills** (user-facing): `init-library`, `new-stack`, `catalog-sources`, `audit-stack`, `enrich-stack`, `process-inbox`, `lookup`. Each is a SKILL.md with a procedural walkthrough.
2. **Agents**: 4 workers (`source-extractor`, `article-synthesizer`, `validator`, `enrichment`). Scale-sensitive dispatch (sharding work across N sub-agents) is done parent-side by the `catalog-sources`, `audit-stack`, and `enrich-stack` skills directly — there are no orchestrator agents.
3. **Templates** (scaffolding): `templates/library/` and `templates/stack/` are copied into user repos to bootstrap structure.

The plugin itself holds no knowledge. It manipulates user-owned library repos.

## Key Flows

### Library creation
`/stacks:init-library {path}` → copy `templates/library/` to path → create private GitHub repo → write `~/.config/stacks/config.json` pointing at the new library.

### Stack creation
`/stacks:new-stack {name}` (from within a library) → copy `templates/stack/` to `{name}/` → register in library's `catalog.md`.

### Catalog pipeline (W0 → W4)
`/stacks:catalog-sources [stack]` → Step 3.5 convert non-text sources (`convert-sources.sh`: PDF→pdfplumber text, `.docx`→pandoc, spreadsheets/slides/legacy Office→libreoffice; images/scanned-PDFs/unknown-binaries skipped+reported; converted originals archived to gitignored `sources/.raw/`; runs before enumeration so the agent only ever sees text) → W0 enumerate `sources/incoming/` (these ARE the new-source set; a paren-in-filename gate fails early) → W1 source-extractor (parallel, 1 source per agent for source isolation; slug immutability enforced; writes `dev/extractions/{batch_id}-concepts.md`) → W1b `dedup-extractions.py` slug-collision dedup (merges `source_paths[]` across shared slugs, writes one self-contained `_dedup-{slug}.md` per slug plus `_dedup-meta.txt` of counts the parent sources) → W2 article-synthesizer (parallel per unique concept, strip-on-rewrite rule; inline wave-cap of 25 agents per wave) → W2 tag drift check (`normalize-tags.sh`) halts on out-of-vocab tags against `STACK.md` `allowed_tags:`, skipped if absent → W3 source filing to publisher dirs → W4 MoC regeneration (`regenerate-moc.sh`) preserving `## Reading Paths`.

### Inbox routing
`/stacks:process-inbox` (from any repo) → read library's `inbox/*.md` → classify each against existing stacks via content + source metadata → move matched to target stack's `sources/incoming/` → report unmatched. Routing only (no quality gate).

### Audit pipeline (stateless drift report)
`/stacks:audit-stack {stack}` → A1 dispatch the `validator` agent over articles (one agent unless article count exceeds the 25 cap, then inline `${ARTICLES[@]:i:CAP}` slices in parallel, each with a `BATCH_TAG`). Each validator strips legacy marks, **fixes claims that contradict their cited source in place** (excludes `sources/incoming/` and `sources/trash/`), records corrections + soft spots (claims not tied to a source) to `dev/audit/_audit-${BATCH_TAG}.md`, and sets `last_verified`. No inline body marks. Parent re-gates each article via `gate-batch.sh ... article-validated` (shape = populated `last_verified` date). → bash report: aggregate the `_audit-*.md` batch files into `dev/audit/report.md` (corrections applied + soft spots), delete the batch files. → log + commit.

Each audit run is independent: the validator re-marks from scratch and the report is rebuilt from the current marks. There is no `findings.md` ledger, no carry-forward, no convergence pass-loop, and no glossary/invariants/contradictions synthesis — those (and the catalog↔audit extraction-hash flywheel) were removed in 0.21.0.

### Enrich pipeline (gap → source acquisition)
`/stacks:enrich-stack {stack}` slots `audit → enrich → catalog`: it acquires sources for **gaps**, then closes the loop (runs `catalog-sources` + `audit-stack` itself). A gap is either an audit soft spot (a claim with no cited source, from `dev/audit/soft-spots.tsv`) or a **lookup miss** (a query the stack could not answer, mined from telemetry by `lookup-misses.sh`; sentinel slug `lookup-miss`, no home article). Step 3 stale-drops soft spots whose claim left the article, appends misses, and dispatches the `enrichment` agent (CAP=12) one source per gap: web-search, verify the source grounds the *specific* claim (not just the topic), tier it against `STACK.md`, dedup by URL. Two staging modes: **interactive** (default) presents findings and stages only operator-approved sources; **`--auto`** (lookup's hands-free path) skips the prompt and auto-stages `CANDIDATE` verdicts only (tier 1-3, quote re-verified after fetch — never `WEAK`/`DUP`/`NOSOURCE`). `--query <text>` scopes a run to exactly one gap (the live miss path uses it so one lookup never enriches the whole backlog). No persistent enrichment ledger; each run derives its work fresh.

### Lookup
`/stacks:lookup {question}` (from any repo) → read `~/.config/stacks/config.json` → open library catalog + per-stack `index.md` (resolve `--stack {name|a,b,c}` scope, else all stacks) → **recognize** matching articles over the `## Articles` routing map (each entry `- [[slug|title]] — {routing line}`; the LLM matches on meaning), supplemented by `rank-articles.sh` keyword rank over bodies for body-content matches and un-migrated stacks → load the matched articles → synthesize a cited answer → optional Step 7 Karpathy-loop file-back (extend an existing article or write a new one, then commit). Article-only; the legacy guide mode and the `extraction_hash` frontmatter field are gone.

**Auto-enrich on a miss (#69):** when lookup recognizes no article (a miss), it logs the miss (telemetry, with the searched stack) then invokes `/stacks:enrich-stack {stack} --auto --query "{query}"` hands-free — research the gap, auto-stage a `CANDIDATE` source, catalog + re-audit, then retry the query and return the enriched answer. `--query` keeps it scoped to the one missed query (0.37.0 fix; 0.36.0 had it enriching the whole backlog off a single miss).

**Routing map (project-brief "Design principle", #59):** `index.md` is a concept-routing map — the synthesizer emits a `routing:` frontmatter line per article (what it covers / questions it answers, in asker's terms), `regenerate-moc.sh` composes those into the `## Articles` list, and `/stacks:lookup` recognizes over them. Articles synthesized before #59 carry no `routing:`, so they render as bare title links until re-cataloged (no backfill shipped — that's an LLM batch over existing libraries). The two axes the whole system optimizes are retrieval friction (the path to the right article) and per-article truthfulness (the article matches its sources).

## Parent-side sharded dispatch

The scale-sensitive waves (catalog W1/W2, audit A1) are sharded and dispatched directly by the parent skill, not by an orchestrator agent. Orchestrator agents were removed because nested Task dispatch was unreliable: when the harness dropped Task on a nested call, the orchestrator silently fell back to inline execution and bundled every shard into one context, hitting "Prompt is too long" on exactly the stacks sharding was meant to keep below the ceiling. Parent-side dispatch keeps Task usage shallow (always reachable) and lets the parent run all deterministic pieces (dedup, per-slug split, wave gating) as code.

Per-wave bounds: 1 source per source-extractor agent (W1, prevents concept-bleed across sources); 25 agents per W2 wave; 25 articles per validator agent (audit A1), sliced into more agents above that. All sharding uses the inline `${ARRAY[@]:i:CAP}` idiom — there is no `shard-batches.sh`. The parent runs the `gate-batch.sh` write-or-fail + structure gate after each fan-in.

## Write-or-fail gate

Every agent-producing wave gates through `gate-batch.sh {epoch} {label} {kind} {path}...`. The caller captures `DISPATCH_EPOCH=$(date +%s)` immediately before dispatch; after fan-in each expected path must be non-empty AND have mtime strictly newer than the epoch (size+mtime check, folded into gate-batch in 0.21.0 from the former standalone `assert-written.sh`), then pass the `assert-structure.sh` content-shape check for `{kind}` (`-` skips structure). Both halves matter: size alone misses a stale pre-existing file, mtime alone misses an empty write. The gate enumerates expected file paths, never a directory (dir mtime does not advance on in-place file edits). A sub-agent returns only text, no exit code, so this file-based gate is how the parent confirms the agent actually produced output.

## Slug immutability invariant

W1 source-extractor cannot rename an existing article's slug — it matches by claim overlap and reuses the existing slug as both `slug` and `target_article`. Combined with W1b dedup, this eliminates silent overwrite by parallel W2 dispatches writing to the same filename.

## Marketplace Registration Pattern

Directory-source plugin:
- `marketplace.json` declares `"source": "./"` so the plugin lives at repo root
- `install.sh` adds entries to `~/.claude/settings.json` under `extraKnownMarketplaces` and `enabledPlugins`
- Updates happen via `git pull`, no cache refresh needed

This mirrors the ChuggiesMart pattern — same mechanism, single-plugin variant.

## Known Weak Spots

- W4 MoC generator (`regenerate-moc.sh`) and the tag parse in `normalize-tags.sh` use `awk`; not exercised against mawk-only environments. (Both now parse inline and block tag forms — fixed 0.37.0.)
- **Shell state does not persist between Bash blocks** (env vars/functions are lost; cwd persists). The skills set `STACK`/`SCRIPTS_DIR`/arrays/epochs in one block and use them in later blocks, relying on the model to re-thread them — fragile for derived state (a pre-dispatch epoch can't be re-derived). Bit the 0.36.0 lookup auto-path twice. Structural fix (move orchestration into scripts) tracked in **#72**. See also the stacks CLAUDE.md gotcha.
- **Output gates prove a file was written, not that every dispatched item was processed.** `gate-batch.sh`/`assert-structure.sh` check shape + freshness, not per-item coverage, and the audit gate keys on `last_verified == today` (a same-day rerun passes articles an aborted validator skipped). Run-manifest redesign tracked in **#71**.
- Lookup-miss enrichment is driven off global telemetry that can't tell two libraries apart and never marks a miss resolved (batch path only; the live `--query` path is unaffected). Tracked in **#73**.
