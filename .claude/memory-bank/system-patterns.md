# stacks System Patterns

## Architecture

Three-layer plugin:

1. **Skills** (user-facing): `init-library`, `new-stack`, `ingest-sources`, `process-inbox`, `refine-stack`, `ask`. Each is a SKILL.md with a procedural walkthrough.
2. **Agents** (workers): 7 subagents invoked by skills to do focused work (clustering, extraction, synthesis, cross-reference, validation, findings).
3. **Templates** (scaffolding): `templates/library/` and `templates/stack/` are copied into user repos to bootstrap structure.

The plugin itself holds no knowledge. It manipulates user-owned library repos.

## Key Flows

### Library creation
`/stacks:init-library {path}` → copy `templates/library/` to path → create private GitHub repo → write `~/.claude/stacks-config.json` pointing at the new library.

### Stack creation
`/stacks:new-stack {name}` (from within a library) → copy `templates/stack/` to `stacks/{name}/` → register in library's `catalog.md`.

### Ingestion pipeline
`/stacks:ingest-sources [stack]` → detect files in `stacks/{stack}/sources/incoming/` → topic-clusterer (group sources) → topic-extractor (per group) → topic-synthesizer (produce topic guide) → update index/catalog.

### Inbox routing
`/stacks:process-inbox` (from any repo) → read library's `inbox/*.md` → classify each against existing stacks via content + source metadata → move matched to target stack's `sources/incoming/` → report unmatched.

### Refinement
`/stacks:refine-stack` (within library) → cross-referencer (links/contradictions across guides) → validator (guide claims vs. sources) → synthesizer (glossary + invariants) → findings-analyst (coverage + research direction).

### Lookup
`/stacks:ask {question}` (from any repo) → read `~/.claude/stacks-config.json` → open library catalog + indexes → load relevant topic guides → synthesize answer.

## Marketplace Registration Pattern

Directory-source plugin:
- `marketplace.json` declares `"source": "./"` so the plugin lives at repo root
- `install.sh` adds entries to `~/.claude/settings.json` under `extraKnownMarketplaces` and `enabledPlugins`
- Updates happen via `git pull`, no cache refresh needed

This mirrors the ChuggiesMart pattern — same mechanism, single-plugin variant.

## Known Weak Spots

- Agents sometimes return content in chat instead of writing files (see CLAUDE.md gotchas section once #11 and #15 are documented).
- Bad arguments to `ingest-sources` can silent-fail (#6).
- No `sources/incoming/` gitignore in library template yet (#4) — users accidentally commit raw sources.
