---
session: 14
---

# stacks Active Context

## Current state

- Plugin at 0.21.0, versions synced in `plugin.json` + `marketplace.json`. The aggressive ponytail cut shipped: 3 agents (concept-identifier, article-synthesizer, validator), 6 skills, two pipelines (catalog W0→W4, stateless audit drift report), article-only ask. 16 files deleted; functional source ~4,833→2,142 lines.
- Memory bank (system-patterns, tech-context, project-brief), README, and start-brief all current to 0.21.0.
- README skills table now groups by lifecycle and documents the config-resolved vs cwd-relative invocation split (the "run from" column).
- 4 open issues. The live backlog centers on real-document ingest: #55 (concept-identifier robustness) and #51 (web fetch), plus #54 (skill scoping) and #10 (qmd search at scale).

## Next priority

Ingest robustness is the through-line: stacks should catalog the user's pre-existing PDF/HTML/docx resource library, not hand-made markdown. Highest leverage is stacks #55 (concept-identifier reads any file blindly with Read — guard binaries, page or convert long PDFs, rename the agent); its non-binding direction folds in the intake-filter widening for `--from`/`process-inbox` and the Office-conversion shim. Web ingest is #51 (fetch-sources). Skill-scoping tech-debt is #54 (deferred by user, not urgent). End-to-end smoke in a temp library was never run this session; floor gates pass (26 bats green, versions synced), so run it interactively when convenient (no issue filed — one-shot verification, not a tracked defect).

---

## CONTEXT HANDOFF - 2026-06-13 (Session 14)

### Session summary

Shipped the 0.21.0 simplification, then aligned the orientation docs and triaged the real-document ingest gap into tracked issues.

Spine (commit log `6ff1b79..c4db81c`): executed the ponytail/simplicity cut as 0.21.0 — reverted the 0.20.0 feature set (#7 comparison pages, #18 guide synthesis, #40 inbox quality gate), removed extract-reddit, rewrote audit-stack into a stateless drift report (no findings.md ledger, no carry-forward, no convergence loop, no glossary/invariants synthesis), slimmed catalog-sources, aligned references/templates/README/memory-bank, and bumped to 0.21.0 with the CHANGELOG and doc scrub. Then refreshed start-brief for 0.21.0 (it had drifted to the old 5-agent/wikilink/findings architecture), and reworked the README skills table twice: first added a "run from" column, then reordered by lifecycle after the user pushed back that grouping process-inbox with ask implied a kinship that does not exist (process-inbox mutates the library and feeds catalog-sources; it only shares ask's config-based invocation).

No-commit thread (the session's later half): walked through the "drop a folder, let it sort and digest" goal and corrected my own wrong claim that the engine is markdown-only. Verified the digest engine already reads PDF/HTML/text/images via the concept-identifier agent's Read tool (catalog W0 enumerates all file types, line 143); the limits are the two intake filters (`--from` and `process-inbox` accept only .md/.txt) plus genuine gaps for Office binaries (need conversion) and large PDFs (Read's ~20-page cap truncates silently). Filed three issues from this.

### Chat

(filled in Phase 8)

### Changes made

| Change | Status |
|--------|--------|
| 0.21.0 simplification: revert #7/#18/#40, remove extract-reddit, audit→stateless drift report, slim catalog-sources, align docs, bump + CHANGELOG | Shipped, pushed (d111e8b..2062faa) |
| start-brief.md refreshed for 0.21.0 (was stale to pre-cut architecture) | Shipped (08aee65) |
| README skills grouped by library-resolution, index.md tree note fixed | Shipped (7b26c27) |
| README skills reordered by lifecycle; "run from" reframed as invocation not kind | Shipped (c4db81c) |
| Ingest-path capability investigation (engine reads PDF/HTML; intake filters gate them) | No commit (design) → tracked in #55 |

### Knowledge extracted

Memory bank (system-patterns, tech-context, project-brief) was rewritten to the slimmed 0.21.0 system during the simplification; start-brief regenerated this session. No new memory-bank edits this segment — the later ingest findings are work-items, tracked as issues, not system-as-built knowledge.

### Decisions recorded

None formal (no ADR). README grouping axis (lifecycle, not invocation) settled in prose and the README itself.

### Next session priority

Real-document ingest. stacks #55 is the highest-leverage item (concept-identifier robustness: binary guard, large-PDF strategy, agent rename — resolver decides the name). #51 covers web fetch. #54 (skill scoping) is deferred tech-debt, not urgent. Intake-filter widening and Office conversion are folded into #55's non-binding direction, not filed separately. Smoke test: no issue, because it is a one-shot verification, not a tracked defect — run interactively.

### Open issues

stacks: 4 open (#10 qmd search, #51 fetch-sources, #54 skill scoping, #55 concept-identifier robustness). Cross-repo: ChuggiesMart #551 (README-as-canonical rollout). 0 stale specs.
