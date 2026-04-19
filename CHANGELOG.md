## 0.9.0-alpha.2 — 2026-04-18

- feat(ask): article-mode branch in Step 5. When the queried stack has `articles/*.md` files, reads articles; otherwise falls back to `topics/*/guide.md` (legacy guide mode). Detection uses `test -d {stack}/articles && find {stack}/articles -maxdepth 1 -name '*.md' | head -1 | grep -q .` — no STACK.md field required. Addresses stacks#20.
- feat(ask): Step 4 now extracts any user-authored `## Reading Paths` section from `{stack}/index.md` as additional retrieval context, augmenting the existing Topics-table matching.

## 0.9.0-alpha.1 — 2026-04-18

- feat(catalog-sources): new ingestion skill producing article-per-concept wiki entries. Waves W0 (enumerate incoming/) → W0b (prior-findings skip list) → W1 (concept-identifier, parallel per source) → W1b (bash slug-collision dedup) → W2 (article-synthesizer, parallel per unique concept) → W2b (deterministic wikilink pass) → W3 (source filing) → W4 (MoC regeneration preserving ## Reading Paths). Ships alongside the existing ingest-sources pipeline during transition; #22 removes the old skill. Addresses stacks#19.
- feat(agents): add `concept-identifier` (single-pass concept identification + claim extraction, slug immutability on existing articles) and `article-synthesizer` (writes articles/{slug}.md with extraction_hash frontmatter, strip-on-rewrite rule for prior-cycle audit marks, 300-800 word body, inline [source-slug] citations). 3+ worked examples each per plugin convention.
- feat(scripts): add `scripts/assert-written.sh` write-or-fail gate (test -s + mtime > dispatch_epoch, Linux-only via `stat -c %Y`, fixed AGENT_WRITE_FAILURE error string) and `scripts/wikilink-pass.sh` deterministic linker (bold-term extraction from glossary, first-occurrence per-article substitution, self-link exclusion, skip-if-already-wrapped).
- feat(references): rewrite wave-engine.md to document catalog-sources (W0-W4) and audit-stack (A1-A5) wave tables, write-or-fail gate contract, slug immutability, W1b dedup, feedback flywheel. Old W0-W6 content removed.

## 0.8.3 — 2026-04-17

- feat(ingest-sources): auto-pick target stack(s) when invoked with no argument. Scans all stacks for `sources/incoming/` files and ingests each one sequentially, largest batch first. Explicit stack argument and `--from` still win. Removes the "ERROR: Specify a stack name" dead-end when the user's intent is obvious from library state.

## 0.8.2 — 2026-04-17

- feat(process-inbox): add split-content classification rule. Files whose `## ` sub-topics span multiple stacks are now routed by ⅔ majority rather than always treated as ties. The winning stack is recorded along with off-topic sub-topic headings so the ingestion step can flag them. Only near-even splits stay in inbox. Addresses the library-stack S4 s779 tie where 3 testing sub-topics + 2 sysops sub-topics had no routing rule.
- fix(ingest-sources): add pre-ingest gate for source filenames containing `(` or `)`. The Step 3 index parser `grep -o 'sources/[^)"]*'` silently truncates on `)`, producing a broken index. Fail early with a rename instruction instead of running agents against a broken source list.
- fix(refine-stack): verify WebFetch produced a non-empty file in Step 9 gap-filling before counting it as fetched. Empty fetches (404 body, paywall stub, auth redirect rendered as blank) were silently entering the ingest waves and leaving dead source entries in the index. Removes the file and skips instead.

## 0.8.1 — 2026-04-17

- fix(process-inbox): stage inbox deletions alongside incoming additions. The commit step assumed `inbox/` was gitignored (true for new libraries scaffolded at 0.8.0+, false for libraries that predate the template gitignore). Now uses `git add -A inbox/ {stacks}/sources/incoming/` so both tracked and ignored inbox files produce a clean tree after routing. Observed in library-stack where the first 14-file route left deletions unstaged and required a cleanup commit.

## 0.8.0 — 2026-04-17

- feat(skills): add `stacks:process-inbox` skill — classifies inbox/ session extracts against existing stacks using content and source metadata, routes matched files to `{stack}/sources/incoming/`, and reports unmatched files. Runs from any repo via stacks config. Handles filename collisions, zero-stacks, and missing inbox/ directory.
- feat(templates/library): scaffold `inbox/` directory on new libraries; add `/inbox/` to library `.gitignore` (transient routing artifacts, not library content).

## 0.7.2 — 2026-04-15

- fix(templates/stack): STACK.md topic template now distinguishes Pitfalls (terrain surprises) from Patterns (how to do things correctly) and Field Notes (production observations). Added explicit pitfall gate definition to prevent misclassification.
- fix(topic-synthesizer): added pitfall gate to Judgment Bias — only file under Pitfalls if an experienced practitioner who understands the design intent would still get burned.
- fix(topic-extractor): added same pitfall gate to extraction tagging — catches misclassification before synthesis.
## 0.7.1 — 2026-04-15

- feat(ask): add Step 7 query-filing loop — valuable synthesized answers are filed back into the stack as new or updated topic guides. Implements Karpathy's compounding principle: knowledge gained through querying accumulates in the library, not just chat history.
## 0.7.0 — 2026-04-15

- feat(refine-stack): add Step 9 gap-filling loop — after findings are presented, agent fetches sources for P1/P2 research items, saves to incoming/, and re-ingests only affected topic groups. Implements the Karpathy principle: identifying gaps is half the job, the LLM should also close them. P3 items (new topics) are flagged but not acted on without human direction.
# Changelog

## 0.6.0 — 2026-04-12

- feat(ingest-sources): `--from {path}` flag stages markdown/text files from an existing directory into `sources/incoming/` before ingest runs. Enables one-command migration from existing knowledge repos. Skips PDFs, images, and binaries with a count reported to the user.

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
