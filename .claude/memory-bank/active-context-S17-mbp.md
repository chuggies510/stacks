---
session: 17
---

# stacks Active Context

## Current state

- Plugin at **0.46.0**. Epic **#87** (pipeline orchestration → checked-in scripts) is mid-execution: enrich migrated, audit + catalog pending.
- Shipped this session: maintenance skills self-resolve the library (0.44.0); the `check-coverage.sh` per-item coverage gate + `references/article-contract.md` SSOT + enrich `CAP=12→5` (0.45.0); gate hardening after a codex review (0.45.1); the enrich pipeline migrated into `scripts/pipeline/enrich.sh` (`prep|gate|finish`, state via files not shell env) (0.46.0).
- The memory bank was stale at session start (said 0.37.0 / 7 skills); the intervening ingest-book + deep-reference work (0.38–0.43.1) and this session's #87 work are now reconciled into system-patterns.md + tech-context.md.
- `dev/specs/pipeline-orchestration-ssot.md` + `dev/plans/pipeline-orchestration-ssot.md` hold the fable-authored spec + 10-task plan. ADR-001 records the substrate decision.

## Open thread

**Epic #87 execution is in flight — decide the next slice.** The enrich vertical slice is complete and proven (`enrich.sh` + hardened coverage gate + agent receipt contract; self-check 6/6, bats 103). The remaining plan tasks:

- **T7 (audit migration)** and **T8 (catalog migration)** — the two remaining live-pipeline clobber paths. Both now clone the proven `enrich.sh` `prep|gate|finish` template + the hardened `check-coverage.sh`; they are parallel-safe (disjoint skills/scripts). T7 also retires the `last_verified == today` date-gate; T8 has the most phases (W0–W4).
- **T6 (Workflow-vs-Agent measurement for enrich fan-out)** — lower value; current parallel-`Agent` dispatch works, and the `--auto` path is locked to a plain Agent call anyway (Workflow needs explicit opt-in). Defer.

My lean (from this session): fire **T7 + T8 as parallel opus background agents** (clobber paths → session tier), each source-only + smoke-tested, returned for review before landing — exactly the T5 pattern that worked. Surface artifact: `dev/plans/pipeline-orchestration-ssot.md` (Tasks 7, 8; dependency graph + Checkpoint B).

## Next priority

Resolve the open thread first (T7 + T8, or pause). Full backlog for direction-setting — **13 open issues in 3 groups + 4 standalone**:

- **Epic #87** (parent, open) → sub-issues **#72** (shell-state root), **#71** (coverage gate — mechanism shipped, applied to enrich only), **#76** (fan-out dup + CAP; CAP half done). Plus follow-up **#92** (check-coverage reconciles globally, not per-batch — codex-surfaced, low priority).
- **#77** (tracking parent, drift audit) → sub-issues **#88** (source-ref bare-form corpus migration), **#89** (`dedup-extractions.py` per-source tier), **#90** (dead `updated` field fate), **#91** (`regenerate-moc.sh` never emits `## Sources`).
- **Standalone**: **#73** (lookup-miss telemetry can't tell libraries apart — bounded), **#70** (cross-repo knowledge digest — large, cross-repo w/ workspace-toolkit), **#86** (cold-start empty stack from scope — design-first), **#54** (library-only skills load everywhere — design-first).
- Closed this session: #74, #63 (verified already-done), #75 (Evernote — not planned; content already ingested, approach preserved at `docs/proposals/evernote-ingest.md`).

---

## CONTEXT HANDOFF - 2026-07-07 (Session 17)

### Session summary

Started from a stale S16 handoff (0.37.0); the library maintainer had left a fresh backlog of good issues while the tool sat. Triaged and grouped 11 open issues via issues-planner + a problem-solving simplification-cascade pass, then executed. Closed #74 and #63 (both verified already-fixed in code — #63's find-dance was gone, #74 fixed with a 3-skill library-resolver change shipped as 0.44.0). Filed epic **#87** collapsing the pipeline-fragility cluster (#72/#71/#76) and had a **fable** subagent write the spec + plan (`/agent-skills:spec` + `/agent-skills:plan`) into `dev/`; resolved both of its flagged unknowns against the first-party Workflow tool contract. Closed **#75** (Evernote) not-planned and preserved the proven ingest approach as `docs/proposals/evernote-ingest.md` (initially mis-applied to #87 by mistake, reversed cleanly). Executed epic #87 slice 1 via parallel background agents: T1 (CAP=5), T2 (article-contract SSOT + 6 pointer edits), T4 (check-coverage.sh) → 0.45.0; split #77 into #88–#91 (T3); migrated enrich into `scripts/pipeline/enrich.sh` (T5) → 0.46.0. A **codex** review of the 0.45.0 slice found three false-pass holes in the coverage gate (missing-file warn-not-fatal, dup manifest ids deduped, malformed rows) — all fixed and regression-guarded as 0.45.1. During T5 integration, caught and root-fixed a cd-empty-string footgun before it could copy into the audit/catalog migrations. Reopened #71 (a stray commit keyword had closed it prematurely; its fix only covers enrich) and filed #92 (per-batch reconciliation).

### Chat

`S17-pipeline-orchestration-first-slice`

### Changes made

| Change | Status |
|--------|--------|
| 0.44.0 — maintenance skills self-resolve the library (#74), close #74/#63 | shipped `e090ddc` |
| dev/ spec + plan for epic #87 (fable) | shipped `426b37a` |
| docs/proposals/evernote-ingest.md (#75 preserved) | shipped `25920a5` |
| 0.45.0 — check-coverage.sh + article-contract.md SSOT + enrich CAP 12→5 | shipped `ca6b99f` |
| 0.45.1 — harden check-coverage.sh vs 3 codex false-pass holes | shipped `319a95f` |
| 0.46.0 — migrate enrich into scripts/pipeline/enrich.sh (T5) | shipped `db92268` |
| Issues: filed #87, #88–#91, #92; closed #74/#63/#75; reopened #71 | done |

### Knowledge extracted

- `system-patterns.md`: new sections on per-pipeline `prep|gate|finish` orchestration (#87) and the article-contract SSOT; the #72/#71 Known Weak Spots updated to reflect enrich-migrated / audit+catalog-pending.
- `tech-context.md`: added `check-coverage.sh` + `scripts/pipeline/enrich.sh` rows; removed the stale `locate-plugin-root.sh` reference (#63).
- `docs/decisions/decision-log.md`: created; ADR-001 (orchestration substrate).

### Decisions recorded

ADR-001 — hybrid per-pipeline scripts, Workflow fan-out deferred behind a measured prototype.

### Next session priority

Resolve the open thread: **epic #87 T7 (audit) + T8 (catalog) migrations** — parallel opus background agents cloning the enrich.sh template, source-only + smoke-tested, review before landing; then Checkpoint B. T6 (Workflow measurement) deferred. Full 13-issue backlog grouping is in the Next priority section above for direction-setting.

### Open issues

13 open (epic #87 + #72/#71/#76/#92; #77 + #88/#89/#90/#91; standalone #73/#70/#86/#54). No stale specs.
