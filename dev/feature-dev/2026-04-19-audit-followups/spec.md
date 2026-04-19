# Spec: audit follow-ups (epic #38 → #32-#37)

## What we're building

Six orchestrator + audit-pipeline fixes surfaced by the S9 `/ai-ml-tools:context-engineering` audit. Bundled as one epic: they share subsystem ownership (orchestrators, audit-stack, catalog-sources), a common summary-JSON contract, and coupled file edits.

Target version: **0.13.0** (semver-minor; internal contract change + behavior changes, no user-facing skill surface breaks).

## State verification

All 6 sub-issues verified against current tree (stacks master @ 735cb81):

| # | Claim | Verified file:line |
|---|---|---|
| 32 | A2 and A3 still single-dispatch | `skills/audit-stack/SKILL.md:134`, `:167` |
| 33 | Contract divergence, no schema_version | `agents/validator-orchestrator.md:80`, `agents/concept-identifier-orchestrator.md:75,133`; neither file contains `schema_version` |
| 34 | Validator orchestrator explicitly ships full sources | `agents/validator-orchestrator.md:58` |
| 35 | W2 dispatches `N_UNIQUE_CONCEPTS` in one message, no cap | `agents/concept-identifier-orchestrator.md:108` |
| 36 | W1b writes monolithic `_dedup.md` only; article-synthesizer reads aggregated path | `agents/concept-identifier-orchestrator.md:111`, `agents/article-synthesizer.md:16` |
| 37 | A5 archives via `cp`, no rotation/eviction | `skills/audit-stack/SKILL.md:274`; `agents/findings-analyst.md:107-112` (carry-forward, no cycle count) |

All 6 → verdict `verified`. Full pipeline applies; no close-only reclassifications.

## Exploration findings

Relevant files (updated timestamps from last session):

```
agents/
  article-synthesizer.md              # input contract change (#36)
  concept-identifier-orchestrator.md  # W1b split (#36), W2 wave cap (#35), contract (#33)
  findings-analyst.md                 # terminal_transitioned_on field (#37)
  findings-analyst-orchestrator.md    # NEW (#32)
  synthesizer.md                      # unchanged (wrapped by new orchestrator)
  synthesizer-orchestrator.md         # NEW (#32)
  validator-orchestrator.md           # source sharding (#34), contract (#33)
  validator.md                        # per-batch source list input (#34)
skills/
  audit-stack/SKILL.md     # Steps 5/7 dispatch orchestrators (#32); rotation between A4 and A5 (#37); contract-gate parsing (#33)
  catalog-sources/SKILL.md # Step 6 contract-gate parsing (#33)
references/
  wave-engine.md           # reflect all above
scripts/
  assert-written.sh        # unchanged (existing helper)
```

