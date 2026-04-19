# Plan — Pipeline Blockers Epic (#31)

Spec: `spec.md` in this directory.

Six sub-issues executed sequentially, one per alpha version. Seventh task promotes to clean `0.12.0`.

## Ordering rationale

Low-risk schema and contract fixes first; wrapper-orchestrator pattern proved on the smallest surface (#30 validator) before extending to the larger surface (#27 catalog). `article-synthesizer.md` edits sequenced to avoid merge conflicts (#23 before #25). Batch math (#26) lands before catalog orchestrator (#27) because the orchestrator invokes it.

```
Task 1 (#29 resolvable_by)      → alpha.1
Task 2 (#23 extraction_hash)    → alpha.2
Task 3 (#25 tag vocabulary)     → alpha.3   (depends on 2: article-synthesizer.md)
Task 4 (#26 batch math)         → alpha.4
Task 5 (#30 validator orchestrator) → alpha.5  (proves wrapper pattern)
Task 6 (#27 catalog orchestrator)   → alpha.6  (applies pattern; uses #23 hash script + #26 batch math)
Task 7 (clean 0.12.0 release)   → 0.12.0
```

## Cross-task conventions

**Script authoring.** Every new script opens with `set -euo pipefail`. Error messages go to stderr with a fixed prefix matching the existing `AGENT_WRITE_FAILURE:` convention in `scripts/assert-written.sh:9`. New scripts: `compute-extraction-hash.sh` (prefix `COMPUTE_EXTRACTION_HASH:`), `normalize-tags.sh` (prefix `TAG_DRIFT:`).

**Per-task commit.** Each task commits its own files (via `git add {listed files}`, not `git add -A`), bumps plugin.json + marketplace.json to the task's alpha version, and appends a CHANGELOG entry under the alpha header. Commit message format:

```
feat({scope}): {short description} (#31, task {N}, closes #{sub-issue})

{2-3 line rationale}

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

**Convergence three-file sync.** Task 1 (#29) touches three files that must stay synchronized for any future change: `agents/findings-analyst.md`, `skills/audit-stack/SKILL.md`, `references/wave-engine.md`. After Task 1 lands, the canonical definition lives in `agents/findings-analyst.md`; the other two reference it. Future tasks that touch convergence must grep all three.

**wave-engine.md contention.** Five of the six tasks edit different sections of `references/wave-engine.md`. Sequential execution avoids merge conflicts. Section ownership:

```bash
# Verify before each task that targets wave-engine.md:
grep -n '^###\|^##' references/wave-engine.md
```

| Task | wave-engine.md section |
|------|------------------------|
| Task 1 #29 | lines 93-99 (Convergence rule) |
| Task 2 #23 | line 148 (W1 output field list) |
| Task 4 #26 | line 18 (waves table W1 row) + lines 136-146 (W1 execution) |
| Task 5 #30 | lines 192-210 (A1 execution) |
| Task 6 #27 | lines 136-165 (W1 + W1b + W2 execution — largest section) |

**SKILL.md contention.** `catalog-sources/SKILL.md` is touched by Tasks 2, 3, 4, and 6. `audit-stack/SKILL.md` is touched by Tasks 1 and 5. Sequential order prevents conflict.

**Verification commands are read-only.** Per CLAUDE.md gotcha "Parallel Agent Verify Side-Effects Destroy Sibling Work," no verifyCommand may mutate state (no `git`, no `rm`, no fixture resets). All checks use `grep`, `awk`, `jq`, `wc`, `test -f`.

---

## Task 1 — #29 resolvable_by schema + A4 awk rewrite

**Goal.** Add `resolvable_by` field to findings-item schema, rewrite A4 convergence awk, document intentional behavior change for research_question items, bump schema_version 2 → 3.

**Files.**

- `agents/findings-analyst.md` — edit lines 27-33 (frontmatter template, schema_version bump), lines 54-75 (both item shapes get new field), lines 90-96 (carry-forward v2→v3 field promotion rule), lines 100-102 (convergence prose verbatim from spec)
- `skills/audit-stack/SKILL.md` — edit lines 174-183 (schema_version 3 reference), lines 214-227 (A4 awk rewrite verbatim from spec)
- `references/wave-engine.md` — edit lines 97-99 (convergence prose verbatim from spec)

**Acceptance criteria.**

1. All three item shapes in findings-analyst.md include `resolvable_by` field with the four-way emit rule.
2. A4 awk filter is `resolvable_by == "audit-stack" AND status != "terminal"` (not the dead filter on `fetch_source|research_question`).
3. Convergence prose identical string in all three files (grep-verifiable).
4. `schema_version: 3` appears in findings-analyst.md frontmatter template and audit-stack/SKILL.md reference.
5. Carry-forward rule explicitly notes v2-to-v3 field promotion.

**Verify command.**

```bash
test -f agents/findings-analyst.md && \
grep -q 'resolvable_by:' agents/findings-analyst.md && \
grep -q 'schema_version: 3' agents/findings-analyst.md && \
grep -q 'resolvable_by == "audit-stack"' skills/audit-stack/SKILL.md && \
grep -qc 'resolvable_by: audit-stack' references/wave-engine.md && \
! grep -qE 'fetch_source or research_question' skills/audit-stack/SKILL.md
```

**Version bump.** plugin.json + marketplace.json to `0.12.0-alpha.1`. CHANGELOG entry under `## 0.12.0-alpha.1 — 2026-04-19`.

---

## Task 2 — #23 extraction_hash helper script + W1b integration

**Goal.** Compute extraction_hash deterministically during W1b; wire into concept-identifier and article-synthesizer contracts. Retire `hash_inputs` field.

**Files.**

- `scripts/compute-extraction-hash.sh` (new) — reads a string from stdin, emits sha256sum; opens with `set -euo pipefail`; stderr prefix `COMPUTE_EXTRACTION_HASH:` on error
- `agents/concept-identifier.md` — edit line 29 (strike "computed downstream"), lines 45-47, 72-74, 101-103 (remove `hash_inputs:` blocks from the three worked examples)
- `agents/article-synthesizer.md` — edit line 16 (rewrite input description; strike "already computed")
- `skills/catalog-sources/SKILL.md` — extend the W1b bash block at lines 260-310 (after the awk block, loop over each unique slug, compute sha256 of sorted-source-paths + slug, Edit the `extraction_hash: {value}` line into the appropriate concept block in `_dedup.md`)
- `references/wave-engine.md` — edit line 148 (W1 output field list: replace `hash_inputs` with `extraction_hash`; note populated by W1b)

**Acceptance criteria.**

1. `scripts/compute-extraction-hash.sh` exists, is executable (`chmod +x`), passes shellcheck if available, and emits a 64-hex-char sha256 given a test string.
2. `agents/concept-identifier.md` has zero `hash_inputs` occurrences.
3. `agents/article-synthesizer.md:16` no longer says "already computed."
4. `skills/catalog-sources/SKILL.md` W1b block invokes `compute-extraction-hash.sh` for each unique slug.
5. `references/wave-engine.md:148` lists `extraction_hash` (not `hash_inputs`).

**Verify command.**

```bash
test -x scripts/compute-extraction-hash.sh && \
[ "$(echo -n "test|slug" | scripts/compute-extraction-hash.sh | wc -c | tr -d ' ')" = "65" ] && \
! grep -q 'hash_inputs' agents/concept-identifier.md && \
! grep -q 'already computed' agents/article-synthesizer.md && \
grep -q 'compute-extraction-hash.sh' skills/catalog-sources/SKILL.md && \
grep -q 'extraction_hash' references/wave-engine.md && \
! grep -q 'hash_inputs' references/wave-engine.md
```

(Note: `wc -c` on sha256 output is 65 — 64 hex chars plus newline.)

**Version bump.** plugin.json + marketplace.json to `0.12.0-alpha.2`. CHANGELOG entry.

---

## Task 3 — #25 tag vocabulary + halt-on-drift check

**Goal.** Declare canonical tag vocabulary in STACK.md template; require article-synthesizer to pick from the list; add post-W2 halt-on-drift script.

**Files.**

- `scripts/normalize-tags.sh` (new) — reads `allowed_tags:` from STACK.md, greps every `articles/*.md` for `tags[0]` not in that list, halts with stderr `TAG_DRIFT:` listing offending article-slug + tag pairs. `set -euo pipefail`. No auto-rewrite.
- `templates/stack/STACK.md` — insert new `## Tag Vocabulary` section between `## Filing Rules` and `## Frontmatter Convention`. Contains `allowed_tags:` YAML block (empty by default, operator fills in) plus a 2-sentence explainer.
- `agents/article-synthesizer.md` — edit lines 34-36 (tag-selection prose). New language: "Tag values MUST be chosen from the `allowed_tags:` list in STACK.md. If that list is absent or empty, emit a console warning 'tag-vocabulary not declared' and proceed with free-form tags (backward compat for stacks that haven't migrated)."
- `skills/catalog-sources/SKILL.md` — insert post-W2b hook (between Step 9 W2b and Step 10 W3) that invokes `normalize-tags.sh`; halt pipeline on non-zero exit.

**Acceptance criteria.**

1. `scripts/normalize-tags.sh` exists, executable, halts with `TAG_DRIFT:` on mismatch, passes on match.
2. `templates/stack/STACK.md` has a `## Tag Vocabulary` section inserted at the correct position.
3. article-synthesizer prompt requires vocabulary-chosen tags with a backward-compat warning fallback.
4. catalog-sources skill invokes normalize-tags.sh between W2b and W3.

**Verify command.**

```bash
test -x scripts/normalize-tags.sh && \
grep -q '^## Tag Vocabulary' templates/stack/STACK.md && \
grep -q 'allowed_tags' templates/stack/STACK.md && \
grep -q 'allowed_tags' agents/article-synthesizer.md && \
grep -q 'normalize-tags.sh' skills/catalog-sources/SKILL.md && \
awk '/^## Filing Rules/,/^## Tag Vocabulary/' templates/stack/STACK.md | grep -q '^## Tag Vocabulary'
```

(Last line verifies ordering: Tag Vocabulary appears after Filing Rules.)

**Version bump.** plugin.json + marketplace.json to `0.12.0-alpha.3`. CHANGELOG entry.

---

## Task 4 — #26 batch math for W1 dispatch

**Goal.** Replace prose batching rule with deterministic bash block; rename extraction file outputs from source-slug to batch-id; update concept-identifier contract.

**Files.**

- `skills/catalog-sources/SKILL.md` — rewrite lines 225-256 (SOURCE_SLUGS block → new dispatch math block producing SOURCES_PER_AGENT, N_AGENTS, BATCH_IDS arrays; rewrite dispatch comment and gate loop to iterate BATCH_IDS)
- `agents/concept-identifier.md` — edit line 30 (output path) and line 34 (output-file description); rewrite to note batch-mode: "You receive N sources (N≥1); write one merged file to `dev/extractions/batch-{batch_id}-concepts.md` containing one concept block per unique concept across those sources."
- `references/wave-engine.md` — edit line 18 (waves table W1 output path), lines 136-146 (W1 execution prose); note batching rule lives in catalog-sources skill.

**Acceptance criteria.**

1. Dispatch math bash block present in catalog-sources/SKILL.md with SOURCES_PER_AGENT + N_AGENTS + BATCH_IDS variables.
2. Gate loop iterates BATCH_IDS, writes to `dev/extractions/batch-{batch_id}-concepts.md`.
3. concept-identifier contract reflects batch-mode output path.
4. wave-engine.md waves table uses `batch-{batch_id}-concepts.md`.
5. Rule for `N_SOURCES < 10` → one-per-source (preserves current small-stack behavior).

**Verify command.**

```bash
grep -q 'SOURCES_PER_AGENT' skills/catalog-sources/SKILL.md && \
grep -q 'BATCH_IDS' skills/catalog-sources/SKILL.md && \
grep -qE 'batch-\$\{?batch_id\}?-concepts\.md' skills/catalog-sources/SKILL.md && \
grep -qE 'batch-\{batch_id\}-concepts\.md' agents/concept-identifier.md && \
grep -qE 'batch-\{batch_id\}-concepts\.md' references/wave-engine.md && \
! grep -qE '\{source-slug\}-concepts\.md' agents/concept-identifier.md
```

**Version bump.** plugin.json + marketplace.json to `0.12.0-alpha.4`. CHANGELOG entry.

---

## Task 5 — #30 validator-orchestrator wrapper

**Goal.** Introduce `agents/validator-orchestrator.md`; replace A1 single-validator dispatch with orchestrator dispatch; shard articles across multiple validators.

**Files.**

- `agents/validator-orchestrator.md` (new) — frontmatter `tools: Task, Bash, Glob, Read`, `model: sonnet`, description starting with "Use when..."; body describes dispatch math (mirror #26 shape, ARTICLES_PER_AGENT capped at 15), per-batch validator Task dispatches, per-article assert-written gate loop, summary JSON return
- `skills/audit-stack/SKILL.md` — rewrite Step 4 (lines 103-127): replace the inline single-validator dispatch with an orchestrator dispatch. Main session dispatches one validator-orchestrator; orchestrator owns the assert-written gate loop (per-article) and returns a JSON summary; main session verifies orchestrator successful exit as implicit gate.
- `references/wave-engine.md` — rewrite A1 section at lines 192-210 to describe orchestrator wrapper pattern.

**Acceptance criteria.**

1. `agents/validator-orchestrator.md` exists with correct frontmatter (4-field: name, tools, model, description).
2. audit-stack Step 4 dispatches validator-orchestrator (not the validator directly).
3. Dispatch math in the orchestrator prompt: `N < 15 → one agent over all`; otherwise `ARTICLES_PER_AGENT = ceil(N/5)` capped at 15.
4. Each per-batch validator receives full sources dir (noted explicitly in the orchestrator prompt to prevent misunderstanding).

**Verify command.**

```bash
test -f agents/validator-orchestrator.md && \
head -6 agents/validator-orchestrator.md | grep -q '^name: validator-orchestrator' && \
head -6 agents/validator-orchestrator.md | grep -q '^tools:.*Task' && \
grep -q 'validator-orchestrator' skills/audit-stack/SKILL.md && \
grep -q 'ARTICLES_PER_AGENT' agents/validator-orchestrator.md && \
grep -q 'validator-orchestrator' references/wave-engine.md
```

**Version bump.** plugin.json + marketplace.json to `0.12.0-alpha.5`. CHANGELOG entry.

---

## Task 6 — #27 concept-identifier-orchestrator wrapper

**Goal.** Introduce `agents/concept-identifier-orchestrator.md`; replace main-session W1/W1b/W2 blocks with a single orchestrator dispatch; plumb summary JSON back for commit-step counts.

**Files.**

- `agents/concept-identifier-orchestrator.md` (new) — frontmatter `tools: Task, Bash, Glob, Grep, Read, Write`, `model: sonnet`, description starting with "Use when..."; body describes dispatch math (reuses #26 rule), W1b dedup awk + compute-extraction-hash.sh invocation, W2 dispatch, summary JSON write to `$STACK/dev/extractions/_orchestrator-summary.json`
- `skills/catalog-sources/SKILL.md` — replace Step 6 (W1 dispatch + gate loop), Step 7 (W1b dedup block), Step 8 (W2 dispatch + gate loop) with a single orchestrator dispatch. Rewrite Step 12 (commit): read counts via `jq -r '.n_articles_new' $STACK/dev/extractions/_orchestrator-summary.json` instead of bash-array dereferences at lines 437-438.
- `references/wave-engine.md` — rewrite W1+W1b+W2 execution prose at lines 136-165 to describe orchestrator wrapper pattern.

**Acceptance criteria.**

1. `agents/concept-identifier-orchestrator.md` exists with correct 4-field frontmatter.
2. catalog-sources Steps 6-8 replaced by orchestrator dispatch.
3. Orchestrator writes `_orchestrator-summary.json` with required fields.
4. Step 12 reads counts via jq from the summary file (not from NEW_ARTICLE_SLUGS bash array).
5. Orchestrator prompt references compute-extraction-hash.sh (from Task 2) and #26 batch math.

**Verify command.**

```bash
test -f agents/concept-identifier-orchestrator.md && \
head -6 agents/concept-identifier-orchestrator.md | grep -q '^name: concept-identifier-orchestrator' && \
grep -q 'concept-identifier-orchestrator' skills/catalog-sources/SKILL.md && \
grep -q '_orchestrator-summary.json' skills/catalog-sources/SKILL.md && \
grep -q 'jq -r .n_articles_new\|jq -r ".n_articles_new"' skills/catalog-sources/SKILL.md && \
! grep -q '\${NEW_ARTICLE_SLUGS\[@\]}' skills/catalog-sources/SKILL.md && \
grep -q 'compute-extraction-hash.sh' agents/concept-identifier-orchestrator.md
```

**Version bump.** plugin.json + marketplace.json to `0.12.0-alpha.6`. CHANGELOG entry.

---

## Task 7 — Clean 0.12.0 release

**Goal.** Promote to clean `0.12.0`. Roll alpha CHANGELOG entries into a single release-notes block.

**Files.**

- `.claude-plugin/plugin.json` — version `0.12.0`
- `.claude-plugin/marketplace.json` — version `0.12.0` (in plugins[0].version)
- `CHANGELOG.md` — insert new `## 0.12.0 — 2026-04-19` header above the alpha entries; write a consolidated release-notes block summarizing all 6 sub-issue fixes. Keep the alpha entries intact for historical record per existing CHANGELOG convention.

**Acceptance criteria.**

1. Both plugin.json and marketplace.json read `0.12.0` (no `-alpha` suffix).
2. CHANGELOG has `## 0.12.0 — 2026-04-19` header with bullet list covering #23, #25, #26, #27, #29, #30.
3. Alpha entries preserved below the release header.

**Verify command.**

```bash
[ "$(jq -r '.version' .claude-plugin/plugin.json)" = "0.12.0" ] && \
[ "$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)" = "0.12.0" ] && \
grep -q '^## 0.12.0 — 2026-04-19' CHANGELOG.md && \
grep -qE '^## 0.12.0-alpha\.[1-6]' CHANGELOG.md
```

**Version bump.** plugin.json + marketplace.json to `0.12.0`. This task's commit IS the version bump.

---

## Closure notes

After Task 7, epic #31 closes via `workspace-toolkit/references/issue-close-protocol.md`. Each sub-issue (#23, #25, #26, #27, #29, #30) closes on its own task's commit SHA during execution; epic #31 closes on Task 7's SHA with a comment summarizing the 6 closed sub-issues.

Per CLAUDE.md: stacks is a directory-source plugin, so no `claude plugin update` cycle. A `git push` from this repo makes the new version active immediately on the next session start.
