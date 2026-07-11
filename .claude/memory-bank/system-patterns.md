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
`/stacks:new-stack {name}` (from any repo, like every stacks skill — resolves the configured library from `~/.config/stacks/config.json`, or cwd if it is itself a library, then scaffolds there) → copy `templates/stack/` to `{name}/` → register in library's `catalog.md`. **Field-usage model (0.50.0/#54):** the build/maintain skills are NOT library-cwd-bound; they resolve the library from config and operate in place, because most stack work happens in the field (a consuming repo — an audit, a PCA), not inside the library. new-stack's scaffold is one Bash block that re-derives names per block (0.50.1/#54 codex fix — the harness wipes env between blocks, so a cross-block `$STACK_NAME` was empty and scaffolding failed from a field repo).

### Catalog pipeline (W0 → W4)
`/stacks:catalog-sources [stack]` → Step 3.5 convert non-text sources (`convert-sources.sh`: PDF→pdfplumber text, `.docx`→pandoc, spreadsheets/slides/legacy Office→libreoffice; images/scanned-PDFs/unknown-binaries skipped+reported; converted originals archived to gitignored `sources/.raw/`; runs before enumeration so the agent only ever sees text) → W0 enumerate `sources/incoming/` (these ARE the new-source set; a paren-in-filename gate fails early) → W1 source-extractor (parallel, 1 source per agent for source isolation; slug immutability enforced; writes `dev/extractions/{batch_id}-concepts.md`) → W1b `dedup-extractions.py` slug-collision dedup (merges `source_paths[]` across shared slugs, writes one self-contained `_dedup-{slug}.md` per slug plus `_dedup-meta.txt` of counts the parent sources) → W2 article-synthesizer (parallel per unique concept, strip-on-rewrite rule; inline wave-cap of 25 agents per wave) → W2 tag drift check (`normalize-tags.sh`) halts on out-of-vocab tags against `STACK.md` `allowed_tags:`, skipped if absent → W3 source filing to publisher dirs → W4 MoC regeneration (`regenerate-moc.sh`) preserving `## Reading Paths`.

### Inbox routing
`/stacks:process-inbox` (from any repo) → read library's `inbox/*.md` → classify each against existing stacks via content + source metadata → move matched to target stack's `sources/incoming/` → report unmatched. Routing only (no quality gate).

### Audit pipeline (stateless drift report)
`/stacks:audit-stack {stack}` → A1 dispatch the `validator` agent over articles (one agent unless article count exceeds the 25 cap, then inline `${ARTICLES[@]:i:CAP}` slices in parallel, each with a `BATCH_TAG`). Each validator strips legacy marks, **fixes claims that contradict their cited source in place** (excludes `sources/incoming/` and `sources/trash/`), records corrections + soft spots (claims not tied to a source) to `dev/audit/_audit-${BATCH_TAG}.md`, and sets `last_verified`. No inline body marks. Parent re-gates each article via `gate-batch.sh ... article-validated` (shape = populated `last_verified` date). → bash report: aggregate the `_audit-*.md` batch files into `dev/audit/report.md` (corrections applied + soft spots), delete the batch files. → log + commit.

Each audit run is independent: the validator re-marks from scratch and the report is rebuilt from the current marks. There is no `findings.md` ledger, no carry-forward, no convergence pass-loop, and no glossary/invariants/contradictions synthesis — those (and the catalog↔audit extraction-hash flywheel) were removed in 0.21.0.

### Enrich pipeline (gap → source acquisition)
`/stacks:enrich-stack {stack}` slots `audit → enrich → catalog`: it acquires sources for **gaps**, then closes the loop (runs `catalog-sources` + `audit-stack` itself). A gap is either an audit soft spot (a claim with no cited source, from `dev/audit/soft-spots.tsv`) or a **lookup miss** (a query the stack could not answer, mined from telemetry by `lookup-misses.sh`; sentinel slug `lookup-miss`, no home article). `enrich.sh prep` stale-drops soft spots whose claim left the article, appends misses, and shards the gaps CAP=5 into `dispatch.tsv`; the skill then dispatches the `enrichment` agent one source per gap: web-search, verify the source grounds the *specific* claim (not just the topic), tier it against `STACK.md`, dedup by URL. Two staging modes: **interactive** (default) presents findings and stages only operator-approved sources; **`--auto`** (lookup's hands-free path) skips the prompt and auto-stages `CANDIDATE` verdicts only (tier 1-3, quote re-verified after fetch — never `WEAK`/`DUP`/`NOSOURCE`). `--query <text>` scopes a run to exactly one gap (the live miss path uses it so one lookup never enriches the whole backlog). No persistent enrichment ledger; each run derives its work fresh.

### Lookup
`/stacks:lookup {question}` (from any repo) → read `~/.config/stacks/config.json` → open library catalog + per-stack `index.md` (resolve `--stack {name|a,b,c}` scope, else all stacks) → **recognize** matching articles over the `## Articles` routing map (each entry `- [[slug|title]] — {routing line}`; the LLM matches on meaning), supplemented by `rank-articles.sh` keyword rank over bodies for body-content matches and un-migrated stacks → load the matched articles → synthesize a cited answer → optional Step 7 Karpathy-loop file-back (extend an existing article or write a new one, then commit). Article-only; the legacy guide mode and the `extraction_hash` frontmatter field are gone.

**Auto-enrich on a miss (#69):** when lookup recognizes no article (a miss), it logs the miss (telemetry, with the searched stack) then invokes `/stacks:enrich-stack {stack} --auto --query "{query}"` hands-free — research the gap, auto-stage a `CANDIDATE` source, catalog + re-audit, then retry the query and return the enriched answer. `--query` keeps it scoped to the one missed query (0.37.0 fix; 0.36.0 had it enriching the whole backlog off a single miss).

**Routing map (project-brief "Design principle", #59):** `index.md` is a concept-routing map — the synthesizer emits a `routing:` frontmatter line per article (what it covers / questions it answers, in asker's terms), `regenerate-moc.sh` composes those into the `## Articles` list, and `/stacks:lookup` recognizes over them. Articles synthesized before #59 carry no `routing:`, so they render as bare title links until re-cataloged (no backfill shipped — that's an LLM batch over existing libraries). The two axes the whole system optimizes are retrieval friction (the path to the right article) and per-article truthfulness (the article matches its sources).

## Parent-side sharded dispatch

The scale-sensitive waves (catalog W1/W2, audit A1) are sharded and dispatched directly by the parent skill, not by an orchestrator agent. Orchestrator agents were removed because nested Task dispatch was unreliable: when the harness dropped Task on a nested call, the orchestrator silently fell back to inline execution and bundled every shard into one context, hitting "Prompt is too long" on exactly the stacks sharding was meant to keep below the ceiling. Parent-side dispatch keeps Task usage shallow (always reachable) and lets the parent run all deterministic pieces (dedup, per-slug split, wave gating) as code.

Per-wave bounds: 1 source per source-extractor agent (W1, prevents concept-bleed across sources); enrich CAP=5 per `enrichment` agent; catalog W2 and audit A1 slice at 25 per agent. Each pipeline's `prep` phase does the sharding and writes the `dispatch.tsv` manifest; the parent skill reads it and fans out, then the `gate` phase runs the `gate-batch.sh` write-or-fail + structure gate after fan-in. There is no `shard-batches.sh` — the sharding is inline `${ARRAY[@]:i:CAP}` inside the scripts.

## Write-or-fail gate

Every agent-producing wave gates through `gate-batch.sh {epoch} {label} {kind} {path}...`. The pipeline's `prep` phase captures `RUN_ID` (an epoch) into `run.env` before dispatch; at the `gate` phase each expected path must be non-empty AND have mtime strictly newer than that epoch (size+mtime check, folded into gate-batch in 0.21.0 from the former standalone `assert-written.sh`), then pass the `assert-structure.sh` content-shape check for `{kind}` (`-` skips structure). Both halves matter: size alone misses a stale pre-existing file, mtime alone misses an empty write. The gate enumerates expected file paths, never a directory (dir mtime does not advance on in-place file edits). A sub-agent returns only text, no exit code, so this file-based gate is how the parent confirms the agent actually produced output.

## Pipeline orchestration: per-pipeline prep|gate|finish scripts (epic #87)

The deterministic control flow of each fan-out pipeline lives in one checked-in script per pipeline (`scripts/pipeline/{catalog,audit,enrich}.sh`) with phase subcommands, because a bash script cannot spawn subagents so the flow is always `prep` → model dispatch (stays skill prose) → `gate` → `finish` (catalog adds `queue`/`dedup`/`gate-w1`/`gate-w2`). State crosses phases through files under `dev/<phase>/` (`run.env` KEY=VAL carrying `RUN_ID`; `dispatch.tsv` the coverage manifest `batch_tag<TAB>item_id[<TAB>metadata]`), never shell env. This is the structural fix for #72 and the home for the #71 coverage gate. **All three live pipelines shipped: enrich (0.46.0), audit (0.47.0), catalog (0.48.0); each carries an inline `--self-check`.** The Workflow-tool fan-out substrate was measured head-to-head against Agent-calls on a 15-gap enrich run (T6) and **deferred** — substrate-neutral on tokens/wall-clock/yield, its schema/context wins already gate-backstopped and only binding at ~100-item fan-out; record in `dev/t6-measurement/decision.md`.

## Article contract SSOT (`references/article-contract.md`, 0.45.0)

One checked-in definition of the article-file frontmatter schema, bare source-ref form, per-source tier semantics, and the W1 concept-block shape, with `assert-structure.sh` named as enforcement — the same role `reference-tier.md` plays for the deep-reference tier. Five stages that used to restate (and drift on) the schema now point at it (STACK.md template, the four agent defs, catalog-sources, lookup). The #77 schema-drift cluster is closed (0.49.0): `extraction_hash` and `updated` are both dead and stripped from the corpus (#90); tier attaches per `source_path` — `dedup-extractions.py` carries a `source_path → tier` map and emits it inline per source (`- {path} (tier N)`), the synthesizer reads it for hierarchy weighting (#89); source-refs are bare-only, the corpus prefix-strip and lookup's dual-resolution removal done (#88).

## Slug immutability invariant

W1 source-extractor cannot rename an existing article's slug — it matches by claim overlap and reuses the existing slug as both `slug` and `target_article`. Combined with W1b dedup, this eliminates silent overwrite by parallel W2 dispatches writing to the same filename.

## Corpus scope map to worker agents (0.57.0–0.58.0)

Every worker agent makes a corpus-relative judgment — reuse-vs-mint (extractor), what-to-write / what-to-cross-link (synthesizer), is-this-already-sourced (enrich), does-this-claim-belong (validator). Each now receives the `{stack}/index.md` `## Articles` scope map (the `slug — one-line scope` routing lines the library already maintains for lookup) as that judgment's surface, not just a bare slug/URL listing. Falls back to the bare listing when no `## Articles` map exists yet (first catalog run).

- **Extractor** (0.57.0, #95): reuses a slug when a concept falls within an existing article's described scope instead of minting a sub-topic fragment (the #106 fragmentation root). 0.57.1 added the reverse guard — keep distinct existing articles distinct; the scope map can over-correct a weaker tier into *lumping* two articles into one (measured: haiku recall 0.80 on one pass).
- **Synthesizer** (0.58.0, #110): writes within its slug's boundary, cross-links a sibling with `[[slug]]` instead of restating it.
- **Enrich** (0.58.0, #98 agent half): checks whether an already-filed source grounds the claim before spending a web search (topic-aware `DUP`, not URL-equality). The staging-time URL-dedup script bug stays open under #98.
- **Validator** (0.58.0, #98/#106): promotes an uncited-but-already-listed-source claim to a `CORRECTION` (add citation) instead of a soft spot; emits a returned-text structural (lumping/fragmentation) advisory, surfaced in the audit summary — no new audit-file line kind.

The lever generalized from one stage to all four: the pipeline maintains the scope map for lookup; the worker dispatches now hand it over.

## Marketplace Registration Pattern

Directory-source plugin:
- `marketplace.json` declares `"source": "./"` so the plugin lives at repo root
- `install.sh` adds entries to `~/.claude/settings.json` under `extraKnownMarketplaces` and `enabledPlugins`
- Updates happen via `git pull`, no cache refresh needed

This mirrors the ChuggiesMart pattern — same mechanism, single-plugin variant.

## Known Weak Spots

- W4 MoC generator (`regenerate-moc.sh`) and the tag parse in `normalize-tags.sh` use `awk`; not exercised against mawk-only environments. (Both now parse inline and block tag forms — fixed 0.37.0.)
- **Shell state does not persist between Bash blocks** (env vars/functions are lost; cwd persists). Resolved for the fan-out pipelines: catalog, audit, and enrich all run through `scripts/pipeline/*.sh` phases carrying state in `dev/<phase>/` files, no cross-block env (**#72 / epic #87**, see Pipeline orchestration above). The trap remains a live caution for any new SKILL.md Bash-block prose — see the stacks CLAUDE.md gotcha.
- **Output gates now prove per-item coverage, not just that a file was written.** `scripts/check-coverage.sh` (0.45.0, hardened 0.45.1) reconciles a dispatch manifest against per-item receipt rows and fails by name on an omission, duplicate, unknown id, or missing file. Applied across all three pipelines: enrich reconciles gap_ids, audit keys on per-article `VALIDATED` receipts (the `last_verified == today` date-gate is retired — a same-day rerun with a dropped validator now fails by name), and catalog's strict 1:1 item↔file mapping makes `gate-batch.sh`'s per-path presence check the coverage gate (no `check-coverage.sh` needed). The audit/enrich gates reconcile **per batch** (`check-coverage.sh --batched`, 0.49.0 / #92): each batch's dispatched ids are checked against only its own receipt file, catching a cross-batch misattribution the global union missed, and failing if a manifest batch tag has no receipt-file pair.
- **Worker agents pin `model: sonnet` uniformly — now being measured, not yet re-tiered** (#95 / epic #109). Extraction has a gold-set benchmark (`dev/experiments/model-tier/extraction-benchmark.md`); the scope-map pattern (above) is what lets a cheaper tier clear it, but sonnet stays the reliable pick (haiku's cliff recall is variance-prone, 0.80↔1.0) and local models (qwen3-30b-a3b, gemma4-31b, a 122B-A10B straddle — scored by the peer session liminal, `results-liminal-S59.md`) clear the bar only behind a pal-chat harness (the Agent tool reaches only sonnet/haiku/opus/fable). Synthesis/enrichment/validation now have the context fix but no per-stage benchmark yet — that is the next #109 unit.
- Lookup-miss enrichment mines a shared global telemetry log. **Per-library scoping + a 30-day recency window shipped (0.51.0 / #73, now closed):** each `/stacks:lookup` records its resolved library path in telemetry, and `lookup-misses.sh` filters to the enriching library (`select(.library == $lib)`) and drops misses older than `LOOKUP_MISS_WINDOW_DAYS` (default 30; ISO-string cutoff via jq `now`, no `date -d` host trap). Pre-#73 records carry no library and age out — no migration. Still deferred (no longer #73-tracked): a durable gap ledger that marks a miss *resolved* once its article lands; the recency window is the stand-in, re-surfacing an unclosed miss until it ages out.
