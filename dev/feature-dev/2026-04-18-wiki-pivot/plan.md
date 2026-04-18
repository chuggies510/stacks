# Plan: Wiki Pivot

**Issue**: chuggies510/stacks#17 (epic with 4 sub-issues: #19, #20, #21, #22)
**Spec**: `dev/feature-dev/2026-04-18-wiki-pivot/spec.md`
**Baseline**: `stacks=0.8.3` (plugin.json at Step 13; marketplace.json=0.8.0 pre-mismatch is resolved as a side effect of progressive bumps)

## Task DAG

```
Wave 1 (parallel, 9 tasks): T1, T2, T3, T4, T5, T8, T10, T11, T12
Wave 2 (parallel, 2 tasks): T6 (needs T1-T5), T13 (needs T1, T2, T5, T10-T12)
Wave 3:                     T7  (ships #19 as 0.9.0-alpha.1; needs T6)
Wave 4:                     T9  (ships #20 as 0.9.0-alpha.2; needs T7, T8)
Wave 5:                     T14 (ships #21 as 0.9.0-alpha.3; needs T9, T13)
Wave 6:                     T15 (ships #22 as 0.9.0 cutover; needs T14)
```

Edges:
- T1-T5 are independent foundational files (scripts, agents, wave-engine).
- T6 needs all of T1-T5 present.
- T7 ships #19 after T6.
- T8 is independent: pure text edit to `skills/ask/SKILL.md`, article-mode branch checks `articles/` directory at runtime so no plan-time coupling to T6.
- T9 ships #20 after T7 (version sequence) and T8 (file landed).
- T10-T12 are agent prompt edits; no code-level deps; run in Wave 1 alongside T1-T5 and T8.
- T13 needs T1, T2, T5 (shared helpers + wave-engine) and T10-T12 (agents reshaped).
- T14 ships #21 after T9 (version sequence) and T13 (file landed).
- T15 ships #22 after T14; atomic cutover commit.

Maximum parallel fan-out: 9 agents concurrently runnable at start (T1-T5, T8, T10-T12). Wave 2 fans out T6 and T13 in parallel (disjoint file ownership: `skills/catalog-sources/` vs `skills/audit-stack/`). Version bumps serialize via their blockedBy chain.

## Tasks

### Task 1 — scripts/assert-written.sh (shared helper)

Create the write-or-fail gate. Invoked after every agent dispatch in both catalog-sources and audit-stack skills.

Signature: `bash scripts/assert-written.sh {path} {dispatch_epoch} {agent_label}`. Exits 0 if the file at {path} is non-empty AND `stat -c %Y` mtime > {dispatch_epoch}. Exits 1 with a fixed error string otherwise. Linux-only (`stat -c %Y`).

No deps. Sub-issue: #19.

### Task 2 — scripts/wikilink-pass.sh (shared helper)

Create the deterministic wikilink pass. Invoked at W2b (catalog) and A2b (audit).

Signature: `bash scripts/wikilink-pass.sh {articles-dir} {glossary-path}`. Reads `**bold**` terms from glossary.md (via `grep -oP '(?<=\*\*)[^*]+(?=\*\*)'`), scans each article for case-insensitive verbatim match, wraps first occurrence per term per article in `[[...]]`, preserves original capitalization, skips self-links (article slug == term slug), skips already-wrapped terms. No-op if glossary.md absent.

No deps. Sub-issue: #19.

### Task 3 — agents/concept-identifier.md (new agent)

Identifies discrete concepts per source AND extracts relevant claims per concept (single pass; absorbs article-extractor role).

Contract: input = source file paths + STACK.md + skip list of `extraction_hash` values + existing articles/ listing. Output = `dev/extractions/{source-slug}-concepts.md` with concept blocks (`slug`, `title`, `source_paths`, `hash_inputs`, `target_article`). Enforces slug immutability: if a concept matches an existing article (claim overlap), use that article's slug as both `slug` and `target_article`. New slugs only for genuinely new concepts. Include 3+ worked examples in the agent prompt.

No deps. Sub-issue: #19.

### Task 4 — agents/article-synthesizer.md (new agent)

Writes one `articles/{slug}.md` per unique concept.

