# stacks System Patterns

## Architecture

Three-layer plugin:

1. **Skills** (user-facing): `init-library`, `new-stack`, `catalog-sources`, `audit-stack`, `process-inbox`, `ask`. Each is a SKILL.md with a procedural walkthrough.
2. **Agents** (workers): 5 subagents invoked by skills — `concept-identifier`, `article-synthesizer`, `validator`, `synthesizer`, `findings-analyst`.
3. **Templates** (scaffolding): `templates/library/` and `templates/stack/` are copied into user repos to bootstrap structure.

The plugin itself holds no knowledge. It manipulates user-owned library repos.

## Key Flows

### Library creation
`/stacks:init-library {path}` → copy `templates/library/` to path → create private GitHub repo → write `~/.config/stacks/config.json` pointing at the new library.

### Stack creation
`/stacks:new-stack {name}` (from within a library) → copy `templates/stack/` to `stacks/{name}/` → register in library's `catalog.md`.

### Catalog pipeline (W0 → W4)
`/stacks:catalog-sources [stack]` → W0 enumerate `sources/incoming/` → W0b prior-findings skip list from `dev/audit/findings.md` → W1 concept-identifier (parallel per source, slug immutability enforced) → W1b bash slug-collision dedup (merge `source_paths[]` across shared slugs) → W2 article-synthesizer (parallel per unique concept, strip-on-rewrite rule) → W2b deterministic wikilink pass → W3 source filing → W4 MoC regeneration preserving `## Reading Paths`.

### Inbox routing
`/stacks:process-inbox` (from any repo) → read library's `inbox/*.md` → classify each against existing stacks via content + source metadata → move matched to target stack's `sources/incoming/` → report unmatched.

### Audit pipeline (A1 → A5) with convergence loop
`/stacks:audit-stack {stack}` → A1 validator inline-marks articles `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` (strips prior-cycle marks first, updates `last_verified` frontmatter; excludes `sources/incoming/` and `sources/trash/`) → A2 synthesizer produces `glossary.md`, `invariants.md`, `contradictions.md` at stack root → A2b shared wikilink pass → A3 findings-analyst writes `dev/audit/findings.md` per locked schema v2 (four sections: New Acquisitions, Articles to Re-Synthesize, Research Questions, Deferred; id = SHA256; status enum with terminal `failed`; carry-forward) → A4 bash convergence check: `generative_open` = non-terminal items with `action: fetch_source` OR `action: research_question` (2 consecutive empty passes OR `MAX_AUDIT_PASSES` cap, default 3) → A5 on convergence `cp` to `dev/audit/closed/{audit_date}-findings.md` so active `findings.md` persists for the next catalog cycle.

### Feedback flywheel
Catalog reads findings.md at W0b (skip list from terminal statuses; driving acquisitions from open items). Audit writes findings.md at A3 (carry-forward preserves terminal statuses by id). A5 uses cp (not mv) — findings.md is the persistent baseline that closes the loop.

### Lookup
`/stacks:ask {question}` (from any repo) → read `~/.config/stacks/config.json` → open library catalog + indexes → detect article-mode vs guide-mode via `articles/` directory presence → extract `## Reading Paths` context from `index.md` → load up to 3 matching articles (article mode) or topic guides (guide mode) → synthesize answer → optional Step 7 file-result-back branches on the same MODE flag (article mode writes `articles/{slug}.md` with `extraction_hash: ""`; guide mode writes `topics/{topic}/guide.md`).

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

- W1b dedup and W4 MoC generator depend on gawk (nested arrays); mawk fallback is noted in catalog-sources SKILL.md but not implemented.
- Audit-stack outer pass loop re-enters Steps 4-8 textually; not all model variants will execute the loop deterministically without the operator re-invoking.
- Cross-stack retrieval in `/stacks:ask` is stub (one-stack scope only); blocks on-demand guide synthesis (#5, #18).
