# stacks Tech Context

## Project Structure

| Directory/File | Purpose |
|----------------|---------|
| `.claude-plugin/plugin.json` | Plugin identity and version |
| `.claude-plugin/marketplace.json` | Single-plugin marketplace descriptor (source: "./") |
| `agents/` | 5 subagent definitions (concept-identifier, article-synthesizer, validator, synthesizer, findings-analyst) |
| `skills/{name}/SKILL.md` | User-invocable skills: ask, audit-stack, catalog-sources, init-library, new-stack, process-inbox |
| `scripts/` | Lifecycle scripts (install.sh, uninstall.sh, update.sh, init.sh) plus pipeline helpers (assert-written.sh, wikilink-pass.sh, telemetry.sh) |
| `templates/library/` | Files copied when `/stacks:init-library` creates a library |
| `templates/stack/` | Files copied when `/stacks:new-stack` scaffolds a stack; includes `dev/audit/` and `dev/extractions/` skeletons |
| `references/` | Reference docs: `wave-engine.md` (catalog + audit wave tables, gate contract, feedback flywheel), `refresh-procedure.md`, topic template |
| `dev/` | Planning and feature-dev artifacts (not shipped with plugin) |
| `CHANGELOG.md` | Version history |
| `README.md` | User-facing readme |

## Pipeline helpers

| Script | Purpose |
|--------|---------|
| `scripts/assert-written.sh {path} {dispatch_epoch} {agent_label}` | Write-or-fail gate: `test -s` + `stat -c %Y > dispatch_epoch`. Linux-only. Fixed `AGENT_WRITE_FAILURE` error string. |
| `scripts/wikilink-pass.sh {articles-dir} {glossary-path}` | Deterministic wikilink injection. Reads bold terms from glossary, wraps first case-insensitive occurrence per term per article, preserves capitalization, skips self-links and already-wrapped. No-op when glossary absent. |

## CLI Commands

```bash
# Git
git remote -v                        # git@github.com:chuggies510/stacks.git
git log --oneline -10

# Issues
gh issue list --state open
gh issue view {N}

# Install / test cycle
bash scripts/install.sh              # registers plugin in ~/.claude/settings.json
# restart Claude Code, then:
/stacks:init-library ~/tmp/test-library
/stacks:new-stack test-stack
/stacks:catalog-sources test-stack
/stacks:audit-stack test-stack
/stacks:ask some question
```

## Dependencies

Pure markdown + bash plugin. No package manager, no build step. No `package.json`, `pyproject.toml`, `Cargo.toml`.

Runtime dependencies:
- `jq` (version file parsing, known_marketplaces.json fallback)
- `gawk` (GNU awk, for W1b nested-array dedup)
- `perl` (wikilink-pass.sh regex substitution)
- Linux `stat -c %Y` (mtime extraction; macOS/BSD not supported)

Consumers of this plugin:
- `~/.claude/settings.json` — `extraKnownMarketplaces` + `enabledPlugins` entries written by install.sh
- `~/.config/stacks/config.json` — written by `/stacks:init-library` to point `ask` and `process-inbox` at the active library

## Version Sync

Two files must match on every version change:
- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → plugin entry `version`

Mismatches cause the launcher to show stale versions.
