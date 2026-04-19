## 0.13.0-alpha.4 (unreleased)

- feat(audit-stack): new `agents/synthesizer-orchestrator.md` (A2) and `agents/findings-analyst-orchestrator.md` (A3) wrap the previously-unsharded synthesizer and findings-analyst dispatches. Both use the schema-v1 envelope and the single-shard fast-path pattern (A2 cap `ARTICLES_PER_AGENT=30` since synthesizer reads articles only; A3 cap 15 matching A1). Above the cap, shard agents write partials to `dev/audit/_a{2,3}-partial-{batch_id}.md`; A2 re-dispatches `synthesizer` with a merge task, A3 bash-merges by item id with terminal-wins precedence. `skills/audit-stack/SKILL.md` Steps 5 and 7 rewritten to dispatch the orchestrators. Unblocks mep-stack (~250 articles). Closes #32.

## 0.13.0-alpha.3 (unreleased)

- feat(concept-identifier-orchestrator, article-synthesizer): W1b writes per-slug `_dedup-{slug}.md` files; W2 dispatch passes the per-slug path; article-synthesizer reads only its own slug's block. `_dedup.md` preserved as aggregated audit-trail artifact. Progressive disclosure cuts per-agent tokens at large W2 fan-outs. Closes #36.
- feat(concept-identifier-orchestrator): W2 dispatch capped at `W2_WAVE_CAP=25` parallel agents per wave with loop. Each wave captures its own `DISPATCH_EPOCH_W2_WAVE` for per-wave assert-written gating. `counts.n_w2_waves` field populated in the summary JSON. Prevents Task-tool parallel-dispatch saturation on large fresh catalog runs. Closes #35.

## 0.13.0-alpha.2 (unreleased)

- feat(validator-orchestrator): per-batch source union via pre-dispatch citation graph. `validator-orchestrator` builds a `SOURCE_MAP` (slug → path) from `sources/` and a per-article `ARTICLE_SOURCES` map from frontmatter `sources:` + inline `[source-slug]` refs. Each per-batch validator receives only the union of its articles' cited sources instead of the full tree. Batches whose articles have zero resolvable citations fall back to the full tree as a safety net. `validator.md` Input contract updated. Closes #34.

## 0.13.0-alpha.1 (unreleased)

- feat(orchestrators, audit-stack, catalog-sources): unified orchestrator summary-JSON contract. Both `validator-orchestrator` and `concept-identifier-orchestrator` now write a schema_version=1 envelope (`{schema_version, wave, status, counts, epochs}`) to `dev/audit/_a1-summary.json` and `dev/extractions/_w1-w2-summary.json` respectively. Orchestrators return only an `ORCHESTRATOR_OK: wave=X` receipt line on stdout; structural data lives in the file. Failure markers unified to `ORCHESTRATOR_FAILED: wave={wave} reason={short}`. Main-session gates in `skills/audit-stack/SKILL.md` Step 4 and `skills/catalog-sources/SKILL.md` Step 6 / Step 10 updated to nested `.counts.FIELD` jq paths. Closes #33.

## 0.12.1 — 2026-04-19

- refactor(audit-stack, catalog-sources): simplify orchestrator summary-JSON gates to require only the fields the main session actually consumes. `validator-orchestrator` gate now checks `(.n_articles | type) == "number"` only; the other three fields (`n_batches`, `articles_per_agent`, `dispatch_epoch`) stay in the JSON as informational but are not mandatory. `concept-identifier-orchestrator` drops the `new_slugs[]` and `updated_slugs[]` arrays from its summary file — the main session reads only counts at Step 10, and the arrays were never consumed downstream. Also drops a narration paragraph from `concept-identifier-orchestrator.md` body that belonged in a commit message, not an agent prompt.

## 0.12.0 — 2026-04-19

