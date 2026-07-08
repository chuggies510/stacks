# Decision Log

| ID | Date | Title | Status | Session | Issue |
|----|------|-------|--------|---------|-------|
| ADR-001 | 2026-07-07 | Pipeline orchestration substrate: per-pipeline prep\|gate\|finish scripts, Workflow deferred | Active | 17 | #87 |

### ADR-001: Pipeline orchestration substrate: per-pipeline prep|gate|finish scripts, Workflow deferred

**Date**: 2026-07-07 | **Session**: 17 | **Status**: Active

**Context**: The catalog/audit/enrich pipelines ran their deterministic control flow (arg parse, sharding, gating, dedup) as bash prose across SKILL.md Bash blocks, but the harness wipes shell env between blocks, so state silently evaporated (#72); the gates proved a file was written, not that every dispatched item was processed (#71); and the fan-out was hand-copied per skill (#76).

**Decision**: One checked-in orchestration script per pipeline (`scripts/pipeline/{catalog,audit,enrich}.sh`) with `prep|gate|finish` phase subcommands, mirroring `ingest-book` Step 3B. State crosses phases through files under `dev/<phase>/` (`run.env`, `dispatch.tsv`), never shell env. Model fan-out stays skill prose. A shared `check-coverage.sh` reconciles dispatched ids against per-item receipt rows. One `references/article-contract.md` SSOT replaces five drifted schema restatements. Full design in `dev/specs/pipeline-orchestration-ssot.md`; 10-task plan in `dev/plans/pipeline-orchestration-ssot.md`.

**Alternatives**: Workflow-tool-only (rejected — a workflow script has no filesystem/Bash access, so gates/dedup/staging/commits can't live there; confirmed first-party). Migrating fan-out to the Workflow tool was measured head-to-head against parallel-`Agent` dispatch on a live 15-gap enrich run (T6, Session 18): substrate-neutral on tokens/wall-clock/yield, its schema-robustness and context-isolation wins already gate-backstopped and only binding at ~100-item fan-out — so Workflow is deferred and Agent-calls retained for all three pipelines (T9 resolved, no code; record in `dev/t6-measurement/decision.md`). Python orchestrators (rejected — every existing helper is bash).

**Consequences**: All three pipelines shipped (enrich 0.46.0, audit 0.47.0, catalog 0.48.0). `check-coverage.sh` hardened after a codex review found three false-pass holes (0.45.1). A per-batch reconciliation gap remains (#92). Epic #87 closed Session 18 with #72/#71/#76; #77 stays open for its downstream schema sub-issues (#88-#91, of which #91 was closed as misfiled).
