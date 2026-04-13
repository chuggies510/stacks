# Changelog

## 0.5.2 — 2026-04-12

- feat: library CLAUDE.md template now includes Session Start section — enumerates stacks, shows topic/source/incoming counts, available commands, and derives next-action suggestion after /workspace-toolkit:start runs
- fix: catalog.md template had stale skill name (`/stacks:new` → `/stacks:new-stack`)

## 0.5.1 — 2026-04-12

- fix: library templates (CLAUDE.md, README.md) had stale skill names from pre-rename
- fix: refresh-procedure.md referenced nonexistent `/stacks:ingest refresh` mode and wrong output file
- fix: topic-extractor agent referenced phantom "CLAUDE.md fallback" for source hierarchy
- fix: telemetry.sh used `#!/bin/bash` instead of `#!/usr/bin/env bash`
- fix: init.sh removed pointless `2>&1` on `gh repo create`
- fix: new-stack replaced `perl` placeholder replacement with `sed` (drops unlisted dependency)
- fix: uninstall.sh added comments explaining why it cleans up files install.sh doesn't write

## 0.5.0 — 2026-04-12

- feat: rename all skills to descriptive names — `init-library`, `new-stack`, `ingest-sources`, `ask`, `refine-stack`
- All cross-references in skills, README, CLAUDE.md updated

## 0.4.1 — 2026-04-12

- fix(init): split `gh repo create --source --push` into separate create + remote add + push steps — combined flag is unreliable
- fix(init): error trap no longer deletes local directory after GitHub repo is created; reports recovery instructions instead

## 0.4.0 — 2026-04-12

- docs: README rewrite with accurate skill list, agent table, pipeline descriptions, requirements
- docs: CLAUDE.md rewrite with marketplace registration model, corrected plugin structure
- fix: standardize agent model fields to shorthand (`sonnet`) across all 7 agents
- fix: expand .gitignore with standard patterns

## 0.3.0 — 2026-04-12

- feat: `/stacks:init-library` skill, library creation is now self-service from within Claude Code
- fix: all skills used stale `pluginPaths["stacks@local"]` fallback, replaced with `known_marketplaces.json` lookup
- fix: gate check error messages now say "Run /stacks:init-library" instead of "Run bash path/to/..."

## 0.2.0 — 2026-04-12

- fix(install): register as directory-source marketplace with `marketplace.json`, matching how ChuggiesMart and impeccable register. Previous approaches (writing `installed_plugins.json`, `pluginPaths`, symlinks) all failed.
- fix(uninstall): clean up `extraKnownMarketplaces`, `known_marketplaces.json`, and `installed_plugins.json` — was still referencing old `stacks@local` / `pluginPaths` keys
- fix(update): remove broken `claude plugin update stacks` call. Directory-source plugins update via `git pull`, no cache refresh needed.
- feat(init): create private GitHub repo and push initial commit via `gh`. `--public` flag available. Uses `git init -b main` to avoid branch name warnings.

## 0.1.0 — 2026-04-12

Initial release.

- Five skills: `/stacks:init-library`, `/stacks:new-stack`, `/stacks:ingest-sources`, `/stacks:ask`, `/stacks:refine-stack`
- Seven agents: topic-clusterer, topic-extractor, topic-synthesizer, cross-referencer, validator, synthesizer, findings-analyst
- Templates for library and stack bootstrapping
- Lifecycle scripts: install, uninstall, update, init
- Reference docs: wave engine, refresh procedure, default topic template
