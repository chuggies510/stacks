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
├── agents/                    # 5 subagent definitions (YAML frontmatter + prompt)
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

### Claude Code Task-tool Sub-agent System Prompts Are Loaded From Frontmatter, Not Forwarded

When building orchestrator agents that dispatch other agents via the Task tool, the sub-agent's system prompt is loaded automatically from its frontmatter by `subagent_type`. An orchestrator cannot inject, extend, or "forward" the callee's prompt. Any instruction like "read `$AGENTS_DIR/validator.md` and pass that prompt to each agent, extended with..." is functionally useless — the Task tool's task-content parameter is the per-invocation input the sub-agent sees as its user message, not a system-prompt override. Consequences: (a) orchestrators should not take `$AGENTS_DIR` as an input if the only justification was reading a sub-agent's prompt file, and (b) the sub-agent's contract must be stable enough to run from its frontmatter alone, with per-invocation variation passed as task-content. Got burned: S9 epic #31 T5 validator-orchestrator initially carried a `Read $AGENTS_DIR/validator.md` step that was physically impossible; rewrite caught in Phase-5 review. T6 shipped the fix baked in.

### Claude Code Sub-agent Success Is Observable Only as Returned Text, Not Exit Codes

Sub-agents dispatched via the Task tool return a text response to the calling session. They do not return a shell exit code. Any gate the main session wants to enforce against sub-agent (or orchestrator) success must parse the returned text for an observable signal. Two reliable patterns: (a) emit a final JSON payload as the last content of the response and have the main session parse it with `grep -oE '\{...\}' | jq`; (b) write a summary file to disk and have the main session verify both the file's presence and a required-field type-check. Pair the two for defense-in-depth: a hallucinated "success" JSON line cannot fake a file that wasn't written. Symptom on failure: main session sees truncated or empty text and hangs or silently marks the work done. Got burned: S9 T5 initial draft said "treat successful exit as the implicit A1 gate"; reviewer pointed out there is no exit code to observe. Now standardized: JSON payload + (where applicable) summary file + field type-check.

### `jq -e` With `and` Operator Treats `0` and `[]` as Falsy

`jq -e '.count1 and .count2'` and `jq -e '.arr1 and .arr2'` evaluate their expressions for jq-truthiness — and in jq, `0`, `""`, `[]`, `{}`, `null`, and `false` are ALL falsy. A gate like `jq -e '.n_articles_new and .n_articles_updated'` fires correctly on the first catalog run (both counts > 0) but false-fails on every incremental run after the skip list populates, because both counts become `0` and the `and` short-circuits. Empty arrays `[]` trigger the same bug. Fix: test for key existence and correct types, not truthiness: `jq -e '(.n_articles_new | type) == "number" and (.n_articles_updated | type) == "number"'`. This passes for zero-count valid outputs and still catches missing/wrong-typed fields. Got burned: S9 T6 concept-identifier-orchestrator gate; caught by correctness reviewer at H severity before ship. Affects any bash pipeline using `jq -e` to validate a JSON summary where zero counts or empty arrays are legitimate.

## Chuggies Bot

@chuggies_bot is a Telegram-based AI assistant that reads memory banks and issues across repos. It runs on Dev Pi (192.168.3.4) via OpenClaw. Memory bank handoffs are consumed by the bot's nightly refresh (2am Pacific) — keep `active-context.md` structured and current.
