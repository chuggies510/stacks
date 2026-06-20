## 0.31.0 — 2026-06-20

**enrich-stack closes its own loop instead of handing you two more commands.** After you approve staging, it now offers to catalog + audit in the same session — the approval was the only real decision, the rest was button-pushing.
- Step 8 asks one Y/n (because `catalog-sources` commits), surfaces any caveats on the staged sources, then runs `/stacks:catalog-sources` + `/stacks:audit-stack` and reports which gaps the re-audit cleared. Decline and it prints the manual next step, same as before. (`skills/enrich-stack/SKILL.md`, stacks#67)

## 0.30.0 — 2026-06-20

**Catalog runs stop leaving two manual cleanup chores behind.** Source refs and publisher dirs now come out canonical, so the operator no longer hand-fixes them after every run.
- Source refs are normalized to bare `sources/{...}` at W1b dedup — the redundant `<stack>/sources/` prefix (echoed from the dispatched path) is stripped before it reaches article frontmatter, so refs resolve and a `- sources/` checker can't skip a prefixed line. The synthesizer contract now states the bare-form rule too. (`scripts/dedup-extractions.py`, `agents/article-synthesizer.md`, stacks#65)
- W3 filing canonicalizes the publisher slug (lowercase, collapse `.`/`_`/space to `-`, strip trailing punctuation) and reuses an existing `sources/<dir>` on a match, so one publisher no longer fragments into `up.codes` / `up-codes` / `cpsc.gov` siblings. (`scripts/normalize-publisher.sh`, `skills/catalog-sources/SKILL.md`, stacks#66)
- New bats coverage for both. (`tests/normalize-publisher.bats`, `tests/dedup-extractions.bats`)

## 0.29.0 — 2026-06-19

**The pipeline can now go *find* sources, not just ingest what you drop in.** `/stacks:audit-stack` flags soft spots (article claims with no cited source); closing them used to be all-manual web-searching. The new `/stacks:enrich-stack {stack}` acquires candidate sources for you.
- New `enrichment` agent: per soft spot, web-searches for one grounding source, verifies it states the actual claim (not just the topic), rates its tier, and dedups against already-filed sources. Four verdicts: CANDIDATE / WEAK (low-tier only) / DUP (already filed) / NOSOURCE. (`agents/enrichment.md`)
- New `/stacks:enrich-stack` skill: reads the audit's soft spots, drops stale ones (claim no longer in the article), dispatches the agent in batches, then presents found sources for approval and stages only what you approve into `incoming/` — never auto-ingests. (`skills/enrich-stack/SKILL.md`)
- `audit-stack` now persists a machine-readable `dev/audit/soft-spots.tsv` (verbatim claim + reason) so enrich reads structured data, not the human report's markdown; the validator emits the claim and reason as separate fields. (`agents/validator.md`, `skills/audit-stack/SKILL.md`)
- New `enrichment-findings` gate shape + bats coverage. (`scripts/assert-structure.sh`, `tests/assert-structure.bats`)

## 0.28.0 — 2026-06-19

**Skills find your library even before the machine is registered.** `/stacks:lookup` and `/stacks:process-inbox` used to hard-stop with "run init-library" when no config file existed — even when you were standing inside a fully-built library. They now resolve gracefully.
- New `scripts/resolve-library.sh` honors the `$STACKS_CONFIG` override (the scripts already used it; the skills ignored it) and falls back to the current directory when it is itself a library (has `catalog.md`). Covered by `tests/resolve-library.bats`.
- `lookup` and `process-inbox` Step 1 now call the resolver instead of each duplicating the config-read block. (`skills/lookup/SKILL.md`, `skills/process-inbox/SKILL.md`)
- `process-inbox` re-establishes `STACKS_ROOT` in its file-move step, which runs as a separate shell where the variable would otherwise be unset.
- Fixed `rewrite-source-refs.sh` failing on macOS: bare `sed -i` works on Linux (GNU sed) but needs `sed -i ''` on macOS (BSD sed). Now detects the flavor, so source-ref rewriting after `catalog-sources` works on both. (`scripts/rewrite-source-refs.sh`)
- Realigned `marketplace.json` (had drifted to 0.26.2) with `plugin.json`.

## 0.27.1 — 2026-06-18

**`/stacks:lookup` excludes private sources by path, not tier.** The primary-sources block now excludes `liminal/`, `field-notes/`, and `internal/` by path prefix rather than by source tier, so a legitimately high-tier private source is no longer surfaced. (`skills/lookup/SKILL.md`)

## 0.27.0 — 2026-06-18

**lookup: keyword-rank fallback retired; recognition over routing lines is now the sole retrieval path.**
- Step 3: removed `--stack` scope flag — Hop-1 recognition now routes all queries to the right stack without manual scoping.
- Step 6: removed `rank-articles.sh` keyword supplement — all article selection is recognition-only over routing lines. Validated against keyword on plumbing (5/5 articles): recognition scored 5/5 correct vs keyword's 3/5.

## 0.26.2 — 2026-06-18

**Rename the `ask` skill to `lookup` to eliminate generic-verb ambiguity.** The name `/stacks:ask` was being treated as a plain question rather than routing into the lookup pipeline. The skill is now `/stacks:lookup`.

- Renamed `skills/ask/` to `skills/lookup/`, updated skill frontmatter name and telemetry tag. (`skills/lookup/SKILL.md`)
- Updated all skill-name references across CLAUDE.md, README, start-brief, memory-bank, agents, scripts, and library templates. (#62)

## 0.26.1 — 2026-06-18

**`regenerate-moc.sh` no longer nests wikilink markup inside index entries when an article title itself contains `[[ ]]`.** Titles like `Bash [[test]] conditional syntax` were emitted as `[[slug|Bash [[test]] conditional syntax]]`, breaking the outer link in any wiki renderer and in `/ask`'s recognition surface. The inner `[[`/`]]` are now stripped from the display label before composing the entry; the slug (the real link target) is unaffected.

- Strip `[[`/`]]` from the display label inside the `[[slug|label]]` entry — slug is the canonical target, so the display label can drop markup it can't nest. (`scripts/regenerate-moc.sh`)
- Bats: added case — title with `[[ ]]` markup → no nested brackets in `index.md`. (`tests/regenerate-moc.bats`) (#60)

## 0.26.0 — 2026-06-18

**`audit-stack` now fixes wrong claims instead of tagging them and walking away, and stops rewriting whole articles just to stamp marks.** Before, the validator marked every claim inline (`[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]`) — which rewrote the entire article body to add a few tags (~64:1 token waste) and, worse, left a claim that contradicted its source sitting in the article with a `[DRIFT]` label. Since `/ask` reads articles and never the sources, that drifted-but-tagged claim was served as confident misinformation until a human re-cataloged. Now the validator reads-and-fixes: a claim that contradicts its cited source is corrected in place from the source, and a claim with no cited source is recorded as a "soft spot" in the report (left in the body, not deleted). No inline marks at all.

- **Validator is read-and-fix.** Contradictions are rewritten in place against the cited source (higher-tier source wins on conflict); unsourced claims become soft spots; legacy inline marks are stripped on sight. It writes per-batch findings to `dev/audit/_audit-{tag}.md` (tab-separated corrections + soft spots). (`agents/validator.md`)
- **Audit report has two sections** — corrections applied (what the validator auto-edited, so you can eyeball it) and soft spots (claims to source or confirm) — aggregated from the batch files, which are then deleted. The old four-mark counts and grep-the-body report are gone. (`skills/audit-stack/SKILL.md` Steps 3-5)
- **Validation gate shape changed**: a validated article is now signaled by a populated `last_verified:` date, not an inline mark. (`scripts/assert-structure.sh` `article-validated` kind; `tests/assert-structure.bats` updated)
- Mark vocabulary scrubbed from README, project-brief, system-patterns, tech-context, start-brief, and the synthesizer's strip rule (kept as legacy cleanup for un-migrated articles). (#57)

## 0.25.0 — 2026-06-18

**`/stacks:ask` no longer writes to your library behind your back, and its stack-scope flag is one flag instead of two.** Filing a query answer back into the library (the "Karpathy loop") used to auto-decide and auto-commit; now it asks first and does nothing unless you opt in. The two near-duplicate scope flags collapse into one.

- **File-back is opt-in.** `/ask` delivers the answer, then — only if filing is worthwhile — offers to file it, naming the target stack and whether it would extend or create an article. No write, no commit, until you say yes. (`skills/ask/SKILL.md` Step 7)
- **`--stack` takes a single stack or a comma list** (`--stack hvac` or `--stack hvac,swe`); the separate `--stacks` flag is gone, dropping ~25 lines of duplicate parsing. (`skills/ask/SKILL.md` Step 3; start-brief + system-patterns scrubbed of `--stacks`)
- New articles written by file-back now include the `routing:` field (#59) and register in `index.md` as a routing line, not a bare title link.
- The dead index-read and the hard top-3 retrieval cap (items 3-4 of the issue) were already resolved when the routing-map work (#59) landed first — recognition reads the index, and the keyword cap is now 10. (#58)

## 0.24.0 — 2026-06-18

**`index.md` becomes a routing map, so `/stacks:ask` finds the right article by recognizing what it covers — not just matching keywords.** Before, the index was a bare title list and lookup leaned entirely on keyword grep over article bodies; an article whose title didn't echo the question got missed even when it was the right one. Now each article carries a one-line description of what it covers and the questions it answers, the index composes those into a recognition map, and `/ask` reads the map and picks by meaning first (keyword rank still backs it up). This is the Layer-2 "connection" piece of the design north star: the LLM lands on the right article by pattern.

- **Synthesizer emits a `routing:` frontmatter line** per article — what it covers / questions it answers, in an asker's words, not a title restatement. (`agents/article-synthesizer.md`)
- **`regenerate-moc.sh` composes routing lines into the `## Articles` map** (`- [[slug|title]] — {routing}`); articles synthesized before this field render as bare links, so old indexes still rebuild cleanly. (`scripts/regenerate-moc.sh`, `tests/regenerate-moc.bats` — 3 cases)
- **`/ask` recognizes over the routing map first**, then merges in `rank-articles.sh` keyword hits (cap raised 3→10 for the merge; #58 finalizes the cap). (`skills/ask/SKILL.md` Steps 4-5)
- Existing libraries: routing lines populate as articles are re-cataloged; no bulk backfill shipped (that's an LLM pass over every article, run it deliberately). (#59)

## 0.23.1 — 2026-06-18

**Cataloged articles no longer cite source files at a path that no longer exists.** When `catalog-sources` files a source from `incoming/` to its publisher dir, the articles citing it now get their paths fixed in the same pass — before, every cataloged article pointed at an empty `sources/incoming/`, so every citation was a dead link.

- catalog W3 calls a new `rewrite-source-refs.sh` after each `mv`, swapping `sources/incoming/{file}` → `sources/{publisher}/{file}` across the stack's articles. Catches both ref forms (frontmatter `sources/...` and body `{stack}/sources/...`) by matching the shared `sources/incoming/` substring. (`skills/catalog-sources/SKILL.md` Step 8, `scripts/rewrite-source-refs.sh`, `tests/rewrite-source-refs.bats` — 6 cases). Doubles as the one-shot fixer for libraries cataloged before this fix. (#56)

## 0.23.0 — 2026-06-13

**`/stacks:ask` now searches inside article bodies, not just titles and tags — so it stops missing articles once a stack grows past a few dozen.** Before, retrieval scored each article only on its frontmatter `title`/`tags`/slug; an article whose relevant content was in the body never surfaced unless the query happened to echo its title. Past ~50-75 articles per stack that breaks down and `ask` returns wrong or incomplete sources. Now a keyword rank over the whole file picks the top 3. (#10, partial — the keyword wall; semantic-synonym retrieval via qmd is a later escalation, not built)

### Added

- **`scripts/rank-articles.sh`** — ranks articles against a query by case-insensitive keyword count over the whole file (body weight 1, `title:` line +5), drops stopwords and <3-char tokens, returns the top N `score⇥path` lines across all scoped stacks. Pure `grep`/`sort`, no new dependency, no index to maintain. (`tests/rank-articles.bats` — 7 cases incl. a body-only match that title-search would miss)
- `/stacks:ask` Step 5 calls it instead of asking the model to eyeball frontmatter. Empty output → honest "no matching content", no synthesis from nothing. (`skills/ask/SKILL.md`)

### Why not qmd

The original #10 proposed Karpathy's BM25/vector engine + an MCP server + an index. That's the second fix, not the first: the keyword wall (title-only matching) falls to `grep` over bodies with zero dependencies. qmd earns its slot only when retrieval misses on pure semantic synonyms keyword search can't catch — a sharper, later trigger than raw article count.

## 0.22.0 — 2026-06-13

**Stacks can now swallow the documents it exists for — PDFs, Word, Excel — instead of only hand-written markdown.** Before, the extractor read whatever file it was handed straight with the Read tool: a long PDF stopped at ~20 pages with no warning, and a `.docx` (zipped XML) came back as garbled bytes. A knowledge base built on silently-incomplete extraction reads as authoritative while being wrong. Now a conversion stage turns every document into full readable text before extraction, and anything it can't convert (images, scanned PDFs, unknown binaries) is skipped and reported, never garbled. (#55)

### Added

- **`scripts/convert-sources.sh`** — single type-aware conversion stage. PDF → `pdfplumber` text (whole document, no page cap; multi-column layout preserved, then blank-line runs squeezed); `.docx` → `pandoc`; spreadsheets/slides/legacy Office → `libreoffice` headless. Images, scanned PDFs (no text layer), and unknown binaries are skipped with a per-file reason. Converted originals are archived to `sources/.raw/` (gitignored), so provenance survives without bloating the article repo. Missing tool → that file is skipped-and-reported, never a crash. (`scripts/convert-sources.sh`, `tests/convert-sources.bats` — 6 cases incl. a real PDF round-trip)
- catalog-sources Step 3.5 runs the converter on each stack's `sources/incoming/` before W0 enumeration, so the extractor agent always receives readable text. (`skills/catalog-sources/SKILL.md`)

### Changed

- **Renamed the `concept-identifier` agent to `source-extractor`** to match its full job: it reads a source, extracts claims, maps concepts to article slugs, and assigns tiers — not just "identify concepts". (`agents/source-extractor.md`, catalog-sources dispatch + gate label, README, memory bank)
- **`--from` staging now accepts documents, not just `.md`/`.txt`.** It stages `.pdf/.docx/.xlsx/.pptx` and friends into `incoming/`, then the convert stage handles them — type-awareness lives in one place (the converter) rather than split across `--from`, the converter, and `process-inbox`. (`skills/catalog-sources/SKILL.md` Step 1.5)
- **New runtime dependencies** for document ingest: `pdfplumber` (fetched ephemerally via `uv run --with`, no install), `pandoc`, `libreoffice`. Each is only invoked for the formats that need it; a missing tool degrades to skip-and-report. (memory bank `tech-context.md`)

## 0.21.0 — 2026-06-13

**Cut stacks down to the one thing it's for: drop a source in, ask a question, get a grounded answer.** Everything that didn't serve that path is gone. The plugin is roughly half its former size (16 files deleted). Breaking: skills and the audit findings ledger were removed, so libraries built against the old audit format lose their `findings.md` flywheel (articles and sources are untouched).

### Removed

- **Audit is now a stateless drift report.** `audit-stack` validates each article against its cited sources (inline VERIFIED/DRIFT/UNSOURCED/STALE marks) and writes a fresh `dev/audit/report.md` listing what drifted. Gone: the `synthesizer` and `findings-analyst` agents, the `glossary.md`/`invariants.md`/`contradictions.md` artifacts, the `findings.md` carry-forward ledger, the convergence pass-loop, and the `reconcile`/`rotate`/`merge-findings` scripts. Each run stands alone — no state to drift. (audit-stack 487 → ~120 lines)
- **Dropped the extraction-hash skip-list flywheel** from catalog. Catalog no longer reads prior findings to skip unchanged concepts (W0b), no longer computes or stores `extraction_hash`, and no longer writes the `_w1-w2-summary.json` envelope it immediately read back (the parent already holds the counts as shell vars). (`compute-extraction-hash.sh` deleted; `concept-identifier`, `article-synthesizer`, `assert-structure.sh`, `ask` lose their hash coupling)
- **Cut the wikilink/Obsidian integration.** No consumer rendered `[[wikilinks]]`, so the W2b wikilink pass, the `glossary`-driven linker, and the Obsidian setup doc are gone. (`wikilink-pass.sh`, `references/obsidian.md` deleted; `references/wave-engine.md` and `references/refresh-procedure.md` deleted as orphaned/duplicative)
- **Reverted three 0.20.0 features that didn't earn their keep:** on-demand guide synthesis (`#18`), comparison pages (`#7`), and the inbox quality gate (`#40`). `skills/guide/`, `agents/comparison-synthesizer.md`, `skills/extract-reddit/`, and `extract-reddit-thread.py` are deleted; process-inbox is back to routing-only. The scheduled maintenance loop (`#14`, `scripts/loop.sh`) is **kept**.
- **Gate-fold:** `assert-written.sh` (the write-or-fail size+mtime check) was inlined into its only caller, `gate-batch.sh`. `shard-batches.sh` is gone — both pipelines now slice batches inline with `${ARRAY[@]:i:CAP}`.

### Changed

- catalog-sources keeps its core path: enumerate sources → identify concepts (W1) → dedup (W1b) → synthesize articles (W2, inline wave-cap) → file sources (W3) → regenerate the Map of Contents (W4).
- Agent roster: 5 workers → 3 (concept-identifier, article-synthesizer, validator).
- Article frontmatter no longer carries `extraction_hash`; the `article-md` structure gate and the `ask` filing template drop the field.

## 0.20.0 — 2026-06-13

Phase 3+4: inbox quality gate, scheduled maintenance loop, on-demand guide synthesis, and a comparison page type.

### Added

- process-inbox: quality gate — low-quality files route to `library/recycling-bin/` instead of stack incoming dirs, assessed by reading the file body. The Step 6 report gains a Recycled section when files are recycled. (#40)
- `scripts/loop.sh`: scheduled library maintenance — delegates inbox routing to `/stacks:process-inbox` via `claude -p`, then catalogs each stack with pending incoming files. Enable with `touch $LIBRARY/.loop-enabled`. Add to crontab with an explicit PATH that includes claude's install dir. Covered by `tests/loop.bats` (6 cases). (#14)
- `/stacks:guide`: new skill — synthesizes a long-form guide (800-2000 words) from library articles. Writes `library/guides/{slug}.md` with full article attribution and commit SHAs. `--stacks` scopes to named stacks; `--regenerate` rebuilds from current articles. (#18)
- `/stacks:ask`: checks `library/guides/` before article retrieval (Step 1.5) and surfaces an existing guide. (#18)
- Comparison page type: source files with `## Comparison: X vs Y` sections produce `comparisons/{slug}.md` via the new `comparison-synthesizer` agent. Requires ≥3 criteria or the page is skipped with a `COMPARISON_SKIPPED` report. catalog-sources Step 5.5 (W0c) pre-filters before W1; W1–W2 process only standard sources; an all-comparison run skips straight to index regen. W4 index rebuild now emits a Comparisons section. (#7)
- STACK.md template: `## Comparison Template` section documents the expected comparison page structure.
- `templates/stack/index.md`: now shows Articles, Comparisons, and Sources sections.

## 0.19.1 — 2026-06-12

Ponytail cleanup sweep: deleted dead orchestrator agents, removed the legacy guide-mode path, factored copy-pasted pipeline logic into shared scripts, swapped hand-rolled loops for stdlib. No change to live pipeline behavior.

### Removed

- **Deleted the four no-op orchestrator agents**: they were deprecated stubs kept "for external callers" with zero live callers, since catalog-sources and audit-stack dispatch the worker agents directly. Their stale "this is the live mechanism" descriptions are repointed to parent-side dispatch. (`agents/{validator,synthesizer,findings-analyst,concept-identifier}-orchestrator.md` deleted; `system-patterns.md`, `tech-context.md`, `wave-engine.md` rewritten)
- **Removed the legacy guide-mode path from `/stacks:ask`**: the catalog pipeline only produces `articles/`, and `topics/*/guide.md` has had no producer since 0.9.0. Mode-detection, guide-scoring, mixed-case, and guide-filing branches are gone; the skill is article-only. (`skills/ask/SKILL.md`, ~30 lines)
- **Dropped the dead `noop` finding action**: `merge-findings.py` has no `noop` bucket, so any such item was silently discarded at merge anyway. Also removed two one-shot schema-migration paragraphs (v2→v3, v3→v4) with no in-repo file to migrate from. (`agents/findings-analyst.md`)
- Dead `usage()`/`--help` handlers in `install`/`uninstall`/`update.sh` (no caller passes flags), the `agent_label` default in `assert-structure.sh` (every caller passes it), a redundant `command -v gh` check in `init-library` (the next `gh auth status` already reports it), the never-entered registry-install fallback in `locate-plugin-root.sh`, and a duplicate stub comment in `ask`.

### Changed

- **Factored three shared pipeline scripts** so the same logic stops being copy-pasted between catalog-sources and audit-stack: `gate-batch.sh` (the write-or-fail + structure gate loop, 5 call sites), `shard-batches.sh` (the awk article/source batch sharder, 3 sites), `collision-dest.sh` (the filename-collision rename loop, shared with process-inbox). New `tests/gate-batch.bats` (4 cases) covers the failure-aggregation path. (`scripts/{gate-batch,shard-batches,collision-dest}.sh` new)
- Collision-suffix numbering now starts at `-1` (was `-2`); cosmetic, both yield unique names.
- Removed the redundant agent-side write gate from `synthesizer` (the parent skill re-gates every output); dropped `Bash` from its tools.

### Internal

- stdlib swaps in the Python helpers: `collections.Counter` for hand-listed zero-init keys and `re.finditer` for a hand-rolled occurrence loop (`reconcile-findings.py`); `dict.fromkeys` for set-based source dedup and a de-duplicated writer (`dedup-extractions.py`); a 4-branch terminal-precedence ladder collapsed to 2 (`merge-findings.py`); dropped an unread `max_depth_applied` stat (`extract-reddit-thread.py`).
- bash: `grep -qxF` set-membership replacing an associative-array build (`normalize-tags.sh`); `shopt -s nullglob` replacing a per-file existence guard (`wikilink-pass.sh`); one redundant `tr` dropped (`regenerate-moc.sh`).
- Doc-drift fix: removed the stale "cross-stack ask is a stub" weak-spot note (`#5` shipped in 0.19.0) from `system-patterns.md`.

## 0.19.0 — 2026-05-10

Phase 2: pipeline content-structure gates and cross-stack lookup.

### Added

- feat(#50): `scripts/assert-structure.sh` — content-shape gate for pipeline output files. Checks 7 types: `concept-batch`, `dedup-md`, `dedup-meta`, `article-md`, `article-validated`, `glossary-md`, `invariants-md`. Companion to `assert-written.sh` (mtime gate). Comes with a 21-test bats suite at `tests/assert-structure.bats`.
- feat(#50): `catalog-sources` — assert-structure gates at W1 (`concept-batch`), W1b (`dedup-md`, `dedup-meta`), and W2 (`article-md`). Truncated or empty pipeline outputs now halt with a named `STRUCTURE_FAILURE:` error before they propagate downstream.
- feat(#50): `audit-stack` — assert-structure gates at A1 (`article-validated`) and A2 (`glossary-md`, `invariants-md`). Validator output with no marks and synthesizer output with no entries both halt the pipeline immediately.
- feat(#5): `/stacks:ask` cross-stack lookup. Default behavior (no flag) now searches all stacks in the library. `--stack {name}` forces single-stack scope (prior behavior). `--stacks {a,b,c}` scopes to a named subset. Answer format cites contributing stack(s). Step 7 filing updated for multi-stack targets. Retrieval block labelled as a stub for #10 (qmd) replacement.

Closes #50, closes #5.

## 0.18.0 — 2026-05-10

Bug sprint: stale extraction artifacts, awk harness clobber, missing post-A1 wikilink restore, and fuzzy reconcile for rewritten claims.

### Fixes

- fix(catalog-sources): pre-clean `dev/extractions/batch-*-concepts.md` and `_dedup*.md` before W1 dispatch. Without this, stale batch files from a prior catalog run that ended mid-flight would feed the dedup step as if they were fresh output from the current run, producing phantom concepts or incorrect merge counts. Zero-sources early-exit path is unaffected — rm runs after the source-count guard. Closes #46.
- fix(audit-stack): re-run `wikilink-pass.sh` after A1 cleanup (new Step 4.5: A1b). Validator agents strip `[[wikilinks]]` from sentences they rewrite; without this pass those links were absent when A2 synthesized the glossary, causing A2b's pass to add fewer links than intended. A no-op on first-pass runs where `glossary.md` is not yet present. Closes #44.
- fix(audit-stack): fuzzy claim match in `reconcile-findings.py`. Sentence-level fuzzy scoring (Jaccard pre-filter ≥ 0.30, SequenceMatcher ratio ≥ 0.55) now detects rewritten claims that still carry a `[VERIFIED]` or `[DRIFT]` mark in the immediately following window and closes them with a `rewrite-then-verify` note. Previously these items were left `unchanged` and aged out by `rotate-findings.sh` rather than being credited to the validator that actually resolved them. Claims shorter than 4 tokens are excluded from fuzzy scoring to avoid false positives on short boilerplate fragments. Adds `closed-rewrite-verified` action key to reconcile output. Only stdlib (`difflib`) added. Closes #47.

### Refactors

- refactor(catalog-sources): move per-slug extraction split from awk for-loop in SKILL.md into `dedup-extractions.py`. The awk loop used `$2` to extract the slug field from `_dedup.md` — a pattern susceptible to the Claude Code skill-harness `$N` substitution gotcha documented in CLAUDE.md (harness replaces `$0`/`$2` literals with positional skill args before the model sees the body). Python now writes `_dedup-{slug}.md` directly during the dedup pass, using the already-computed `slug_seen`/`slug_sources` data structures; no second read of `_dedup.md` required. Removes the awk loop and the prose reference to it. Closes #48, closes #49.

## 0.17.1 — 2026-05-09

Three-lens review patches on the 0.17.0 reconcile pass.

### Fixes

- fix(merge-findings.py): seed the merge's `by_id` map from the post-reconcile `findings.md` before processing partials. Without this seed, a closure produced by reconcile via the deleted-article path had no batch agent to carry it forward and was silently dropped from the merged output. The CHANGELOG entry for 0.17.0 promised this closure path; the seed makes the promise honest. Terminal items from the seed survive when no partial covers them; partials overlay via the existing terminal-wins precedence.
- fix(reconcile-findings.py): escape backslash and quote characters in existing `note:` field text before re-wrapping in double quotes. Prior implementation produced invalid YAML if a note ever contained a literal `"` (latent — no live findings.md currently has such notes).

### Refactors

- refactor(reconcile-findings.py): collapse manual mark-search loop into a single compiled `re` alternation pattern. Drop the dead `saw_status` fallback branch in `_close()` (status field is guaranteed present on open items by the caller's gate). Drop `closed_total` from the print line (derivable sum of three adjacent fields). Strip the WHAT-comment "Find which mark appears first" — the WHY block above already covers it. Header field-wrap collapsed to single-line-per-field to match `merge-findings.py` and `dedup-extractions.py`.

### Docs

- docs(reconcile-findings.py): drop `closed-claim-removed` from the `reconcile()` docstring return-value enum. The branch was removed during 0.17.0 smoke testing because findings-analyst paraphrases claims when extracting (drops parentheticals, expands acronyms), which made claim-not-found-in-article false-fire. Header rewritten to match actual behavior.
- docs(CHANGELOG.md): 0.17.0 entry corrected — auto-close handles VERIFIED/DRIFT validation transitions and deleted articles; the "claim rewritten out of article" path is intentionally excluded.

## 0.17.0 — 2026-05-09

Flywheel automation: pre-A3 reconcile auto-closes prior open findings when validation transitions resolve them. Schema enum narrowed to remove dead values.

### Features

- feat(audit-stack): pre-A3 reconcile pass via new `scripts/reconcile-findings.py`. Closes prior `open` findings whose claims now carry `[VERIFIED]` or `[DRIFT]` inline marks, or whose articles were deleted between cycles. Closures land as `status: closed` with `terminal_transitioned_on: $AUDIT_DATE` and a structured `note:` line. Closes the manual-bookkeeping gap in the Karpathy-style flywheel: the operator drops a source addressing an open `fetch_source` finding, recatalogs, and the next audit auto-closes the corresponding finding without hand-editing YAML. Ambiguous-match cases (claim text appearing more than once in the article body) are logged to stderr and carried forward unchanged. Findings-analyst agents read the post-reconcile findings.md, so closures are visible to their existing terminal-carry-forward logic without any agent prompt change. The "claim rewritten out of article" close path is intentionally excluded — findings-analyst paraphrases claims when extracting (drops parentheticals, expands acronyms), so a verbatim-search miss usually means paraphrasing rather than rewrite; see 0.17.1 for the merge seed that completes the deleted-article path.

### Removed

- remove(schema): `status: stale` and `status: failed` removed from the findings.md enum. Both values were defined in `agents/findings-analyst.md` but never emitted by any code path; pre-removal grep across all stacks confirmed zero live uses. Affected files: `agents/findings-analyst.md`, `scripts/merge-findings.py`, `scripts/rotate-findings.sh`, `skills/audit-stack/SKILL.md`, `references/wave-engine.md`.

## 0.16.2 — 2026-05-09

Bugfix: regenerate-moc.sh wrote literal `\n` between article links instead of newlines.

### Fixes

- fix(scripts/regenerate-moc.sh): line accumulation used `"...\n"` inside a double-quoted bash string (which is a literal backslash-n, not a newline), then emitted via `printf '%s'` (which does not interpret backslashes). Result: every per-tag article list rendered as one long line with `\n` between entries instead of a markdown bullet list. Switched to `$'\n'` ANSI-C quoting which gives a real newline. Surfaced on the first plumbing catalog run in library-stack (5 articles, single tag group).

## 0.16.1 — 2026-05-08

Three-round-review tightening of the new extract-reddit skill.

### Refactors

- refactor(extract-reddit-thread.py): drop `--max-comments` and `--max-depth` flags. The only call site passed both at their defaults. Constants live in the script (`MAX_COMMENTS = 100`, `MAX_DEPTH = 6`); edit there if you ever need to scale up.
- refactor(extract-reddit-thread.py): strip `id`, `parent`, `created_utc` from per-comment records and drop `indent=2` from the JSON output. Comment records are now `{author, score, depth, body}`. Output dropped from ~78KB to ~28KB on a 100-comment thread (~64% smaller context payload for the filter pass).
- refactor(extract-reddit-thread.py): drop `stats.dropped_deleted_or_removed` — the field name implied a deletion count but the math (`num_comments - len(flat)`) silently lumped depth-truncated comments in too. Stats now report only `comments_parsed`, `comments_kept`, `max_depth_applied`.
- refactor(extract-reddit/SKILL.md): cut "Notes on the filter" section (duplicated Step 4 rules), the preamble paragraph (restated the description), and 2 of 3 bullets in "When this skill is the wrong tool" (speculative future-tool references). The remaining failure mode — private/quarantined subreddit — moved into a dedicated section since the script's error message points at it.

## 0.16.0 — 2026-05-08

New skill: `/stacks:extract-reddit` — capture a Reddit thread into the library as an inbox source with a critical wheat-vs-chaff filter on comments.

### Features

- feat(extract-reddit): new skill takes a Reddit thread URL and an optional stack name. Fetches post + comments via the public `.json` endpoint with a browser User-Agent (bare curl is blocked by Reddit's edge), follows the linked article via WebFetch when present, and writes a single inbox markdown file. With a stack arg the file lands in `{stack}/sources/incoming/`; without one it lands in library-root `inbox/` for `/stacks:process-inbox` to route. The wheat-vs-chaff cut is documented in the skill body — first-hand cost data, technical claims with model numbers, policy specifics, and dated rebate facts are kept; partisan venting, generic doom, defiance without install detail, and one-line snark are dropped, with the cut categories logged in an auditable ledger inside each output file.
- feat(scripts): `scripts/extract-reddit-thread.py` — Python stdlib (urllib, no deps) fetcher that normalizes any Reddit URL form (old.reddit, www.reddit, redd.it short-link), walks the comment tree, drops `[deleted]`/`[removed]` while still recursing past them for substantive children, sorts by score, and caps to top-N at depth-D. Defaults: top 100, depth 6. Surfaces 403 (blocked, suggest PRAW upgrade) and 429 (rate-limited) with actionable error messages.

## 0.15.4 — 2026-04-30

Readability refactor: inline code extracted to scripts/, deprecated orchestrators stubbed.

### Refactors

- refactor(catalog-sources): W1b Python dedup block (~97 lines) extracted to `scripts/dedup-extractions.py`. Skill step replaced with `python3 "$SCRIPTS_DIR/dedup-extractions.py" "$STACK/dev/extractions" "$DEDUP"`. Side-output contract (_dedup-meta.txt sourced by caller) unchanged.
- refactor(catalog-sources): W4 MoC generator bash block (~43 lines) extracted to `scripts/regenerate-moc.sh`. Skill step replaced with `"$SCRIPTS_DIR/regenerate-moc.sh" "$STACK"`.
- refactor(audit-stack): A3 Python merge block (~76 lines) extracted to `scripts/merge-findings.py`. Skill step replaced with `python3 "$SCRIPTS_DIR/merge-findings.py" "$STACK" "$AUDIT_DATE" "$STACK_HEAD" "$NEW_PASS_COUNTER"`. Interface adapted from env-var reads to sys.argv; logic verbatim.
- refactor(agents): concept-identifier-orchestrator, findings-analyst-orchestrator, synthesizer-orchestrator, validator-orchestrator reduced from ~856 total lines to 6-line stubs each. Description frontmatter preserved (deprecation date, root cause, replacement skill). Body: ORCHESTRATOR_DEPRECATED redirect for any external caller.

## 0.15.3 — 2026-04-30

Full-plugin parallel-reviewer audit (library-stack S15). 6 findings: 1 high, 2 medium, 3 low. All applied.

### Fixes

- fix(catalog-sources): W1b extraction hash now piped to `compute-extraction-hash.sh` via stdin instead of positional args. The prior invocation (`compute-extraction-hash.sh "$slug" $paths`) passed args the script ignores — it reads only stdin. Every slug was hashed as empty input, producing the constant SHA256 digest `e3b0c44...` for all articles. The W0b skip list then matched every slug on subsequent runs, silently blocking all re-processing. Correct format: `printf '%s' "$(echo "$paths" | tr '\n' '|')${slug}" | compute-extraction-hash.sh` (paths sorted, pipe-joined, slug appended, no trailing newline). HIGH.
- fix(rotate-findings): section headers (`## New Acquisitions`, `## Articles to Re-Synthesize`, etc.) inside findings.md were absorbed into the preceding item buffer when `in_item=1`. If the first item of a section was rotated out, its buffer — including the section header — went to `findings-archive.md`, leaving the surviving items in that section without a header in the rewritten `findings.md`. Fix: added awk rule `in_item && /^## / { printf "%s\n", $0 >> tmp_findings; next }` immediately before the catch-all to route section headers directly to the output file. MEDIUM.
- fix(wikilink-pass): skip-check now uses `grep -qiF "[[$term]]"` (fixed-string) instead of `grep -qi "\[\[$term\]\]"` (regex). Glossary terms containing regex metacharacters (`.`, `*`, `+`) were interpreted as patterns; `.` in `C.O.P` would match `[[CCOP]]`, producing false-positive skips where the wikilink was never written. The perl replacement on the following line already used `\Q$t\E` (quotemeta) — the grep check now matches. LOW.

### Refactors

- refactor(skills): all 6 skills now use `locate-plugin-root.sh` in Step 0 telemetry. The prior ask, process-inbox, new-stack, and init-library skills used a direct cache-first telemetry find (inverted preference order vs. `locate-plugin-root.sh`, which prefers installLocation). On directory-source dev installs the 4 old-pattern skills loaded telemetry from a cached older version. The 4-line block was also copy-pasted verbatim 4 times. MEDIUM.
- refactor(new-stack, init-library): Steps 3 now use `$STACKS_ROOT` set in Step 0 (via locate-plugin-root.sh) to derive template dir and init.sh path, replacing their own inline cache-first finds. LOW.

### Docs

- docs(findings-analyst-orchestrator): DEPRECATED description updated from "awk merge" to "Python merge" — the A3 merge was converted to Python in 0.15.1, but the orchestrator's stale description still said awk. LOW.

## 0.15.2 — 2026-04-30

Batch of 14 findings surfaced by parallel-reviewer audit of the 0.13.0 → 0.15.1 release window (library-stack S14). Six high-severity issues were latent or silent (none would have raised an obvious error, but several would have produced subtly wrong output on the next user-driven run). Seven medium-severity issues are doc/contract drift and edge-case gaps.

Audit context: the 0.14.0 deprecation of the four orchestrator agents was correct architecturally (silent fallback to inline execution under nested Task is unrecoverable), but the docs and several call sites still described the deprecated pattern as live. This release closes that gap.

### Fixes

- fix(audit-stack): A1 per-batch citation graph now matches indented frontmatter `sources:` entries. The prior awk required column-0 `- ` dashes, but `article-synthesizer` writes the list with two-space indent (`  - path`). Every frontmatter source entry was silently skipped, falling through to inline-`[slug]` body grep + full-tree fallback for any article that lacked inline citations. The svelte audit converged via the fallback rather than the citation graph; this fix restores intended behavior.
- fix(catalog-sources): W1b per-slug awk split now emits an `END` flush block. The prior implementation flushed `block` only on the next `## Concept:` header, so the alphabetically-last slug was buffered into memory and never written. Single-concept catalog runs produced an empty `_dedup-{slug}.md` and then a malformed article. Latent until a user catalogs a 1-concept source set on 0.14.0+.
- fix(catalog-sources): W2 wave loop now injects `extraction_hash` into each per-slug dedup file BEFORE dispatching `article-synthesizer` for that wave. The prior layout placed the injection block after the wave loop closed, where `WAVE_SLICE` was out of scope. Article-synthesizer agents read the per-slug file at dispatch time, so a missing hash field at dispatch yielded an article with empty `extraction_hash` frontmatter, breaking the W0b skip-list flywheel for the next catalog run. Latent because no fresh catalog had been run on 0.14.0+ before this release.
- fix(audit-stack): rotate-findings.sh archive write now passes `$DISPATCH_EPOCH - 1` to `assert-written.sh`. The gate uses `mtime <= dispatch_epoch` (strict less-than-or-equal); the rotate script is synchronous and finishes within the same clock second on SSDs, tripping the gate as `AGENT_WRITE_FAILURE` even when the rotation was correct. Latent until a stack accumulates `ROTATION_CYCLES` worth of terminal items.
- fix(catalog-sources): W0b skip-list awk now uses `^- id:` boundary triggers instead of blank-line termination. The prior implementation relied on a trailing blank line as the item delimiter; items that abut without a separator (or where the last item lacks a trailing blank) had `status` from one item bleed into the next, causing false-positive skip-list inclusion. Switched to a `flush()` function called at each new `- id:` and at `END`.
- fix(rotate-findings.sh): trap-registered temp file vars (`KEEP_FILE`, `ROTATE_FILE`, `TMP_FINDINGS`, `COUNT_FILE`) are now initialized to empty string before the EXIT trap is registered. Previously, any failure between trap registration and the mktemp calls would have aborted inside the trap on `set -u` unbound-variable, masking the original error.
- fix(audit-stack): A3 python merge now buckets by `status` first, then by `action`. Items with `status: deferred` route to the Deferred section regardless of action (matching the `findings-analyst` schema definition: "Deferred = operator moved to status: deferred"). Previously, a `fetch_source` item the operator marked `status: deferred` was rendered under "New Acquisitions"; data integrity was preserved (the `raw` block still carried `status: deferred`) but section placement was wrong.

### Refactors

- refactor(scripts): new `scripts/locate-plugin-root.sh` echoes `STACKS_ROOT` using the authoritative lookup order (`installLocation` first, cache scan fallback). Both SKILL Step-0 telemetry blocks and Step-2/3 plugin-root resolution now call it instead of duplicating the lookup logic in four places (with inverted preference order between Step 0 and Step 2/3 in the prior layout).
- refactor(audit-stack): `_a3-summary.json` no longer emits hard-coded `carried_items: 0` and `rotated_items: 0`. The fields were never populated correctly; the comment in the code admitted "out of scope here." Removed from the schema. No external consumer reads these fields; the rotation count is already echoed by `rotate-findings.sh` to stdout for the operator.
- refactor(catalog-sources): the empty-source short-circuit in W1 now writes a zero-count summary file and exits cleanly, instead of falling through vacuous loops with a misleading "Jump to summary write" comment that referenced behavior the code did not implement.

### Docs

- docs(references/wave-engine.md): rewritten to describe parent-side parallel sharding for A1, A2, A3, and W1+W1b+W2. The prior text named the four deprecated orchestrator agents as the canonical dispatch agents and described their internal logic as the live contract. Both SKILLs read this reference at startup; the drift would have produced incorrect dispatch on any agent that took the reference at face value. A4 description corrected to match SKILL implementation (gates on `generative_open == 0` only; `open_count` is for reporting). Summary-JSON contract section rewritten to describe parent-driven summary writes.
- docs(agents/synthesizer.md): contract now documents the three dispatch modes (shard, merge, single) the audit-stack SKILL uses. The agent's `description:` field claimed stack-root-only output; in shard mode the agent writes `dev/audit/_a2-partial-NN.md` with no equivalent in the contract. Description updated; new `## Modes` section added.
- docs(skills/{audit-stack,catalog-sources}/SKILL.md): em dashes in prose replaced with commas/colons per workspace style rule.

## 0.15.1 — 2026-04-30

One fix surfaced during the first end-to-end audit on 0.15.0 (library-stack S13, svelte: 79 articles, 2 passes, converged via operator-applied resynthesis on a single DRIFT). Closes #43.

- fix(audit-stack): A3 deterministic merge in `skills/audit-stack/SKILL.md` Step 7 now runs as inline python rather than awk. The prior awk used gawk's 3-arg `match($i, /pat/, m)` form which silently fails on mawk (the default `awk` on Debian/Ubuntu/Mint), producing zero-merged findings while `assert-written.sh` still passes the gate (mtime advanced even though the file is empty). Detection was indirect: `pass_counter` set, frontmatter present, but item count == 0. The S13 svelte audit hit this and worked around it with parent-side python; that workaround is now the SKILL contract. Parent script no longer requires gawk; mawk-only systems are first-class. Section grouping (`## New Acquisitions` / `## Articles to Re-Synthesize` / `## Research Questions` / `## Deferred`) is also clearer in code than in nested awk, so the merge now produces the canonical 4-section structure directly instead of dumping all blocks under no header.

## 0.15.0 — 2026-04-30

Two fixes surfaced during the first end-to-end audit on 0.14.1 (library-stack S12, pca-stack: 20 articles, 2 passes, converged with 90 fetch_source items).

- fix(audit-stack agents): `validator`, `synthesizer`, and `findings-analyst` agent frontmatter now declares `Bash` in the tools list. Their SKILL prompts and agent contracts ask each of them to run `scripts/assert-written.sh` after writing their outputs (the per-agent gate the parent then re-checks), and `findings-analyst` is also expected to compute `sha256` for item ids. Without `Bash` they could do neither — every audit run on 0.14.1 surfaced agents reasoning "I cannot execute bash" and either skipping the gate or emitting pseudo-ids that the parent had to recompute. Adding `Bash` lets each agent honor its contract; the parent gates and parent-side `python3` recompute become belt-and-suspenders rather than the only enforcement.
- feat(audit-stack): A4 convergence now short-circuits when `pass_counter == 1` AND the pass is empty. The "2 consecutive empty passes" rule exists to confirm that a prior pass's `resynthesize` actions actually closed open items; on a first pass with zero `audit-stack`-resolvable items, there were never any such actions to verify, so pass 2 would be a deterministic no-op. Stacks whose articles have only `fetch_source` work (most fresh catalog runs) now converge in one pass instead of two. Existing "2 consecutive empty" rule still applies for any subsequent-pass empty case.

## 0.14.1 — 2026-04-29

Two regressions in the 0.14.0 audit-stack refactor surfaced on first execution against pca-stack (library-stack S11). Both were lost behavior the deprecated orchestrator agents had handled.

- fix(audit-stack): batch-builder awk no longer references `$0`. The skill harness performs shell-positional `$N` substitution on the rendered SKILL.md, which turned the awk literal `$0` into the skill's first argument (e.g. `pca-stack`). The arithmetic `pca - stack` evaluated to 0 inside awk, writing `0\n` to every batch file. Replaced `printf "%s\n", $0` with bare `print` (which defaults to `$0` + ORS, no `$N` literal). Affects A1, A2, A3 batch sharding.
- fix(audit-stack): A1 now builds a parent-side per-batch citation graph and passes the per-batch source union to each validator agent, restoring the 0.13.0 #34 behavior dropped in the 0.14.0 orchestrator removal. Without this, the SKILL left "the sources tree path" undefined and each invocation had to invent it (full tree → prompt-bloat regression at scale, or stale paths → mass UNSOURCED). Slug→path map now indexes by basename so catalog-sources W3 file moves do not break audit-time citation resolution. Full-tree fallback retained for batches with zero resolvable citations.

## 0.14.0 — 2026-04-29

Pivots audit-stack and catalog-sources from nested-orchestrator dispatch to parent-side parallel sharding. Closes #41 and #42 (filed and resolved same session, library-stack S10).

Root cause: orchestrator agents (`validator-orchestrator`, `synthesizer-orchestrator`, `findings-analyst-orchestrator`, `concept-identifier-orchestrator`) declared `tools: Task` in frontmatter, but nested Task dispatch was unreliable in practice. When Task wasn't available to the nested subagent, the orchestrators silently fell back to inline execution, bundling every shard's work into one context. On 79-article stacks (svelte audit) and 45-source catalogs (swe), they hit "Prompt is too long" — the exact failure mode their sharding was designed to prevent. Even when nested Task did work, the original batch sizes (15 articles per validator, 30 per synthesizer, 1-or-10 sources per concept-identifier) were too coarse for clean per-agent attention.

- feat(audit-stack): A1, A2, A3 now do parent-side parallel dispatch directly. Validator and findings-analyst at 3 articles per agent (was 15); synthesizer at 10 per shard (was 30) with parent-driven merge pass; A3 merge replaced with deterministic awk in the parent (terminal-wins by id, no agent judgment). `validator-orchestrator`, `synthesizer-orchestrator`, `findings-analyst-orchestrator` marked deprecated for audit-stack.
- feat(catalog-sources): W1, W1b, W2 refactored to parent-side dispatch. W1 at 1 source per concept-identifier agent (was 1-or-10 batch math). W1b runs deterministic Python merge in the parent (slug-keyed `source_paths[]` union with first-seen-order preservation, per-slug awk split, `extraction_hash` via existing script). W2 keeps 1 slug per article-synthesizer with `W2_WAVE_CAP=25` per dispatch wave; parent owns gating and hash injection. `concept-identifier-orchestrator` marked deprecated.
- fix(audit-stack): A4 empty-pass check now keys solely on `generative_open == 0`. Previously required `open_count == 0 AND generative_open == 0`, which contradicted the skill's own comment that fetch_source/research_question items "do not block convergence." Stacks with only out-of-scope open items (sysops at pass 2: 41 items, all fetch_source/research_question) now converge cleanly instead of running to budget cap.
- docs(orchestrator agents): all four orchestrator agents carry deprecation notices in their frontmatter description pointing at the new parent-side patterns. Kept registered for any external caller still wired to them; not removed.

### Architecture note

The orchestrator pattern (parent skill → orchestrator subagent → fan-out worker subagents) is now considered an antipattern wherever the harness can drop Task on nested calls. Two-level fan-out should be designed as parent skill → worker subagents, with cross-cutting steps (dedup, merge, gate) as deterministic scripts in the parent process. Future pipelines should not introduce middle-tier orchestrator agents.

## 0.13.0 — 2026-04-19

Audit follow-ups epic (#38). Closes sub-issues #32, #33, #34, #35, #36, #37. Ships the unified orchestrator summary-JSON contract (schema_version=1 envelope), two new orchestrator wrappers for A2 and A3 (unblocking mep-stack scale), per-batch source sharding for A1, per-slug progressive disclosure + wave cap for W2, and a findings rotation policy that keeps `findings.md` bounded across audit cycles.

- feat(orchestrators, audit-stack, catalog-sources): unified orchestrator summary-JSON contract. Both `validator-orchestrator` and `concept-identifier-orchestrator` write a `schema_version=1` envelope (`{schema_version, wave, status, counts, epochs}`) to `dev/audit/_a1-summary.json` and `dev/extractions/_w1-w2-summary.json`. Orchestrators return only an `ORCHESTRATOR_OK: wave=X` receipt line on stdout; structural data lives in the file. Failure markers unified to `ORCHESTRATOR_FAILED: wave={wave} reason={short}`. Main-session gates in audit-stack Step 4 and catalog-sources Step 6 / Step 10 use nested `.counts.FIELD` jq paths. Closes #33.
- feat(validator-orchestrator): per-batch source union via pre-dispatch citation graph. `SOURCE_MAP` (slug to path) built from `sources/` and per-article `ARTICLE_SOURCES` from frontmatter `sources:` plus inline `[source-slug]` refs. Each validator receives only the union of its batch's cited sources. Full-tree fallback when a batch has zero resolvable citations. `validator.md` Input contract updated. Closes #34.
- feat(concept-identifier-orchestrator, article-synthesizer): W1b writes per-slug `_dedup-{slug}.md` files; W2 dispatch passes the per-slug path; `article-synthesizer` reads only its own slug's block. `_dedup.md` preserved as aggregated audit-trail artifact. Progressive disclosure cuts per-agent tokens at large W2 fan-outs. Closes #36.
- feat(concept-identifier-orchestrator): W2 dispatch capped at `W2_WAVE_CAP=25` parallel agents per wave with loop. Each wave captures its own `DISPATCH_EPOCH_W2_WAVE` for per-wave `assert-written.sh` gating. `counts.n_w2_waves` populated in the summary JSON. Prevents Task-tool parallel-dispatch saturation on large fresh catalog runs. Closes #35.
- feat(audit-stack): new `agents/synthesizer-orchestrator.md` (A2) and `agents/findings-analyst-orchestrator.md` (A3) wrap the previously single-dispatch synthesizer and findings-analyst. Both use the schema-v1 envelope and a single-shard fast path (A2 cap `ARTICLES_PER_AGENT=30` since synthesizer reads articles only; A3 cap 15 matching A1). Above the cap, shard agents write `dev/audit/_a{2,3}-partial-{batch_id}.md`; A2 re-dispatches `synthesizer` with a merge task, A3 bash-merges by item id with terminal-wins precedence. `skills/audit-stack/SKILL.md` Steps 5 and 7 rewritten. Unblocks mep-stack (~250 articles). Closes #32.
- feat(findings-analyst, audit-stack): rotation policy for terminal-status items. Schema v3 to v4 adds `terminal_transitioned_on: YYYY-MM-DD` set when items first enter a terminal status; carry-forward migration block backfills the field to current `audit_date` on first encounter (no hand-editing). New `scripts/rotate-findings.sh` runs at `audit-stack` Step 8.5 (between A4 convergence and A5 archive, only when converged). Terminal items older than `ROTATION_CYCLES` audit cycles (default 3, grepped from `STACK.md`) move to `dev/audit/findings-archive.md`. Archive write gated by `assert-written.sh` when rotation count > 0. Closes #37.
- docs(references): `references/wave-engine.md` synced to reflect all six changes (summary-JSON contract subsection, A1 source-sharding, new A2/A3 orchestrator dispatch patterns, per-slug W1b + W2 wave cap, new A4.5 rotation step).

### Alpha cuts consolidated into 0.13.0

The five alpha entries below shipped progressively during epic #38 and roll up into the `## 0.13.0 — 2026-04-19` release header above. Per-alpha bullets preserved below for historical commit-to-change traceability.

## 0.13.0-alpha.5 — 2026-04-19

- feat(findings-analyst, audit-stack): rotation policy for terminal-status items (T5, closes #37).

## 0.13.0-alpha.4 — 2026-04-19

- feat(audit-stack): synthesizer-orchestrator + findings-analyst-orchestrator A2/A3 wrappers (T4, closes #32).

## 0.13.0-alpha.3 — 2026-04-19

- feat(concept-identifier-orchestrator, article-synthesizer): per-slug `_dedup-{slug}.md` split (T3, closes #36).
- feat(concept-identifier-orchestrator): W2 wave cap with loop (T3, closes #35).

## 0.13.0-alpha.2 — 2026-04-19

- feat(validator-orchestrator): per-batch source union citation graph (T2, closes #34).

## 0.13.0-alpha.1 — 2026-04-19

- feat(orchestrators, audit-stack, catalog-sources): unified orchestrator summary-JSON contract schema_version=1 (T1, closes #33).

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

## 0.26.3 — 2026-06-18

**lookup: primary sources now listed at the bottom of every answer.**
- Step 7 reads the `sources:` frontmatter from each cited article, extracts Author/Title/Date/URL from the source file header, and renders a "Primary sources:" block under the answer.
- Practitioner/internal sources (Tier 3, liminal, field-notes) are excluded — only citable publications surface.

## 0.27.1 — 2026-06-18

**lookup: tighten primary-source exclusion to path-based only.**
- Previously excluded all Tier 3 sources, which blocked public practitioner references (Fowler bliki, Wooledge wiki, ZenML research) from appearing in citations.
- Now excludes only paths containing `liminal`, `field-notes`, or `internal` — private session notes only. Public sources surface regardless of tier as long as a URL exists.
