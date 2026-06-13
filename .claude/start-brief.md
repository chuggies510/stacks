<!--
Start-brief: distilled orientation loaded by /start.
Distilled 2026-06-13 from:
  tech-context.md @ 3dce5c536059e98484a10b15e2dc2f8352c8ba45
  system-patterns.md @ f95f45f4c97916e2585e785fb35c1159097be195
Run /workspace-toolkit:refresh-start-brief when source files have drifted substantively.
-->

# stacks Start Brief

Claude Code plugin for building and maintaining curated domain knowledge libraries. Sources are cataloged into article-per-concept wiki entries (flat `articles/` directory) queryable with `/stacks:ask` from any repo; an audit pass validates each article against its cited sources and writes a fresh drift report. This repo is the tool, not a library: no knowledge content lives here.

## Tech context

### Deployment and registration

- Directory-source plugin: `marketplace.json` declares `"source": "./"`, so the plugin loads directly from this repo root. No build step, no cache refresh.
- `bash scripts/install.sh` writes `extraKnownMarketplaces` + `enabledPlugins` entries into `~/.claude/settings.json`. Mirrors the ChuggiesMart pattern.
- Update mechanism is `git pull`. Restart Claude Code to pick up changes.
- Version sync: `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions must match on every change, or the launcher shows stale versions. Bump both plus a CHANGELOG entry per change.
- Repo: `git@github.com:chuggies510/stacks.git`. Issues: `gh issue list --state open`. Current version 0.21.0.

### Config consumers

- `~/.claude/settings.json` — marketplace + enabled-plugin registration (written by install.sh).
- `~/.config/stacks/config.json` — written by `/stacks:init-library`, points `ask` and `process-inbox` at the active library.

### Tooling and dependencies

- Pure markdown + bash plugin. No package manager, no build step, no `package.json`/`pyproject.toml`.
- Runtime deps: `jq` (version/marketplace parsing), `python3` (W1b dedup, `dedup-extractions.py`), `awk` (W4 MoC + tag parse), Linux `stat -c %Y` for mtime (macOS/BSD not supported).
- Tests: `bats` (`tests/gate-batch.bats`, `tests/assert-structure.bats`).
- Skill frontmatter is only `name` + `description` (description starts "Use when..."). No `version`/`allowed-tools`/`thinking`. Agent frontmatter: `tools`, `model`, `description`, 3+ worked examples in the prompt.

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

Three-layer plugin; the plugin holds no knowledge, it manipulates user-owned library repos.

1. Skills (user-facing): `init-library`, `new-stack`, `catalog-sources`, `audit-stack`, `process-inbox`, `ask`. Each is a `skills/{name}/SKILL.md` procedural walkthrough.
2. Agents: 3 workers — `concept-identifier`, `article-synthesizer`, `validator`. No orchestrator agents.
3. Templates: `templates/library/` and `templates/stack/` copied into user repos to bootstrap structure.

### File conventions

- `agents/` subagent definitions. `skills/{name}/SKILL.md`. `scripts/` lifecycle (install/uninstall/update/init/locate-plugin-root/loop) plus pipeline helpers. `templates/library|stack/`. `references/` holds only `default-topic-template.md`. `dev/` planning artifacts (not shipped).
- Articles are flat (no typed subdirs), 300-800 words (stretch 1200), plain markdown with inline `[source-slug]` citations.
- Pipeline helpers: `gate-batch.sh {epoch} {label} {kind} {path}...` (write-or-fail size+mtime + `assert-structure.sh` content-shape, `-` skips structure); `dedup-extractions.py {extr_dir} {dedup_path}` (W1b slug merge); `normalize-tags.sh {root}` (halts on out-of-vocab tags vs `STACK.md` `allowed_tags:`); `regenerate-moc.sh {root}` (W4 MoC, preserves `## Reading Paths`); `collision-dest.sh {dir} {file}` (non-colliding filename).