Pipeline blockers epic (#31). Closes sub-issues #23, #25, #26, #27, #29, #30. Ships the orchestrator-wrapper pattern for both A1 (audit) and W1/W1b/W2 (catalog), the extraction-hash skip-list flywheel, per-stack tag vocabulary with halt-on-drift, deterministic W1 batch math, and a `resolvable_by` schema split that unblocks audit-stack convergence.

- feat(catalog-sources): new `agents/concept-identifier-orchestrator.md` wraps W1 concept-identifier dispatch, W1b slug-collision dedup + `compute-extraction-hash.sh` loop, and W2 article-synthesizer dispatch into a single main-session Task dispatch. Writes `dev/extractions/_orchestrator-summary.json` with accurate `n_articles_new` / `n_articles_updated` counts, which the Step 10 commit now reads via `jq` instead of the previously unpopulated `NEW_ARTICLE_SLUGS` / `UPDATED_ARTICLE_SLUGS` bash arrays. `skills/catalog-sources/SKILL.md` Steps 6-8 collapsed to one orchestrator dispatch (Step 6); `references/wave-engine.md` W1+W1b+W2 sections rewritten. Closes #27.
- feat(audit-stack): shard A1 validator dispatch via new `agents/validator-orchestrator.md` wrapper. The single-agent validator hit the "Prompt is too long" ceiling at ~75 articles because one agent received every article body plus every source file. The orchestrator splits articles across parallel `validator` agents (1 batch when `N <= 15`; otherwise `ARTICLES_PER_AGENT = min(ceil(N/5), 15)`) while each per-batch validator still sees the full sources tree (sources are the reference surface, not shardable). The orchestrator owns the per-article `assert-written.sh` gate loop and returns a summary JSON the main session parses as the A1 gate. `skills/audit-stack/SKILL.md` Step 4 and `references/wave-engine.md` A1 section rewritten accordingly. Closes #30.
- feat(catalog-sources, concept-identifier): replace prose-level W1 batching rule with a deterministic dispatch-math block. `SOURCES_PER_AGENT=10` baseline with a small-stack bypass of `1` when `N_SOURCES < 10`; `N_AGENTS = ceil(N_SOURCES / SOURCES_PER_AGENT)` bounds parallel dispatch regardless of source-set size. Introduces stable `batch-{1..N}` ids and renames extraction outputs from `dev/extractions/{source-slug}-concepts.md` to `dev/extractions/batch-{batch_id}-concepts.md`. concept-identifier contract now accepts N sources per invocation and writes one merged file per batch, deduping within-batch at the source level. Closes #26.
- feat(article-synthesizer, catalog-sources): declare canonical tag vocabulary per stack via new `## Tag Vocabulary` section in `templates/stack/STACK.md` (`allowed_tags:` YAML list). article-synthesizer now picks tags from that list and emits a `tag-vocabulary not declared` warning for unmigrated stacks. New `scripts/normalize-tags.sh` runs post-W2b and halts the catalog pipeline with `TAG_DRIFT: {slug}: {tag}` on stderr if any article acquires an out-of-vocabulary tag. No auto-rewrite. Backward-compat: stacks without `allowed_tags:` skip the check. Closes #25.
- feat(catalog-sources, concept-identifier, article-synthesizer): compute `extraction_hash` deterministically during W1b via new `scripts/compute-extraction-hash.sh` (sha256 of sorted source paths + `|` + slug). concept-identifier no longer emits the vestigial `hash_inputs` field; article-synthesizer copies the W1b-populated hash verbatim into article frontmatter. Restores the skip-list flywheel so already-synthesized content can be detected across catalog cycles. Closes #23.
- feat(findings-analyst, audit-stack): add `resolvable_by` field to findings items (schema v3). A4 convergence now filters on `resolvable_by == audit-stack`; `fetch_source` and `research_question` items are reported but no longer block convergence: they belong to catalog-sources and external resolution respectively. Carry-forward rule auto-populates `resolvable_by` from `action` on v2→v3 migration. Closes #29.

### Alpha cuts consolidated into 0.12.0

The five alpha entries below were shipped progressively during epic #31 and are rolled up in the `## 0.12.0 — 2026-04-19` release header above. The per-alpha bullets are preserved for historical commit-to-change traceability.

## 0.12.0-alpha.5 — 2026-04-19

- feat(audit-stack): shard A1 validator dispatch via new `agents/validator-orchestrator.md` wrapper. The single-agent validator hit the "Prompt is too long" ceiling at ~75 articles because one agent received every article body plus every source file. The orchestrator splits articles across parallel `validator` agents (1 batch when `N < 15`; otherwise `ARTICLES_PER_AGENT = min(ceil(N/5), 15)`) while each per-batch validator still sees the full sources tree (sources are the reference surface, not shardable). The orchestrator owns the per-article `assert-written.sh` gate loop and returns a summary JSON; the main session treats successful exit as the implicit A1 gate. `skills/audit-stack/SKILL.md` Step 4 and `references/wave-engine.md` A1 section rewritten accordingly. Closes #30.

## 0.12.0-alpha.4 — 2026-04-19

- feat(catalog-sources, concept-identifier): replace prose-level batching rule with a deterministic dispatch-math block. `SOURCES_PER_AGENT=10` baseline with a small-stack bypass of `1` when `N_SOURCES < 10`; `N_AGENTS = ceil(N_SOURCES / SOURCES_PER_AGENT)` bounds parallel dispatch regardless of source-set size. Introduces stable `batch-{1..N}` ids and renames extraction outputs from `dev/extractions/{source-slug}-concepts.md` to `dev/extractions/batch-{batch_id}-concepts.md`. concept-identifier contract now accepts N sources per invocation and writes one merged file per batch, deduping within-batch at the source level so a concept appearing in multiple assigned sources becomes one block with a multi-entry `source_paths:`. W1b awk dedup unchanged (globs on `*-concepts.md`); cross-batch dedup still produces the unified `_dedup.md` for W2. Closes #26.

## 0.12.0-alpha.3 — 2026-04-19

- feat(article-synthesizer, catalog-sources): declare canonical tag vocabulary per stack via new `## Tag Vocabulary` section in `templates/stack/STACK.md` (`allowed_tags:` YAML list). article-synthesizer now picks tags from that list and emits a `tag-vocabulary not declared` stdout warning for unmigrated stacks. New `scripts/normalize-tags.sh` runs post-W2b and halts the catalog pipeline with `TAG_DRIFT: {slug}: {tag}` on stderr if any article acquires an out-of-vocabulary tag. No auto-rewrite — operator resolves drift by editing the article or extending the vocabulary. Backward-compat: stacks without `allowed_tags:` skip the check. Closes #25.

## 0.12.0-alpha.2 — 2026-04-19

- feat(catalog-sources, concept-identifier, article-synthesizer): compute `extraction_hash` deterministically during W1b via new `scripts/compute-extraction-hash.sh` (sha256 of sorted source paths + `|` + slug). concept-identifier no longer emits the vestigial `hash_inputs` field; article-synthesizer copies the W1b-populated hash verbatim into article frontmatter. Restores the skip-list flywheel so already-synthesized content can be detected across catalog cycles. Closes #23.

## 0.12.0-alpha.1 — 2026-04-19

- feat(findings-analyst, audit-stack): add resolvable_by field to findings items (schema v3). A4 convergence now filters on resolvable_by == audit-stack; fetch_source and research_question items are reported but no longer block convergence — they belong to catalog-sources and external resolution respectively. Carry-forward rule auto-populates resolvable_by from action on v2→v3 migration. Closes #29.

## 0.11.1 — 2026-04-19

- fix(catalog-sources, audit-stack): SCRIPTS_DIR/STACKS_ROOT detection now prefers `installLocation` from `~/.claude/plugins/known_marketplaces.json` over scanning `~/.claude/plugins/cache/`. Directory-source installs have an authoritative path in `known_marketplaces.json`; cache scans could return a stale pre-pivot version (e.g. 0.8.3) and dispatch removed agents or skip newer scripts. Cache scan is now the fallback for registry-style installs. Closes #24.
- fix(findings-analyst): agent prompt now reinforces that the response to the operator must be a one-line confirmation only, not the findings content. Agent was silently returning full YAML inline and skipping the Write call despite having the tool; the assert-written gate caught it but re-dispatch was expensive. Closes #28.

## 0.11.0 — 2026-04-18

- fix(ask): Step 7 (file-result-back / Karpathy loop) now branches on the same MODE flag set in Step 5. Article-mode stacks write filings to `articles/{slug}.md` with proper frontmatter (`extraction_hash: ""`, `last_verified: ""`, `updated: <today>`); guide-mode stacks keep writing to `topics/{topic}/guide.md`. Previously both branches wrote to legacy `topics/` which does not exist in article-mode stacks (shipped bug from the 0.9.0 wiki-pivot cutover). Addresses #7 (filing-path slice only; broader "entity/comparison/synthesis page types" reframe left open).
- docs(references): add `references/obsidian.md` covering library-as-vault setup, graph view, Web Clipper configuration for `sources/incoming/`, and four Dataview query recipes (never-validated, single-source, staleness, tag coverage). Closes #9.
- docs(README): add a short "browse with Obsidian" section pointing to the new reference.

## 0.10.0 — 2026-04-18

- feat(findings-analyst): generate cross-article **Research Questions** alongside gap/drift findings. Schema `v1` → `v2`. Adds fourth section to `dev/audit/findings.md` with `action: research_question` items that name a tension, the articles involved, and a verification target. Question IDs are keyed on sorted article slugs + question text (stable across passes regardless of listing order). Closes #8.
- feat(audit-stack A4 convergence): research_question items count toward empty-pass gating alongside fetch_source. Renamed internal counter `fetch_open` → `generative_open` to reflect both action types. Budget cap and 2-consecutive-empty-pass rules unchanged.
- feat(wave-engine reference): updated convergence rule, feedback flywheel, and W0 gate text to document the two generative action types.
- compat: no migration required. Existing schema-v1 findings files carry forward unchanged — the agent reads old items and writes the schema-v2 file on the next pass. Old items retain their existing IDs; carry-forward rules apply.

## 0.9.2 — 2026-04-18

- feat(templates): add `sources/trash/` soft-delete bin to stack template. `mv {stack}/sources/{publisher}/foo.md {stack}/sources/trash/` pulls a filed source out of circulation without losing it. Gitignored. Closes #1.
- feat(validator + audit-stack A1): validator input now explicitly excludes `sources/incoming/` (pending) and `sources/trash/` (soft-deleted). Prevents trashed sources from re-surfacing as citation targets during audit.
- docs(library template): trash usage blurb in `templates/library/CLAUDE.md` Conventions section.

## 0.9.1 — 2026-04-18

- feat(templates): add `templates/stack/.gitignore` with `sources/incoming/`. New stacks scaffolded via `/stacks:new-stack` ignore the incoming staging directory, matching the library-level `/inbox/` pattern. Closes #4.

## 0.9.0 — 2026-04-18

BREAKING: `ingest-sources` and `refine-stack` removed. `catalog-sources` and `audit-stack` are the replacements. No migration path for existing `topics/*/guide.md` files — rebuild from source with `/stacks:catalog-sources`. Closes #22.

- breaking(skills): remove `skills/ingest-sources/` and `skills/refine-stack/` — superseded by `catalog-sources` and `audit-stack`
- breaking(agents): remove `agents/topic-clusterer.md`, `agents/topic-extractor.md`, `agents/topic-synthesizer.md`, `agents/cross-referencer.md` — old pipeline agents no longer needed
- breaking(templates): remove `templates/stack/dev/curate/` subtree; add `templates/stack/dev/audit/` and `templates/stack/dev/extractions/`
- refactor(sweep): all cross-repo references updated — `ingest-sources` → `catalog-sources`, `refine-stack` → `audit-stack` across CLAUDE.md, README.md, all skill files, refresh-procedure.md, templates/library/CLAUDE.md, templates/library/README.md
- bump: `0.9.0-alpha.3` → `0.9.0` (resolves pre-existing 0.8.3/0.8.0 plugin.json/marketplace.json mismatch as side effect)

## 0.9.0-alpha.3 — 2026-04-18

- feat(audit-stack): new validation skill. Waves A1 (validator inline-marks articles with [VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE], strips prior-cycle marks first, updates last_verified) → A2 (synthesizer produces glossary.md / invariants.md / contradictions.md at stack root) → A2b (shared wikilink pass) → A3 (findings-analyst writes dev/audit/findings.md per locked schema) → A4 (bash convergence: 2 consecutive empty passes OR MAX_AUDIT_PASSES cap, default 3) → A5 (archive copy to dev/audit/closed/{audit_date}-findings.md on convergence). Per-article A1 gate loop (directory mtime does not advance on in-place file edits). Addresses stacks#21.
- feat(agents): reshape validator, synthesizer, findings-analyst prompts. Validator writes inline marks, strips prior cycle, sets last_verified. Synthesizer produces three stack-root artifacts with independent-corroboration rule. Findings-analyst writes locked schema (id = full SHA256 of {article-slug}|{finding_type}|{claim}, status enum including terminal `failed`, carry-forward from prior pass, three sections).
- feat(loop-closure): catalog-sources W0b reads prior findings.md to skip already-synthesized extraction_hash values. audit-stack A5 uses cp so findings.md persists for the next catalog cycle.

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
