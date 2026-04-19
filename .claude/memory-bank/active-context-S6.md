---
session: 6
---

# stacks Active Context

## Current Work Focus

### Current State
- Plugin at 0.11.0 (plugin.json + marketplace.json synced).
- Pipeline: 6 skills, 5 agents. Catalog (W0-W4) + audit (A1-A5) + ask + process-inbox + init-library + new-stack.
- 12 open issues (was 5, +7 filed this session during dogfood): #5, #7, #10, #14, #18, #23, #24, #25, #26, #27, #28, #29, #30.
- Library-stack migration in flight. sysops fully migrated + audited (11 articles, pass-1 budget-cap). svelte cataloged (75 articles) but audit blocked at validator scale wall. swe and mep untouched.

### Open Themes
- **Scale wall**: The dogfood run surfaced that neither catalog-sources W1 nor audit-stack A1 tolerates >~25 articles/sources per agent dispatch. All substantive library stacks (svelte 75, swe ~70, pre-split mep ~107→~250) need this fix before migration can continue.
- **Agent-contract enforcement**: findings-analyst silently skipped Write (#28); article-synthesizer silently leaves extraction_hash empty (#25). Gate catches one, not the other.
- **Convergence dependency**: A4 convergence logic blocks on fetch_source items that only catalog-sources can close (#29) — first-audit always budget-caps by design.
- **Directory-source SCRIPTS_DIR resolution**: auto-detect finds stale cache, not active repo (#23).

---

## CONTEXT HANDOFF - 2026-04-19 (Session 5)

### Session Summary

Dogfood migration of library-stack from old topic-guide format to 0.11.0 article-per-concept wiki. Planned 4 stacks; completed 1 (sysops fully) + 1 partial (svelte cataloged, audit blocked). Along the way, exercised `/stacks:catalog-sources` and `/stacks:audit-stack` through their full pipelines on real data and filed 7 issues against the plugin for scale and contract gaps that surfaced.

**Library-stack commits** (all in `~/2_project-files/library-stack/`, NOT this repo):
- `c453dee` chore(sysops): stage sources for migration
- `cdea8f4` feat(sysops): catalog 5 sources → 11 articles
- `10d9404` audit(sysops): pass 1, budget-cap converged (77 VERIFIED, 38 UNSOURCED, 0 DRIFT)
- `9d8583f` chore(svelte): stage sources
- `08013ec` checkpoint(svelte): 25 extractions, 75 unique concepts
- `d9434e4` feat(svelte): catalog 25 sources → 75 articles

**Issues filed on stacks** (this repo, no commits):
- **#23** — catalog-sources SCRIPTS_DIR auto-detect finds stale 0.8.3 cache over directory-source 0.11.0 repo.
- **#24** — no chunking guidance for >50 source catalog runs (blocks pre-split mep-stack at 107).
- **#25** — article-synthesizer leaves extraction_hash empty; concept-identifier contract says "computed downstream" but nothing downstream computes it. Skip-list flywheel non-functional.
- **#26** — article-synthesizer tag drift across parallel dispatches; sysops got `bash` (5) + `bash-scripting` (1) sibling groups for same domain. No controlled vocabulary.
- **#27** — orchestration loop lives in main session context; proposes wrapper agent for N>30. Empirical finding: general-purpose subagent does NOT expose Task despite `*` tool claim — wrapper would need custom agent frontmatter with Task explicitly listed.
- **#28** — findings-analyst returned full YAML inline in chat and skipped Write despite contract + tool availability. Gate caught it. Had to manually persist content from agent's return.
- **#29** — audit-stack A4 convergence blocks on `fetch_source` items that only catalog-sources can resolve. Every first-audit budget-caps by design.
- **#30** — validator in A1 hits "Prompt is too long" at 75 articles (modified 25 before dying). Same-class root as #24: no batching.

svelte partial audit state was reverted (`git checkout -- svelte/articles/`) so working tree is clean; next session's A1 starts from committed d9434e4.

### Chat

(filled in Phase 8)

### Session Rating

(filled in Phase 8)

### Changes Made

| Change | Status |
|--------|--------|
| Library-stack sysops: migrate topic→article, catalog, audit (pass 1 budget-cap) | Done |
| Library-stack svelte: migrate topic→article, catalog (75 articles) | Done |
| Library-stack svelte: audit | Blocked by #30 (validator scale wall) |
| Library-stack swe: migrate | Deferred (next session) |
| Library-stack mep: split into div-22/23/26 + migrate | Deferred (needs #24 first) |
| File 7 dogfood issues on stacks plugin | Done |
| Update stacks system-patterns.md Known Weak Spots with the 4 dogfood findings | Done |

### Knowledge Extracted

- **system-patterns.md Known Weak Spots** — added four new weak-spot entries covering scale walls (#24/#27/#30), agent-contract non-enforcement (#25/#28), convergence cross-skill dependency (#29), and SCRIPTS_DIR auto-detect stale-cache problem (#23). Each entry names the issue number.
- **No CLAUDE.md updates** — the stale-cache gotcha is fully captured in issue #23 and won't recur once fixed; not worth a permanent gotcha entry.
- **No ADRs** — all workarounds this session were pragmatic recovery, not architectural decisions.

### Decisions Recorded

None formal. Inline pragmatic choices:
- Revert partial svelte validator run rather than commit incomplete state, so next session starts from a clean catalog commit.
- Manually persist findings-analyst's inline-returned YAML (workaround for #28) to let A4+A5 proceed for sysops rather than re-dispatch.
- Budget-cap sysops audit at pass 1 rather than run passes 2-3 — all open items are fetch_source/research_question that audit-stack cannot close.
- Used general-purpose subagent as orchestration wrapper for svelte W2-W4; it had to write articles itself because Task tool isn't actually available to it. Articles committed are schema-valid but not produced by parallel `stacks:article-synthesizer` dispatches.

### Next Session Priority

**Primary: decide on scale fix before continuing library migration.**

The 4 open library stacks (swe ~70, div-23 ~250 expected) cannot be migrated without #24 (catalog chunking) and #30 (validator batching). Two paths:

- **Fix the scale issues first** (probably 1-2 sessions): chunk catalog-sources W1 dispatch into N-source batches, chunk audit-stack A1 validator into article-range batches. Then resume migration with proper tooling.
- **Finish swe manually** (maybe feasible at 33 sources; ~75 articles): would stress-test #24/#30 further but still within the wall. Defer div-22/23/26 until fix lands.

My lean: fix scale first. Every additional manual migration accumulates the same recovery costs (partial state reverts, inline content persists, gate failures). Better to ship the fix.

**Secondary cleanup**:
- Close/update #5, #7, #10, #14, #18 triage status against the new issue set.
- The stacks audit-hit threshold (S5 done this session) suggested a memory-bank accuracy pass — that was the original /start note. Deferred because library migration was the actual work. Run on S6 if scope allows.

### Open Issues

**stacks (12 open)**:
- Scale: #24 (catalog no-chunking), #27 (orchestration wrapper), #30 (validator no-batching)
- Contract: #25 (extraction_hash empty), #26 (tag drift), #28 (findings-analyst write silence)
- Design: #29 (convergence blocks on fetch_source)
- Infra: #23 (SCRIPTS_DIR stale cache)
- Growth (pre-S5): #5 cross-stack ask, #7 comparison-page, #10 qmd deferred, #14 scheduled loop, #18 on-demand guide (blocked by #5)

**library-stack (1 open)**: #1 mep-stack split into CSI divisions (div-22/23/26). In-flight — sysops + svelte migrated but mep not touched this session.

Prior open items from earlier ChuggiesMart sessions carry forward unchanged.
