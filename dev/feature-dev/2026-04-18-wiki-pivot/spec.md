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
- Version mismatch: `plugin.json` = 0.8.3 vs `marketplace.json` = 0.8.0. Fixed as part of #22.

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
- **Harness engineering**: every agent dispatch has a `test -s` post-write gate; empty files halt the pipeline with a named error rather than silently continuing. Single shared `scripts/assert-written.sh` helper.
- **Knowledge priming**: locked `findings.md` schema (frontmatter + item shape) means agents receive a templated contract, not a narrative ask.
- **Karpathy gist**: article-per-concept unit, flat directory, LLM-readable + human-browsable in Obsidian. Article size 300-800 words fits direct-load retrieval (no vector/MCP needed for libraries of tens of articles).

## Architecture decision

**Pragmatic-fastest proposal + 4 tweaks.** User selected at Step 10.

Per-sub-issue ceremony slicing:
- **#19** (catalog-sources pipeline + source filing) — architect ceremony fired, 3 parallel framings
- **#20** (retrieval + MoC + wikilink parser) — covered in unified proposal; no independent ceremony
- **#21** (audit-stack + findings + deterministic linker + loop closure) — covered in unified proposal
- **#22** (rename cutover + version bump) — **mechanical, no architecture**; skips to plan rows directly

### Pipeline structure

**`catalog-sources`** (replaces `ingest-sources`):

| Wave | Agent / Module | Input | Output |
|------|----------------|-------|--------|
| W0 | bash enumerate | `sources/incoming/*`, `index.md` | `NEW_SOURCES` list |
| W0b | bash prior-findings gate | `findings.md` | skip list of already-synthesized `extraction_hash` values |
| W1 | `concept-identifier` (parallel per source batch) | source files, `STACK.md`, skip list | `dev/extractions/{source-slug}-concepts.md` |
| W2 | `article-synthesizer` (parallel per concept) | concept block, existing article if present, `STACK.md` | `articles/{slug}.md` + `dev/extractions/{slug}.summary.yaml` (renamed identifiers, rewritten blocks) |
| W2b | bash wikilink pass | all articles + `glossary.md` | articles mutated in-place |
| W2c | bash cross-file consistency sweep | all W2 summaries, all articles | queued findings for next audit pass if stale references to renamed slugs |
| W3 | bash source filing | `sources/incoming/*` | `sources/{publisher}/*` |
| W4 | bash MoC update | all article frontmatter | `{stack}/index.md` |

**`audit-stack`** (replaces `refine-stack`):

| Wave | Agent / Module | Input | Output |
|------|----------------|-------|--------|
| A1 | `validator` (reshaped) | all articles + all sources | inline `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` marks on articles + `dev/audit/validation-scratch.md` |
| A2 | `stack-synthesizer` (reshaped `synthesizer`) | all articles | `{stack}/glossary.md`, `{stack}/invariants.md`, `{stack}/contradictions.md` |
| A2b | bash wikilink pass (shared helper) | articles + glossary | articles mutated in-place |
| A3 | `findings-analyst` (reshaped) | articles + validation-scratch + contradictions + prior `findings.md` | `dev/audit/findings.md` |
| A4 | bash convergence check | current + prior findings | empty-pass signal |
| A5 | bash archive | — | `dev/audit/closed/{audit_date}-findings.md` |

Convergence: 2 consecutive empty passes OR pass-count budget cap (default 3), whichever first. Empty = zero `open` status items AND zero `action: fetch_source` items.

### Agent roster (7 → 6)

Removed:
- `topic-clusterer.md` — concept is the unit; no clustering wave
- `cross-referencer.md` — cross-linking is deterministic post-write bash pass

Added:
- `concept-identifier.md` — identifies discrete concepts per source; emits per-source concept extraction markdown
- `article-synthesizer.md` — writes one `articles/{slug}.md` per concept, frontmatter included

Reshaped (same file, updated prompt):
- `validator.md` — adds inline mark editing of articles + writes `dev/audit/validation-scratch.md`
- `synthesizer.md` → `stack-synthesizer.md` — adds `contradictions.md` output at stack root
- `findings-analyst.md` — writes locked schema, carries forward prior status by item ID

Unchanged: none touched outside the pipelines.

### Decision-point resolutions

