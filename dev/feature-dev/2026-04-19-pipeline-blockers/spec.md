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

Introduce `scripts/compute-extraction-hash.sh` taking a `path + slug` concatenation and emitting `sha256sum` of the UTF-8 bytes. Invoke from W1b (`skills/catalog-sources/SKILL.md` Step 7) during dedup: for each unique slug, compute `sha256sum <<< "{sorted-source-paths-newline-joined}|{slug}"` and write `extraction_hash: {value}` into the `_dedup.md` block. Remove the `hash_inputs` field from concept-identifier's output contract (it becomes vestigial once hash lands in `_dedup.md`). Rewrite `agents/article-synthesizer.md:16` — strike "already computed" and re-describe the input as "extraction_hash populated by W1b dedup pass." Rewrite `agents/concept-identifier.md:29` — strike "computed downstream"; replace with "hash is computed by `scripts/compute-extraction-hash.sh` during W1b dedup."

Verification: grep a post-catalog article for `extraction_hash: [0-9a-f]{64}` — must match.

### #25 — Declared vocabulary in STACK.md + post-W2 normalizer sweep

Add `allowed_tags:` block to the STACK.md template (`templates/stack/STACK.md`). The block is an ordered list of canonical tag strings. article-synthesizer reads STACK.md (already an input per `agents/article-synthesizer.md:18`) and the prompt section is rewritten to require tags chosen from the declared vocabulary. This is necessary but not sufficient.

The sufficient mechanism: a deterministic post-W2 `scripts/normalize-tags.sh` that reads every `articles/*.md` tag, checks membership in the declared vocabulary, and emits a diff report. For any tag not in vocabulary, the script falls back to a levenshtein-distance match against vocabulary entries (`{article-tag}: {vocab-match} (distance=N)`). If distance ≤ 2, auto-rewrite in place; otherwise halt with a `TAG_DRIFT` error naming every unresolved tag. The normalizer sweep runs after W2b (wikilink pass), before W3 (source filing). Operators extend the vocabulary by editing STACK.md — no code changes required.

Verification: on a stack with `allowed_tags: [bash, powershell, linux]`, an article emitting `tags: [bash-scripting]` must either be auto-rewritten to `bash` or halt the pipeline. Test fixtures in `scripts/tests/`.

### #26 — Deterministic batch sizing: ceil(N/5) capped at 10 sources/agent

Replace the prose "one per source or per batch" in `skills/catalog-sources/SKILL.md:233,243` with a concrete rule: `N_AGENTS = ceil(min(N_SOURCES, N_SOURCES/5))`, `SOURCES_PER_AGENT = ceil(N_SOURCES / N_AGENTS)`, capped so no single agent receives more than 10 sources. Below `N_SOURCES < 10`, dispatch one agent per source (current behavior — single-agent and batch rules agree at small N). Dispatch math lives in a bash block before W1 dispatch. Output file naming changes: batch agents write to `dev/extractions/batch-{batch-id}-concepts.md` instead of `{source-slug}-concepts.md`. W1b dedup awk already globs `*-concepts.md` — zero change required there. The assert-written gate loop iterates over batch IDs instead of source slugs. concept-identifier's prompt now says "you receive N sources (N≥1); produce one merged concepts file containing concept blocks from all of them."

Verification: on an artificial 50-source stack, dispatch count is 5 (ceil(50/5) = 10; capped to max sources/agent gives 5 agents at 10 sources each).

### #27 — concept-identifier-orchestrator wrapper (wraps W1 + W1b + W2 only)

Introduce `agents/concept-identifier-orchestrator.md`. Main session dispatches one orchestrator with:
- Source list (from `NEW_SOURCES`)
- Skip-list of extraction hashes (from W0b)
- STACK.md path
- Articles-directory listing
- Scripts dir path (so it can call `compute-extraction-hash.sh` and `assert-written.sh`)

Orchestrator performs:
- W1 dispatch using the #26 batching rule (parallel batch agents)
- W1 gate loop (assert-written per batch file)
- W1b dedup (invoking awk block + compute-extraction-hash.sh per unique slug)
- W2 dispatch (parallel article-synthesizer agents, one per unique slug)
- W2 gate loop (assert-written per article)

Orchestrator returns **one** summary to main session: `{n_sources, n_batches, n_concepts, n_articles_new, n_articles_updated, failed_articles[]}`. Main session keeps W0 (enumerate), W0b (skip-list), W2b (wikilink pass), W3 (source filing), W4 (MoC regen), and commit (Step 12) — these are bash-only, small, and benefit from staying visible.

Verification: on a 25-source stack (svelte-sized), main session context at end of catalog is at least 50% smaller than the pre-refactor baseline. Explicit metric: token count of main-session messages between W0 and the final commit message.

