# Changelog

## 0.2.0 — 2026-04-12

- fix(install): register as directory-source marketplace with `marketplace.json`, matching how ChuggiesMart and impeccable register. Previous approaches (writing `installed_plugins.json`, `pluginPaths`, symlinks) all failed.
- fix(uninstall): clean up `extraKnownMarketplaces`, `known_marketplaces.json`, and `installed_plugins.json` — was still referencing old `stacks@local` / `pluginPaths` keys
- fix(update): remove broken `claude plugin update stacks` call. Directory-source plugins update via `git pull`, no cache refresh needed.
- feat(init): create private GitHub repo and push initial commit via `gh`. `--public` flag available. Uses `git init -b main` to avoid branch name warnings.

## 0.1.0 — 2026-04-12

Initial release.

- Four skills: `/stacks:ingest`, `/stacks:lookup`, `/stacks:refine`, `/stacks:new`
- Five agents: topic-extractor, topic-synthesizer, topic-clusterer, cross-referencer, gap-analyzer
- Templates for library and stack bootstrapping
- Lifecycle scripts: install, uninstall, update, init
- Reference docs: wave engine, refresh procedure, default topic template
