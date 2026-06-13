<!--
Start-brief: distilled orientation loaded by /start.
Distilled 2026-06-12 from:
  tech-context.md @ 35e3d0839acc47ae383c9cbd8451769d51e57bcb
  system-patterns.md @ f5665e541817a2bdcfef923bf9c4cc314bd83689
Run /workspace-toolkit:refresh-start-brief when source files have drifted substantively.
-->

# stacks Start Brief

stacks is a Claude Code plugin for building and maintaining curated domain knowledge libraries: sources are cataloged into article-per-concept wiki entries (flat `articles/` directory, `[[wikilink]]` cross-links) queryable with `/stacks:ask` from any repo, with an audit loop that validates articles against sources and closes via a persistent `findings.md` driving the next catalog cycle. This repo is the tool, NOT a library; no knowledge content is committed here.

## Tech context

### Deployment and registration
- Directory-source marketplace plugin. `marketplace.json` declares `"source": "./"` so the plugin loads from repo root.
- `bash scripts/install.sh` writes `extraKnownMarketplaces` + `enabledPlugins` entries to `~/.claude/settings.json`. Mirrors the ChuggiesMart pattern.
- Updates ship via `git pull`; no cache refresh or `claude plugin update` needed. Restart Claude Code to pick up changes.
- `~/.config/stacks/config.json` (written by `/stacks:init-library`) points `ask` and `process-inbox` at the active library.
- Repo: `git@github.com:chuggies510/stacks.git`. Issues: `gh issue list --state open`.

### Version sync
Two files must match on every version change: `.claude-plugin/plugin.json` `version` and `.claude-plugin/marketplace.json` plugin-entry `version`. Mismatches show stale versions in the launcher. Bump both + CHANGELOG entry per change.

### Tooling and dependencies
- Pure markdown + bash plugin. No package manager, no build step, no `package.json`/`pyproject.toml`.
- Runtime deps: `jq` (version/config parsing), `gawk` (W1b nested-array dedup, W4 MoC), `perl` (wikilink-pass.sh), Linux `stat -c %Y` (mtime; macOS/BSD unsupported).
- Skill frontmatter: `name` + `description` only; description starts with "Use when...". No `version`/`allowed-tools`/`thinking`.
- Agent frontmatter: `tools` (comma-separated), `model`, `description`; 3+ worked examples in the prompt.

### Test cycle
```bash
bash scripts/install.sh        # register plugin; restart Claude Code, then:
/stacks:init-library ~/tmp/test-library
/stacks:new-stack test-stack
/stacks:catalog-sources test-stack
/stacks:audit-stack test-stack
/stacks:ask some question
rm -rf ~/tmp/test-library      # do not commit test library content
```

## System patterns

### Core architecture
Three-layer plugin: (1) skills (user-facing SKILL.md walkthroughs: init-library, new-stack, catalog-sources, audit-stack, process-inbox, ask); (2) agents (5 workers only: concept-identifier, article-synthesizer, validator, synthesizer, findings-analyst; no orchestrators); (3) templates (`templates/library/`, `templates/stack/` copied into user repos). Scale-sensitive dispatch is done parent-side directly by the `catalog-sources` and `audit-stack` skills. The plugin holds no knowledge; it manipulates user-owned library repos.

### File conventions
- `agents/` subagent definitions. `skills/{name}/SKILL.md`. `scripts/` lifecycle (install/uninstall/update/init) + pipeline helpers. `templates/library|stack/`. `references/` (`wave-engine.md` holds wave tables + gate contract). `dev/` planning artifacts (not shipped).
- Articles are flat (no typed subdirs), 300-800 word soft cap, `[[wikilinks]]` injected by deterministic post-write bash pass (not agent output).
- Pipeline helpers: `assert-written.sh {path} {epoch} {label}` (write-or-fail), `wikilink-pass.sh {articles} {glossary}` (first-occurrence wrap), `compute-extraction-hash.sh` (sha256 of sorted source paths + slug; anchors the skip-list flywheel), `normalize-tags.sh {root}` (halts on out-of-vocab tags vs `STACK.md` `allowed_tags:`).

### Catalog pipeline (W0 to W4)
`/stacks:catalog-sources [stack]`: W0 enumerate `sources/incoming/` -> W0b skip list from `dev/audit/findings.md` -> W1 concept-identifier (parallel, `SOURCES_PER_AGENT=10` baseline, 1-per-agent small-stack bypass; slug immutability) -> W1b bash slug-collision dedup + `extraction_hash` via `scripts/compute-extraction-hash.sh` -> W2 article-synthesizer (parallel per concept, copies `extraction_hash` verbatim; 25-agent cap per wave) -> W2b wikilink pass -> W2b-post tag drift check (`normalize-tags.sh`) -> W3 source filing -> W4 MoC regen preserving `## Reading Paths`.

### Audit pipeline (A1 to A5) with convergence loop
`/stacks:audit-stack {stack}`: A1 validator inline-marks articles `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` (strips prior-cycle marks, updates `last_verified`; excludes `sources/`) -> A2 synthesizer writes `glossary.md`/`invariants.md`/`contradictions.md` -> A2b wikilink pass -> A3 findings-analyst writes `dev/audit/findings.md` (schema v2, id=SHA256, terminal `failed` status, carry-forward) -> A4 convergence check (2 empty passes or `MAX_AUDIT_PASSES` default 3) -> A5 on convergence `cp` (not `mv`) to `dev/audit/closed/{date}-findings.md` so active findings.md persists for the next catalog cycle.

### Feedback flywheel
Catalog reads findings.md at W0b (skip list from terminal statuses, acquisitions from open items). Audit writes it at A3 (carry-forward preserves terminal by id). A5 `cp` keeps findings.md as the persistent baseline that closes the loop.

### Cross-cutting harness patterns
- Parent-side sharded dispatch: all scale-sensitive waves (W1, W2, A1, A2, A3) are sharded and dispatched directly by the parent skill. No orchestrator agents. Per-batch caps: <=3 articles per validator/findings-analyst shard; <=10 per synthesizer shard; 1 source per concept-identifier agent. A2 and A3 use a two-phase reduce (shards emit `_a{2,3}-partial-{NN}.md`, then one merge-mode agent or inline python collapses them); single-shard fast path skips partials.
- Write-or-fail gate: every agent-producing wave pairs `test -s` with `stat -c %Y > dispatch_epoch` via `scripts/assert-written.sh`. Caller captures `DISPATCH_EPOCH=$(date +%s)` before dispatch. Size alone misses stale files; mtime alone misses empty writes. Gate enumerates file paths, never a directory.
- Summary-JSON contract: parent skill writes `dev/{audit,extractions}/_{wave}-summary.json` after each wave fan-in. Envelope: `{schema_version: 1, wave, status, counts{...}, epochs{...}}`. Gates `jq -e` nested `.counts.FIELD` type checks (never `jq -e '.a and .b'` since `0` is jq-falsy).
- Slug immutability: W1 matches by claim overlap, reuses existing slug; combined with W1b dedup, eliminates silent overwrite by parallel W2 writes.

### Known weak spots
gawk dependency (W1b dedup, W4 MoC; mawk fallback noted but unimplemented); audit-stack outer pass loop re-enters textually (not all models loop deterministically without operator re-invoke).

---

Full sources:
- .claude/memory-bank/tech-context.md (deployments, services, infrastructure)
- .claude/memory-bank/system-patterns.md (architecture, patterns, workflows)
- .claude/memory-bank/active-context-S*.md (current session focus + handoff)
- CLAUDE.md (project gotchas)
- ~/chungus/dev/CLAUDE.md (workspace gotchas, communication style)