### Catalog pipeline (W0 to W4)

`/stacks:catalog-sources [stack]`: W0 enumerate `sources/incoming/` (new-source set; paren-in-filename gate fails early) → W1 `concept-identifier` parallel, 1 source per agent for isolation, slug immutability, writes `dev/extractions/{batch_id}-concepts.md` → W1b `dedup-extractions.py` merges `source_paths[]` across shared slugs, writes one `_dedup-{slug}.md` per slug plus `_dedup-meta.txt` → W2 `article-synthesizer` parallel per unique concept, strip-on-rewrite, 25-agent wave cap → W2 tag-drift check (`normalize-tags.sh`, skipped if `allowed_tags:` absent) → W3 source filing to publisher dirs → W4 MoC regeneration (`regenerate-moc.sh`).

### Audit pipeline (stateless drift report)

`/stacks:audit-stack {stack}`: A1 dispatch `validator` over articles (one agent unless count exceeds the 25 cap, then inline `${ARRAY[@]:i:CAP}` slices in parallel). Each validator strips prior marks, re-marks every claim `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` against cited sources, updates `last_verified`. Parent re-gates each article (`gate-batch.sh ... article-validated`) → bash drift report greps marks, writes `dev/audit/report.md` (counts + every flagged claim) → log + commit. Each run is independent: re-marks from scratch, rebuilds the report. No findings ledger, no carry-forward, no convergence loop, no glossary/invariants synthesis.

### Other flows

- `/stacks:init-library {path}`: copy `templates/library/` → create private GitHub repo → write `~/.config/stacks/config.json`.
- `/stacks:new-stack {name}`: copy `templates/stack/` to `{name}/` → register in library `catalog.md`.
- `/stacks:process-inbox`: read library `inbox/*.md` → classify against existing stacks via content + source metadata → move matched to target stack's `sources/incoming/` → report unmatched. Routing only, no quality gate.
- `/stacks:ask {question}`: read config → open catalog + per-stack `index.md` (resolve `--stack`/`--stacks` scope, else all) → score and load up to 3 matching articles → synthesize cited answer → optional file-back (extend or write an article, commit). Article-only.

### Cross-cutting harness patterns

- Parent-side sharded dispatch: scale-sensitive waves (catalog W1/W2, audit A1) are sharded and dispatched directly by the parent skill, not an orchestrator. Orchestrators were removed because nested Task dispatch silently fell back to inline execution and hit "Prompt is too long". Bounds: 1 source per W1 agent, 25 agents per W2 wave, 25 articles per validator. Sharding uses inline `${ARRAY[@]:i:CAP}`.
- Write-or-fail gate: every agent-producing wave gates through `gate-batch.sh`. Caller captures `DISPATCH_EPOCH=$(date +%s)` before dispatch; each expected file must be non-empty AND mtime strictly newer than the epoch (size alone misses a stale file, mtime alone misses an empty write), then pass `assert-structure.sh` for `{kind}`. Sub-agents return only text and no exit code, so the file-based gate is the success signal. The gate enumerates file paths, never a directory.
- Slug immutability: W1 cannot rename an existing article's slug — it matches by claim overlap and reuses the slug as both `slug` and `target_article`. With W1b dedup this eliminates silent overwrite by parallel W2 writes to the same filename.

### Known weak spots

- `regenerate-moc.sh` / `normalize-tags.sh` use `awk`, not tested against mawk-only environments.
- `gate-batch.sh` uses Linux `stat -c %Y`; macOS/BSD syntax differs, unsupported.

---

Full sources:
- .claude/memory-bank/tech-context.md (deployments, services, infrastructure)
- .claude/memory-bank/system-patterns.md (architecture, patterns, workflows)
- .claude/memory-bank/active-context-S*.md (current session focus + handoff)
- CLAUDE.md (project gotchas)
- ~/chungus/dev/CLAUDE.md (workspace gotchas, communication style)
