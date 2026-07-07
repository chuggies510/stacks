# Plan: pipeline orchestration + article contract into checked-in scripts

**Spec:** `dev/specs/pipeline-orchestration-ssot.md` (the orchestration-SSOT epic, #87).
**Slicing:** vertical per pipeline — each migration task lands a whole pipeline (script + SKILL.md shrink + agent receipt contract) so the repo never holds a half-migrated skill. Every task is independently shippable with its own semver bump + CHANGELOG entry.

## Dependency graph

```
T1 CAP=5 (standalone) ──────────────────────────────┐
T2 article-contract SSOT ──► T3 file #77 sub-issues │
T4 check-coverage.sh + run-state convention         │
        │                                           │
        ├──► T5 enrich pipeline migration ◄─────────┘ (T1 folds in trivially if not yet shipped)
        │           │
        │           └──► T6 Workflow prototype + measurement (decision gate)
        │                       │
        ├──► T7 audit pipeline migration            │
        ├──► T8 catalog pipeline migration          │
        │           └───────────┴──► T9 catalog/audit fan-out substrate per T6 decision
        └──────────────────────────► T10 cleanup + close-out
```

T1 and T2/T3 have no dependencies — start immediately, in parallel if staffed. T4 blocks all migrations. Enrich goes first (single-phase, cleanest, and the Workflow measurement rides it); audit second (simplest coverage win, kills the date-gate); catalog last (most phases).

---

## Task 1 — Enrichment batch size CAP=12 → 5 (standalone)

**Maps to:** the batch-size half of the fan-out issue (#76). **Spec:** Decision 3.
**Files:** `skills/enrich-stack/SKILL.md` (Step 4: `CAP=12` → `CAP=5`, rewrite the surrounding rationale comment in place to cite the batch-size experiment instead of the serial-web-calls argument — rewrite, don't append); `.claude-plugin/{plugin,marketplace}.json` + `CHANGELOG.md` (patch bump).
**Acceptance:** `grep -n 'CAP=' skills/enrich-stack/SKILL.md` shows 5 with the experiment-grounded rationale; no other cap changed (`grep -rn 'CAP=' skills/` — validator stays 3, W2 wave stays 25).
**Verification:** a 12-gap enrich run on the test library dispatches 3 agents (5+5+2), not 1.

## Task 2 — Article-contract SSOT doc + pointer edits

**Maps to:** the schema seam of the drift audit (#77); prerequisite for the receipt-row contracts (T5/T7/T8 agents cite it). **Spec:** Decision 4.
**Files:** new `references/article-contract.md` (frontmatter field table with writer/reader per field, `extraction_hash` ruled dead, bare source-ref form, tier-per-source_path semantics, concept-block format, names `assert-structure.sh` kinds as enforcement); pointer edits in `templates/stack/STACK.md` (replace the wrong Frontmatter Convention + the phantom `/stacks:ingest` mention), `agents/{article-synthesizer,source-extractor,validator,enrichment}.md`, `skills/catalog-sources/SKILL.md` Step 2, `skills/lookup/SKILL.md` Step 7 (fix the prefixed source-ref example against the contract). Minor bump.
**Acceptance:** exactly one file greps for the full frontmatter field list; `templates/stack/STACK.md` no longer contains `sources: 0`, `last_ingested`, or `/stacks:ingest`; every agent definition references the contract path.
**Verification:** catalog one source on the test library; the produced article passes `assert-structure.sh article-md` and its frontmatter matches the contract's field table by eye.

## Task 3 — Split #77's corpus/doc migrations into sub-issues

**Maps to:** the drift audit (#77), non-schema remainder. Depends on T2 (each issue cites the contract as the target state).
**Files:** none (issue filing via `/file-issue`; use `--body-file`, never inline heredoc backticks per dev-layer gotcha). Four issues: source-ref prefix migration across existing stacks + lookup citation fix; `extraction_hash` strip (930 articles); `regenerate-moc.sh` `## Sources` emit-or-stop-promising; stale plugin docs (`CLAUDE.md` agent count/skill list, audit-stack `[STALE]` remnant).
**Acceptance:** four issues open, each naming the contract doc and the affected files; #77 body updated to point at them.

## Task 4 — `check-coverage.sh` + run-state convention (shared substrate)

**Maps to:** the coverage-gate gap (#71, mechanism) + env-persistence root (#72, mechanism). Blocks T5/T7/T8. **Spec:** Decisions 1–2.
**Files:** new `scripts/check-coverage.sh` (`<dispatch.tsv> <output-file>...` → exact set reconciliation; omissions/duplicates/unknowns each fail naming ids; missing file = its ids missing); the `dispatch.tsv` + `run.env` shapes documented in the script header (the convention's home — no separate doc). Patch/minor bump.
**Acceptance (the red-when-broken test):** an inline self-check or `bats`-free demo run against fabricated inputs fails on (a) one dropped id, (b) one duplicated id, (c) one unknown id, (d) one deleted output file — each with the id named — and passes the clean set.
**Verification:** run the self-check; all five cases behave.

### Checkpoint A — substrate review
Human eyeballs T2's contract doc + T4's manifest shapes before any pipeline consumes them; a wrong shape here is built three times.

## Task 5 — Enrich pipeline migration (first vertical slice)

**Maps to:** #72 (enrich) + #71 (enrich) + the fan-out-duplication half of #76. Depends on T4 (+T2 for the agent pointer). **Spec:** Decisions 1–2 table row.
**Files:** new `scripts/pipeline/enrich.sh` (`prep` absorbs Steps 1–3: arg parse incl. `--auto`/`--query`, filed-sources listing, stale-check, writes `dev/enrich/dispatch.tsv` + `run.env` with RUN_ID; `gate` = `gate-batch.sh` + `check-coverage.sh` over gap_ids; `finish` = URL-dedup prep for the operator table + cleanup); `skills/enrich-stack/SKILL.md` (Steps 1–5 + 8 collapse to script calls; Step 6 approval and Step 7 staging stay prose — they are judgment + WebFetch); `agents/enrichment.md` (findings contract: one row per assigned gap_id required — NOSOURCE already exists, so this is stating the coverage obligation + RUN_ID). Minor bump.
**Acceptance:** no Bash block in enrich-stack SKILL.md consumes a prior block's variable (read every fence); T4's mutilation test rerun against a real enrich run's artifacts fails correctly; interactive and `--auto` modes both work.
**Verification:** full enrich run on the test library (seeded soft spots), both modes; deliberately delete one `_enrich-*.md` before `gate` and watch it fail naming that batch's gap_ids.

## Task 6 — Workflow prototype for enrich fan-out + head-to-head measurement

**Maps to:** #76's Done-When (Workflow-based enrich measured; substrate decision recorded). Depends on T5.
**Files:** a checked-in workflow script (location per Workflow tool convention — e.g. `scripts/pipeline/enrich-workflow.js`, final path settled at implementation); `dev/` decision record with the four metrics (tokens, wall-clock, candidate yield, false-positive rate) on the same gap set, Agent-calls vs Workflow. The two spec open items are resolved (Workflow needs explicit opt-in, so the `--auto` path stays a plain Agent call; the fs/Bash bans are confirmed) — this task is now purely the measurement on the explicit multi-gap batch path, no contract-verification prelude.
**Acceptance:** decision record exists with real numbers and a named winner; enrich-stack SKILL.md dispatches via the winner; single-gap `--query` runs stay on a plain Agent call either way.
**Verification:** both substrates run green on the same test-library gap set before the numbers are compared.

### Checkpoint B — substrate decision
The T6 record decides T9. Human confirms before catalog/audit fan-out moves.

## Task 7 — Audit pipeline migration

**Maps to:** #71 (the date-gate headline case) + #72 (audit). Depends on T4; parallel-safe with T5 after Checkpoint A.
**Files:** new `scripts/pipeline/audit.sh` (`prep`: article enum, CAP=3 slices, `dev/audit/dispatch.tsv` + `run.env`; `gate`: gate-batch + check-coverage over `VALIDATED` receipt rows keyed on RUN_ID; `finish`: report.md + soft-spots.tsv aggregation — where a missing `_audit-*.md` now fails instead of `cat 2>/dev/null || true` shrinking the report — log entry prep); `skills/audit-stack/SKILL.md` (Steps 1, 3-gate, 4 collapse to script calls); `agents/validator.md` (emit `VALIDATED<TAB>{slug}<TAB>{RUN_ID}` per article, clean articles included; keep setting `last_verified`); `scripts/assert-structure.sh` (`article-validated` kind retired or re-pointed — the gate no longer keys on today's date; rewrite the kind's comment in place). Minor bump.
**Acceptance:** #71's repro steps go red: same-day second audit with a simulated dropped batch FAILS naming the skipped slugs (was: passed clean); no cross-block variables in audit-stack SKILL.md.
**Verification:** audit test library twice same day, killing one validator's output between runs; gate fails by name. Then a clean run is green.

## Task 8 — Catalog pipeline migration

**Maps to:** #72 (catalog) + #71 (catalog W1/W2). Depends on T4 + T2; last because it has the most phases.
**Files:** new `scripts/pipeline/catalog.sh` (`prep`: arg parse incl. `--from` + multi-stack queue, staging, convert-sources call, W0 enum + paren gate, W1 `dispatch.tsv`; `dedup` phase wrapping `dedup-extractions.py` + structure asserts, emitting W2 wave manifests with per-wave epochs; `gate w1|w2`; `finish`: tag drift, W3 filing + `rewrite-source-refs.sh`, W4 MoC, log+commit); `skills/catalog-sources/SKILL.md` (all bash fences collapse; the near-dup review Step 5.5 stays interactive prose reading the script's NEAR_DUP output); `agents/source-extractor.md` (receipt: one concept-batch file per source is already the per-item output — state the obligation + contract pointer). Minor bump.
**Acceptance:** no cross-block variables in catalog-sources SKILL.md; W2 coverage = expected article set gated per wave (existing gate-batch behavior, now manifest-driven); multi-stack auto-queue and `--from` both still work.
**Verification:** end-to-end catalog on the test library with 3 sources incl. one `--from` staged and one PDF (exercises convert); then the full catalog→audit→enrich cycle green (epic acceptance 6).

## Task 9 — Catalog/audit fan-out substrate per T6 decision

**Maps to:** #76's "decide whether catalog/audit migrate to Workflow, with rationale". Depends on T6 + T7 + T8.
**Files:** if Workflow won: workflow scripts for W1/W2 and A1 mirroring T6's shape, SKILL.md dispatch prose swapped; if Agent calls won: no code — write the recorded rationale into the T6 decision record and close.
**Acceptance:** the decision record covers all three pipelines with rationale; whatever runs is green on the test library.

## Task 10 — Cleanup + close-out

**Maps to:** epic hygiene (#87). Depends on all prior.
**Files:** `.claude/memory-bank/system-patterns.md` (rewrite "Parent-side sharded dispatch", "Write-or-fail gate", and the two Known Weak Spots entries in place — they describe the pre-migration world); plugin `CLAUDE.md` (rewrite the env-persistence gotcha: cross-block env is now structurally avoided, the trap remains for skill authors); CHANGELOG final entry; close #72/#71/#76 individually (`gh issue view N --json state` after — the `Closes #A, #B` keyword only binds the first ref) and the epic; T3's sub-issues stay open under #77.
**Acceptance:** epic-level acceptance criteria 1–6 from the spec all verified with evidence; memory bank matches shipped behavior; stale-doc grep (`grep -rn 'CAP=12\|last_verified == today\|orchestrator agent' .claude/ CLAUDE.md`) comes back clean.

---

## Issue-mapping summary

| Task | Work | Issue |
|------|------|-------|
| T1 | enrichment batch size 5 | #76 (batch size) |
| T2 | article-contract SSOT | #77 (schema seam) |
| T3 | corpus-migration sub-issues | #77 (split) |
| T4 | coverage helper + run-state | #71 + #72 (mechanism) |
| T5 | enrich migration | #72, #71 (enrich) |
| T6 | Workflow measurement | #76 (substrate) |
| T7 | audit migration | #71 (headline), #72 |
| T8 | catalog migration | #72, #71 (catalog) |
| T9 | fan-out decision applied | #76 |
| T10 | cleanup + close | #87 |