Helper scripts identified for new work:
- `scripts/rotate-findings.sh` (NEW, #37): bash pass between A4 and A5.
- Citation-graph builder lives inline in `validator-orchestrator.md` bash (#34) — no new script file (small enough to stay in the agent prompt).

## Research findings

No external/web research needed. Fully internal change; every mechanism prescribed in the source issues + established by S9 (#30/#27) precedent. Stacks library not applicable (this repo is the tool, not a knowledge library).

Step 6a/6b skipped: fully internal change.
Step 7 problem-solving skipped: approach settled per S9 audit.
Step 8 clarifying: answered (include #37, confirmed).
Step 8.5 auto-skip (a) fired: every sub-issue has explicit Done When with mechanism → no architects.

## Architecture decision

Single design per sub-issue. No design alternatives dispatched (auto-skip 8.5).

### #33 — Unified summary-JSON contract (foundation; ships first)

**Decision.** Every orchestrator writes `$STACK/dev/extractions/_{wave}-summary.json` OR `$STACK/dev/audit/_{wave}-summary.json` (per its pipeline sub-tree) as the single authoritative output. Inline-JSON return text reduced to a minimal receipt line. Every summary JSON uses a uniform envelope:

```json
{
  "schema_version": 1,
  "wave": "a1" | "w1-w2" | "a2" | "a3",
  "status": "ok",
  "counts": { /* wave-specific */ },
  "epochs": { /* wave-specific */ }
}
```

Per-wave `counts`:
- `a1`: `{n_articles, n_batches, articles_per_agent}`
- `w1-w2`: `{n_sources, n_batches_w1, n_concepts_input, n_unique_concepts, n_articles_new, n_articles_updated, n_w2_waves}` (last field added per #35)
- `a2`: `{n_articles, n_batches, glossary_terms, invariants, contradictions}`
- `a3`: `{n_articles, n_batches, new_items, carried_items, rotated_items}`

Per-wave `epochs` (for gate debug only, not read by main session):
- `a1`: `{dispatch_epoch}`
- `w1-w2`: `{dispatch_epoch_w1, dispatch_epoch_w2}`
- `a2`: `{dispatch_epoch}`
- `a3`: `{dispatch_epoch}`

**Failure marker:** single convention `ORCHESTRATOR_FAILED: wave={wave} reason={short}` on stdout; failed paths/ids on stderr.

**Main-session gate:** read the summary file, verify `schema_version == 1`, verify `status == "ok"`, type-check required `counts` fields at their nested paths. Orchestrator's returned text carries a receipt line (`ORCHESTRATOR_OK: wave={wave}`) — fast-fail signal before disk read; structural data lives in the file. Defense-in-depth per CLAUDE.md gotcha.

**Enumerated gate expression changes:**
- `skills/audit-stack/SKILL.md` A1 gate (currently at line 122-130): replace flat `(.n_articles | type) == "number"` with nested path + envelope check: `jq -e '(.schema_version == 1) and (.status == "ok") and (.counts.n_articles | type) == "number"' "$SUMMARY_PATH"`. Receipt parse changes from `grep -oE '\{[^{}]*"n_articles"[^{}]*\}'` to `grep -q '^ORCHESTRATOR_OK: wave=a1'`.
- `skills/catalog-sources/SKILL.md` Step 6 gate (currently at lines 238-249): replace `grep -q '"status".*"ok"'` with `grep -q '^ORCHESTRATOR_OK: wave=w1-w2'`; file-check `jq -e` expression updates to `(.counts.n_articles_new | type) == "number" and (.counts.n_articles_updated | type) == "number" and (.counts.n_sources | type) == "number"`.

**Summary paths:** validator-orchestrator writes `dev/audit/_a1-summary.json`. concept-identifier-orchestrator writes `dev/extractions/_w1-w2-summary.json` (renamed from `_orchestrator-summary.json`). New A2/A3 orchestrators (from #32) follow the same pattern: `dev/audit/_a2-summary.json`, `dev/audit/_a3-summary.json`.

**Migration:** `A1_ORCHESTRATOR_FAILED:` and `CATALOG_ORCHESTRATOR_FAILED:` markers both replaced by the unified `ORCHESTRATOR_FAILED: wave={wave} reason={short}` form.

### #32 — A2 synthesizer-orchestrator + A3 findings-analyst-orchestrator

**Decision.** Two new orchestrator agents, same sharding pattern as validator-orchestrator (cap `ARTICLES_PER_AGENT=15`, shard math `ceil(N/5)` capped at 15). Both use the two-phase reduce pattern because A2 and A3 have cross-article logic that can't be fully sharded.

**A2 (`synthesizer-orchestrator.md`):**
- Shard 1: each `synthesizer` agent over its article slice produces `dev/audit/_a2-partial-{batch_id}.md` — YAML block with three lists: candidate glossary entries (term + definition + source), candidate invariant rules (rule + article-slug + cited source), candidate contradictions (topic + articles + claims).
- Reduce: orchestrator bash pass merges partials:
  - Glossary: dedup on term, STACK.md tier-hierarchy wins for conflicts.
  - Invariants: promote only if rule appears in 2+ articles citing 2+ distinct sources (independence check preserved across shards).
  - Contradictions: dedup on `(article-a, article-b, topic)` triple.
- Writes final `glossary.md`, `invariants.md`, `contradictions.md` at stack root.
- Per-output gate via `assert-written.sh`; summary JSON.
- **Glossary conflict resolution mechanism (resolved):** tier-hierarchy resolution for conflicting glossary definitions is done by a dedicated `synthesizer-merge` sub-agent dispatched after the shard fan-in. The merge agent reads all `_a2-partial-*.md` files + STACK.md and writes the three final stack-root files. This is one extra Claude dispatch, not bash parsing of STACK.md's tier list. Two-phase: shards fan out → one merge agent fans in. Glossary/invariant/contradiction logic that requires tier-awareness stays inside Claude, not in orchestrator bash.

**A3 (`findings-analyst-orchestrator.md`):**
- Shard 1: each `findings-analyst` agent over its article slice + prior findings.md + contradictions.md produces `dev/audit/_a3-partial-{batch_id}.md` — partial findings list with full item shapes (id + all fields).
- Reduce: orchestrator bash pass merges partials:
  - Dedup on `id` (sha256 already stable across shards).
  - Preserve carry-forward: prior findings.md consulted by each shard; merge conflicts on same-id resolved by status-precedence (terminal > open, never regresses).
  - Research-question generation: single extra cross-shard pass over all articles' marks. Kept in the orchestrator as a small Claude-driven final sweep (not in shards, because research questions span article pairs that may land in different shards). Actually simpler: all shards see a lightweight cross-article index (slug → (article, tags[], marks[]) one-liner) via orchestrator-built summary, so each shard can author research questions involving its own articles and any indexed sibling. Dedup by `id` at reduce time.
- Writes final `dev/audit/findings.md` with correct `pass_counter` and schema v3 frontmatter.
- Per-output gate; summary JSON.

Both orchestrators: **single-shard fast path when `N <= 15`** — dispatch one agent, skip the partials-file + merge pass entirely, write final outputs directly. This is the common case on current stacks (mep-stack ~50-100 articles runs as single shard; the reduce pass only fires at 250+). Keeps current-stack complexity identical to today while unblocking scale.

### #36 — Per-slug `_dedup-{slug}.md` split (ships before #35)

**Decision.** W1b inside `concept-identifier-orchestrator` writes two artifacts:
1. `dev/extractions/_dedup.md` — single merged file (audit trail, operator-readable). Unchanged from today.
2. `dev/extractions/_dedup-{slug}.md` — one file per unique slug containing that slug's merged concept block. New.

W2 dispatch passes the per-slug file path as the task content; `article-synthesizer` Input section updated to "Read your assigned `_dedup-{slug}.md` file" (one small file, not a 250-block aggregate).

### #35 — W2 wave cap (ships after #36 so waves iterate over per-slug files)

**Decision.** Add constant `W2_WAVE_CAP=25` in `concept-identifier-orchestrator.md`. Wrap W2 dispatch in a wave loop:

```bash
W2_WAVE_CAP=25
i=0
n=${#CONCEPT_SLUGS[@]}
n_w2_waves=0
while (( i < n )); do
  WAVE_SLICE=( "${CONCEPT_SLUGS[@]:i:W2_WAVE_CAP}" )
  DISPATCH_EPOCH_W2_WAVE=$(date +%s)
  # dispatch all W2 agents in WAVE_SLICE in one Task-tool message
  # gate each article in WAVE_SLICE with DISPATCH_EPOCH_W2_WAVE
  ((i += W2_WAVE_CAP)); ((n_w2_waves++))
done
```

Each wave captures its own epoch. Per-article `assert-written.sh` gate runs per wave against that wave's epoch (stale pre-existing files from prior waves still pass correctly because this wave's articles were all written after `DISPATCH_EPOCH_W2_WAVE`). Summary JSON adds `n_w2_waves` (informational).

### #34 — Validator per-batch source union

**Decision.** `validator-orchestrator.md` pre-dispatch bash builds a citation graph:

```bash
# Build slug → path map from sources/
declare -A SOURCE_MAP
while IFS= read -r src; do
  slug=$(basename "$src" .md)
  SOURCE_MAP[$slug]="$src"
done < <(find "$STACK/sources" -type f -name '*.md' \
  -not -path '*/incoming/*' -not -path '*/trash/*')

# Per article, extract cited slugs from frontmatter sources: and inline [slug] refs
for article in "${ARTICLES[@]}"; do
  frontmatter_slugs=$(awk '/^sources:/{found=1; next} found && /^  - /{print $2} found && !/^  -/{exit}' "$article" | xargs -I{} basename {} .md)
  inline_slugs=$(grep -oE '\[[a-z0-9-]+\]' "$article" | tr -d '[]' | sort -u)
  # Union and resolve via SOURCE_MAP
done

# For each batch, union its articles' cited-slug paths into ARTICLE_SOURCES_FOR_BATCH[idx]
```

Each validator agent receives only `ARTICLE_SOURCES_FOR_BATCH[idx]` paths as its sources, not the full tree. Falls back to full-tree if any article has zero resolvable citations (defense: articles with pure `[UNSOURCED]` marks have no explicit cites; the validator must still see enough context to verify other marks, so include the full tree for those batches). Worked example added to `validator-orchestrator.md`.

### #37 — findings.md rotation

**Decision.** Three-part change:

1. **`findings-analyst.md` schema update (v3 → v4):** add `terminal_transitioned_on: YYYY-MM-DD` field. Set when the agent first transitions an item into a terminal status. Preserved on carry-forward.
2. **`findings-analyst.md` v3→v4 migration block** (same pattern as v2→v3 at line 113): "When reading a prior-pass item whose status is terminal (`applied`, `closed`, `deferred`, `stale`, `failed`) but which lacks `terminal_transitioned_on` (schema v3 item), set `terminal_transitioned_on` to the current `audit_date` before writing the v4 item. `rotate-findings.sh` then always sees the field populated." No hand-editing of existing findings.md files required; the migration fires automatically on the first A3 pass after the schema bump.
3. **`scripts/rotate-findings.sh` (NEW):** called from `skills/audit-stack/SKILL.md` between A4 convergence decision and A5 archive (only when `converged=1`). Reads `dev/audit/findings.md`, for each terminal-status item computes distinct-audit-date cycles between `terminal_transitioned_on` and current `audit_date` by reading the archive file for prior audit_dates (or counting cycles since `terminal_transitioned_on` using audit_dates it has seen — simplest: the script takes the current `audit_date` as arg, treats missing `terminal_transitioned_on` as `audit_date` itself → cycles=0 → no rotation, safe first-run behavior). If ≥ `ROTATION_CYCLES` (default 3, parsed from `STACK.md` with the same pattern as `MAX_AUDIT_PASSES`), item moves to `dev/audit/findings-archive.md` (append-only, chronological, `## rotated_on: YYYY-MM-DD` headers grouping each batch). Items are removed from active `findings.md`.
4. **Archive write-gate:** after `rotate-findings.sh` runs, if it reports ≥1 item rotated, `skills/audit-stack/SKILL.md` calls `assert-written.sh "$STACK/dev/audit/findings-archive.md" "$DISPATCH_EPOCH" "rotate-findings"` (epoch captured immediately before script invocation). Catches silent archival failure.

Archive is operator-readable history; findings-analyst's carry-forward reads active file only. `schema_version` in frontmatter bumps to v4.

## Constraints

- Plugin version bumps per S9 policy: each sub-issue shipping commit → `0.13.0-alpha.N`; closing commit → clean `0.13.0`. CHANGELOG entries under each alpha header; closing commit rolls them into the final release section.
- All 6 tasks complete before the final version cut.
- `bash scripts/sync-versions.sh` must pass at the final commit (plugin.json + marketplace.json in sync).
- Ship order: **#33 → #32 → #36 → #35 → #34 → #37**. #33 first so all new/edited orchestrators adopt the schema-versioned envelope. #36 before #35 so wave iteration uses per-slug files. #34 independent (validator). #37 independent, final.
- Every agent dispatched by an orchestrator still loads its system prompt from frontmatter. Orchestrators never attempt to inject prompt text. (Existing CLAUDE.md gotcha.)
- Summary JSON is the success observable per CLAUDE.md gotcha ("subagent success observable as returned text, not exit codes"). Keep both file-presence + field type-check defense-in-depth at main-session gates.
- Do not use `jq -e` with `and` over counts (existing CLAUDE.md gotcha — `0` is falsy). All type-check gates use `(.foo | type) == "number"` form.

## Done When

- [ ] `#33` closed: both existing orchestrators write `_{wave}-summary.json` with schema_version=1 envelope. Main-session gates parse file only. Failure markers unified to `ORCHESTRATOR_FAILED: wave=…`.
- [ ] `#32` closed: `synthesizer-orchestrator.md` and `findings-analyst-orchestrator.md` shipped; audit-stack Steps 5 + 7 dispatch them. Both use schema v1 envelope. ARTICLES_PER_AGENT=15.
- [ ] `#36` closed: W1b writes per-slug `_dedup-{slug}.md`; article-synthesizer Input updated; W2 dispatches per-slug paths.
- [ ] `#35` closed: W2 dispatch capped at 25 per wave with loop; `n_w2_waves` in summary JSON.
- [ ] `#34` closed: validator-orchestrator builds citation graph, each batch gets its union only; worked example documented.
- [ ] `#37` closed: findings-analyst schema v4 adds `terminal_transitioned_on`; carry-forward section contains v3→v4 migration rule; `scripts/rotate-findings.sh` runs between A4 and A5; `findings-archive.md` appears on eviction; archive write is gated by `assert-written.sh`.
- [ ] `references/wave-engine.md` reflects all of the above.
- [ ] `CHANGELOG.md` has a 0.13.0 section rolled up from alpha entries.
- [ ] `.claude-plugin/plugin.json` + `marketplace.json` both at `0.13.0`; `sync-versions.sh` passes.
- [ ] Final `/a-review` + `/simplify` pass clean.
- [ ] Parent epic `#38` closed referencing final commit SHA.
