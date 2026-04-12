# CLAUDE.md

This repo is the `stacks` tool: a Claude Code plugin. It is NOT a knowledge library. Do not store knowledge content here — that belongs in a private library repo initialized with `bash scripts/init.sh`.

## Plugin structure

```
stacks/
├── .claude-plugin/plugin.json   # Plugin identity and version
├── skills/{name}/SKILL.md       # User-invocable skills (ingest, lookup, refine, new)
├── agents/                      # Subagent definitions (YAML frontmatter + prompt)
├── scripts/                     # Lifecycle and utility scripts
├── templates/
│   ├── library/                 # Files copied when init.sh bootstraps a new library
│   └── stack/                   # Files copied when /stacks:new scaffolds a stack
│       ├── sources/incoming/    # Incoming source drop zone
│       ├── topics/              # Topic guide directories
│       └── dev/curate/extractions/  # Raw extraction working files
└── references/                  # Reference docs: wave engine, refresh procedure, topic template
```

## Frontmatter convention

Skill files live at `skills/{name}/SKILL.md`. Frontmatter uses only `name` and `description` fields — no `version`, `allowed-tools`, or `thinking`. Description starts with "Use when..." for trigger matching.

```yaml
---
name: stacks:ingest
description: Use when the user wants to ingest new sources into a stack...
---
```

Agent files live in `agents/`. Frontmatter defines `tools` (comma-separated), `model`, and `description`. Include 3+ worked examples in agent prompts.

## Development workflow

1. Edit source files in this repo.
2. Bump version in `.claude-plugin/plugin.json`.
3. `git commit && git push`
4. Install updated plugin: `bash scripts/install.sh` or `claude plugin update stacks` (if registered as marketplace plugin).
5. Restart Claude Code session to pick up changes.

Any edit to plugin files (commands, skills, agents, scripts) requires a semver bump. Without it, the deployment pipeline cannot detect changes.

## Testing convention

```bash
# Install the plugin
bash scripts/install.sh

# Create a test library
bash scripts/init.sh ~/tmp/test-library

# Run skills against it (point Claude at ~/tmp/test-library as your library)
/stacks:new test-stack
/stacks:ingest
/stacks:lookup some question

# Clean up
rm -rf ~/tmp/test-library
```

Do not commit test library content to this repo.
