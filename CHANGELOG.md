# Changelog

## 0.4.0 — 2026-04-12

- docs: README rewrite with accurate skill list, agent table, pipeline descriptions, requirements
- docs: CLAUDE.md rewrite with marketplace registration model, corrected plugin structure
- fix: standardize agent model fields to shorthand (`sonnet`) across all 7 agents
- fix: expand .gitignore with standard patterns

## 0.3.0 — 2026-04-12

- feat: `/stacks:init` skill, library creation is now self-service from within Claude Code
- fix: all skills used stale `pluginPaths["stacks@local"]` fallback, replaced with `known_marketplaces.json` lookup
- fix: gate check error messages now say "Run /stacks:init" instead of "Run bash path/to/..."

## 0.2.0 — 2026-04-12

- fix(install): register as directory-source marketplace with `marketplace.json`, matching how ChuggiesMart and impeccable register. Previous approaches (writing `installed_plugins.json`, `pluginPaths`, symlinks) all failed.
- fix(uninstall): clean up `extraKnownMarketplaces`, `known_marketplaces.json`, and `installed_plugins.json` — was still referencing old `stacks@local` / `pluginPaths` keys
- fix(update): remove broken `claude plugin update stacks` call. Directory-source plugins update via `git pull`, no cache refresh needed.
- feat(init): create private GitHub repo and push initial commit via `gh`. `--public` flag available. Uses `git init -b main` to avoid branch name warnings.

## 0.1.0 — 2026-04-12

Initial release.

- Five skills: `/stacks:init`, `/stacks:new`, `/stacks:ingest`, `/stacks:lookup`, `/stacks:refine`
- Seven agents: topic-clusterer, topic-extractor, topic-synthesizer, cross-referencer, validator, synthesizer, findings-analyst
- Templates for library and stack bootstrapping
- Lifecycle scripts: install, uninstall, update, init
- Reference docs: wave engine, refresh procedure, default topic template
