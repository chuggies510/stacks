---
session: 18
---

# stacks Active Context

## Current state
- Epic #87 (pipeline orchestration + article contract) is complete and closed. All three fan-out pipelines run through `scripts/pipeline/{enrich,audit,catalog}.sh` prep|gate|finish phases, state crossing via `dev/<phase>/` files, per-item coverage gated, no cross-block shell state.
- Plugin at 0.48.0 (no bump this session past T8; T6/T9/T10 touched no deployed artifact).
- Open issues: 10. The #77 schema-reconciliation cluster (#88 bare source-refs, #89 per-source tier collapse, #90 dead `updated` field, #92 per-batch coverage) is the coherent next epic; singletons #54, #70, #73, #86, #93 stand alone.

## Open thread

None, closed clean. The session finished the epic, closed it out, corrected one misfiled issue (#91), and the user yagni'd the one follow-up idea (a source→article reverse-index section in the MoC, which would need #89 fixed first).

## Next priority

No urgent move — the epic is a complete unit. If picking up: the #77 cluster (#88/#89/#90/#92) is the natural next epic; #89 (per-source tier collapse) is the keystone since it blocks both a correct source roster and honest tier display. Otherwise pull any standalone (#93 pure-reference W1 gate, #86 empty-stack cold-start) from the backlog.

---

## CONTEXT HANDOFF - 2026-07-07 (Session 18)

### Session summary

Carried Epic #87 (move pipeline orchestration out of SKILL.md Bash blocks into checked-in scripts) from mid-flight to fully closed across five tasks. **T7** (0.47.0): migrated the audit pipeline into `scripts/pipeline/audit.sh` prep|gate|finish, replacing the `last_verified == today` date-gate with a per-article `VALIDATED` receipt reconciled by `check-coverage.sh --verdict` + a RUN_ID-per-row check; codex found the RUN_ID column was decorative, fixed to gate on it. **T8** (0.48.0): migrated the catalog pipeline into `scripts/pipeline/catalog.sh` queue|prep|gate-w1|dedup|gate-w2|finish — recognized catalog's strict 1:1 item↔file mapping makes gate-batch presence the coverage gate (no check-coverage needed), and a single W2 freshness floor suffices; codex found 7 issues (6 fixed, all manifest-authoritative-not-live-tree), and I fixed a latent set -e+pipefail crash in the shipped enrich.sh URL loop and filed #93. **T6**: ran the Workflow-vs-Agent-calls measurement live on 15 real electrical enrich gaps (both paths, same gap set) — substrate-neutral on all four metrics, decision recorded in `dev/t6-measurement/decision.md`, **Agent-calls retained, Workflow deferred**. **T9**: resolved, no code. **T10**: reconciled system-patterns / start-brief / the plugin CLAUDE.md gotcha to shipped reality, verified all six epic acceptance criteria empirically, closed #72/#71/#76 + the epic. Then, on an open-ended "whatever you think," hunted #91 (claimed MoC missing a `## Sources` section), found it misfiled (the promise is the per-article Sources section — fulfilled 53/53 — not a MoC promise), and closed it with evidence. User yagni'd building a real MoC source roster.

### Chat

S18-pipeline-orchestration-epic-close

### Changes made

| Change | Status |
|--------|--------|
| T7 — audit.sh prep\|gate\|finish + VALIDATED receipt gate (0.47.0) | Committed `7882648` |
| T8 — catalog.sh queue\|prep\|dedup\|gate\|finish + enrich URL-crash fix (0.48.0) | Committed `7245b50` |
| T6 — Workflow-vs-Agent enrich measurement + decision record | Committed `6e301bb` |
| T10 — memory bank reconciled to shipped state, epic closed | Committed `a27278d` |
| ADR-001 updated (T6 measurement outcome, epic closed) + S18 handoff | This commit |
| #91 closed as misfiled (empirical: 53/53 articles have Sources section) | Issue-only, no commit |

### Knowledge extracted

- `system-patterns.md`: rewrote parent-side-dispatch, write-or-fail-gate, orchestration-status, and the two now-resolved Known Weak Spots (T10). `start-brief.md`: epic-complete + coverage-applied (T10). `tech-context.md`: all three pipeline rows (T7/T8). Plugin `CLAUDE.md`: env-persistence gotcha rewritten (structurally avoided by the scripts; trap remains for new skill authors).
- ADR-001: updated Alternatives/Consequences to record the T6 measurement outcome and epic closure.
- Borderline trap NOT codified as a gotcha (Workflow is deferred, not in the shipped path): the Workflow tool delivers `args` JSON-encoded not parsed, needing a defensive `JSON.parse`. Recorded in `dev/t6-measurement/decision.md`.

### Decisions recorded

ADR-001 (updated) — Workflow fan-out substrate measured and deferred; Agent-calls retained for all three pipelines. Full record in `dev/t6-measurement/decision.md`.

### Next session priority

Epic #87 done, no urgent carry. Natural next epic is the #77 schema-reconciliation cluster (#88/#89/#90/#92), keystone #89. Standalones #93/#86/#73/#70/#54 available.

### Open issues

10 open (#54, #70, #73, #77, #86, #88, #89, #90, #92, #93). No stale specs.
