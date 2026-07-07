# Spec: pipeline orchestration + article contract into checked-in scripts

**Epic:** the orchestration-SSOT epic (#87), covering the env-persistence root (#72), the coverage-gate gap (#71), the fan-out duplication + enrichment batch size (#76), and the schema half of the drift audit (#77).
**Status:** design artifact, no source edits. Written 2026-07-07.

## Objective

The three fan-out pipelines (catalog, audit, enrich) run their deterministic control flow — argument parsing, sharding math, dispatch epochs, gates, aggregation, cleanup, commits — as bash prose inside each SKILL.md, split across Bash blocks between which shell variables do not survive (#72). The gates prove "a file was freshly written", not "every dispatched item was processed" (#71). The fan-out plumbing is hand-copied per skill, and the enrichment batch size (CAP=12, gaps per research agent) is measured worst-on-every-axis (#76). The article contract (frontmatter fields, source-ref form, tier semantics) is restated in five places and has drifted in all of them (#77).

This spec decides the substrate that fixes the root once, the coverage-manifest mechanism, the enrichment batch size, and the single source of truth for the article contract. Verifiable goal: after implementation, (a) no SKILL.md Bash block reads a variable set in an earlier block, (b) a dropped work item fails its pipeline's gate by name, (c) enrichment dispatches ≤5 gaps per agent, (d) exactly one checked-in artifact defines the article contract and every stage points at it.

## Decision 1 — Substrate: hybrid (per-pipeline orchestration script + Workflow fan-out, phased)

**Recommendation: a hybrid mirroring the ingest-book Step 3B split.** One checked-in orchestration script per pipeline owns everything deterministic; only the model work fans out via the `Workflow` tool, and that migration is phased behind a measurement.

- **Deterministic prep, gating, aggregation, cleanup, and the commit boundary move into one checked-in script per pipeline** (`scripts/pipeline/{catalog,audit,enrich}.sh`, bash — matching the existing helper style; `dedup-extractions.py` stays python). Each script exposes **phase subcommands** (`prep`, `gate`, `finish`) because the model dispatch necessarily interrupts the script: a bash script cannot spawn subagents, so the pipeline is always script-phase → model-dispatch → script-phase.
- **State crosses phases through a run-state file, never shell env.** `prep` writes `dev/<phase>/run.env` (KEY=VAL, the proven `_dedup-meta.txt` pattern) carrying `RUN_ID` (the dispatch epoch/nonce), counts, and paths, plus a **dispatch manifest** `dev/<phase>/dispatch.tsv` (see Decision 2). Later phases re-read them from disk. This is the structural fix for #72: every remaining SKILL.md Bash block is one self-contained script call; nothing rides shell env between blocks.
- **Model fan-out** (the actual `Agent` calls) stays a model action in prose, but the prose shrinks to "dispatch one agent per line of `dispatch.tsv`, grouped by batch_tag" — the shard math (`${ARRAY[@]:i:CAP}`), wave caps, and expected-path construction all live in `prep`.
- **Workflow migration is phased, enrich first.** Per the batch-size experiment issue (#76), prototype `enrich-stack`'s fan-out as a `Workflow` (a checked-in JS orchestrator that spawns agents via `agent()`/`pipeline()`/`parallel()`) and measure it head-to-head against plain parallel `Agent` calls on the same gap set (tokens, wall-clock, candidate yield, false positives). Catalog/audit follow only if the measurement holds; the decision is recorded either way. The scripts in this spec are substrate-agnostic: `prep`/`gate`/`finish` are identical whether the middle is Agent calls or a Workflow, so nothing is built twice.

**Deterministic-vs-model split per pipeline** (what stays bash vs what fans out):

| Pipeline | Deterministic (script) | Model fan-out |
|----------|------------------------|---------------|
| catalog | arg parse, `--from` staging, convert-sources, W0 enumerate, W1 manifest, W1b dedup (python, unchanged), W2 wave manifests, gates, tag drift, W3 filing, W4 MoC, log+commit | W1 source-extractor, W2 article-synthesizer, near-dup merge judgment (Step 5.5, stays interactive) |
| audit | arg parse, article enum + slicing, manifest, coverage gate, report + soft-spots.tsv aggregation, log+commit | A1 validator |
| enrich | arg parse (`--auto`/`--query`), filed-sources listing, stale-check, gap manifest, gate, URL dedup, staging quote re-verify, cleanup | enrichment research agents, operator approval (stays interactive), staged-source WebFetch/Write |

**Rejected:** *Workflow-only* — a workflow script has no filesystem, Bash, or `Date.now` access (per the ingest-book precedent), so gates, dedup, staging, and commits cannot live there. *Script-only status quo dispatch forever* (never Workflow) — leaves parallel-dispatch correctness and the fragile 8-tab-field findings shape gate to model prose; #76's schema-return and resume-from-cache wins are real, so it earns a measured prototype rather than a permanent no. *Python orchestrators* — jq/git/mv-heavy phases and every existing helper are bash; python adds a second idiom for no parsing need TSV+awk doesn't cover (minor fork, defaulted).

## Decision 2 — Per-item coverage manifest (#71)

**Recommendation: a dispatch manifest written by `prep`, per-item receipt rows emitted by every agent, reconciled exactly by a shared `check-coverage.sh` in `gate`.**

- **Manifest shape:** `dev/<phase>/dispatch.tsv`, one row per work item: `batch_tag<TAB>item_id`. The item id is the natural per-pipeline key: source path (catalog W1), concept slug (catalog W2), article slug (audit A1), gap_id (enrich). `run.env` carries `RUN_ID` (epoch nonce) alongside.
- **Receipt shape:** each agent's output must contain **one row per assigned item id**, including explicit no-op verdicts. Enrichment already does this per gap (`NOSOURCE` is a row); the validator gains a `VALIDATED<TAB>{slug}<TAB>{RUN_ID}` row per article processed (a clean article is a row, not silence); catalog W2's receipt IS the article file (the manifest enumerates the expected file set, which `gate-batch.sh` already checks per path).
- **Reconciliation:** new shared `scripts/check-coverage.sh <dispatch.tsv> <output-file>...` — union the emitted ids across output files and require exact set equality with the dispatched ids: **omissions, duplicates, and unknown ids each fail with the offending ids named**. A missing findings file surfaces as all of its batch's ids missing, killing the current `cat _audit-*.md 2>/dev/null || true` silent-shrink path. It is a new helper, not a `gate-batch.sh` extension, because the input shape differs (an id set vs a path list); `gate-batch.sh` keeps the write-or-fail + structure half and runs first.
- **Audit success signal changes:** the gate keys on the `VALIDATED` rows carrying this run's `RUN_ID`, replacing the `last_verified == today` date check (which passes a same-day rerun that skipped articles). `last_verified` stays in article frontmatter as corpus metadata; it just stops being the gate.

**Non-goal:** semantic completeness. The manifest proves every dispatched *item* produced a receipt; it cannot prove the extractor found all 8 concepts in a source or the validator checked every claim. That stays a model-quality concern, out of scope.

**Rejected:** per-item nonce stamped into each article's frontmatter (#71's non-binding sketch) — mutates 900+ corpus files with run bookkeeping every audit; the receipt rows in the transient findings files carry the same proof without touching the corpus.

## Decision 3 — Enrichment batch size: CAP=12 → CAP=5, shipped standalone first (#76)

**Recommendation: change `CAP=12` to `CAP=5` in enrich-stack Step 4 now, as an independent one-line change ahead of the substrate work.** The controlled experiment in the batch-size issue (#76): batch~5 (B6 condition) beats batch 12 on source quality (found the exact-title paper the mega-agent missed), wall-clock (~8 min vs ~14), and blast radius (half the gaps lost per agent death), at +15% billable tokens; below 5 doubles cost for no quality gain and batch=1 regresses (scope-exclusion false positive). Nothing about the number depends on the substrate; folding it into the migration just delays a measured win. The validator's CAP=3 and catalog's caps are NOT touched — the ~5 finding is specific to web-search-heavy agents (per #76's own caveat).

## Decision 4 — Article-contract SSOT: `references/article-contract.md`

**Recommendation: one checked-in contract doc at `references/article-contract.md`, following the existing `references/reference-tier.md` precedent (a schema doc the skills are told to read before filing), with `assert-structure.sh` named as its executable enforcement.**

It defines, in one place:
1. **Article frontmatter schema** — every field with type, writer stage, and reader stage(s). This is where `extraction_hash` (930 corpus articles, zero readers) is ruled dead and `routing:`/`last_verified`/`updated` are ruled required.
2. **Source-ref format** — bare `sources/{publisher}/{file}.md`, never stack-prefixed (the synthesizer's current rule becomes the contract; lookup's prefixed example is drift to fix against it).
3. **Tier semantics** — tier attaches **per source_path, not per concept** (a merged concept spans tiers; per #77's F6 finding), defining what extractor emits, dedup preserves, and synthesizer/validator consume.
4. **Concept-block format** — the `## Concept:` extraction shape currently restated in catalog-sources SKILL.md, the extractor agent, and `dedup-extractions.py` comments.

Every stage that currently restates any of this (templates/stack/STACK.md "Frontmatter Convention", the four agent definitions, catalog-sources Step 2, lookup Step 7) is edited to point at the contract instead. `assert-structure.sh`'s `article-md`/`concept-batch` kinds are the machine check and must match the doc; the doc names them so a future field lands in both or the drift is visible in one diff. #77's corpus-migration items (strip prefixed source-refs, drop `extraction_hash` from existing articles, `## Sources` emit-or-stop, stale plugin docs) are downstream sub-issues that attach to this seam — the epic ships the SSOT and the pointer edits, not the corpus migrations.

**Rejected:** machine-readable schema (JSON Schema / YAML spec consumed by scripts) — nothing would consume it except `assert-structure.sh`, which is 5 grep lines; a generated validator is machinery for one reader. The doc + named enforcement pair is the lazy version that still kills the drift.

## Goals

1. Kill cross-block shell state: every SKILL.md Bash block in catalog/audit/enrich is self-contained (one script call, or literals the model re-supplies safely). (#72)
2. Every fan-out gate reconciles dispatched items against per-item receipts; a dropped item, dead agent, or missing findings file fails by name. (#71)
3. Enrichment dispatch runs at the measured batch size (~5). (#76)
4. One artifact defines the article contract; zero stages restate the field list. (#77 seam)
5. A recorded, measured decision on Workflow vs Agent-call fan-out, enrich first. (#76)

## Non-goals

- Corpus migrations (source-ref normalization across 4 stacks, `extraction_hash` strip, `## Sources`) — sub-issues attached to the SSOT, not this epic.
- Semantic-completeness verification of agent output (see Decision 2 non-goal).
- Touching validator/catalog batch caps — measure separately per #76's caveat.
- lookup / process-inbox / ingest-book restructuring — lookup's cross-block state is lighter and ingest-book already has the target shape; revisit after the three pipelines land.
- Any change to what the pipelines produce (articles, reports, staged sources are byte-identical in the happy path, except receipt rows in transient findings files).

## Project structure (new/changed files)

```
scripts/
├── pipeline/
│   ├── catalog.sh      ← new: prep|gate|finish phases for catalog-sources
│   ├── audit.sh        ← new: prep|gate|finish for audit-stack
│   └── enrich.sh       ← new: prep|gate|finish for enrich-stack
├── check-coverage.sh   ← new shared: dispatch.tsv vs emitted receipt ids
├── gate-batch.sh       ← unchanged (write-or-fail half stays)
└── assert-structure.sh ← changed: article-validated kind re-keyed on RUN_ID receipt; kinds cross-named in the contract doc
references/
└── article-contract.md ← new SSOT (Decision 4)
skills/{catalog-sources,audit-stack,enrich-stack}/SKILL.md  ← blocks collapse to script calls
agents/{source-extractor,article-synthesizer,validator,enrichment}.md ← receipt-row contract + point at SSOT
templates/stack/STACK.md ← Frontmatter Convention → pointer at SSOT
```

## Testing strategy

- Each orchestration script gets a smoke check runnable against a throwaway library (`/stacks:init-library ~/tmp/test-library` per repo testing convention): `prep` on a seeded stack produces a well-formed `dispatch.tsv` + `run.env`; `gate` with a hand-mutilated output set (one id dropped, one duplicated, one unknown, one findings file deleted) fails naming exactly those ids — the red-when-broken test #71 demands.
- `check-coverage.sh` carries an inline self-check the same way (fabricated manifest + outputs).
- The Workflow-vs-Agent decision is a measurement, not a test: same gap set, both substrates, the four #76 metrics, written into the decision record.
- Visual/behavioral: one full end-to-end run of each skill on the test library before calling any pipeline migrated (skills are TUI-adjacent prose; bats-style logic checks don't prove the model follows the shrunk prose).

## Boundaries

- **Always:** keep `prep`/`gate`/`finish` substrate-agnostic (same script regardless of Agent-call vs Workflow middle); keep operator gates (enrich Step 6 approval, catalog near-dup review, ingest map confirm) interactive — scripts never auto-approve; semver + CHANGELOG per landed change; per-pipeline migration lands whole (script + SKILL.md shrink + agent receipt contract in one change), never a half-migrated skill.
- **Never (was "ask first", now resolved):** launching a Workflow from lookup's hands-free `--auto` path — the Workflow tool fires only on explicit user opt-in and cannot infer it, so the auto path stays a plain `Agent` call. A single-gap `--query` run is 1 gap = 1 agent anyway, no fan-out to orchestrate. **Ask first:** any change to caps other than enrichment's.
- **Never:** state passed between SKILL.md Bash blocks via env; a gate that keys on calendar date; a stage restating the article field list instead of pointing at the contract.

## Acceptance criteria (epic-level)

1. `grep` over the three SKILL.md files finds no Bash block consuming a variable defined in a prior block (#72's Done-When).
2. The mutilated-output gate test fails on omission, duplicate, unknown id, and missing file, each named (#71's Done-When).
3. enrich-stack dispatches ≤5 gaps per agent (#76 partial).
4. Workflow-vs-Agent head-to-head numbers + decision recorded in `dev/` (#76's Done-When).
5. Exactly one file matches a grep for the article frontmatter field list; template/agents/skills carry pointers (#77 seam).
6. Full catalog→audit→enrich cycle on the test library is green end to end.

## Open items flagged for the human — both RESOLVED 2026-07-07 against the first-party Workflow tool contract

- **Workflow multi-agent opt-in vs `--auto`: CONFIRMED.** The Workflow tool fires only on explicit user opt-in and cannot infer it, so lookup's hands-free auto-enrich (#69) cannot ride a Workflow. Resolved as above: the `--auto`/single-gap `--query` path stays a plain `Agent` call; the Workflow migration (T6/T9) covers only the explicit multi-gap batch path (audit soft-spots + telemetry misses). No Task-6 verification needed — the constraint is settled.
- **Workflow contract grounding: CONFIRMED first-party.** The fs/Bash/`Date.now` restrictions are real (no filesystem or Node API access; `Date.now()`/`new Date()` throw — pass timestamps in), which is exactly why the hybrid split is mandatory, not just preferred: gates, dedup, staging, and commits cannot live in a workflow script. `agent()` with a JSON schema returns a validated object; `pipeline()`/`parallel()` fan out. Task 6 stays as the *measurement* (tokens/wall-clock/yield/false-positives), but no longer needs to first verify the contract.