Contract: input = one concept block + existing article (if `target_article` set) + STACK.md. Output = `articles/{slug}.md` with full frontmatter (`extraction_hash`, `last_verified=""`, `updated=today`, `sources[]`, `title`, `tags[]`), 300-800 word body, inline `[source-slug]` citations, no wikilinks. Strip-on-rewrite: when existing article is input, strip all `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` markers from its body before producing the updated article. Include 3+ worked examples.

No deps. Sub-issue: #19.

### Task 5 — references/wave-engine.md (rewrite)

Rewrite to document both catalog-sources waves (W0, W0b, W1, W1b, W2, W2b, W3, W4) and audit-stack waves (A1, A2, A2b, A3, A4, A5). Each wave gets a row in its respective table with agent/module, input, output, write-or-fail gate. Old W0-W6 content preserved as `references/wave-engine-legacy.md` (implementer's choice; or removed outright since #22 retires the old skills).

No deps. Sub-issue: #19 (extended at T13, but written fully at T5 so T13 doesn't need to edit the doc).

### Task 6 — skills/catalog-sources/SKILL.md

Full skill file. Step 0 Telemetry (boilerplate from existing skills). Steps for W0 through W4 per spec's wave table. Dispatches concept-identifier (T3) and article-synthesizer (T4), invokes assert-written.sh (T1) after each dispatch, invokes wikilink-pass.sh (T2) at W2b. W1b slug-collision dedup is inline bash (group concept blocks by slug, merge source_paths). W3 source filing is inline bash (mv from incoming/ to publisher dir). W4 MoC generator preserves any `## Reading Paths` section in existing index.md verbatim while rewriting everything else.

Blocked by: T1, T2, T3, T4, T5. Sub-issue: #19.

### Task 7 — version 0.9.0-alpha.1 + CHANGELOG (ships #19)

Bump `.claude-plugin/plugin.json` to `0.9.0-alpha.1`. Bump `.claude-plugin/marketplace.json` plugins[0].version to match. Prepend CHANGELOG entry describing the catalog-sources pipeline shipping alongside ingest-sources.

Blocked by: T6. Sub-issue: #19 (closes).

### Task 8 — skills/ask/SKILL.md (article-mode branch)

Edit existing skill. Add Step 4: read `{stack}/index.md` and extract any `## Reading Paths` section as additional retrieval aid. Modify Step 5: branch on `articles/` directory presence (`find {stack}/articles -maxdepth 1 -name '*.md' | head -1 | grep -q .`). If articles present, read matching articles; if absent, fall back to existing `topics/*/guide.md` logic.

The three user-message strings that reference `/stacks:ingest-sources` in this file are left correct-for-now (the old skill is still runnable through alpha.3). T15 sweeps them to `/stacks:catalog-sources` as part of the cutover.

No deps: pure text edit; article-mode branch runtime-checks `articles/` directory. Sub-issue: #20.

### Task 9 — version 0.9.0-alpha.2 + CHANGELOG (ships #20)

Bump plugin.json + marketplace.json to `0.9.0-alpha.2`. CHANGELOG entry for article-mode retrieval.

Blocked by: T7 (version sequence), T8 (file shipped). Sub-issue: #20 (closes).

### Task 10 — agents/validator.md (prompt update)

Edit prompt only; keep filename. Update to mark articles inline with `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` (replaces previous refine-stack behavior of emitting a report). Add strip-prior-cycle-marks pre-step: before validating an article, strip any existing inline markers (they're stale from the previous audit). Write inline marks AS the sole output — no separate scratch file. Set `last_verified` frontmatter to today for each article touched. Include 3+ worked examples covering all four mark types. Rewrite must also remove any lingering references to the old pipeline (`topic-clusterer`, `topic-extractor`, `topic-synthesizer`, `cross-referencer`, `refine-stack`, `ingest-sources`, `validation-report.md`) from the existing prompt body — T15 sweeps the repo-wide, but catching here prevents a late fail.

No deps. Sub-issue: #21.

### Task 11 — agents/synthesizer.md (prompt update)

Edit prompt only; keep filename. Three outputs at stack root: `glossary.md` (alphabetical bolded terms extracted from article bodies), `invariants.md` (rules appearing in 2+ articles independently), `contradictions.md` (claims where articles conflict with per-article citation). Include 3+ worked examples. Rewrite must also remove any lingering references to the old pipeline (`topic-clusterer`, `topic-extractor`, `topic-synthesizer`, `cross-referencer`, `refine-stack`, `ingest-sources`) from the existing prompt body.

No deps. Sub-issue: #21.

### Task 12 — agents/findings-analyst.md (prompt update)

Edit prompt only; keep filename. Write `dev/audit/findings.md` per locked schema: frontmatter (`audit_date`, `stack_head`, `pass_counter`, `schema_version`), items with ID = `sha256({article-slug}|{finding_type}|{normalized-claim})`, status enum includes `failed` (terminal), three sections (New acquisitions / Articles to re-synthesize / Deferred). Read inline marks directly from articles (no scratch file); read prior findings.md and carry forward item status by ID match. Include 3+ worked examples. Rewrite must also remove any lingering references to the old pipeline (`topic-clusterer`, `topic-extractor`, `topic-synthesizer`, `cross-referencer`, `refine-stack`, `ingest-sources`) from the existing prompt body.

No deps. Sub-issue: #21.

### Task 13 — skills/audit-stack/SKILL.md

Full skill file. Step 0 Telemetry. Waves A1-A5 per spec. Dispatches validator (T10), synthesizer (T11), findings-analyst (T12); invokes assert-written.sh (T1) after each; invokes wikilink-pass.sh (T2) at A2b; inline bash for A4 convergence check (2 consecutive empty passes OR `MAX_AUDIT_PASSES` from STACK.md, default 3) and A5 archive to `dev/audit/closed/{date}-findings.md`.

Blocked by: T1, T2, T5, T10, T11, T12. Sub-issue: #21.

### Task 14 — version 0.9.0-alpha.3 + CHANGELOG (ships #21)

Bump plugin.json + marketplace.json to `0.9.0-alpha.3`. CHANGELOG entry for audit-stack + loop closure.

Blocked by: T9 (version sequence), T13 (file shipped). Sub-issue: #21 (closes).

### Task 15 — rename cutover + repo-wide sweep + 0.9.0 (ships #22)

Atomic breaking commit. Three groups of work:

**Group A — remove old pipeline artifacts:**
- `git rm -r skills/ingest-sources skills/refine-stack`
- `git rm agents/topic-clusterer.md agents/topic-extractor.md agents/topic-synthesizer.md agents/cross-referencer.md`
- `git rm -r templates/stack/dev/curate` (entire subtree including `extractions/.gitkeep`)

**Group B — scaffold replacement template dirs:**
- `mkdir -p templates/stack/dev/audit templates/stack/dev/extractions`
- `touch templates/stack/dev/audit/.gitkeep templates/stack/dev/extractions/.gitkeep`

**Group C — sweep references across repo** (replace old names with new per context; keep historical mentions in `CHANGELOG.md` only):
- `CLAUDE.md` (repo root) — 3 hits
- `README.md` (repo root) — 12 hits
- `skills/ask/SKILL.md` — 3 user-message strings `/stacks:ingest-sources` → `/stacks:catalog-sources`
- `skills/new-stack/SKILL.md` — 2 hits
- `skills/process-inbox/SKILL.md` — 2 hits
- `references/refresh-procedure.md` — 5 hits (pipeline description now describes `catalog-sources` + `audit-stack`)
- `templates/library/CLAUDE.md` — 6 hits
- `templates/library/README.md` — 2 hits

**Group D — version bump + CHANGELOG:**
- Bump `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` to `0.9.0` (final; resolves pre-existing 0.8.3/0.8.0 mismatch as a side effect)
- Prepend CHANGELOG entry documenting the breaking cutover (old skill/agent names removed, no migration path for existing guides, `0.9.0-alpha.3 → 0.9.0`)

**Verify:**
```
grep -rI 'ingest-sources\|refine-stack\|topic-clusterer\|cross-referencer\|topic-extractor\|topic-synthesizer\|dev/curate' . \
  --exclude-dir=.git --exclude-dir=dev --exclude-dir=.claude \
  --exclude=CHANGELOG.md --exclude=wave-engine-legacy.md
```
Returns zero matches. Excludes are: `.git` (internal), `dev/` (feature-dev artifacts + briefs are historical design record), `.claude/` (memory-bank is session handoff record), `CHANGELOG.md` (historical release notes), `wave-engine-legacy.md` (explicit legacy doc if implementer chose to preserve it in T5).

Blocked by: T14. Sub-issue: #22 (closes).
