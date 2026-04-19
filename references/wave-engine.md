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
| W1 | `concept-identifier` (parallel per batch) | source files, `STACK.md`, skip list | `dev/extractions/{batch_id}-concepts.md` |
| W1b | bash slug-collision dedup | all W1 outputs | unified concept list with `source_paths[]` merged for shared slugs |
| W2 | `article-synthesizer` (parallel per unique concept) | concept block, existing article if present, `STACK.md` | `articles/{slug}.md` |
| W2b | bash wikilink pass | all articles + `glossary.md` (if present) | articles mutated in-place |
| W2b-post | bash tag drift check | all articles + `STACK.md` `allowed_tags:` | halt pipeline on out-of-vocab tag; exit 0 if `allowed_tags:` absent |
| W3 | bash source filing | `sources/incoming/*` | `sources/{publisher}/*` |
| W4 | bash MoC update | all article frontmatter + `index.md` existing `## Reading Paths` block | `{stack}/index.md` |

---

## audit-stack waves

| Wave | Agent / Module | Input | Output |
|------|----------------|-------|--------|
| A1 | `validator-orchestrator` wrapping N parallel `validator` shards | all articles + per-batch citation-graph source union | inline `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` marks on articles |
| A2 | `synthesizer-orchestrator` wrapping N parallel `synthesizer` shards + merge pass | all articles | `{stack}/glossary.md`, `{stack}/invariants.md`, `{stack}/contradictions.md` |
| A2b | bash wikilink pass (shared helper) | articles + glossary | articles mutated in-place |
| A3 | `findings-analyst-orchestrator` wrapping N parallel `findings-analyst` shards + bash merge | articles (inline marks are the data source), contradictions, prior `findings.md` | `dev/audit/findings.md` |
| A4 | bash convergence check | current + prior findings | empty-pass signal |
| A4.5 | `scripts/rotate-findings.sh` | `findings.md` + `STACK.md` `ROTATION_CYCLES:` | items rotated to `dev/audit/findings-archive.md` |
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

### W1 + W1b + W2 — Orchestrator dispatch

