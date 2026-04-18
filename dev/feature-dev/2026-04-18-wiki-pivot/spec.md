# Wiki Pivot — spec

Epic: chuggies510/stacks#17
Sub-issues: #19 (catalog-sources pipeline), #20 (retrieval + MoC), #21 (audit-stack + loop closure), #22 (rename cutover + version bump)

## What we're building

Replace the guide-per-topic output shape with an article-per-concept wiki shape, and close the loop between `audit-stack` (new) and `catalog-sources` (new) so findings flow back into the next synthesis pass rather than accumulating as a stale report.

## Exploration findings

Current plugin state:
- `skills/ingest-sources/` produces one `topics/{topic}/guide.md` per topic via waves W0 enumerate → W0b cluster → W1 extract → W2 synthesize.
- `skills/refine-stack/` produces a findings report and a cross-reference report via W3 cross-ref → W4 validate → W5 glossary/invariants → W6 findings.
- 7 agents: `topic-clusterer`, `topic-extractor`, `topic-synthesizer`, `cross-referencer`, `validator`, `synthesizer`, `findings-analyst`.
- 6 skills: `ask`, `init-library`, `new-stack`, `process-inbox`, `ingest-sources`, `refine-stack`.
- Version mismatch: `plugin.json` = 0.8.3 vs `marketplace.json` = 0.8.0. Resolved progressively (each sub-issue bumps pre-release; #22 finalizes to 0.9.0).

Pain observed in library-stack usage:
- Cross-reference audits repeatedly find 10+ "links that should exist" between concepts in different guides. Wiki shape makes these structural links at catalog time.
- Updating a concept that appears in 2+ guides required editing both; one canonical article eliminates that.
- Topic clustering judgment was papered over — topic boundaries blurry (e.g., git-github-workflow vs release-management vs engineering-practices all claim the same mechanics).
- Audit findings queue doesn't close: S5-S7 accumulated 12+ unapplied cross-links with nothing consuming findings.md back into the guides.

## Research findings

Read (architects, during Step 9):
- `swe/topics/knowledge-system-design/guide.md`
- `swe/topics/multi-agent-pipeline-design/guide.md`
- `swe/topics/skill-prompt-engineering/guide.md`
- `swe/sources/standards/fowler-knowledge-priming.md`
- `swe/sources/standards/fowler-feedback-flywheel.md`
- `swe/sources/standards/fowler-harness-engineering.md`
- https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

Influence on the design (embedded, not cited inline in the pipeline code):
- **Feedback flywheel**: `findings.md` → `catalog-sources` consumes → re-synthesize flagged → new `findings.md`. Items carry status; the loop archives annotated findings rather than discarding.
- **Harness engineering**: every agent dispatch has a `test -s` + timestamp gate; empty or stale pre-existing files halt the pipeline with a named error rather than silently continuing. Single shared `scripts/assert-written.sh` helper.
- **Knowledge priming**: locked `findings.md` schema (frontmatter + item shape) means agents receive a templated contract, not a narrative ask.
- **Karpathy gist**: article-per-concept unit, flat directory, LLM-readable + human-browsable in Obsidian. Article size 300-800 words fits direct-load retrieval (no vector/MCP needed for libraries of tens of articles).

## Architecture decision

**Pragmatic-fastest proposal + 4 tweaks + S1 review dispositions.** User selected at Step 10; revised at Step 12 review gate.

Per-sub-issue ceremony slicing:
- **#19** (catalog-sources pipeline + source filing) — architect ceremony fired, 3 parallel framings
- **#20** (retrieval + MoC + wikilink parser) — covered in unified proposal; no independent ceremony
- **#21** (audit-stack + findings + deterministic linker + loop closure) — covered in unified proposal
- **#22** (rename cutover + version bump) — **mechanical, no architecture**; skips to plan rows directly

### Skill structure (applies to both new skills)

Both `catalog-sources` and `audit-stack` SKILL.md files open with Step 0 Telemetry per existing pattern (see `skills/ingest-sources/SKILL.md:Step 0`). Step 0 resolves `telemetry.sh` via `find ~/.claude/plugins/cache ... | sort -V | tail -1` with `known_marketplaces.json` fallback, then fires `SKILL_NAME="stacks:{name}" bash "$TELEMETRY_SH"`. Subsequent steps follow the wave tables below.

### Pipeline structure

**`catalog-sources`** (replaces `ingest-sources`):

| Wave | Agent / Module | Input | Output |
|------|----------------|-------|--------|
| W0 | bash enumerate | `sources/incoming/*`, `index.md` | `NEW_SOURCES` list |
| W0b | bash prior-findings gate | `findings.md` | skip list of already-synthesized `extraction_hash` values |
| W1 | `concept-identifier` (parallel per source batch) | source files, `STACK.md`, skip list | `dev/extractions/{source-slug}-concepts.md` |
| W1b | bash slug-collision dedup | all W1 outputs | unified concept list with `source_paths[]` merged for shared slugs |
| W2 | `article-synthesizer` (parallel per unique concept) | concept block, existing article if present, `STACK.md` | `articles/{slug}.md` |
| W2b | bash wikilink pass | all articles + `glossary.md` (if present) | articles mutated in-place |
| W3 | bash source filing | `sources/incoming/*` | `sources/{publisher}/*` |
| W4 | bash MoC update | all article frontmatter + `index.md` existing `## Reading Paths` block | `{stack}/index.md` |

Cross-file drift from parallel `article-synthesizer` dispatches is handled by two mechanisms, not a sweep wave:
1. **Slug immutability** (W1 prompt rule): once a concept slug is set and its article exists, concept-identifier cannot propose a rename. New concepts get new slugs; existing concepts keep theirs. Eliminates drift at the source.
2. **Audit `[DRIFT]` marks** (A1 in audit-stack): the next audit pass surfaces any stale prose references.

**`audit-stack`** (replaces `refine-stack`):

| Wave | Agent / Module | Input | Output |
|------|----------------|-------|--------|
| A1 | `validator` (reshaped prompt, filename unchanged through transition) | all articles + all sources | inline `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` marks on articles |
| A2 | `synthesizer` (reshaped prompt, filename unchanged through transition) | all articles | `{stack}/glossary.md`, `{stack}/invariants.md`, `{stack}/contradictions.md` |
| A2b | bash wikilink pass (shared helper) | articles + glossary | articles mutated in-place |
| A3 | `findings-analyst` (reshaped prompt, filename unchanged through transition) | articles (inline marks are the data source), contradictions, prior `findings.md` | `dev/audit/findings.md` |
| A4 | bash convergence check | current + prior findings | empty-pass signal |
| A5 | bash archive | — | `dev/audit/closed/{audit_date}-findings.md` |

Convergence: 2 consecutive empty passes OR pass-count budget cap (default 3), whichever first. Empty = zero `open` status items AND zero `action: fetch_source` items with non-terminal status. Items with `status: failed`, `deferred`, or `manual_review` do not count as open work.

### Agent roster (7 → 6)

Removed:
- `topic-clusterer.md` — concept is the unit; no clustering wave
- `cross-referencer.md` — cross-linking is deterministic post-write bash pass

Added (new files in `agents/`):
- `concept-identifier.md` — identifies discrete concepts per source AND extracts relevant claims per concept (absorbs the `article-extractor` role called out in #19's original scope; single-pass design avoids a separate extraction wave). Enforces slug immutability per W1 prompt.
- `article-synthesizer.md` — writes one `articles/{slug}.md` per unique concept, frontmatter included.

Reshaped (**filename unchanged through #19/#20/#21** so the old `refine-stack` skill can still dispatch by name during transition; renames, if any, are part of #22):
- `validator.md` — prompt updated to mark articles inline AND strip prior cycle marks from input articles before running (prevents accumulation across audit cycles).
- `synthesizer.md` — prompt updated to produce three stack-root artifacts (`glossary.md`, `invariants.md`, `contradictions.md`). File stays at `synthesizer.md`.
- `findings-analyst.md` — prompt updated to write locked findings schema; reads inline `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` marks directly from articles (no separate scratch file).

All new/reshaped agents conform to plugin frontmatter convention: `tools` (comma-separated), `model`, `description`, 3+ worked examples in the body. The `color` frontmatter field is optional (existing agents are split 4-with, 3-without).

### Decision-point resolutions

| # | Decision | Resolution |
|---|----------|------------|
| 1 | `extraction_hash` inputs | SHA256 of canonical source bytes (trailing whitespace stripped per line) concatenated with concept slug. Deterministic regardless of mtime, filesystem, or git checkout timestamps. |
| 2 | Source filing timing | W3 after all W2 article writes pass their gates. Partial failure: unmoved sources stay in `incoming/` and are picked up next run. No rollback. |
| 3 | concept-identifier contract | Input: source file paths, `STACK.md`, skip list, existing `articles/` listing. Output: one `.md` per source with concept blocks (`slug`, `title`, `source_paths`, `hash_inputs`, `target_article`). **Slug immutability**: if any concept matches an existing article (by claim overlap), the concept block MUST use that article's existing slug as both `slug` and `target_article`. Concept-identifier cannot propose a renamed slug for an existing article. New slugs only for genuinely new concepts. |
| 4 | W1b slug-collision dedup | bash pass between W1 and W2. For each concept block across all W1 outputs, group by `slug`. For any slug appearing in 2+ blocks, merge `source_paths[]` into a single block and dispatch exactly one W2 synthesizer with the unified source list. Silent overwrite by parallel W2 dispatches is impossible because W2 dispatches are per-unique-slug. |
| 5 | article-synthesizer contract | Input: one concept block, existing article if `target_article` set, `STACK.md`. Output: `articles/{slug}.md`. **Strip-on-rewrite**: when the existing article is present on input, strip all `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` markers from its body before producing the updated article. First-write frontmatter: `extraction_hash` (from W1b), `last_verified=""`, `updated=today`, `sources[]` (unified paths from W1b), `title`, `tags[]`. Body: 300-800 words, inline `[source-slug]` citations, no wikilinks (linker pass writes them). Validator populates `last_verified` on its A1 pass. |
| 6 | Deterministic wikilink pass | `scripts/wikilink-pass.sh {articles-dir} {glossary-path}`. Reads glossary bold terms (`grep -oP '(?<=\*\*)[^*]+(?=\*\*)' glossary.md`), case-insensitive match, first occurrence per term per article, self-links excluded (skip when article slug matches term slug), paraphrase not matched, preserve original capitalization in wrapped text. Runs at W2b, A2b, and whenever glossary.md is regenerated. Safe if `glossary.md` is absent (first-ever catalog run) — pass is a no-op. |
| 7 | Findings `content-hash` | Full SHA256 (not truncated) of `article-slug + "\|" + finding_type + "\|" + space-normalized claim text`. Stable across reformatting; changes when claim text changes (correct behavior). Article slug is immutable per decision 3, so ID is stable under article evolution. |
| 8 | Findings status enum | `open | applied | closed | deferred | stale | failed`. `failed` set by catalog-sources when a `fetch_source` action errors out (network error, 404, parser failure). Per decision 9, `failed` is terminal and does not keep convergence open. |
| 9 | Empty pass | Zero items with `status: open` AND zero `action: fetch_source` items in non-terminal status. Terminal statuses: `applied`, `closed`, `deferred`, `stale`, `failed`. An item stuck in `failed` does not block convergence — the operator fixes it out-of-band or the catalog records a deferred rationale. |
| 10 | Budget cap | `MAX_AUDIT_PASSES` (default 3) read from `STACK.md`. Single cap; no wall-clock belt-and-suspenders. |
| 11 | Retrieval fallback signal | `test -d {stack}/articles && find {stack}/articles -maxdepth 1 -name '*.md' | head -1 | grep -q .`. Presence → article mode. Absence → guide mode. No `STACK.md` field needed. |
| 12 | MoC generation | Auto-generated by bash at W4 from article `tags[0]` frontmatter. The generator reads existing `index.md`, **preserves any `## Reading Paths` section verbatim**, and rewrites the remainder of the file (title, generated groupings). Hand-curated reading paths go in that preserved section in the same file. No separate `index-custom.md`. |
| 13 | Write-or-fail | `scripts/assert-written.sh {path} {dispatch_epoch} {agent_label}` → `test -s $path && [ $(stat -c %Y $path) -gt $dispatch_epoch ]` → fixed error string on failure. Dispatch caller captures `DISPATCH_EPOCH=$(date +%s)` immediately before `Task` invocation. The timestamp check prevents a stale pre-existing file from passing the gate when the agent wrote to chat instead of disk. Parallel waves collect all expected paths, check after fan-in, report all failures together. Linux-only (`stat -c %Y`); cross-platform is explicitly out of scope. |
| 14 | `dev/extractions/` vs `dev/audit/` | `dev/extractions/` holds `concept-identifier` outputs; ephemeral between runs, not committed. `dev/audit/` holds `findings.md`, `closed/`; committed. Old `dev/curate/` layout remains in place during transition (old `refine-stack` writes there); #22 removes `dev/curate/` from library templates. |

### Directory layout (new)

```
{stack}/
  articles/
    {slug}.md                      # flat, no typed subdirs
  sources/
    incoming/                      # staged sources awaiting synthesis
    {publisher}/                   # filed sources
  topics/                          # legacy, read-only until user deletes
    {topic}/guide.md
  dev/
    audit/
      findings.md                  # current audit result
      closed/
        {audit_date}-findings.md   # archived annotated findings
    extractions/
      {source-slug}-concepts.md    # concept-identifier output, ephemeral
  glossary.md                      # patron-visible, stack root
  invariants.md                    # patron-visible, stack root
  contradictions.md                # patron-visible, stack root
  index.md                         # auto-generated MoC; preserves ## Reading Paths section
  STACK.md
```

Path change note (conventions): `glossary.md` and `invariants.md` move from `dev/curate/` (old) to stack root (new). This is intentional — the old refine-stack skill continues reading `dev/curate/glossary.md` during transition (until #22 retires it); the new audit-stack writes to stack root. References to the old path live in `skills/refine-stack/SKILL.md` and `references/wave-engine.md` — both retired or overwritten in #22.

### Version bump policy

Per workspace CLAUDE.md ("every code change that touches functionality gets a semver bump and CHANGELOG entry"), each sub-issue carries its own bump:

- #19 completion: `0.9.0-alpha.1` (plugin.json + marketplace.json in sync) + CHANGELOG entry documenting catalog-sources pipeline shipped alongside ingest-sources
- #20 completion: `0.9.0-alpha.2` + CHANGELOG for article-mode retrieval
- #21 completion: `0.9.0-alpha.3` + CHANGELOG for audit-stack + loop closure
- #22 completion: `0.9.0` (final) + CHANGELOG for breaking cutover, old skills/agents removed

The pre-release tags signal "new surface, old surface still present" during transition. #22 remains the atomic breaking commit.

### Rename ordering

Old skills (`ingest-sources`, `refine-stack`) + old agents (`topic-clusterer`, `cross-referencer`, `topic-extractor`, `topic-synthesizer`) stay in place and functional during #19/#20/#21. Reshaped agents (`validator.md`, `synthesizer.md`, `findings-analyst.md`) keep their filenames unchanged; only their prompt bodies change. This keeps the old `refine-stack` pipeline runnable by name during transition. #22 deletes old skills and old agents atomically; no agent files get renamed.

## Constraints

Inherited from brief (locked):
- Pre-1.0 personal tool. Hard-cut rename in #22.
- No migration of existing `topics/*/guide.md`. Rebuild from source. Legacy stays read-only until user deletes.
- Flat article directory. No typed subdirs.
- `[[wikilinks]]` for cross-links, not markdown links.
- Article size: soft 300-800 words, stretch to ~1200. Prompt-level guidance, not a gate.
- Direct-load retrieval only. No vector/MCP/qmd.
- Agent write-or-fail is a hard failure mode. Bash `test -s` + timestamp gate after every dispatch.
- Agent count: 6 total across both pipelines.
- Defer #7 page types. Single article shape ships first.

Inherited from S1 reconciliation:
- Standard findings `content-hash` is full SHA256 (not truncated).
- Pass-count budget (default 3), not USD.

Applied from swe stack (knowledge-system-design, multi-agent-pipeline-design):
- Write-or-fail gate combines `test -s` with timestamp-newer-than-dispatch (zero-byte files and stale pre-existing files both pass `-s` alone silently).

Applied from S1 spec review gate:
- Cross-file drift from parallel W2 is prevented by slug immutability + audit DRIFT catch (not a W2c sweep wave).
- Validator writes inline marks as the sole output; no separate validation-scratch file. Findings-analyst reads marks directly from articles.
- Article-synthesizer strips prior-cycle inline marks on re-synthesis.
- Status enum includes `failed` (terminal); convergence rule excludes it.
- MoC auto-generator preserves `## Reading Paths` section in `index.md`; no separate `index-custom.md`.
- W1b slug-collision dedup runs between W1 fan-in and W2 fan-out.
- Version bump per sub-issue (alpha.1, alpha.2, alpha.3) + CHANGELOG, honoring workspace rule.

## Done when

### #19 — catalog-sources pipeline + source filing

Files created:
- `skills/catalog-sources/SKILL.md` (Step 0 telemetry + waves W0-W4)
- `agents/concept-identifier.md` (with 3+ worked examples)
- `agents/article-synthesizer.md` (with 3+ worked examples)
- `scripts/assert-written.sh` (shared helper invoked by both new skills)
- `scripts/wikilink-pass.sh` (shared helper invoked at W2b and A2b)
- `references/wave-engine.md` (rewritten to document new catalog-sources + audit-stack wave tables; old wave content preserved as `references/wave-engine-legacy.md` or removed — implementer's choice)

Behavior:
- `catalog-sources` callable; produces flat `articles/{slug}.md` for a fresh stack from `sources/incoming/`.
- `sources/incoming/` empties to `sources/{publisher}/` after successful run.
- Agent write-failure halts pipeline with a named error via `assert-written.sh` (both `-s` and timestamp-newer-than-dispatch checks).
- Every article has `extraction_hash`, `last_verified`, `updated`, `sources[]`, `title`, `tags[]` in frontmatter.
- Concept-identifier enforces slug immutability on existing articles.
- W1b dedup collapses parallel concept-identifier outputs with matching slugs into single W2 dispatches.
- Version bumped to `0.9.0-alpha.1` (plugin.json + marketplace.json in sync) with CHANGELOG entry.
- Old `ingest-sources` pipeline unchanged and still runnable.

### #20 — retrieval + MoC + wikilinks

Files modified:
- `skills/ask/SKILL.md` — Step 5 gains article-mode branch (reads `articles/*.md` when `articles/` dir contains `.md` files; falls back to `topics/*/guide.md` otherwise per decision 11).
- `{stack}/index.md` generator in catalog-sources W4 — preserves `## Reading Paths` section verbatim.

Behavior:
- `/stacks:ask` detects article mode vs guide mode via `articles/` directory presence and routes accordingly.
- `index.md` auto-generated from article `tags[0]` at catalog run; preserves any user-edited `## Reading Paths` section.
- `[[wikilink]]` parsing works in articles; Obsidian graph view shows article-to-article edges.
- Version bumped to `0.9.0-alpha.2` + CHANGELOG.

### #21 — audit-stack + findings + loop closure

Files created:
- `skills/audit-stack/SKILL.md` (Step 0 telemetry + waves A1-A5)
- `references/wave-engine.md` (audit-stack wave table added; #19 creates the file, #21 extends)

Files modified (prompts only; filenames preserved):
- `agents/validator.md`
- `agents/synthesizer.md`
- `agents/findings-analyst.md`

Behavior:
- `audit-stack` callable; produces `findings.md` per locked schema (frontmatter + item shape + status enum including `failed`).
- Validator writes inline `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` marks on articles; no separate scratch file.
- Article-synthesizer strips prior-cycle marks on re-synthesis (verified via catalog→audit→catalog→audit cycle test).
- `synthesizer` writes `glossary.md`, `invariants.md`, `contradictions.md` at stack root.
- Deterministic wikilink pass runs at A2b; no cross-referencer agent.
- Convergence fires at 2 consecutive empty passes or `MAX_AUDIT_PASSES` cap.
- `catalog-sources` reads prior `findings.md` at run start, acts on `fetch_source` acquisitions, re-synthesizes flagged articles, annotates per-item status, archives to `dev/audit/closed/{audit_date}-findings.md`.
- `audit → catalog → audit` sequence produces a differential second audit (carries forward deferred, surfaces only new, does not re-run applied).
- Version bumped to `0.9.0-alpha.3` + CHANGELOG.

### #22 — rename cutover + version bump

- `skills/ingest-sources/` removed.
- `skills/refine-stack/` removed.
- `agents/topic-clusterer.md` removed.
- `agents/topic-extractor.md` removed.
- `agents/topic-synthesizer.md` removed.
- `agents/cross-referencer.md` removed.
- Reshaped agents (`validator.md`, `synthesizer.md`, `findings-analyst.md`) remain at their original filenames.
- `dev/curate/` removed from library templates; templates ship `dev/audit/` + `dev/extractions/`.
- `plugin.json` and `marketplace.json` bumped from `0.9.0-alpha.3` to `0.9.0` in sync (resolves the pre-existing 0.8.3 vs 0.8.0 mismatch as a side effect — the sync-versions script makes this mechanical).
- CHANGELOG entry documents breaking cutover.
- Workspace routing / library CLAUDE.md references old names only in historical CHANGELOG.
- `grep -rI "ingest-sources\|refine-stack\|topic-clusterer\|cross-referencer\|topic-extractor\|topic-synthesizer\|dev/curate" .` returns only CHANGELOG and historical commit references.
