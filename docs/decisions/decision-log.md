# Decision Log

| ID | Date | Title | Status | Session | Issue |
|----|------|-------|--------|---------|-------|
| ADR-001 | 2026-07-07 | Pipeline orchestration substrate: per-pipeline prep\|gate\|finish scripts, Workflow deferred | Active | 17 | #87 |

### ADR-001: Pipeline orchestration substrate: per-pipeline prep|gate|finish scripts, Workflow deferred

**Date**: 2026-07-07 | **Session**: 17 | **Status**: Active

**Context**: The catalog/audit/enrich pipelines ran their deterministic control flow (arg parse, sharding, gating, dedup) as bash prose across SKILL.md Bash blocks, but the harness wipes shell env between blocks, so state silently evaporated (#72); the gates proved a file was written, not that every dispatched item was processed (#71); and the fan-out was hand-copied per skill (#76).

**Decision**: One checked-in orchestration script per pipeline (`scripts/pipeline/{catalog,audit,enrich}.sh`) with `prep|gate|finish` phase subcommands, mirroring `ingest-book` Step 3B. State crosses phases through files under `dev/<phase>/` (`run.env`, `dispatch.tsv`), never shell env. Model fan-out stays skill prose. A shared `check-coverage.sh` reconciles dispatched ids against per-item receipt rows. One `references/article-contract.md` SSOT replaces five drifted schema restatements. Full design in `dev/specs/pipeline-orchestration-ssot.md`; 10-task plan in `dev/plans/pipeline-orchestration-ssot.md`.

**Alternatives**: Workflow-tool-only (rejected — a workflow script has no filesystem/Bash access, so gates/dedup/staging/commits can't live there; confirmed first-party). Migrating fan-out to the Workflow tool is deferred behind a measured enrich prototype (T6), not adopted yet — the current parallel-`Agent` dispatch works. Python orchestrators (rejected — every existing helper is bash).

**Consequences**: Enrich shipped (0.46.0); audit (T7) and catalog (T8) pending. `check-coverage.sh` hardened after a codex review found three false-pass holes (0.45.1). A per-batch reconciliation gap remains (#92). The epic (#87) stays open until all three pipelines migrate.