| # | Decision | Resolution |
|---|----------|------------|
| 1 | Wave structure | See tables above |
| 2 | `extraction_hash` inputs | SHA256 of canonical source bytes (trailing whitespace stripped per line) concatenated with concept slug. Deterministic regardless of mtime, filesystem, or git checkout timestamps. |
| 3 | Source filing timing | W3 after all W2 article writes pass their `test -s` gates. Partial failure: unmoved sources stay in `incoming/` and are picked up next run. No rollback. |
| 4 | concept-identifier contract | Input: source file paths, `STACK.md`, skip list. Output: one `.md` per source with concept blocks (`slug`, `title`, `source_paths`, `hash_inputs`, `target_article`). Cross-source concepts set `target_article` to the existing slug to trigger update-mode in synthesizer. |
| 5 | article-synthesizer contract | Input: one concept block, existing article if `target_article` set, `STACK.md`. Output: (a) `articles/{slug}.md` with full frontmatter (`extraction_hash`, `last_verified=""`, `updated=today`, `sources[]`, `title`, `tags[]`), 300-800-word body, inline `[source-slug]` citations, no wikilinks (linker pass writes them); (b) `dev/extractions/{slug}.summary.yaml` with `renamed:` and `rewritten_blocks:` arrays (empty arrays allowed) for the W2c sweep to consume. |
| 6 | Article frontmatter on first write | `extraction_hash`, `last_verified` (empty), `updated` (today), `sources[]`, `title`, `tags[]`. Validator fills `last_verified` on its next pass. |
| 7 | Deterministic wikilink pass | `scripts/wikilink-pass.sh {articles-dir} {glossary-path}`. Reads glossary bold terms (`grep -oP '(?<=\*\*)[^*]+(?=\*\*)' glossary.md`), case-insensitive match, first occurrence per term per article, self-links excluded (skip when article slug matches term slug), paraphrase not matched, preserve original capitalization in wrapped text. |
| 8 | Findings `content-hash` | Full SHA256 (not truncated) of `article-slug + "\|" + finding_type + "\|" + space-normalized claim text`. Stable across reformatting; changes when claim text changes (correct behavior). |
| 9 | Empty pass | Zero items with `status: open` AND zero items with `action: fetch_source`. Items with `status: deferred` or `manual_review` do not count. |
| 10 | Budget cap | `MAX_AUDIT_PASSES` (default 3) read from `STACK.md`. Optional `AUDIT_BUDGET_MINUTES` wall-clock cap. USD cost is not observable mid-loop; pass count is. |
| 11 | Retrieval fallback signal | `test -d {stack}/articles && find {stack}/articles -maxdepth 1 -name '*.md' | head -1 | grep -q .`. Presence → article mode. Absence → guide mode. No `STACK.md` field needed. |
| 12 | MoC generation | Auto-generated by bash at W4 from article `tags[0]` frontmatter. Overwrites `index.md` each run. Hand-curated reading paths go in `index-custom.md` (also read by `/stacks:ask`). |
| 13 | Write-or-fail | `scripts/assert-written.sh {path} {dispatch_epoch} {agent_label}` → `test -s $path && [ $(stat -c %Y $path) -gt $dispatch_epoch ]` → fixed error string on failure. Dispatch caller captures `DISPATCH_EPOCH=$(date +%s)` immediately before `Task` invocation. The timestamp check prevents a stale pre-existing file from passing the gate when the agent wrote to chat instead of disk (validates against the known failure mode from swe:multi-agent-pipeline-design). Parallel waves collect all expected paths, check after fan-in, report all failures together. |
| 14 | `dev/extractions/` vs `dev/audit/` | `dev/extractions/` holds `concept-identifier` outputs; ephemeral between runs, not committed. `dev/audit/` holds `findings.md`, `validation-scratch.md`, `closed/`; committed. Old `dev/curate/` layout untouched. |

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
      validation-scratch.md        # validator-to-analyst handoff
      closed/
        {audit_date}-findings.md   # archived annotated findings
    extractions/
      {source-slug}-concepts.md    # concept-identifier output, ephemeral
  glossary.md                      # patron-visible, stack root
  invariants.md                    # patron-visible, stack root
  contradictions.md                # patron-visible, stack root
  index.md                         # auto-generated MoC
  index-custom.md                  # optional hand-curated reading paths
  STACK.md
