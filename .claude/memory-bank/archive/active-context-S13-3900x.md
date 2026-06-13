---
session: 13
---

# stacks Active Context

## Current state

- Plugin at 0.19.1 (versions synced in plugin.json + marketplace.json). 0.20.0 still reserved for Phase 3+4.
- Phase 2 shipped (#50 assert-structure gates, #5 cross-stack ask). No live-pipeline changes since.
- Phase 3+4 plan written, a-reviewed, all 4 tasks pending: `dev/superpowers/plans/2026-05-10-stacks-phase3-4.md`.
- Agent roster is now 5 workers only (the 4 orchestrator stubs were deleted this session).
- New shared pipeline scripts in play: `gate-batch.sh`, `shard-batches.sh`, `collision-dest.sh`.

## Next priority

Execute the Phase 3+4 plan (all 4 tasks, ships as 0.20.0): `dev/superpowers/plans/2026-05-10-stacks-phase3-4.md`. Backlog otherwise: 7 open issues, one bug (`#52` wikilink-pass.sh corrupting source paths in YAML frontmatter when a glossary term matches inside a filename) and six features (`#51 #40 #18 #14 #10 #7`). `#52` is the only correctness item if a quick win is preferred over the plan.

---

## CONTEXT HANDOFF - 2026-06-12 (Session 13)

### Session summary

Whole-plugin ponytail (over-engineering) review, then applied in full. Ran a 4-agent parallel review (bash / python / agents / skills), synthesized a tiered findings list, and on the user's "do it all" applied every tier via 6 parallel sonnet agents partitioned by file ownership (no two agents touched the same file), plus an integration pass.

Spine (2 commits before this handoff):
- `2d52d3f` — start-brief.md self-heal at session start (it was `needs-generation`).
- `fd9757a` — the cleanup sweep itself (0.19.1, 36 files).

Headline cuts: deleted the four no-op orchestrator agents and scrubbed their stale "live mechanism" prose from system-patterns/tech-context/wave-engine/start-brief (they were deprecated stubs with zero callers; dispatch is parent-side); removed the legacy guide-mode path from `/stacks:ask` (no producer since 0.9.0); dropped the dead `noop` finding action and two one-shot schema-migration paragraphs from findings-analyst. Factored three shared scripts out of copy-pasted skill bash (`gate-batch.sh` 5 sites, `shard-batches.sh` 3 sites, `collision-dest.sh` shared with process-inbox) with a 4-case `tests/gate-batch.bats`. stdlib swaps across the Python/bash helpers.

Two integration overrides made on review and flagged: restored `compute-extraction-hash.sh` after a subagent deleted it (five docs name it as a contract, so deletion relocated cost into five edits rather than simplifying); repointed one stale live-behavior orchestrator reference in `validator.md` to the parent dispatch.

### Chat

S13-ponytail-cleanup-sweep

### Changes made

| Change | Status |
|--------|--------|
| `2d52d3f` start-brief.md self-heal (session-start) | Committed + pushed |
| `fd9757a` ponytail cleanup sweep, 0.19.1, 36 files | Committed + pushed |
| Deleted 4 orchestrator agents + doc trail repointed | In `fd9757a` |
| Guide-mode removed from `/stacks:ask` (~30 lines) | In `fd9757a` |
| 3 shared scripts factored + `tests/gate-batch.bats` | In `fd9757a` |
| `compute-extraction-hash.sh` restored (override) | In `fd9757a` |
| tech-context.md scripts inventory updated (3 new) | This handoff commit |

### Knowledge extracted

- `system-patterns.md` / `tech-context.md` / `references/wave-engine.md`: orchestrator-agent prose rewritten to parent-side sharded dispatch; stale "cross-stack ask is a stub" weak-spot note removed (#5 shipped).
- `tech-context.md` pipeline-helpers table: added `gate-batch.sh`, `shard-batches.sh`, `collision-dest.sh`, plus `assert-structure.sh` to the summary list.
- `CHANGELOG.md`: 0.19.1 entry (Removed / Changed / Internal).
- `start-brief.md` regenerated twice (session start, and Phase 7 after the tech-context currency edit).

### Decisions recorded

No ADRs. Two in-flight judgment calls captured in the commit message and CHANGELOG: keep `compute-extraction-hash.sh` (named contract, 5 references); version as patch 0.19.1 not minor (no live-pipeline behavior change, keeps 0.20.0 free for Phase 3+4).

### Next session priority

Execute Phase 3+4 plan (`dev/superpowers/plans/2026-05-10-stacks-phase3-4.md`, 4 tasks → 0.20.0), or clear `#52` (wikilink-pass YAML-frontmatter corruption) as a quick correctness win first. No homeless work-items filed this session: the one deferred sub-item (W1 zero-source guard collapse) was an explicit won't-do, not a defect — collapsing would have added code, not removed it.

### Open issues

7 open (`#52 #51 #40 #18 #14 #10 #7`). 0 stale specs.
