# CLAUDE.md

Claude Code plugin for building and maintaining curated domain knowledge libraries. Sources are ingested into topic guides that can be queried with `/stacks:lookup` from any repo.

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
- `/stacks:audit-stack` — Validate articles against their cited sources, fix contradictions in place, identify gaps
- `/stacks:enrich-stack` — Acquire sources to close audit soft spots
- `/stacks:ingest-book` — Convert a handbook PDF chapter-by-chapter (doc-tools faithful mode) into the deep-reference tier
- `/stacks:lookup` — Look up knowledge from the configured library (articles + deep reference)
- `/stacks:using-stacks` — Entry point that routes to the right stacks skill

## Plugin Structure

```
stacks/
├── .claude-plugin/
│   ├── plugin.json            # Plugin identity and version
│   └── marketplace.json       # Single-plugin marketplace descriptor
├── skills/{name}/SKILL.md     # User-invocable skills (init-library, new-stack, catalog-sources, lookup, audit-stack, enrich-stack, ingest-book, process-inbox, using-stacks)
├── agents/                    # 4 subagent definitions (source-extractor, article-synthesizer, validator, enrichment)
├── scripts/                   # Lifecycle scripts (install, uninstall, update, init)
├── templates/
│   ├── library/               # Files copied when /stacks:init-library creates a library
│   └── stack/                 # Files copied when /stacks:new-stack scaffolds a stack
└── references/                # Reference docs (web-fetch-routing.md, reference-tier.md)
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
/stacks:lookup some question
# clean up
rm -rf ~/tmp/test-library
```

Do not commit test library content to this repo.

## GitHub

- **Repo**: git@github.com:chuggies510/stacks.git
- **Issues**: `gh issue list --state open`

## Gotchas

### Template `.gitignore` Self-Shadows Its Own `.gitkeep` Placeholders

When a template subtree (e.g. `templates/stack/`) ships both a `.gitignore` and a `.gitkeep` inside a to-be-ignored child directory, bare-directory patterns silently block their own placeholder. `sources/trash/` in `templates/stack/.gitignore` matches `templates/stack/sources/trash/` AND `templates/stack/sources/trash/.gitkeep` — so `git add` of the .gitkeep refuses, the template directory ships without its placeholder, and downstream scaffolding has no empty dir to seed. Use `dir/*` + `!dir/.gitkeep`:

```
sources/incoming/*
sources/trash/*
!sources/incoming/.gitkeep
!sources/trash/.gitkeep
```

`dir/*` ignores directory *contents* (what you want for user-added files post-scaffold) while leaving the directory entry traversable so `!.gitkeep` re-include reaches. Diagnose with `git check-ignore -v path/to/.gitkeep`. Affects any `templates/` subtree with a nested `.gitignore`.

### Claude Code Sub-agent Success Is Observable Only as Returned Text, Not Exit Codes

Sub-agents dispatched via the Task tool return a text response to the calling session. They do not return a shell exit code. Any gate the main session wants to enforce against sub-agent success must parse the returned text for an observable signal, or — as both pipelines do — gate on the file the sub-agent was told to write (`gate-batch.sh` checks size + mtime + content-shape). A hallucinated "success" line cannot fake a file that wasn't freshly written. Symptom on failure: main session sees truncated or empty text and hangs or silently marks the work done.

### Shell env does not persist between a skill's Bash blocks; cwd does

A SKILL.md that sets `STACK=...`, `SCRIPTS_DIR=...`, an array, or `DISPATCH_EPOCH=$(date +%s)` in one Bash block and reads it in a later block gets an EMPTY value: the harness re-initializes the shell each call (env vars and functions are lost). The working directory IS preserved across calls, so a `cd` in one block holds for the next (including into a nested skill invocation). Consequences for skill prose: never pass a signal between blocks via an env var — re-derive it in the block that needs it (e.g. re-run `resolve-library.sh` rather than reuse `$LIBRARY`), or pass it through `$ARGUMENTS` of a nested skill (the 0.36/0.37 lookup→enrich path passes `--auto`/`--query` this way, not env). This bit the lookup auto-path twice (an unset `$LIBRARY` `cd`, a lost sentinel). The three fan-out pipelines (catalog, audit, enrich) now avoid this structurally — their deterministic flow lives in `scripts/pipeline/*.sh` phases that cross state through `dev/<phase>/{run.env,dispatch.tsv}` files, never shell env (epic #87, #72). The trap still applies to any NEW skill Bash-block prose: re-derive per block or pass through `$ARGUMENTS`, never an env var.

## Chuggies Bot

@chuggies_bot is a Telegram-based AI assistant that reads memory banks and issues across repos. It runs on Dev Pi (192.168.3.4) via OpenClaw. Memory bank handoffs are consumed by the bot's nightly refresh (2am Pacific) — keep `active-context.md` structured and current.
