# Pipeline Blockers — Scale, Contracts, Convergence

Epic: [#31](https://github.com/chuggies510/stacks/issues/31). Six sub-issues that collectively block library-stack migration onto realistically-sized stacks (swe ~70 articles, mep-split ~100+ sources each).

## What we're building

Six mechanical fixes to the catalog-sources and audit-stack pipelines so a clean cycle can run end-to-end on 50-100+ item stacks without context walls, silent contract violations, or wasted convergence loops.

## Sub-issues in scope

| # | Pain | Fix shape |
|---|------|-----------|
| #23 | article-synthesizer ships `extraction_hash: ""`; skip-list flywheel non-functional | Helper script computes sha256; W1b invokes it; agent prose stops claiming "computed downstream" |
| #25 | Parallel article-synthesizer dispatches emit drifting tags (`bash` / `bash-scripting`) | STACK.md declares canonical tag list; post-W2 normalizer sweep rewrites outliers |
| #26 | W1 has no batching rule — 107-source stack would dispatch 107 parallel agents | `ceil(N/5)` agents, capped at 10 sources/agent; below `N=10`, one-per-source |
| #27 | Main-session context accumulates agent summaries at scale | `concept-identifier-orchestrator` sub-agent wraps W1+W1b+W2; main session sees one summary |
| #29 | A4 convergence blocks on `fetch_source` items audit-stack cannot resolve | Add `resolvable_by: {audit-stack, catalog-sources, external}` to findings items; A4 counts only `audit-stack` items |
| #30 | A1 single validator hits "Prompt is too long" at 75 articles | Shard articles `ceil(N/5)` capped at 15/agent; `validator-orchestrator` sub-agent mirrors #27 pattern |

## State verification

Each sub-issue's claim grepped against current files before authoring:

| # | Verified at | Verdict |
|---|------------|---------|
| #23 | `agents/concept-identifier.md:29`, `skills/catalog-sources/SKILL.md:260-310` (W1b awk never touches hash_inputs), `agents/article-synthesizer.md:16` | verified-broken |
| #25 | `agents/article-synthesizer.md:34-36` (tags block — no vocabulary), `skills/catalog-sources/SKILL.md:398-406` (W4 groups by `tags[0]` with zero normalization) | verified-broken |
| #26 | `skills/catalog-sources/SKILL.md:233,243` (comment-only "one per source or per batch") | verified-broken |
| #27 | `skills/catalog-sources/SKILL.md` — W1, W1b, W2, W2b, W3, W4 all inline in main-session orchestrator; no wrapper agent exists | verified-broken |
| #29 | `skills/audit-stack/SKILL.md:214-227` (awk counts `fetch_source` toward `generative_open`) | verified-broken |
| #30 | `skills/audit-stack/SKILL.md:110` (single validator with full article+source set) | verified-broken |

All 6 verified; none pre-closed.

## Exploration findings

Dispatch architecture (three explorers, full details in session log):

- **Dispatch sites**: every agent dispatch is gated by `scripts/assert-written.sh` with `test -s` + mtime>dispatch_epoch (18 lines, `scripts/assert-written.sh:1-18`). Per-article dispatch works; per-directory does not (Linux mtime behavior).
- **Agent output contracts**:
  - concept-identifier writes `dev/extractions/{source-slug}-concepts.md` (one file per source batch, contains N concept blocks)
  - article-synthesizer writes `articles/{slug}.md` (one file per unique slug)
  - validator edits `articles/*.md` in-place (no new file)
  - synthesizer writes `glossary.md`, `invariants.md`, `contradictions.md`
  - findings-analyst writes `dev/audit/findings.md`
- **W1b dedup awk** (`skills/catalog-sources/SKILL.md:277-303`) groups by slug across all `*-concepts.md` files regardless of how many sources each contains. Multi-source batching is awk-compatible; the only change is the gate-loop's expected-output path list (batch slugs instead of source slugs).
- **Wrapper-agent precedent**: `~/2_project-files/projects/active-projects/ChuggiesMart/workspace-toolkit/skills/resolve-issues-auto/SKILL.md:77-117` — splits N issues into batches of 10, one general-purpose agent per batch, merges JSON responses. Template for #27 and #30 wrappers.
- **extraction_hash data flow**: concept-identifier outputs `hash_inputs: [source-path, concept-slug]`; W1b awk drops the field silently; article-synthesizer assumes `extraction_hash` is pre-computed and writes `""`; W0b reads `extraction_hash` from terminal-status findings items into the skip list; empty hashes match on empty string → skip list non-functional.
- **Tag handling**: article-synthesizer chooses tags by free-form judgment per article with no vocabulary input. W4 MoC regen (`SKILL.md:398-406`) groups articles by `tags[0]`.
- **Convergence state**: `generative_open` awk block (`audit-stack/SKILL.md:214-227`) counts both `fetch_source` and `research_question` toward the blocker count. Convergence definition is duplicated in three places: A4 bash, `agents/findings-analyst.md:100-102`, `references/wave-engine.md:97-99` — must stay synchronized.

## Research findings

**Stacks library** (`~/2_project-files/library-stack/swe/topics/`): five takeaways cross-cut the multi-agent-pipeline-design, skill-prompt-engineering, knowledge-system-design, and engineering-practices guides:

1. **Computational logic must not live in inferential prompts.** `extraction_hash` (sha256 of slug+path) is deterministic; belongs in a bash helper, not agent prose. Same principle for tag canonicalization and convergence filtering.
2. **Output gates check `[[ -s ]]`, not `[[ -f ]]`** — already the convention via `assert-written.sh`; new wrappers must preserve it.
3. **Parallel agents cannot coordinate in-flight**; cross-file consistency requires a post-dispatch sweep. Direct implication for #25 tag drift.
4. **Parallelism counts must be testable at dispatch time** — `ceil(N/5)` is testable; "decide how many to batch" is not.
5. **Convergence must be verified by an independent mechanism.** Tallying `fetch_source` as generative without checking domain-of-resolution is a structural false positive (#29).

**Web research**:
- Anthropic community consensus on parallel agent count: 3-5 concurrent is the practical sweet spot ([claudefa.st](https://claudefa.st/blog/guide/agents/sub-agent-best-practices), [code.claude.com agent-teams](https://code.claude.com/docs/en/agent-teams)).
- Wrapper-agent / split-and-merge pattern well-documented ([mindstudio.ai split-and-merge](https://www.mindstudio.ai/blog/what-is-claude-code-split-and-merge-pattern-sub-agents-parallel), [github.com/anthropics/claude-code#25818](https://github.com/anthropics/claude-code/issues/25818)).
- Controlled-vocabulary pattern for parallel LLM outputs: declared-in-prompt alone degrades at scale; production systems pair it with a post-hoc normalization sweep ([Karpathy/Obsidian-wiki](https://github.com/Ar9av/obsidian-wiki) taxonomy pattern).

## Architecture decision

**One bundle spec, per-sub-issue architecture decisions below.** No architects dispatched — research converged on one direction per sub-issue; user confirmed three forks (#29 mechanism, batch-size rule, wrapper scope).

### #23 — extraction_hash computed by helper script called from W1b

Introduce `scripts/compute-extraction-hash.sh` taking a `path + slug` concatenation and emitting `sha256sum` of the UTF-8 bytes. Script opens with `set -euo pipefail`; errors to stderr with prefix `COMPUTE_EXTRACTION_HASH:` matching the `AGENT_WRITE_FAILURE:` convention in `scripts/assert-written.sh`.

Invoke from W1b (`skills/catalog-sources/SKILL.md` Step 7) during dedup: for each unique slug, compute `sha256sum <<< "{sorted-source-paths-newline-joined}|{slug}"` and write `extraction_hash: {value}` into the `_dedup.md` block. Remove the `hash_inputs` field from concept-identifier's output contract (it becomes vestigial once hash lands in `_dedup.md`). Files to edit for #23:

- `scripts/compute-extraction-hash.sh` (new)
- `agents/concept-identifier.md:29` — strike "computed downstream"; replace with "hash is computed by `scripts/compute-extraction-hash.sh` during W1b dedup." Also remove `hash_inputs:` blocks from the three example concept blocks at lines 45-47, 72-74, 101-103 (they now have vestigial inputs).
- `agents/article-synthesizer.md:16` — strike "already computed" from the input description; rewrite as "extraction_hash populated by W1b dedup pass."
- `skills/catalog-sources/SKILL.md:260-310` — the W1b awk block; add post-awk bash loop that computes hash per slug and rewrites `_dedup.md` to include `extraction_hash: {value}`.
- `references/wave-engine.md:148` — rewrite concept-block field list; replace `hash_inputs` with `extraction_hash` (and note it is populated by W1b, not by concept-identifier).

Verification: grep a post-catalog article for `extraction_hash: [0-9a-f]{64}` — must match.

### #25 — Declared vocabulary in STACK.md + post-W2 halt-on-drift check

Add a new `## Tag Vocabulary` section to the STACK.md template (`templates/stack/STACK.md`), inserted between the existing `## Filing Rules` section and `## Frontmatter Convention` section. The new section contains an `allowed_tags:` YAML block — an ordered list of canonical tag strings — plus a one-paragraph explainer telling operators these are the values article-synthesizer agents must choose from.

article-synthesizer reads STACK.md (already an input per `agents/article-synthesizer.md:18`). Rewrite the tag-selection prose in that agent's prompt to require tags chosen from the declared `allowed_tags:` list. When the list is absent or empty, emit a warning but allow free-form tags (backward compatibility for existing stacks).

Post-W2 check: `scripts/normalize-tags.sh` reads `allowed_tags:` from STACK.md, greps every `articles/*.md` for `tags[0]` values not in that list, and halts with a `TAG_DRIFT:` stderr error naming every offending `{article-slug}: {offending-tag}` pair. No Levenshtein matching, no auto-rewrite — operators edit the article (or extend `allowed_tags:`) and rerun. This matches the existing `scripts/assert-written.sh` halt-on-failure pattern. The check runs after W2b (wikilink pass), before W3 (source filing). Script opens with `set -euo pipefail`; errors to stderr with prefix `TAG_DRIFT:`.

Files to edit for #25:

- `scripts/normalize-tags.sh` (new)
- `templates/stack/STACK.md` — insert `## Tag Vocabulary` section between `## Filing Rules` and `## Frontmatter Convention`.
- `agents/article-synthesizer.md:34-36` — rewrite tag-selection prose to require values from `allowed_tags:` list in STACK.md.
- `skills/catalog-sources/SKILL.md` — add post-W2b bash invocation of `normalize-tags.sh`; wire into the pipeline between Step 9 (W2b) and Step 10 (W3).

Verification: on a stack with `allowed_tags: [bash, powershell, linux]`, an article emitting `tags: [bash-scripting]` halts the pipeline with a `TAG_DRIFT:` error naming the offending article. Test fixture: `scripts/tests/fixtures/tag-drift/`.

### #26 — Deterministic batch sizing: target 5 agents, cap 10 sources/agent

Replace the prose "one per source or per batch" in `skills/catalog-sources/SKILL.md:233,243` with a concrete bash block that computes batch size first, then agent count:

```bash
if (( N_SOURCES < 10 )); then
  SOURCES_PER_AGENT=1
else
  SOURCES_PER_AGENT=$(( (N_SOURCES + 4) / 5 ))   # ceil(N/5) — target 5 agents
  (( SOURCES_PER_AGENT > 10 )) && SOURCES_PER_AGENT=10
fi
N_AGENTS=$(( (N_SOURCES + SOURCES_PER_AGENT - 1) / SOURCES_PER_AGENT ))  # ceil(N / per-agent)
BATCH_IDS=( $(seq 1 "$N_AGENTS") )
```

Worked examples:
- N=7: below threshold → SOURCES_PER_AGENT=1, N_AGENTS=7 (one-per-source, current behavior)
- N=50: SOURCES_PER_AGENT = ceil(50/5) = 10 (cap holds), N_AGENTS = 5
- N=107: SOURCES_PER_AGENT = ceil(107/5) = 22 → capped at 10, N_AGENTS = ceil(107/10) = 11
- N=10: SOURCES_PER_AGENT = ceil(10/5) = 2, N_AGENTS = 5

Output file naming: batch agents write to `dev/extractions/batch-{batch_id}-concepts.md` for `batch_id` in 1..N_AGENTS. W1b dedup awk already globs `*-concepts.md` — zero change required there.

Gate loop rewrite at `skills/catalog-sources/SKILL.md:250-254`:

```bash
for batch_id in "${BATCH_IDS[@]}"; do
  "$SCRIPTS_DIR/assert-written.sh" \
    "$STACK/dev/extractions/batch-${batch_id}-concepts.md" \
    "${DISPATCH_EPOCH}" \
    "concept-identifier"
done
```

concept-identifier's prompt (`agents/concept-identifier.md`) updates: "you receive N sources (N≥1); produce one merged concepts file at `dev/extractions/batch-{batch_id}-concepts.md` containing concept blocks from all of them." Also remove references to `{source-slug}-concepts.md` as the output path.

Files to edit for #26:
- `skills/catalog-sources/SKILL.md:225-256` — dispatch math bash block + gate loop rewrite
- `agents/concept-identifier.md:30,34` — output path from `{source-slug}-concepts.md` to `batch-{batch_id}-concepts.md`; note that one agent writes one merged file for N sources
- `references/wave-engine.md:18` — W1 output path column in the waves table; update to `batch-{batch_id}-concepts.md`

Note on W3 source filing: W3 (`SKILL.md:355-377`) iterates `sources/incoming/` directly, not the extraction files. Publisher inference reads each source file's frontmatter or filename; it does not depend on the extraction-file naming. Batch naming is invisible to W3.

Verification: on an artificial 50-source stack, dispatch count is 5 agents at 10 sources each.

### #27 — concept-identifier-orchestrator wrapper (wraps W1 + W1b + W2 only)

Introduce `agents/concept-identifier-orchestrator.md` with frontmatter:

```yaml
---
name: concept-identifier-orchestrator
tools: Task, Bash, Glob, Grep, Read, Write
model: sonnet
description: Use when catalog-sources needs to dispatch W1 (concept-identifier batch agents), W1b (dedup + hash compute), and W2 (article-synthesizer per concept) without accumulating agent summaries in the main session. Returns one JSON summary; main session retains W0, W0b, W2b, W3, W4, and commit.
---
```

Tools rationale: `Task` to dispatch child agents, `Bash` to run the W1b dedup awk + `compute-extraction-hash.sh` + per-batch assert-written loop, `Glob` and `Read` to enumerate existing articles and STACK.md, `Write` for the `_dedup.md` scratch file.

Main session dispatches one orchestrator with inputs:
- Source list (from `NEW_SOURCES`)
- Skip-list of extraction hashes (from W0b)
- STACK.md path, articles directory path, dev/extractions directory path
- Scripts dir path (for `compute-extraction-hash.sh`, `assert-written.sh`)
- Agents dir path (for concept-identifier and article-synthesizer prompt files)

Orchestrator performs:
- Compute dispatch math per #26
- W1 dispatch (parallel batch agents)
- W1 gate loop (assert-written per batch file)
- W1b dedup (awk block + compute-extraction-hash.sh per unique slug)
- W2 dispatch (parallel article-synthesizer agents, one per unique slug)
- W2 gate loop (assert-written per article)

Orchestrator returns **one** summary JSON to main session:

```json
{
  "n_sources": 25,
  "n_batches": 5,
  "n_concepts": 47,
  "n_articles_new": 42,
  "n_articles_updated": 5,
  "new_article_slugs": ["slug-a", "slug-b", ...],
  "updated_article_slugs": ["slug-c", ...],
  "failed_articles": []
}
```

Main session retains W0 (enumerate), W0b (skip-list), W2b (wikilink pass), W3 (source filing), W4 (MoC regen), and commit (Step 12). The commit step's bash at `skills/catalog-sources/SKILL.md:437-438` currently dereferences `${NEW_ARTICLE_SLUGS[@]}` / `${UPDATED_ARTICLE_SLUGS[@]}` — arrays that no longer exist in main-session context. Rewrite those two lines to read the integer counts directly from the orchestrator's summary JSON (the orchestrator must parse the JSON it returns and expose `N_ARTICLES_NEW` / `N_ARTICLES_UPDATED` as shell variables in the main session; the cleanest mechanism is for the orchestrator to `Write` the summary to a known path like `$STACK/dev/extractions/_orchestrator-summary.json` and have the main session `jq -r` from it).

Files to edit for #27:
- `agents/concept-identifier-orchestrator.md` (new)
- `skills/catalog-sources/SKILL.md` — replace inline W1/W1b/W2 blocks (Steps 6-8) with a single orchestrator dispatch; keep the orchestrator-summary-write and `jq -r` hand-off for the commit step at `SKILL.md:437-438`.
- `references/wave-engine.md:136-165` — update "Execution" subsection for W1+W1b+W2 to note orchestrator-wrapper pattern.

Verification: on a 25-source stack (svelte-sized), main session context at end of catalog is at least 50% smaller than the pre-refactor baseline. Explicit metric: count of Task-tool-return messages visible to the main session between W0 and the final commit. Pre-refactor: one per batch agent + one per article (~50 for a 25-source stack). Post-refactor: exactly one (the orchestrator summary).

### #29 — `resolvable_by` field on findings items

Schema change (`agents/findings-analyst.md:54-75` item shape): add `resolvable_by: {audit-stack, catalog-sources, external}` to both claim-keyed and question-keyed item shapes. `agents/findings-analyst.md` is designated the **canonical** home for the findings schema; `skills/audit-stack/SKILL.md` and `references/wave-engine.md` reference it rather than duplicate the field list. Emit-time rules:

- `action: fetch_source` → `resolvable_by: catalog-sources` (audit-stack has no fetch capability)
- `action: resynthesize` → `resolvable_by: audit-stack` (re-validation catches the corrected claim on the next pass)
- `action: research_question` → `resolvable_by: external` (requires new material the operator must acquire)
- `action: noop` → `resolvable_by: audit-stack` (already resolved within the pass)

A4 convergence rewrite. The current awk at `skills/audit-stack/SKILL.md:214-227` counts items where action is `fetch_source` OR `research_question` AND status is non-terminal. Replace that filter with: **count items where `resolvable_by == audit-stack` AND status is non-terminal.** In practice only `resynthesize` (and lingering `noop`) ever hit this filter, which is the correct convergence signal — resynthesize work is done by audit-stack itself; fetch_source and research_question work is not.

Rewritten awk (to be applied verbatim at SKILL.md:214-227):

```bash
generative_open=$(awk '
  /^- id:/ {
    if (in_item && resolvable == "audit-stack" && status != "terminal") count++
    in_item=1; resolvable=""; status=""
    next
  }
  in_item && /resolvable_by: audit-stack/ { resolvable="audit-stack" }
  in_item && /status: (applied|closed|deferred|stale|failed)/ { status="terminal" }
  END {
    if (in_item && resolvable == "audit-stack" && status != "terminal") count++
    print count+0
  }
' "$FINDINGS" 2>/dev/null || echo "0")
```

Updated convergence prose (to be applied verbatim at `agents/findings-analyst.md:100-102` and `references/wave-engine.md:97-99`):

> An audit pass is empty when: zero items with `status: open` AND zero items with `resolvable_by: audit-stack` in non-terminal status. Items with `resolvable_by: catalog-sources` (`fetch_source`) or `resolvable_by: external` (`research_question`) are reported but do not block convergence — they queue for the next catalog cycle or external action.

**Intentional behavior change: `research_question` items no longer block audit-stack convergence** (they previously did, via the combined fetch_source-OR-research_question filter). Rationale: research questions require new material or external verification; audit-stack cannot resolve them by re-dispatching A1-A3. Operators see them in the findings summary at Step 10; they persist in the active `findings.md` until resolved manually or carried forward by a subsequent audit that closes them.

Schema migration: existing `findings.md` files under `schema_version: 2` lack `resolvable_by`. Bump to `schema_version: 3`; findings-analyst's carry-forward rule (`agents/findings-analyst.md:90-96`) is extended: when the prior-pass item lacks `resolvable_by`, fill it using the default-by-action rules above before emitting the new item. This means the first v3 audit pass on an existing stack auto-populates the field for every carried-forward item. No hand-migration required.

Files to edit for #29:
- `agents/findings-analyst.md:54-75` — add `resolvable_by` to both item shapes
- `agents/findings-analyst.md:90-96` — extend carry-forward rule with v2→v3 field promotion
- `agents/findings-analyst.md:100-102` — updated convergence prose (verbatim text above)
- `agents/findings-analyst.md:27-33` — bump frontmatter `schema_version` from 2 to 3 in the template
- `skills/audit-stack/SKILL.md:174-183` — update schema_version reference and note that findings-analyst is canonical schema home
- `skills/audit-stack/SKILL.md:214-227` — replace A4 awk with the rewritten version above
- `references/wave-engine.md:97-99` — updated convergence prose (verbatim text above)

Verification: on a freshly-cataloged 11-article stack with only `fetch_source` UNSOURCED items, A4 converges on pass 1 (not pass 3 budget-cap). Also verify with a stack that has only `research_question` items — same result.

### #30 — Sharded validator + validator-orchestrator wrapper

Mirror the #26 + #27 pattern on the audit side. Introduce `agents/validator-orchestrator.md` with frontmatter:

```yaml
---
name: validator-orchestrator
tools: Task, Bash, Glob, Read
model: sonnet
description: Use when audit-stack A1 needs to shard validator dispatches across a large article set without accumulating per-agent summaries in the main session. Returns one JSON summary with mark distribution.
---
```

Tools rationale: `Task` to dispatch child validators, `Bash` for dispatch math + assert-written loop, `Glob` + `Read` for article enumeration. No `Write` because the orchestrator only reads; the validators themselves edit articles in place.

Main session A1 dispatches one orchestrator with:
- Articles list (from `EXPECTED_ARTICLES`)
- Sources directory (passed in full — each per-batch validator gets all sources, because any article in its shard may cite any source)
- STACK.md path
- Scripts dir, agents dir paths

Orchestrator dispatch math (mirrors #26 shape):

```bash
if (( N_ARTICLES < 15 )); then
  ARTICLES_PER_AGENT="$N_ARTICLES"
  N_AGENTS=1
else
  ARTICLES_PER_AGENT=$(( (N_ARTICLES + 4) / 5 ))  # ceil(N/5) — target 5 agents
  (( ARTICLES_PER_AGENT > 15 )) && ARTICLES_PER_AGENT=15
  N_AGENTS=$(( (N_ARTICLES + ARTICLES_PER_AGENT - 1) / ARTICLES_PER_AGENT ))
fi
```

Worked examples:
- N=11 (sysops): ARTICLES_PER_AGENT=11, N_AGENTS=1 (single-validator, current behavior)
- N=75 (svelte): ARTICLES_PER_AGENT=15, N_AGENTS=5
- N=250 (pre-split mep): ARTICLES_PER_AGENT=15 (capped), N_AGENTS=17

Orchestrator performs:
- Parallel validator dispatches (unchanged `agents/validator.md` prompt; each validator receives a shard of articles + all sources + STACK.md)
- Per-article assert-written gate loop (unchanged from current A1 at `skills/audit-stack/SKILL.md:117-127`)
- Returns one summary JSON: `{n_articles_validated, n_agents, mark_distribution: {VERIFIED, DRIFT, UNSOURCED, STALE}, failed_articles: []}`

Each per-batch validator receives the **full** `sources/` directory (not a source shard). Rationale: a validator checking article X must follow any inline `[source-slug]` citation in X, and those citations may reference sources that also appear in other articles' shards. Sharding sources would break validator correctness.

A2 (synthesizer), A2b, A3 (findings-analyst) are unchanged. They already receive the full article set and their context pressure is a separate concern out of scope for this epic.

Files to edit for #30:
- `agents/validator-orchestrator.md` (new)
- `skills/audit-stack/SKILL.md:103-127` — replace the inline single-validator dispatch with an orchestrator dispatch; keep the per-article assert-written gate loop as-is (the orchestrator invokes it, not the main session — main session now only asserts the orchestrator's own return, which is implicit in the orchestrator's successful exit)
- `references/wave-engine.md:192-210` — update A1 execution prose to describe the orchestrator pattern

Verification: on a 75-article stack, dispatch count is 5 agents at 15 articles each. The full A1 pass completes without "Prompt is too long" on any single validator. Main-session context budget during A1 drops to one Task return instead of 171 tool-call summaries.

## Constraints

- **`assert-written.sh` is non-negotiable.** Every new agent dispatch (concept-identifier batches, validator batches, orchestrators themselves) is gated by per-file `test -s + mtime > epoch` checks. Directory paths do not count. `scripts/assert-written.sh:1-18` is the only correct usage.
- **Slug immutability** (`references/wave-engine.md:71-73`): batch-mode concept-identifier must still honor slug immutability when an existing `articles/{slug}.md` matches. Multi-source batching does not relax this.
- **W1b dedup awk is gawk-specific.** `skills/catalog-sources/SKILL.md:313` notes mawk incompatibility. Any new awk this epic introduces must preserve gawk compatibility or document a python fallback.
- **Convergence definition in three files.** Any change to A4 must update `skills/audit-stack/SKILL.md`, `agents/findings-analyst.md`, and `references/wave-engine.md` together. Plan must enumerate all three as files-to-edit.
- **gotcha: directory mtime does NOT advance on in-place file edits (Linux).** CLAUDE.md gotcha. `assert-written.sh` usage must pass per-file paths, never directories.
- **gotcha: parallel agent verify side-effects destroy sibling work.** CLAUDE.md gotcha. None of the new validators/orchestrators can run a verify-command that mutates global state (git, fixture dirs). Verify commands stay read-only — grep, jq, wc.
- **Alpha versioning per sub-issue.** Plugin is at 0.11.1. This epic ships 6 functional sub-issues; plan uses `0.12.0-alpha.1` through `0.12.0-alpha.6` (one per sub-issue commit), then a seventh commit bumps to clean `0.12.0` with the rolled-up CHANGELOG entry. Matches the S6 pattern (0.9.0-alpha.1 through alpha.3, then 0.9.0). (`.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` must stay in sync per CLAUDE.md.)
- **Single git repo, no cross-repo.** All work in `stacks/`. No worktree needed — master branch is fine per S6 precedent.

## Done When

- **All 6 sub-issues closed.** Each closes via `issue-close-protocol.md` with the commit SHA for its implementation.
- **End-to-end migration test**: swe stack (~70 articles if post-catalog; or as-inferred from merged-in sources) can be cataloged-then-audited without manual recovery. If no swe-sized library is handy, the verification substitutes a synthetic fixture (`dev/feature-dev/2026-04-19-pipeline-blockers/fixtures/` with N=50 sources and M=75 articles).
- **Measurable outcomes**:
  - A 50-source catalog dispatch creates ≤10 parallel concept-identifier agents (not 50)
  - A 75-article A1 validator dispatch creates ≤5 parallel validator agents (not 1)
  - Main session context budget at end-of-catalog on a 25-source stack drops by at least 50% versus pre-refactor baseline
  - `articles/{slug}.md` frontmatter contains a non-empty 64-character `extraction_hash`
  - A stack with `allowed_tags: [a, b, c]` either converges on those tags or halts with TAG_DRIFT
  - A first-audit pass with only `fetch_source` UNSOURCED items converges on pass 1 (archives to `dev/audit/closed/`)
- **Plugin shipped at 0.12.0** with CHANGELOG entries per alpha version rolled into the final release section.
- **Documentation sync**: `references/wave-engine.md`, `agents/findings-analyst.md`, and `skills/audit-stack/SKILL.md` all carry the `resolvable_by` schema. No drift between the three files (grep-verifiable).