Main session dispatches ONE `concept-identifier-orchestrator` via the Task tool. The orchestrator owns all three waves: W1 concept-identifier fan-out (using the #26 batch math), W1b dedup awk + per-slug split + `scripts/compute-extraction-hash.sh` invocation, W2 article-synthesizer fan-out (wave-capped). It gates every expected output via `scripts/assert-written.sh` and writes `dev/extractions/_w1-w2-summary.json` under the unified schema_version=1 envelope (see [Summary-JSON contract](#summary-json-contract) below).

```bash
# Main session dispatches ONE orchestrator. The orchestrator runs internally:
#   - W1 dispatch: N_AGENTS concept-identifier agents in parallel
#       (SOURCES_PER_AGENT=10 baseline; 1-per-agent when N_SOURCES < 10)
#   - W1 gate:     assert-written.sh per batch-{id}-concepts.md file
#   - W1b:         awk dedup groups blocks by slug, merges source_paths[];
#                  compute-extraction-hash.sh computes the hash per unique slug
#                  using stable byte format `{path1}|{path2}|...|{pathN}|{slug}`
#                  (paths sorted ascending, `|`-joined, echo -n piped so no
#                  trailing newline enters the digest);
#                  then splits the aggregated `_dedup.md` into one
#                  `_dedup-{slug}.md` file per unique slug (self-contained,
#                  slug: line through next slug: boundary). The aggregated
#                  `_dedup.md` is kept as the audit-trail artifact; the
#                  per-slug files are what W2 agents read.
#   - W2 dispatch: N_UNIQUE_CONCEPTS article-synthesizer agents, capped at
#                  W2_WAVE_CAP=25 per wave with a loop. Each wave captures
#                  its own DISPATCH_EPOCH_W2_WAVE and runs its per-article
#                  gate against THAT wave's epoch. `n_w2_waves` records the
#                  actual wave count.
#   - W2 gate:     assert-written.sh per articles/{slug}.md, per wave.
#
# Orchestrator writes dev/extractions/_w1-w2-summary.json (schema_version=1
# envelope) with nested counts {n_sources, n_batches_w1, n_concepts_input,
# n_unique_concepts, n_articles_new, n_articles_updated, n_w2_waves} and
# nested epochs {dispatch_epoch_w1, dispatch_epoch_w2}.
#
# Orchestrator returns on stdout the receipt line:
#   ORCHESTRATOR_OK: wave=w1-w2
# On failure emits `ORCHESTRATOR_FAILED: wave=w1-w2 reason={W1|W2}` marker
# on stdout and failed batch-ids / slugs on stderr.
```

Each concept-identifier agent receives N sources (N≥1) and a `batch_id`, reads its assigned source files, `STACK.md`, and the skip list. Output: one merged `dev/extractions/{batch_id}-concepts.md` with concept blocks (`slug`, `title`, `source_paths`, `target_article`). `extraction_hash` is populated by W1b, not by the concept-identifier. When N>1 the agent dedups within-batch at the source level so a concept appearing in multiple assigned sources becomes one block with a multi-entry `source_paths:`.

Each article-synthesizer agent receives one concept block, the existing article if `target_article` is set, and `STACK.md`. First-write frontmatter includes: `extraction_hash`, `last_verified=""`, `updated=today`, `sources[]`, `title`, `tags[]`. On re-synthesis, the agent strips prior-cycle inline marks (`[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]`) from the existing article body before writing the update.

The orchestrator wrapper pattern exists for the same reason as `validator-orchestrator` (see #30): it moves bash-array state and gate loops out of the main-session skill and into a single dispatch boundary. The summary JSON is what makes accurate end-of-pipeline counts possible; the previous inline pattern never populated `NEW_ARTICLE_SLUGS` / `UPDATED_ARTICLE_SLUGS`.

### W2b — Wikilink pass

```bash
scripts/wikilink-pass.sh {stack}/articles/ {stack}/glossary.md
```

No-op when `glossary.md` is absent. Runs after all W2 assert-written checks pass.

### W2b-post — Tag drift check

```bash
scripts/normalize-tags.sh {stack}
```

Reads `allowed_tags:` (block-list YAML) from `{stack}/STACK.md` and compares every `{stack}/articles/*.md` frontmatter `tags:` against it. Halts with `TAG_DRIFT: {slug}: {tag}` on stderr per offender and non-zero exit; `incoming/` stays untouched so the next run retries after the operator fixes the article or extends the vocabulary. When `allowed_tags:` is absent or empty, exits 0 with a backward-compat warning — drift check is opt-in per stack.

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

Dispatch one `validator-orchestrator` agent. The orchestrator owns dispatch math, the pre-dispatch citation graph, per-batch `validator` dispatches, and the per-article assert-written gate loop. The main session's A1 gate is a receipt-line + summary-file pair (see [Summary-JSON contract](#summary-json-contract) below).

```bash
# Main session dispatches ONE orchestrator via the Task tool. The orchestrator
# shards articles across N_BATCHES parallel `validator` agents (cap 15
# articles per batch), captures its own DISPATCH_EPOCH, and runs
# scripts/assert-written.sh per article before returning.
#   - N <= 15   : 1 batch (ARTICLES_PER_AGENT = N)
#   - N  > 15   : ARTICLES_PER_AGENT = min(ceil(N/5), 15)
#
# Before dispatch, the orchestrator builds a citation graph:
#   - SOURCE_MAP: { source-slug -> sources/.../path.md } from sources/ frontmatter
#   - ARTICLE_SOURCES: per article, union of frontmatter `sources:` +
#     inline `[source-slug]` refs in the body.
# Each per-batch validator receives the UNION of its articles' resolved
# source paths (per-batch citation-graph union), not the full sources tree.
# Full-tree fallback fires when a batch's articles have zero resolvable
# citations (safety net: unresolved slugs still get marked [UNSOURCED] per
# the validator contract but the validator retains a reference surface).
#
# Orchestrator writes dev/audit/_a1-summary.json (schema_version=1 envelope)
# and returns the receipt line on stdout:
#   ORCHESTRATOR_OK: wave=a1
# A response missing the receipt line, or a missing/malformed summary file,
# is treated as A1 failure. On failure the orchestrator also emits
# `ORCHESTRATOR_FAILED: wave=a1 reason={short}` on stdout and reports all
# failed paths on stderr.
```

Per-batch validators read their assigned articles and their per-batch source union (or the full-tree fallback). Before marking, each strips any prior-cycle marks from its article bodies. Output: articles mutated in-place with inline `[VERIFIED]`, `[DRIFT]`, `[UNSOURCED]`, or `[STALE]` marks appended to claims. No separate validation scratch file. Findings-analyst reads these marks directly from articles at A3.

Sharding exists because the single-agent validator hit the "Prompt is too long" ceiling at ~75 articles (see #30). Per-batch source union (vs. full-tree) exists because validator prompts grow with article count AND source count; citation-graph sharding cuts the source surface each validator sees to the set its articles actually cite (see #34). The per-article gate (rather than a directory check) is required because editing files inside a directory does not advance the directory's mtime on Linux.

### A2 — Stack-root artifact synthesis (orchestrator-wrapped)

Dispatch one `synthesizer-orchestrator` agent. The orchestrator shards articles across parallel `synthesizer` agents (cap `ARTICLES_PER_AGENT=30`, higher than A1 because synthesizer reads article text only, no sources tree). When `N_BATCHES == 1` each `synthesizer` writes the three final stack-root files directly; when sharded, each shard writes `dev/audit/_a2-partial-{batch_id}.md` and a second `synthesizer` dispatch runs as a merge pass that resolves dedup, independent-corroboration, and tier-hierarchy rules across shards and emits the three final files. The orchestrator owns per-output `assert-written.sh` gating for both the shard partials and the three final stack-root files.

Orchestrator writes `dev/audit/_a2-summary.json` (schema_version=1 envelope) and returns the receipt line `ORCHESTRATOR_OK: wave=a2` on stdout. On failure it emits `ORCHESTRATOR_FAILED: wave=a2 reason={single-shard-gate|shard-gate|merge-gate|dispatch}` on stdout and failed paths on stderr; no summary file is written on failure.

### A3 — Findings (orchestrator-wrapped)

Dispatch one `findings-analyst-orchestrator` agent. The orchestrator shards articles across parallel `findings-analyst` agents (cap 15 articles per agent, matching A1). When `N_BATCHES == 1` the single shard writes `dev/audit/findings.md` directly; when sharded, each shard writes `dev/audit/_a3-partial-{batch_id}.md` and the orchestrator bash-merges partials into the single `findings.md` by item `id`, applying terminal-wins precedence so carried-forward terminal statuses never regress. Per-output `assert-written.sh` gates cover both the partials and the merged active findings file.

Orchestrator writes `dev/audit/_a3-summary.json` (schema_version=1 envelope) and returns the receipt line `ORCHESTRATOR_OK: wave=a3` on stdout. On failure it emits `ORCHESTRATOR_FAILED: wave=a3 reason={single-shard-gate|shard-gate|merge-gate|dispatch}` on stdout and failed paths on stderr; no summary file is written on failure.

### Summary-JSON contract

All four orchestrators (`validator-orchestrator`, `concept-identifier-orchestrator`, `synthesizer-orchestrator`, `findings-analyst-orchestrator`) write a schema_version=1 envelope to a per-wave summary path:

- W1+W1b+W2 → `dev/extractions/_w1-w2-summary.json`
- A1 → `dev/audit/_a1-summary.json`
- A2 → `dev/audit/_a2-summary.json`
- A3 → `dev/audit/_a3-summary.json`

Envelope shape:

```json
{
  "schema_version": 1,
  "wave": "a1",
  "status": "ok",
  "counts": { "n_articles": 80, "n_batches": 6, "...": "..." },
  "epochs": { "dispatch_epoch": 1713500000 }
}
```

Wave-specific keys live under `counts` (e.g. `glossary_terms` for a2, `new_items` / `carried_items` / `rotated_items` for a3, `n_articles_new` / `n_articles_updated` / `n_w2_waves` for w1-w2). `epochs` carries whatever dispatch epoch(s) the wave captures (w1-w2 carries both `dispatch_epoch_w1` and `dispatch_epoch_w2`).

The orchestrator-return signal is a receipt line of the form `ORCHESTRATOR_OK: wave={wave}` as the final content of its stdout response. The main session's gate is a three-part check: (1) receipt line present, (2) summary file exists and is non-empty, (3) `jq -e` type-check of the required nested fields. Any of the three signals missing is treated as wave failure. On failure the orchestrator emits `ORCHESTRATOR_FAILED: wave={wave} reason={short}` as the final stdout line and reports failed paths on stderr; no summary file is written on failure.

### A2b — Wikilink pass

```bash
scripts/wikilink-pass.sh {stack}/articles/ {stack}/glossary.md
```

Same shared helper as W2b. Runs after A2 assert-written checks pass.

A3 execution follows A2b (see [A3 — Findings (orchestrator-wrapped)](#a3--findings-orchestrator-wrapped) above).

### A4 — Convergence check

Bash reads `dev/audit/findings.md`. Checks empty-pass condition: zero `status: open` items AND zero items with `resolvable_by: audit-stack` in non-terminal status. Items with `resolvable_by: catalog-sources` (fetch_source) or `resolvable_by: external` (research_question) are out of audit-stack's domain and do not block convergence.

If empty pass and this is the 2nd consecutive empty pass: convergence. Proceed to A4.5.
If `MAX_AUDIT_PASSES` reached: convergence regardless of open count. Proceed to A4.5.
Otherwise: report pass count and open item count to user. Pipeline complete for this pass; next pass begins at A1.

### A4.5 — Rotate stale terminal findings

Runs only when A4 set `converged=1`, and runs before A5 so the archive snapshot reflects the post-rotation active file.

```bash
audit_date=$(grep -oP '(?<=audit_date:\s)\S+' "$STACK/dev/audit/findings.md" | head -1)
DISPATCH_EPOCH=$(date +%s)
ROTATION_OUTPUT=$(bash "$SCRIPTS_DIR/rotate-findings.sh" "$STACK" "$audit_date")
rotated_count=$(echo "$ROTATION_OUTPUT" | grep -oP '(?<=rotated_items=)\d+' || echo "0")
if [[ "$rotated_count" -gt 0 ]]; then
  "$SCRIPTS_DIR/assert-written.sh" "$STACK/dev/audit/findings-archive.md" "${DISPATCH_EPOCH}" "rotate-findings"
fi
```

`scripts/rotate-findings.sh` moves items from the active `findings.md` to `dev/audit/findings-archive.md` when they have been in a terminal status (`applied`, `closed`, `deferred`, `stale`, `failed`) for `ROTATION_CYCLES` distinct audit cycles or more (default 3, parsed from `STACK.md`). Items carry a `terminal_transitioned_on: YYYY-MM-DD` field set on their first terminal cycle (schema v4); a carry-forward migration block backfills the field to the current `audit_date` on first encounter for v3 items, so no hand-editing is required.

The assert-written gate fires only when `rotated_items > 0`. Zero-rotation runs (common during the stack's first terminal-accumulation cycles) are no-ops. Findings-analyst carry-forward reads the active file only; rotated items drop out of the working set cleanly.

### A5 — Archive

On convergence:

```bash
cp dev/audit/findings.md "dev/audit/closed/$(date +%Y-%m-%d)-findings.md"
# findings.md remains at dev/audit/findings.md as the baseline for the next cycle
```

Archived findings serve as the historical record. The active `findings.md` carries forward into the next catalog-sources W0b pass.
