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
| A1 | parent-side parallel `validator` shards (≤3 articles per shard) + per-batch citation-graph source union | all articles + per-batch source paths | inline `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` marks on articles |
| A2 | parent-side parallel `synthesizer` shards (≤10 articles per shard) + parent-driven `synthesizer` merge pass | all articles | `{stack}/glossary.md`, `{stack}/invariants.md`, `{stack}/contradictions.md` |
| A2b | bash wikilink pass (shared helper) | articles + glossary | articles mutated in-place |
| A3 | parent-side parallel `findings-analyst` shards (≤3 articles per shard) + parent-side deterministic python merge | articles (inline marks are the data source), contradictions, prior `findings.md` | `dev/audit/findings.md` |
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

An audit pass is empty when: zero items with `resolvable_by: audit-stack` in non-terminal status. Items with `resolvable_by: catalog-sources` (`fetch_source`) or `resolvable_by: external` (`research_question`) are reported but do not block convergence — they queue for the next catalog cycle or external action.

Convergence is reached when ANY of:
- The current pass is empty AND it is `pass_counter == 1` (first-pass-empty short-circuit: no prior resynthesize actions exist to verify, so the "2 consecutive empty" confirmation is trivially satisfied).
- 2 consecutive empty passes (validator changes from a prior resynthesize action did not surface new generative work).
- `MAX_AUDIT_PASSES` from STACK.md reached (default 3).

---

## Feedback flywheel

The loop between the two pipelines closes as follows:

1. `audit-stack` produces `dev/audit/findings.md` (schema v3) with four sections: New Acquisitions (`action: fetch_source`), Articles to Re-Synthesize (`action: resynthesize`), Research Questions (`action: research_question`), and Deferred. Each item carries `status` and `resolvable_by` fields.
2. `catalog-sources` reads prior findings at W0b: it builds a skip list of `extraction_hash` values for already-synthesized content and surfaces generative items (`fetch_source` and `research_question` with identifiable `verification_target`) as new acquisition candidates.
3. `audit-stack` carries item status forward across passes: `applied`, `closed`, `deferred`. A pre-A3 reconcile pass (`scripts/reconcile-findings.py`) auto-closes prior open findings whose claims now validate `[VERIFIED]` or `[DRIFT]`, whose articles were deleted, or whose claim text was rewritten out. A second audit run is differential, not a full re-run from scratch.
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

### W1 + W1b + W2 — Parent-side parallel dispatch

The main session (`catalog-sources` SKILL) shards directly. The `concept-identifier-orchestrator` agent is **deprecated for this skill** because nested Task dispatch was unreliable: when the harness dropped Task on a nested call, the orchestrator silently fell back to inline execution and bundled every shard's work into one context, hitting "Prompt is too long" on stacks the sharding was meant to keep below the ceiling. Parent-side dispatch keeps Task usage shallow and lets the parent run all deterministic pieces (dedup, per-slug split, hash compute, wave gating) as code in the parent process. The orchestrator agent file is kept registered for any external caller still wired to it; do not introduce new callers.

W1 (one `concept-identifier` per source):

- Batch size: 1 source per agent. Per-source isolation matters more than minimizing dispatch count; bundling multiple sources in one agent invites concept-bleed across sources.
- Dispatch: parent emits one Agent call per source in a single message. Each agent receives its assigned source path, `STACK.md`, the existing `articles/` listing (for slug-immutability checks), and the W0b skip list. Each writes one `dev/extractions/batch-{NN}-concepts.md` file with concept blocks (`slug`, `title`, `source_paths`, `target_article`, `tier`, `### Claims`).
- Gate: parent runs `assert-written.sh` per expected batch file after fan-in.

W1b (deterministic in parent, no agent):

