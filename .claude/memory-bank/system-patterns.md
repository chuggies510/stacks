# stacks System Patterns

## Architecture

Three-layer plugin:

1. **Skills** (user-facing): `init-library`, `new-stack`, `catalog-sources`, `audit-stack`, `process-inbox`, `ask`. Each is a SKILL.md with a procedural walkthrough.
2. **Agents**: 5 workers (`concept-identifier`, `article-synthesizer`, `validator`, `synthesizer`, `findings-analyst`). Scale-sensitive dispatch (sharding work across N sub-agents) is done parent-side by the `catalog-sources` and `audit-stack` skills directly.
3. **Templates** (scaffolding): `templates/library/` and `templates/stack/` are copied into user repos to bootstrap structure.

The plugin itself holds no knowledge. It manipulates user-owned library repos.

## Key Flows

### Library creation
`/stacks:init-library {path}` → copy `templates/library/` to path → create private GitHub repo → write `~/.config/stacks/config.json` pointing at the new library.

### Stack creation
`/stacks:new-stack {name}` (from within a library) → copy `templates/stack/` to `stacks/{name}/` → register in library's `catalog.md`.

### Catalog pipeline (W0 → W4)
`/stacks:catalog-sources [stack]` → W0 enumerate `sources/incoming/` → W0b prior-findings skip list from `dev/audit/findings.md` → W1 concept-identifier (parallel per batch, `SOURCES_PER_AGENT=10` baseline with small-stack bypass to 1-per-agent; slug immutability enforced; writes `dev/extractions/{batch_id}-concepts.md`) → W1b bash slug-collision dedup (merges `source_paths[]` across shared slugs) and `extraction_hash` computation via `scripts/compute-extraction-hash.sh` (sha256 of sorted source paths joined by `|` then slug) → W2 article-synthesizer (parallel per unique concept, strip-on-rewrite rule; copies `extraction_hash` verbatim into frontmatter) → W2b deterministic wikilink pass → W2b-post tag drift check (`scripts/normalize-tags.sh`) halts on out-of-vocab tags against `STACK.md` `allowed_tags:` — skipped if `allowed_tags:` absent → W3 source filing → W4 MoC regeneration preserving `## Reading Paths`.

### Inbox routing
`/stacks:process-inbox` (from any repo) → read library's `inbox/*.md` → classify each against existing stacks via content + source metadata → move matched to target stack's `sources/incoming/` → report unmatched.

### Audit pipeline (A1 → A5) with convergence loop
`/stacks:audit-stack {stack}` → A1 validator inline-marks articles `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` (strips prior-cycle marks first, updates `last_verified` frontmatter; excludes `sources/incoming/` and `sources/trash/`) → A2 synthesizer produces `glossary.md`, `invariants.md`, `contradictions.md` at stack root → A2b shared wikilink pass → A3 findings-analyst writes `dev/audit/findings.md` per locked schema v2 (four sections: New Acquisitions, Articles to Re-Synthesize, Research Questions, Deferred; id = SHA256; status enum with terminal `failed`; carry-forward) → A4 bash convergence check: `generative_open` = non-terminal items with `action: fetch_source` OR `action: research_question` (2 consecutive empty passes OR `MAX_AUDIT_PASSES` cap, default 3) → A5 on convergence `cp` to `dev/audit/closed/{audit_date}-findings.md` so active `findings.md` persists for the next catalog cycle.

### Feedback flywheel
Catalog reads findings.md at W0b (skip list from terminal statuses; driving acquisitions from open items). Audit writes findings.md at A3 (carry-forward preserves terminal statuses by id). A5 uses cp (not mv) — findings.md is the persistent baseline that closes the loop.

### Lookup
`/stacks:ask {question}` (from any repo) → read `~/.config/stacks/config.json` → open library catalog + indexes → detect article-mode vs guide-mode via `articles/` directory presence → extract `## Reading Paths` context from `index.md` → load up to 3 matching articles (article mode) or topic guides (guide mode) → synthesize answer → optional Step 7 file-result-back branches on the same MODE flag (article mode writes `articles/{slug}.md` with `extraction_hash: ""`; guide mode writes `topics/{topic}/guide.md`).

