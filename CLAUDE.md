# CLAUDE.md

This repo is the `stacks` tool: a Claude Code plugin. It is NOT a knowledge library. Do not store knowledge content here. Libraries are created with `/stacks:init`.

## Plugin structure

```
stacks/
├── .claude-plugin/
│   ├── plugin.json            # Plugin identity and version
│   └── marketplace.json       # Single-plugin marketplace descriptor
├── skills/{name}/SKILL.md     # User-invocable skills (init, new, ingest, lookup, refine)
├── agents/                    # 7 subagent definitions (YAML frontmatter + prompt)
├── scripts/                   # Lifecycle scripts (install, uninstall, update, init)
├── templates/
│   ├── library/               # Files copied when /stacks:init creates a library
│   └── stack/                 # Files copied when /stacks:new scaffolds a stack
└── references/                # Reference docs: wave engine, refresh procedure, topic template
```

## Frontmatter convention

Skill files live at `skills/{name}/SKILL.md`. Frontmatter uses only `name` and `description` fields. No `version`, `allowed-tools`, or `thinking`. Description starts with "Use when..." for trigger matching.

```yaml
---
name: ingest
description: Use when the user wants to ingest new sources into a stack...
---
```

Agent files live in `agents/`. Frontmatter defines `tools` (comma-separated), `model`, and `description`. Include 3+ worked examples in agent prompts.

## Registration model

Stacks registers as a directory-source marketplace via `extraKnownMarketplaces` in `~/.claude/settings.json`, the same mechanism ChuggiesMart uses. The `marketplace.json` file with `"source": "./"` tells Claude Code the plugin lives at the repo root. `install.sh` writes both the marketplace registration and the `enabledPlugins` entry.

## Development workflow

1. Edit source files in this repo.
2. Bump version in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
3. `git commit && git push`
4. Restart Claude Code session to pick up changes.

Directory-source plugins load directly from the repo. No cache refresh or `claude plugin update` needed. `git pull` is the update mechanism.

## Testing

```bash
bash scripts/install.sh
# restart claude code, then:
/stacks:init ~/tmp/test-library
# open session in ~/tmp/test-library
/stacks:new test-stack
/stacks:ingest test-stack
/stacks:lookup some question
# clean up
rm -rf ~/tmp/test-library
```

Do not commit test library content to this repo.
