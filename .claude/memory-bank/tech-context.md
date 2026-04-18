# stacks Tech Context

## Project Structure

| Directory/File | Purpose |
|----------------|---------|
| `.claude-plugin/plugin.json` | Plugin identity and version |
| `.claude-plugin/marketplace.json` | Single-plugin marketplace descriptor (source: "./") |
| `agents/` | 7 subagent definitions (cross-referencer, findings-analyst, synthesizer, topic-clusterer, topic-extractor, topic-synthesizer, validator) |
| `skills/{name}/SKILL.md` | User-invocable skills: ask, ingest-sources, init-library, new-stack, process-inbox, refine-stack |
| `scripts/` | Lifecycle scripts (install.sh, uninstall.sh, update.sh, init.sh) |
| `templates/library/` | Files copied when `/stacks:init-library` creates a library |
| `templates/stack/` | Files copied when `/stacks:new-stack` scaffolds a stack |
| `references/` | Reference docs: wave engine, refresh procedure, topic template |
| `dev/` | Planning and ops artifacts (not shipped with plugin) |
| `CHANGELOG.md` | Version history |
| `README.md` | User-facing readme |

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
```

## Dependencies

Pure markdown + bash plugin. No package manager, no build step. No `package.json`, `pyproject.toml`, `Cargo.toml`.

Consumers of this plugin:
- `~/.claude/settings.json` — `extraKnownMarketplaces` + `enabledPlugins` entries written by install.sh
- `~/.claude/stacks-config.json` — written by `/stacks:init-library` to point `ask` and `process-inbox` at the active library

## Version Sync

Two files must match on every version change:
- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → plugin entry `version`

Current: 0.8.3.
