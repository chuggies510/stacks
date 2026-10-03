---
session: 7
---

# stacks Active Context

## Current Work Focus

### Current State
- Plugin at 0.11.1 (plugin.json + marketplace.json synced).
- Pipeline unchanged: 6 skills, 5 agents. Catalog (W0-W4) + audit (A1-A5) + ask + process-inbox + init-library + new-stack.
- 12 open issues: 1 epic (#31) + 11 sub/orphan issues. See Open Issues section.
- Library-stack migration still blocked. sysops done, svelte cataloged-only, swe + mep untouched. Epic #31 governs the blocker work.

### Open Themes
- **Blocker epic #31** tracks the 8 issues that collectively prevent clean library migration on realistic-size stacks. 2/8 closed in S6 (#24 stale cache, #28 findings-analyst write silence). 6 remain.
- **Scale cluster (#26, #27, #30)** is the dominant remaining theme — none of the dispatches chunk for stacks >25 items. Largest leverage for unblocking swe + mep migration.
- **Contracts cluster (#23, #25)** — agent outputs silently omit required fields (extraction_hash) or drift on controlled vocabulary (tags). Skip-list flywheel non-functional until #23 fixed.
- **Convergence (#29)** — first-audit always budget-caps because fetch_source items count toward generative_open. Small fix, untouched in S6 because it warrants its own attention.

---

## CONTEXT HANDOFF - 2026-04-19 (Session 6)

### Session Summary

Two-part session: (1) triage pass on the 5 pre-S5 growth issues against the post-wiki-pivot state and the 7 new S5 issues; (2) aggregate the 8 pipeline-blockers into epic #31 and ship two of them as v0.11.1.

Triage rewrote 4 issue bodies to reflect current reality (article-per-concept, renamed commands), narrowed #7 scope, left #18 unchanged.

Filed issue cluster analysis via `/workspace-toolkit:issues-planner` agent dispatch: 13 orphans → 3 clusters (Catalog Scaling, Article Synthesis Contracts, Ask And Retrieval Surfaces) + 3 singletons. Declined to file per-cluster epics; instead filed one combined blocker epic #31 with all 8 forward-progress-blockers (scale + contracts + #29 convergence + #24 stale cache).

Shipped v0.11.1 fixes for the two most mechanical blockers:
- **#24**: SCRIPTS_DIR/STACKS_ROOT detection in catalog-sources and audit-stack now prefers `installLocation` from `~/.claude/plugins/known_marketplaces.json` over a cache scan. Directory-source installs had been silently running against stale 0.8.3 cached scripts/agents.
- **#28**: findings-analyst agent prompt now explicitly forbids inline YAML in the response body and reinforces one-line-confirmation-only shape. The assert-written gate caught the failure in S5 but re-dispatch was expensive.

Commit `0718a5a` on master, pushed. Both issues auto-closed by GitHub on push.

### Chat

S6-issue-triage-epic-blockers

### Session Rating

**Rating**: 4/5
**Note**: (none)

### Changes Made

| Change | Status |
|--------|--------|
| Triage #5 (cross-stack ask) — reframe for article model | Done |
| Triage #7 (page types) — scope narrowed to comparison + synthesis, entity dropped | Done |
| Triage #10 (qmd search) — rebenchmarked scale examples | Done |
| Triage #14 (scheduled loop) — renamed to catalog-sources; added scale-fix dependency | Done |
| Triage #18 (on-demand guide) — left as-is | Done |
| Issues-planner cluster analysis (13 orphans) | Done |
| File blocker epic #31 with 8 sub-issues | Done |
| Fix #24 (SCRIPTS_DIR prefers installLocation) | Done, shipped v0.11.1 |
| Fix #28 (findings-analyst response shape) | Done, shipped v0.11.1 |
| Fix #29 (convergence ignores fetch_source) | Deferred |
| Fix #23/#25 (contract gaps) | Deferred (larger design) |
| Fix #26/#27/#30 (scale cluster) | Deferred (larger design) |

### Knowledge Extracted

- **CHANGELOG.md** — v0.11.1 entry with both fixes described.
- No CLAUDE.md updates. The stale-cache behavior is now fixed in both skills; no permanent gotcha warranted.
- No system-patterns.md updates. `known_marketplaces.json` precedence over cache is a 3-line implementation detail, now captured in inline code comments in both skills.
- No ADRs. Both fixes are mechanical; neither required an architectural choice.

### Decisions Recorded

None formal. Inline pragmatic choices:
- Filed one combined blocker epic #31 over 3 per-cluster epics, because the 8 issues need to be closed collectively before migration can continue — tracking them as one unit surfaces progress more usefully than 3 separate ones.
- Picked #24 + #28 as the pre-stop knockouts (25 min total) over #29 (which is also trivial in shape). Reason: #29 touches convergence logic and warrants its own attention, not a drive-by fix.

### Next Session Priority

**Primary: pick a direction on the scale cluster (#26, #27, #30).**

All three need real design work. Two paths to consider:

1. **Tackle them together as one design** — the fix shape is the same (chunk dispatches, aggregate outputs). One coherent design document → parallel implementation.
2. **Start with #30 validator batching** as a standalone — audit is the first-touched skill when re-running sysops or svelte. Proves the batching pattern on a smaller surface (single agent, single wave) before extending to catalog-sources W1 (#26) and orchestration wrapper (#27).

My lean: path 2. #30 has the cleanest surface — one validator dispatch, per-article assert-written gate already in place. Batching pattern proven there drops the risk of the catalog-sources work.

**Secondary knockouts** (trivial, deferred intentionally):
- **#29 convergence ignores fetch_source** — single counter change in audit-stack Step 8 + findings-analyst doc update. ~30 min. Unblocks clean first-audit convergence.
- **#23 extraction_hash empty** — requires deciding where hash computation lives (script between concept-identifier and article-synthesizer, or inside article-synthesizer). Medium design, small implementation.

**Deferred from prior sessions**:
- Memory-bank accuracy pass (deferred in S5, still applicable at S7 on the 5-session audit cycle since S5 was the trigger point).
- The 4 pre-S5 growth issues (#5, #7, #10, #14, #18) are not blockers and can wait until the blocker epic is done.

### Open Issues

**stacks (12 open)**:
- **Epic #31** Pipeline Blockers [2/8]
  - Scale: #26 catalog chunking, #27 orchestration wrapper, #30 validator batching
  - Contracts: #23 extraction_hash, #25 tag drift
  - Convergence: #29 fetch_source blocks convergence
- **Growth** (not in epic): #5 cross-stack ask, #7 page types, #10 qmd search, #14 scheduled loop, #18 on-demand guide

**library-stack (unchanged from S5)**: #1 mep-stack split into CSI divisions. In-flight but blocked on #26/#30.