### #29 — `resolvable_by` field on findings items

Schema change (`agents/findings-analyst.md:54-75` item shape): add `resolvable_by: {audit-stack, catalog-sources, external}` to both claim-keyed and question-keyed item shapes. Emit-time rules:
- `action: fetch_source` → `resolvable_by: catalog-sources` (always — audit-stack has no fetch capability)
- `action: resynthesize` → `resolvable_by: audit-stack` (re-validation catches the corrected claim next pass)
- `action: research_question` → `resolvable_by: external` (requires new material)
- `action: noop` → `resolvable_by: audit-stack`

A4 convergence awk (`skills/audit-stack/SKILL.md:214-227`) rewritten: `generative_open` counts only items where `resolvable_by == audit-stack` AND action is `fetch_source` or `research_question` in non-terminal status. In practice this means `resynthesize` drives convergence (which never blocks because resynthesize → the article is edited → next pass re-validates). Open `fetch_source` items report but don't block.

Convergence definition must stay synchronized across three files:
- `skills/audit-stack/SKILL.md:214-227` (A4 awk)
- `agents/findings-analyst.md:100-102` (convergence prose)
- `references/wave-engine.md:97-99` (wave-engine spec)

Migration: existing `findings.md` files produced under schema_version: 2 are missing `resolvable_by`. Bump to `schema_version: 3`; findings-analyst promotes missing fields on carry-forward using the default-by-action rules above. No hand-migration of user files required.

Verification: on a freshly-cataloged 11-article stack with only `fetch_source` UNSOURCED items, A4 converges on pass 1 (not pass 3 budget-cap).

### #30 — Sharded validator + validator-orchestrator wrapper

Mirror the #26 + #27 pattern on the audit side. Introduce `agents/validator-orchestrator.md`. Main session A1 dispatches one orchestrator with:
- Articles list (from `EXPECTED_ARTICLES`)
- Sources directory
- STACK.md
- Scripts dir path

Orchestrator performs:
- Dispatch math: `N_AGENTS = ceil(N_ARTICLES / 5)`, `ARTICLES_PER_AGENT = ceil(N_ARTICLES / N_AGENTS)`, capped at 15 articles/agent. Below `N_ARTICLES < 15`, one validator over all (current behavior).
- Parallel validator dispatches (unchanged `agents/validator.md` prompt; each validator now receives a shard of articles instead of the full set)
- Per-article assert-written gate loop (unchanged from current A1)
- Return summary: `{n_articles_validated, mark_distribution: {VERIFIED, DRIFT, UNSOURCED, STALE}, failed_articles[]}`

A2 (synthesizer), A2b, A3 (findings-analyst) are unchanged — they already receive the full article set and their context pressure is a separate concern (out of scope for this epic).

Verification: on a 75-article stack, dispatch count is 5 (ceil(75/5) = 15, capped to 15 articles/agent gives 5 agents). The full A1 pass completes without "Prompt is too long" on any single validator.

## Constraints

- **`assert-written.sh` is non-negotiable.** Every new agent dispatch (concept-identifier batches, validator batches, orchestrators themselves) is gated by per-file `test -s + mtime > epoch` checks. Directory paths do not count. `scripts/assert-written.sh:1-18` is the only correct usage.
- **Slug immutability** (`references/wave-engine.md:71-73`): batch-mode concept-identifier must still honor slug immutability when an existing `articles/{slug}.md` matches. Multi-source batching does not relax this.
- **W1b dedup awk is gawk-specific.** `skills/catalog-sources/SKILL.md:313` notes mawk incompatibility. Any new awk this epic introduces must preserve gawk compatibility or document a python fallback.
- **Convergence definition in three files.** Any change to A4 must update `skills/audit-stack/SKILL.md`, `agents/findings-analyst.md`, and `references/wave-engine.md` together. Plan must enumerate all three as files-to-edit.
- **gotcha: directory mtime does NOT advance on in-place file edits (Linux).** CLAUDE.md gotcha. `assert-written.sh` usage must pass per-file paths, never directories.
- **gotcha: parallel agent verify side-effects destroy sibling work.** CLAUDE.md gotcha. None of the new validators/orchestrators can run a verify-command that mutates global state (git, fixture dirs). Verify commands stay read-only — grep, jq, wc.
- **Alpha versioning per sub-issue.** Plugin is at 0.11.1. This epic ships 6 functional sub-issues; plan uses `0.12.0-alpha.1` through `0.12.0-alpha.5` per sub-issue commit, then clean `0.12.0` on the final commit. (`.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` must stay in sync per CLAUDE.md.)
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
