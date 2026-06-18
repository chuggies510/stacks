---
session: 15
---

# stacks Active Context

## Current state

- Plugin at 0.26.2, versions synced in `plugin.json` + `marketplace.json`. Three agents (source-extractor, article-synthesizer, validator), 6 skills, two pipelines (catalog W0→W4 with a new convert stage, stateless audit drift report), body-keyword lookup retrieval.
- Document ingest now works: catalog-sources Step 3.5 (`scripts/convert-sources.sh`) converts PDFs/Office to text before extraction; the source-extractor agent (renamed from concept-identifier) only ever sees text.
- ask retrieval searches article bodies, not just frontmatter (`scripts/rank-articles.sh`); fixes the title-only-matching wall.
- 40 bats green (added `tests/convert-sources.bats` 7, `tests/rank-articles.bats` 7). Memory bank (system-patterns, tech-context, project-brief), README, start-brief all current to 0.23.0.
- 1 open issue: #54 (maintenance skills load in every repo — deferred by user, not urgent).

## Next priority

Backlog is down to one deferred item (#54). The session closed three issues (#55 ingest, #51 fetch-sources teardown, #10 qmd→keyword retrieval); no urgent next move. Two new scripts (convert-sources.sh, rank-articles.sh) are unit-tested but were never run end-to-end against a real library this session — no issue filed because that is one-shot verification, not a tracked defect. Run `/stacks:catalog-sources` on a stack with a real PDF and `/stacks:lookup` a body-content query when convenient to confirm the live wiring. qmd vector search stays deferred: reopen #10 only on an observed semantic-synonym miss (query should match an article it shares no keywords with), not on article count.

---

## CONTEXT HANDOFF - 2026-06-13 (Session 15)

### Session summary

Worked the ingest-robustness backlog surfaced in S14, closing three issues. (1) #55: built `scripts/convert-sources.sh`, a single type-aware conversion stage that turns PDFs (pdfplumber, no page cap, multi-column layout preserved), `.docx` (pandoc), and spreadsheets/slides/legacy Office (libreoffice headless) into text sidecars before extraction; images, scanned PDFs (no text layer), and unknown binaries are skipped and reported, never garbled; converted originals archive to gitignored `sources/.raw/`. Adopted meap2-it's pre-extraction approach (Claude never reads the binary; their `tools/pdf-extractor.py` uses pdfplumber via `uv run --with`) as the technique, not by vendoring the file. Renamed the `concept-identifier` agent to `source-extractor` across the agent file, dispatch + gate label, README, CLAUDE.md, and memory bank. Widened `--from` staging to accept documents so conversion lives in one place. (2) #51: necessity-descent ruled the proposed fetch-sources skill over-built (its audit `fetch_source` auto-feed seam was deleted in 0.21.0; per-URL routing is inline judgment); harvested the five fetch-failure workarounds into `references/web-fetch-routing.md` and closed it. (3) #10: necessity-descent ruled qmd (BM25/vector engine + MCP + index) rung-6 over-reach; the actual wall is `ask` scoring only frontmatter title/tags/slug. Built `scripts/rank-articles.sh` (grep-count keywords over the whole body, title line +5, drop stopwords) and wired it into ask Step 5; qmd deferred to a sharp reopen trigger.

### Chat

S15-document-ingest-body-retrieval

### Changes made

| Change | Status |
|--------|--------|
| #55: convert-sources.sh + catalog Step 3.5, agent rename, --from widen, 0.22.0 (d3a6b3b) | Shipped, closed |
| #51: web-fetch-routing.md reference, skill dropped, issue closed (632bf86) | Shipped, closed |
| #10: rank-articles.sh + ask Step 5 body retrieval, 0.23.0 (16bafca) | Shipped, closed |

### Knowledge extracted

- `tech-context.md`: added uv+pdfplumber/pandoc/libreoffice runtime deps (graceful skip-and-report on missing tool).
- `system-patterns.md`: catalog pipeline gained the Step 3.5 convert stage; ask flow now body-keyword ranked via rank-articles.sh.
- `project-brief.md` + `start-brief.md`: agent rename, version, retrieval change.
- `references/web-fetch-routing.md`: new — fetch routing table harvested from #51.
- `CLAUDE.md`: corrected stale agent count (5→3) with names.

### Decisions recorded

No ADRs. Two necessity-descents (#51, #10) recorded in the closed-issue comments and CHANGELOG "Why not qmd" / reference footer.

### Next session priority

No open work beyond deferred #54. Verify convert-sources.sh and rank-articles.sh end-to-end against a real library when convenient (no issue — one-shot verification, not a defect). qmd reopen trigger for #10: an observed semantic-synonym miss.

### Open issues

1 open (#54, deferred). 0 stale specs.