## Parent-side sharded dispatch

All scale-sensitive waves (audit A1/A2/A3, catalog W1/W2) are sharded and dispatched directly by the parent skill (`catalog-sources` or `audit-stack`), not by an orchestrator agent. The orchestrator agents that previously owned this work were deprecated because nested Task dispatch was unreliable: when the harness dropped Task on a nested call, the orchestrator silently fell back to inline execution and bundled every shard's work into one context, hitting "Prompt is too long" on stacks the sharding was meant to keep below the ceiling. Parent-side dispatch keeps Task usage shallow (always reachable) and lets the parent run all deterministic pieces (dedup, per-slug split, hash compute, wave gating) as code in the parent process.

Per-batch caps: ≤3 articles per validator shard (A1) and per findings-analyst shard (A3); ≤10 articles per synthesizer shard (A2); 1 source per concept-identifier agent (W1); 25 agents per W2 wave. The rationale in each case is bounded per-agent context: validator and findings-analyst prompts grow with both article count and source count so the cap is tight; synthesizer reads article bodies only so the cap is looser; concept-identifier isolates one source per agent to prevent concept-bleed.

A2 and A3 use a two-phase reduce when sharding fires: shards emit partials (`_a{2,3}-partial-{NN}.md`), then A2 re-dispatches one `synthesizer` agent in merge mode (tier-aware glossary merge, independent-corroboration check) while A3 merges partials with inline python in the parent (terminal-wins precedence by id). Single-shard fast paths skip the partials-merge step when the article count fits one shard. The parent runs the `assert-written.sh` gate loop after each fan-in, then emits the per-wave summary JSON itself. See `references/wave-engine.md`.

### Unified summary-JSON contract

The parent skill writes `dev/{audit,extractions}/_{wave}-summary.json` after each wave's fan-in completes. Envelope: `{schema_version: 1, wave, status, counts{...}, epochs{...}}`. Main-session gates verify the file exists and is non-empty, then `jq -e` nested `.counts.FIELD` paths (never `jq -e '.a and .b'` since `0` is jq-falsy — test field types instead). Schema-version checks let future field additions ship without breaking older gates. See `references/wave-engine.md` § Summary-JSON contract.

## Write-or-fail gate

Every agent-producing wave pairs `test -s` with `stat -c %Y > dispatch_epoch` via `scripts/assert-written.sh`. Caller captures `DISPATCH_EPOCH=$(date +%s)` immediately before dispatch. Both checks needed: size alone misses stale pre-existing files, mtime alone misses empty writes. Gate enumerates expected file paths; never a directory path (dir mtime does not advance on in-place file edits).

## Slug immutability invariant

W1 concept-identifier cannot rename an existing article's slug — it matches by claim overlap and reuses the existing slug as both `slug` and `target_article`. Combined with W1b dedup, this eliminates silent overwrite by parallel W2 dispatches writing to the same filename.

## Marketplace Registration Pattern

Directory-source plugin:
- `marketplace.json` declares `"source": "./"` so the plugin lives at repo root
- `install.sh` adds entries to `~/.claude/settings.json` under `extraKnownMarketplaces` and `enabledPlugins`
- Updates happen via `git pull`, no cache refresh needed

This mirrors the ChuggiesMart pattern — same mechanism, single-plugin variant.

## Known Weak Spots

- W1b dedup and W4 MoC generator depend on gawk (nested arrays); mawk fallback noted in catalog-sources SKILL.md but not implemented.
- Audit-stack outer pass loop re-enters Steps 4-8 textually; not all model variants will execute the loop deterministically without the operator re-invoking.
(Epic #38 closed all six prior audit follow-ups — A2/A3 orchestrators, validator source sharding, W2 wave cap, schema-versioned summary contract, findings rotation. Remaining weak spots are the gawk dependency and the textual outer-pass loop listed above.)
