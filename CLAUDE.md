# CLAUDE.md

Claude Code plugin for building and maintaining curated domain knowledge libraries. Sources are ingested into topic guides that can be queried with `/stacks:ask` from any repo.

This repo is the **stacks tool**. It is NOT a knowledge library. Do not store knowledge content here. Libraries are created with `/stacks:init-library`.

## Slash Commands

**Universal** (from workspace-toolkit plugin):
- `/start` — Initialize session, load memory bank
- `/stop` — Session handoff with knowledge extraction

**This plugin** (stacks:*):
- `/stacks:init-library` — Scaffold a new library repo + private GitHub repo
- `/stacks:new-stack` — Create a new knowledge stack in a library
- `/stacks:catalog-sources` — Process sources/incoming/ into article-per-concept wiki entries
- `/stacks:process-inbox` — Route inbox/*.md files to matching stacks
- `/stacks:audit-stack` — Validate articles, synthesize glossary/invariants, identify gaps
- `/stacks:ask` — Look up knowledge from the configured library

## Plugin Structure

```
stacks/
├── .claude-plugin/
│   ├── plugin.json            # Plugin identity and version
│   └── marketplace.json       # Single-plugin marketplace descriptor
├── skills/{name}/SKILL.md     # User-invocable skills (init, new, catalog-sources, ask, audit-stack, process-inbox)
├── agents/                    # 7 subagent definitions (YAML frontmatter + prompt)
├── scripts/                   # Lifecycle scripts (install, uninstall, update, init)
├── templates/
│   ├── library/               # Files copied when /stacks:init-library creates a library
│   └── stack/                 # Files copied when /stacks:new-stack scaffolds a stack
└── references/                # Reference docs: wave engine, refresh procedure, topic template
```

## Frontmatter Convention

Skill files live at `skills/{name}/SKILL.md`. Frontmatter uses only `name` and `description` fields. No `version`, `allowed-tools`, or `thinking`. Description starts with "Use when..." for trigger matching.

```yaml
---
name: catalog-sources
description: Use when the user wants to catalog sources into a stack...
---
```

Agent files live in `agents/`. Frontmatter defines `tools` (comma-separated), `model`, and `description`. Include 3+ worked examples in agent prompts.

## Registration Model

Stacks registers as a directory-source marketplace via `extraKnownMarketplaces` in `~/.claude/settings.json`, the same mechanism ChuggiesMart uses. The `marketplace.json` file with `"source": "./"` tells Claude Code the plugin lives at the repo root. `install.sh` writes both the marketplace registration and the `enabledPlugins` entry.

## Development Workflow

1. Edit source files in this repo.
2. Bump version in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
3. Update `CHANGELOG.md` with the version entry.
4. `git commit && git push`
5. Restart Claude Code session to pick up changes.

Directory-source plugins load directly from the repo. No cache refresh or `claude plugin update` needed. `git pull` is the update mechanism.

## Version Bumping Rules

Two files must stay in sync:
- `.claude-plugin/plugin.json` — plugin identity
- `.claude-plugin/marketplace.json` — marketplace descriptor

Mismatches cause the launcher to show stale versions. Bump both as part of the change, not as an afterthought. Every code change that touches functionality gets a semver bump and CHANGELOG entry.

## Testing

```bash
bash scripts/install.sh
# restart claude code, then:
/stacks:init-library ~/tmp/test-library
# open session in ~/tmp/test-library
/stacks:new-stack test-stack
/stacks:catalog-sources test-stack
/stacks:ask some question
# clean up
rm -rf ~/tmp/test-library
```

Do not commit test library content to this repo.

## GitHub

- **Repo**: git@github.com:chuggies510/stacks.git
- **Issues**: `gh issue list --state open`

## Chuggies Bot

@chuggies_bot is a Telegram-based AI assistant that reads memory banks and issues across repos. It runs on Dev Pi (192.168.3.4) via OpenClaw. Memory bank handoffs are consumed by the bot's nightly refresh (2am Pacific) — keep `active-context.md` structured and current.