```

### Rename ordering

Old skills (`ingest-sources`, `refine-stack`) + old agents (`topic-clusterer`, `cross-referencer`, `topic-extractor`, `topic-synthesizer`) stay in place during #19/#20/#21. #22 deletes them atomically with the version bump to 0.9.0. This keeps the old pipeline runnable during transition and makes #22 the one breaking-change commit.

## Constraints

Inherited from brief (locked):
- Pre-1.0 personal tool. Hard-cut rename in #22.
- No migration of existing `topics/*/guide.md`. Rebuild from source. Legacy stays read-only until user deletes.
- Flat article directory. No typed subdirs.
- `[[wikilinks]]` for cross-links, not markdown links.
- Article size: soft 300-800 words, stretch to ~1200. Prompt-level guidance, not a gate.
- Direct-load retrieval only. No vector/MCP/qmd.
- Agent write-or-fail is a hard failure mode. Bash `test -s` gate after every dispatch.
- Agent count: 6 total across both pipelines.
- Defer #7 page types. Single article shape ships first.

Inherited from S1 reconciliation:
- Standard findings `content-hash` is full SHA256 (not truncated).
- Pass-count budget (default 3), not USD.
- `index.md` overwrite + `index-custom.md` for hand edits.
- Include `validation-scratch.md` as explicit handoff file.

Applied from swe stack (knowledge-system-design, multi-agent-pipeline-design):
- Write-or-fail gate combines `test -s` with timestamp-newer-than-dispatch (zero-byte files and stale pre-existing files both pass `-s` alone silently).
- W2c cross-file consistency sweep is mandatory after parallel `article-synthesizer` to catch stale references to renamed slugs. Parallel dispatches share a scope-bounded blind spot: each agent cannot see sibling renames.

## Done when

### #19 — catalog-sources pipeline + source filing
- `catalog-sources` skill callable; produces flat `articles/{slug}.md` for a fresh stack from `sources/incoming/`.
- `sources/incoming/` empties to `sources/{publisher}/` after successful run.
- Agent write-failure halts pipeline with a named error (both `-s` and timestamp-newer-than-dispatch checks), not silent continuation.
- Every article has `extraction_hash`, `last_verified`, `updated`, `sources[]`, `title`, `tags[]` in frontmatter.
- `concept-identifier` and `article-synthesizer` agents exist and honor write-or-fail.
- `article-synthesizer` emits `dev/extractions/{slug}.summary.yaml` (renamed/rewritten_blocks) and W2c sweep flags stale references.
- Old `ingest-sources` pipeline unchanged and still runnable.

### #20 — retrieval + MoC + wikilinks
- `/stacks:ask` detects article mode vs guide mode via `articles/` directory presence and routes accordingly.
- `index.md` auto-generated from article `tags[0]` at catalog run.
- `index-custom.md` (if present) also read by `/stacks:ask`.
- `[[wikilink]]` parsing works in articles; Obsidian graph view shows article-to-article edges.

### #21 — audit-stack + findings + loop closure
- `audit-stack` skill callable; produces `findings.md` per locked schema.
- Validator writes inline `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` marks on articles + `validation-scratch.md`.
- `stack-synthesizer` writes `glossary.md`, `invariants.md`, `contradictions.md` at stack root.
- Deterministic wikilink pass runs after A2; no cross-referencer agent.
- Convergence fires at 2 consecutive empty passes or `MAX_AUDIT_PASSES` cap.
- `catalog-sources` reads prior `findings.md` at run start, acts on `fetch_source` acquisitions, re-synthesizes flagged articles, annotates per-item status, archives to `dev/audit/closed/{audit_date}-findings.md`.
- `audit → catalog → audit` sequence produces a differential second audit (carries forward deferred, surfaces only new, does not re-run applied).

### #22 — rename cutover + version bump
- `skills/ingest-sources/` and `skills/refine-stack/` removed.
- `catalog-sources` and `audit-stack` canonical.
- `dev/curate/` removed from library templates; new templates ship `dev/audit/` + `dev/extractions/`.
- `plugin.json` and `marketplace.json` bumped to 0.9.0 in sync.
- CHANGELOG entry documents breaking change.
- Workspace routing / library CLAUDE.md references old names only in historical CHANGELOG.
- `grep -r "ingest-sources\|refine-stack" .` returns only CHANGELOG hits.
