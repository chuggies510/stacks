# Wave Engine — Knowledge Synthesis

Two pipelines replace the old single ingest-then-refine flow:

- **catalog-sources**: enumerates new sources, identifies concepts, synthesizes articles, files sources, updates the MoC.
- **audit-stack**: validates articles, synthesizes stack-root artifacts, produces findings, checks convergence, archives.

The loop closes because `audit-stack` produces `dev/audit/findings.md` and `catalog-sources` reads it at W0b to drive the next synthesis pass. See [Feedback flywheel](#feedback-flywheel) below.

---

## catalog-sources waves

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

---

## audit-stack waves

| Wave | Agent / Module | Input | Output |
|------|----------------|-------|--------|
| A1 | `validator` (reshaped prompt) | all articles + all sources | inline `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` marks on articles |
| A2 | `synthesizer` (reshaped prompt) | all articles | `{stack}/glossary.md`, `{stack}/invariants.md`, `{stack}/contradictions.md` |
| A2b | bash wikilink pass (shared helper) | articles + glossary | articles mutated in-place |
| A3 | `findings-analyst` (reshaped prompt) | articles (inline marks are the data source), contradictions, prior `findings.md` | `dev/audit/findings.md` |
| A4 | bash convergence check | current + prior findings | empty-pass signal |
| A5 | bash archive | — | `dev/audit/closed/{audit_date}-findings.md` |

---

## Write-or-fail gate

Every agent-producing wave is guarded by `scripts/assert-written.sh`:

```bash
# Caller captures epoch immediately before Task dispatch
DISPATCH_EPOCH=$(date +%s)

# ... dispatch agent via Task tool ...

# After fan-in, assert each expected output
scripts/assert-written.sh {output_path} "${DISPATCH_EPOCH}" "{agent_label}"
```

The script combines two checks:

```bash
test -s "$path" && [ "$(stat -c %Y "$path")" -gt "$dispatch_epoch" ]
```

- `test -s`: output exists and is non-empty.
- mtime newer than dispatch epoch: a stale pre-existing file does not pass the gate silently.

On failure the script exits with the fixed error string `AGENT_WRITE_FAILURE` and the pipeline halts. For parallel waves (W1, W2, A1, A2, A3), the caller collects all expected output paths and checks all of them after fan-in, reporting all failures together before halting.

Applies to these waves: W1, W2, A1, A2, A3.

---

## Slug immutability and W1b dedup

### Slug immutability

Once a concept slug is set and its article exists in `articles/`, concept-identifier cannot propose a rename. If a source's concept matches an existing article (by claim overlap), the concept block must use that article's existing slug as both `slug` and `target_article`. New slugs are only created for genuinely new concepts. This eliminates cross-file drift from parallel W2 dispatches at the source.

### W1b dedup

Between W1 fan-in and W2 fan-out, a bash pass groups all concept blocks from all W1 outputs by `slug`. For any slug appearing in 2+ blocks, the pass merges `source_paths[]` into a single unified block and dispatches exactly one W2 article-synthesizer with that unified list. This prevents silent article overwrite by concurrent W2 dispatches.

---

## Wikilink pass

W2b and A2b both call the same shared helper:

```bash
scripts/wikilink-pass.sh {articles-dir} {glossary-path}
```

The script reads glossary bold terms and rewrites the first occurrence of each term per article as a `[[wikilink]]`. Self-links are excluded (when the article slug matches the term slug). When `glossary.md` is absent (first catalog run before the first audit), the pass is a no-op.

---

## Convergence rule (A4)

A4 runs a bash convergence check after each audit-stack pass.

An audit pass is empty when: zero items with `status: open` AND zero items with `resolvable_by: audit-stack` in non-terminal status. Items with `resolvable_by: catalog-sources` (`fetch_source`) or `resolvable_by: external` (`research_question`) are reported but do not block convergence — they queue for the next catalog cycle or external action.

Convergence is reached when: 2 consecutive empty passes OR `MAX_AUDIT_PASSES` from STACK.md (default 3), whichever comes first.

---

## Feedback flywheel

The loop between the two pipelines closes as follows:

1. `audit-stack` produces `dev/audit/findings.md` (schema v3) with four sections: New Acquisitions (`action: fetch_source`), Articles to Re-Synthesize (`action: resynthesize`), Research Questions (`action: research_question`), and Deferred. Each item carries `status` and `resolvable_by` fields.
2. `catalog-sources` reads prior findings at W0b: it builds a skip list of `extraction_hash` values for already-synthesized content and surfaces generative items (`fetch_source` and `research_question` with identifiable `verification_target`) as new acquisition candidates.
3. `audit-stack` carries item status forward across passes: `applied`, `closed`, `deferred`, `failed`, `stale`. A second audit run is differential, not a full re-run from scratch.
4. On convergence, A5 archives findings to `dev/audit/closed/{audit_date}-findings.md`, clearing the active queue.

This replaces the old single-pass model where findings accumulated in a static report with nothing consuming them back into synthesis.

---

## Execution

### W0 — Source enumeration

Diff `sources/incoming/` contents against `index.md` to produce `NEW_SOURCES`:

```bash
ls {stack}/sources/incoming/ | sort > /tmp/sources-incoming.txt
# compare against indexed sources to find not-yet-processed files
```

Gate: if `NEW_SOURCES` is empty and no open generative findings (`fetch_source` or `research_question`) exist in `findings.md`, stop with "Nothing to catalog."

### W0b — Prior-findings gate

Read `dev/audit/findings.md` (if present). Extract `extraction_hash` values from all items with a terminal status (`applied`, `closed`). Pass as skip list to W1 dispatches so concept-identifier does not re-extract already-synthesized content.

Gate: no write-or-fail check (bash read-only pass). Missing `findings.md` is a no-op; skip list is empty.

### W1 — Concept identification (parallel)

Capture epoch, then dispatch one `concept-identifier` agent per source batch:

```bash
DISPATCH_EPOCH=$(date +%s)
# dispatch concept-identifier agents in parallel via Task tool
# after fan-in:
for slug in ${SOURCE_SLUGS}; do
  scripts/assert-written.sh "dev/extractions/${slug}-concepts.md" "${DISPATCH_EPOCH}" "concept-identifier"
done
```

Each agent reads its source files, `STACK.md`, and the skip list. Output: `dev/extractions/{source-slug}-concepts.md` with concept blocks (`slug`, `title`, `source_paths`, `hash_inputs`, `target_article`).

### W1b — Slug-collision dedup

Bash pass reads all `dev/extractions/*-concepts.md` files. Groups concept blocks by `slug`. Merges `source_paths[]` for any duplicate slugs. Emits a unified concept list for W2 dispatch. Ensures one W2 dispatch per unique slug.

### W2 — Article synthesis (parallel)

Capture epoch, then dispatch one `article-synthesizer` agent per unique concept from W1b output:

```bash
DISPATCH_EPOCH=$(date +%s)
# dispatch article-synthesizer agents in parallel via Task tool
# after fan-in:
for slug in ${CONCEPT_SLUGS}; do
  scripts/assert-written.sh "articles/${slug}.md" "${DISPATCH_EPOCH}" "article-synthesizer"
done
```

Each agent receives one concept block, the existing article if `target_article` is set, and `STACK.md`. First-write frontmatter includes: `extraction_hash`, `last_verified=""`, `updated=today`, `sources[]`, `title`, `tags[]`. On re-synthesis, the agent strips prior-cycle inline marks (`[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]`) from the existing article body before writing the update.

### W2b — Wikilink pass

```bash
scripts/wikilink-pass.sh {stack}/articles/ {stack}/glossary.md
```

No-op when `glossary.md` is absent. Runs after all W2 assert-written checks pass.

### W3 — Source filing

```bash
# move sources/incoming/* to sources/{publisher}/
# publisher is read from source frontmatter or inferred from filename
```

Runs after all W2 article writes pass their gates. Partial failure: unmoved sources stay in `incoming/` and are picked up next run. No rollback.

### W4 — MoC update

Bash reads `tags[0]` from all `articles/*.md` frontmatter and regenerates `index.md`. Preserves any existing `## Reading Paths` section verbatim; rewrites all other sections (title, generated groupings by tag).

---

### A1 — Validation (inline marks)

Capture epoch, then dispatch `validator` agent:

```bash
DISPATCH_EPOCH=$(date +%s)
# Enumerate expected output files before dispatch. The validator edits every
# article in place (strips prior-cycle marks, adds new marks, updates
# last_verified), so each article file's mtime advances past DISPATCH_EPOCH.
# A directory-path check would not work: editing files inside a directory
# does not update the directory's own mtime on Linux.
EXPECTED_ARTICLES=( "{stack}"/articles/*.md )
# dispatch validator agent
for article in "${EXPECTED_ARTICLES[@]}"; do
  scripts/assert-written.sh "$article" "${DISPATCH_EPOCH}" "validator"
done
```

The validator reads all articles and all sources. Before running, it strips any prior-cycle marks from article bodies. Output: articles mutated in-place with inline `[VERIFIED]`, `[DRIFT]`, `[UNSOURCED]`, or `[STALE]` marks appended to claims. No separate validation scratch file. Findings-analyst reads these marks directly from articles at A3.

### A2 — Stack-root artifact synthesis

Capture epoch, then dispatch `synthesizer` agent:

```bash
DISPATCH_EPOCH=$(date +%s)
# dispatch synthesizer agent
scripts/assert-written.sh "{stack}/glossary.md" "${DISPATCH_EPOCH}" "synthesizer"
scripts/assert-written.sh "{stack}/invariants.md" "${DISPATCH_EPOCH}" "synthesizer"
scripts/assert-written.sh "{stack}/contradictions.md" "${DISPATCH_EPOCH}" "synthesizer"
```

The synthesizer reads all articles and writes `glossary.md`, `invariants.md`, and `contradictions.md` at stack root.

### A2b — Wikilink pass

```bash
scripts/wikilink-pass.sh {stack}/articles/ {stack}/glossary.md
```

Same shared helper as W2b. Runs after A2 assert-written checks pass.

### A3 — Findings

Capture epoch, then dispatch `findings-analyst` agent:

```bash
DISPATCH_EPOCH=$(date +%s)
# dispatch findings-analyst agent
scripts/assert-written.sh "dev/audit/findings.md" "${DISPATCH_EPOCH}" "findings-analyst"
```

The agent reads articles (inline marks are the data source), `contradictions.md`, and the prior `dev/audit/findings.md` (to carry forward item status). Output: `dev/audit/findings.md` with locked schema (frontmatter + item shape, status enum: `open | applied | closed | deferred | stale | failed`, item `id` is full SHA256 of `{article-slug}|{finding_type}|{space-normalized claim}`).

### A4 — Convergence check

Bash reads `dev/audit/findings.md`. Checks empty-pass condition: zero `status: open` items AND zero items with `resolvable_by: audit-stack` in non-terminal status. Items with `resolvable_by: catalog-sources` (fetch_source) or `resolvable_by: external` (research_question) are out of audit-stack's domain and do not block convergence.

If empty pass and this is the 2nd consecutive empty pass: convergence. Proceed to A5.
If `MAX_AUDIT_PASSES` reached: convergence regardless of open count. Proceed to A5.
Otherwise: report pass count and open item count to user. Pipeline complete for this pass; next pass begins at A1.

### A5 — Archive

On convergence:

```bash
cp dev/audit/findings.md "dev/audit/closed/$(date +%Y-%m-%d)-findings.md"
# findings.md remains at dev/audit/findings.md as the baseline for the next cycle
```

Archived findings serve as the historical record. The active `findings.md` carries forward into the next catalog-sources W0b pass.