- An inline python pass aggregates every concept block from every batch, keyed by slug. For each unique slug it merges `source_paths[]` (set-of-seen with first-seen-order preservation), classifies as `new` or `updated` based on `target_article`, and writes a single canonical `dev/extractions/_dedup.md` plus per-slug `dev/extractions/_dedup-{slug}.md` files.
- An awk pass splits `_dedup.md` into the per-slug files (one block per file, `## Concept:` through next-concept boundary, with `END` flush so the alphabetically-last slug isn't lost).
- `scripts/compute-extraction-hash.sh` computes a stable hash per unique slug using the byte format `{path1}|{path2}|...|{pathN}|{slug}` (paths sorted ascending, `|`-joined, no trailing newline).

W2 (one `article-synthesizer` per unique slug, wave-capped):

- Cap: `W2_WAVE_CAP=25` agents per dispatch wave, sequential waves. Each wave captures its own `DISPATCH_EPOCH_W2_WAVE` so the per-article gate compares each article against the epoch immediately preceding its dispatch.
- Each wave does, in order: (1) inject the wave's slugs' `extraction_hash` into the per-slug dedup files using `${SLUG_HASH[$slug]}` from W1b; (2) capture the wave epoch; (3) dispatch one `article-synthesizer` per slug in a single message; (4) gate every expected article. Hash injection MUST precede dispatch — agents read the per-slug file at dispatch time, so a missing hash field at dispatch yields an article with empty `extraction_hash` frontmatter, breaking the W0b skip-list flywheel for the next catalog run.
- Each agent receives one per-slug dedup file (with hash now present), the existing article if `target_article` is set, and `STACK.md`. First-write frontmatter includes `extraction_hash`, `last_verified=""`, `updated=today`, `sources[]`, `title`, `tags[]`. On re-synthesis, the agent strips prior-cycle inline marks before writing.

Summary write: parent emits `dev/extractions/_w1-w2-summary.json` directly with the schema_version=1 envelope. See [Summary-JSON contract](#summary-json-contract).

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

Parent shards articles into ≤3-article batches and dispatches `validator` agents in parallel (one Agent call per batch in a single parent message). The `validator-orchestrator` agent is **deprecated for this skill** for the same reason as the catalog-sources orchestrator: nested Task was unreliable and the silent fallback to inline execution defeated the sharding.

Before dispatch the parent builds a citation graph:

- `SOURCE_MAP`: slug → path for every file under `sources/` excluding `incoming/` and `trash/` (slug = basename minus `.md`, indexed by basename so catalog-sources W3 file moves do not break audit-time lookup).
- Per article, slug union = frontmatter `sources:` list (entries may be 2-space-indented under YAML convention) plus inline `[source-slug]` refs in the article body.
- Per batch, the parent writes `dev/audit/_a1-sources-{NN}.txt` containing the resolved absolute paths for that batch's slug union. If a batch has zero resolvable citations the parent falls back to the full sources tree so the validator retains a reference surface.

Each validator receives only its batch's article paths and its per-batch source union, not the full tree. Validator strips prior-cycle marks before writing new ones, then writes inline `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` marks in place. Each validator runs `scripts/assert-written.sh` per article it edits. Parent re-runs the gate inline after fan-in and writes `dev/audit/_a1-summary.json` directly (schema_version=1).

Sharding exists because the single-agent validator hit the "Prompt is too long" ceiling at ~75 articles. Per-batch source union (rather than full-tree) exists because validator prompts grow with both article count and source count; citation-graph sharding cuts the source surface each validator sees to the set its articles actually cite. The per-article gate (rather than a directory check) is required because editing files inside a directory does not advance the directory's mtime on Linux.

### A2 — Stack-root artifact synthesis (parent-side shard + merge)

Parent shards articles into ≤10-article batches. The `synthesizer-orchestrator` agent is **deprecated**; parent dispatches `synthesizer` agents in parallel directly.

Phase A (shards): one `synthesizer` per batch writes `dev/audit/_a2-partial-{NN}.md` with three sections (`## Glossary`, `## Invariants`, `## Contradictions`) covering its batch only. Parent gates each partial.

Phase B (merge): parent dispatches one additional `synthesizer` in merge mode that reads all partials, applies cross-shard dedup, independent-corroboration verification, and tier-hierarchy resolution, then writes the three final stack-root files (`glossary.md`, `invariants.md`, `contradictions.md`). Parent gates each.

If the batch count is 1, Phase B is skipped and the single Phase A agent writes the three final stack-root files directly (single mode). The synthesizer agent contract documents all three modes (shard, merge, single).

Smaller per-shard batch (≤10) than the prior orchestrator's 30-cap because per-agent attention to each article matters: a shard producing 25 candidate glossary entries from 30 articles silently misses terms that a shard of 8 articles would catch. Synthesizer reads article bodies only; per-agent context stays small.

Parent writes `dev/audit/_a2-summary.json` directly (schema_version=1).

### A3 — Findings (parent-side shard + deterministic merge)

Pre-dispatch, the parent runs `scripts/reconcile-findings.py` against the prior `dev/audit/findings.md` (no-op if absent). The script closes prior open findings whose claims now carry `[VERIFIED]` or `[DRIFT]`, whose articles were deleted, or whose claim text was rewritten out. Closures land as `status: closed` with `terminal_transitioned_on: $AUDIT_DATE` and a `note:` line. Findings-analyst agents read the post-reconcile findings.md as their carry-forward input.

Parent shards articles into ≤3-article batches and dispatches `findings-analyst` agents in parallel. The `findings-analyst-orchestrator` agent is **deprecated**.

Each agent reads its 1-3 articles' inline marks, the stack-level `contradictions.md`, and the prior `dev/audit/findings.md` (read-only, for carry-forward of terminal-status items by id). Each writes `dev/audit/_a3-partial-{NN}.md` and runs `assert-written.sh`. Parent re-gates each partial after fan-in.

The merge runs as inline python in the parent (no agent): read all partials, split each on `- id:` boundaries, dedup by id with terminal-wins precedence (`applied`, `closed`, `deferred` overrides `open`; latest wins on ties), bucket by status-then-action (`status: deferred` items always route to the Deferred section regardless of action), emit the four canonical sections (`## New Acquisitions` / `## Articles to Re-Synthesize` / `## Research Questions` / `## Deferred`) with frontmatter (`audit_date`, `stack_head`, `pass_counter` incremented, `schema_version: 4`).

Inline python (rather than awk) is mandatory because mawk (default `awk` on Debian/Ubuntu/Mint) silently fails on gawk's 3-arg `match($i, /pat/, m)` form, producing zero-merged findings while the gate still passes (mtime advanced even on empty content). Python avoids the gawk/mawk split entirely.

Parent writes `dev/audit/_a3-summary.json` directly (schema_version=1).

### Summary-JSON contract

The four wave summary files are emitted directly by the parent skill (not by an orchestrator agent):

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

Wave-specific keys live under `counts`: `glossary_terms` / `invariants` / `contradictions` for a2, `new_items` for a3, `n_articles_new` / `n_articles_updated` / `n_w2_waves` for w1-w2. `epochs` carries whatever dispatch epoch(s) the wave captured (w1-w2 carries both `dispatch_epoch_w1` and `dispatch_epoch_w2`).

The parent gate is two-part: (1) the per-shard `assert-written.sh` checks (the parent re-runs them after fan-in independently of any agent-side check), (2) the summary file exists and is non-empty. A failed gate halts the pipeline at that wave.

### A2b — Wikilink pass

```bash
scripts/wikilink-pass.sh {stack}/articles/ {stack}/glossary.md
```

Same shared helper as W2b. Runs after A2 assert-written checks pass.

A3 execution follows A2b (see [A3 — Findings (orchestrator-wrapped)](#a3--findings-orchestrator-wrapped) above).

### A4 — Convergence check

Bash reads `dev/audit/findings.md`. Empty-pass condition: zero items with `resolvable_by: audit-stack` in non-terminal status (`generative_open == 0`). Items with `resolvable_by: catalog-sources` (`fetch_source`) or `resolvable_by: external` (`research_question`) are reported but do not block convergence; looping A1/A2/A3 cannot change them. The `open_count` of all open items is computed for reporting only.

If empty pass and `pass_counter == 1`: convergence (first-pass-empty short-circuit). Proceed to A4.5.
If empty pass and prior pass was also empty: convergence (2 consecutive). Proceed to A4.5.
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

`scripts/rotate-findings.sh` moves items from the active `findings.md` to `dev/audit/findings-archive.md` when they have been in a terminal status (`applied`, `closed`, `deferred`) for `ROTATION_CYCLES` distinct audit cycles or more (default 3, parsed from `STACK.md`). Items carry a `terminal_transitioned_on: YYYY-MM-DD` field set on their first terminal cycle (schema v4); a carry-forward migration block backfills the field to the current `audit_date` on first encounter for v3 items, so no hand-editing is required.

The assert-written gate fires only when `rotated_items > 0`. Zero-rotation runs (common during the stack's first terminal-accumulation cycles) are no-ops. Findings-analyst carry-forward reads the active file only; rotated items drop out of the working set cleanly.

### A5 — Archive

On convergence:

```bash
cp dev/audit/findings.md "dev/audit/closed/$(date +%Y-%m-%d)-findings.md"
# findings.md remains at dev/audit/findings.md as the baseline for the next cycle
```

Archived findings serve as the historical record. The active `findings.md` carries forward into the next catalog-sources W0b pass.
