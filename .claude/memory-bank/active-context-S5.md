---
session: 5
---

# stacks Active Context

## Current Work Focus

### Current State
- Plugin at 0.11.0 (plugin.json + marketplace.json synced).
- Pipeline: 6 skills, 5 agents. Catalog (W0-W4) + audit (A1-A5) + ask + process-inbox + init-library + new-stack.
- findings.md schema at v2 — four sections (New Acquisitions, Articles to Re-Synthesize, Research Questions, Deferred). Convergence counts generative-open = fetch_source + research_question.
- ask Step 7 (file-result-back) branches on MODE: article-mode writes `articles/{slug}.md`, guide-mode keeps legacy `topics/{topic}/guide.md`.
- Stack template gitignores `sources/incoming/` AND `sources/trash/`; validator input excludes both.
- `references/obsidian.md` exists as library-as-vault reference.
- 5 open issues: #5 cross-stack ask (blocks #18), #7 comparison-page only (narrowed), #10 qmd (deferred), #14 scheduled loop (name-update ready), #18 on-demand guide synthesis.

### Open Themes
- **Growth work**: #5 cross-stack ask is the next retrieval primitive; unlocks #18 (on-demand `/stacks:guide "{topic}"` synthesis).
- **Automation**: #14 scheduled loop for inbox→catalog. Would benefit from `workspace-toolkit:loop` integration.
- **Narrower specific gap**: #7 comparison-page template (A vs B with decision table) — no longer requires the broader "page types" reframe.

---

## CONTEXT HANDOFF - 2026-04-18 (Session 4)

### Session Summary

Triaged 12 open issues from the 0.9.0 wiki-pivot backlog; closed 7 (#1, #4, #6, #8, #9, #11, #15) via 5 commits spanning 0.9.1 → 0.11.0. Remaining 5 all have scope notes on-issue.

Three small-scope features shipped:
- **0.9.1** — `templates/stack/.gitignore` with `sources/incoming/` (#4). Trivial fix but landed the gotcha below.
- **0.9.2** — `sources/trash/` soft-delete bin (#1). Added gitignore entry + `.gitkeep` placeholder + `templates/library/CLAUDE.md` conventions blurb. Updated validator input and audit-stack A1 dispatch to exclude `sources/trash/` AND `sources/incoming/` (prevents trashed sources from resurfacing as citation targets). One follow-up commit (3e4df14) fixed gitignore self-shadowing — see Gotcha in CLAUDE.md.
- **0.10.0** — findings-analyst Research Questions section (#8). Schema v1 → v2 with a fourth section for `action: research_question` items. New item shape is question-keyed (involves_articles[], question, verification_target) rather than claim-keyed; id = `sha256("question|{sorted-slugs}|{question-text}")` for stable cross-pass identity. Convergence rule in audit-stack A4 renamed `fetch_open` → `generative_open` and now counts both fetch_source and research_question as open generative work. Empirically verified awk parser against a fixture covering mixed terminal/open states for both action types. No migration required — v1 items carry forward unchanged.

One filing-path bug from 0.9.0 cutover fixed in 0.11.0:
- **0.11.0** — ask Step 7 (Karpathy file-result-back) used to write to `topics/{topic}/guide.md` in both branches. Article-mode stacks have no `topics/` dir so the filing flow was broken. Step 7 now branches on the same MODE flag set in Step 5 — article-mode writes `articles/{slug}.md` with proper frontmatter (`extraction_hash: ""` for query-filed articles, `last_verified: ""` to force revalidation). Guide-mode path preserved for legacy stacks. Shipped alongside `references/obsidian.md` (#9 full close) covering library-as-vault, Web Clipper config pointed at `sources/incoming/`, and four Dataview recipes (never-validated, single-source, staleness, tag coverage). README got a "browse with Obsidian" section pointing at the reference.

#7 narrowed: the "entity/comparison/synthesis page types" framing is stale under the article pipeline. Entity pages fit existing short-article shape; synthesis pages are now covered by article-mode filing. Only comparison pages (A vs B with decision table) remain. Re-scope comment posted.

### Chat

(filled in Phase 8)

### Changes Made

| Change | Status |
|--------|--------|
| Close #6, #11, #15 as obsolete (0.9.0 cutover) | Done |
| 0.9.1 — `templates/stack/.gitignore` with `sources/incoming/`; closed #4 | Done |
| 0.9.2 — `sources/trash/` soft-delete bin + validator exclusion; closed #1 | Done |
| 0.9.2 fix-up — `dir/*` + `!.gitkeep` gitignore pattern | Done |
| 0.10.0 — findings-analyst Research Questions; schema v2; closed #8 | Done |
| 0.11.0 — ask Step 7 article-mode branch + `references/obsidian.md`; closed #9 | Done |
| #7 narrowed to comparison-page only via triage comment | Done |
| Triage comments on remaining #5, #14, #18 with ready-for-work or blocks notes | Done |

### Knowledge Extracted

- **system-patterns.md** — A3 schema v2 + four sections + generative_open convergence; Lookup Step 7 mode-branch filing; validator excludes incoming/trash; removed closed #4 weak-spot; added cross-stack-retrieval as new weak spot.
- **CLAUDE.md** (stacks) — new **Gotchas** section with "Template .gitignore Self-Shadows Its Own .gitkeep Placeholders" — surfaced when 0.9.2 first commit shipped without the .gitkeep; diagnosed with `git check-ignore -v`; fix is `dir/*` + `!dir/.gitkeep` not bare `dir/`.
- **Stacks library inbox** — `{inbox}/stacks-s4-schema-evolution.md` covering additive schema versioning (v1→v2 via new section + action enum value with zero-migration path) and template gitignore self-shadowing gotcha.

### Decisions Recorded

No formal ADR. Decisions visible inline:
- schema v2 is additive-only (v1 items carry forward) — preserves audit history across the bump.
- Query-filed articles use `extraction_hash: ""` rather than a synthesized hash — lets the next catalog-sources run reconcile with real source extractions when they arrive.
- `/stacks:ask` trash exclusion happens at the validator agent layer (prompt wording + skill dispatch bullet), not by changing the catalog-sources scope — keeps catalog-sources' single-responsibility (incoming/ only) clean.

### Next Session Priority

**Primary**: decide whether to tackle #5 cross-stack ask, #14 scheduled loop, or #7 comparison-page template next. All three are ~medium-scope, none block each other.

- **#5 cross-stack ask** is the most leveraged — unlocks #18 on-demand guide synthesis once landed. Design sketch is on-issue.
- **#14 scheduled loop** is the most ergonomic — inbox→catalog hands-off. Just needs `workspace-toolkit:loop` integration + name-update (old issue said `ingest-sources`, now `catalog-sources`).
- **#7 comparison-page** is the narrowest — new agent or new concept-identifier emit type for side-by-side A vs B.

**Secondary**: session 5 is an audit-hit threshold (every 5 sessions). If next session is S5, do a full accuracy pass of memory-bank + CLAUDE.md before starting new work.

### Open Issues

**stacks (5 open)**: #5, #7 (narrowed), #10 (deferred), #14, #18 (blocked by #5). All have triage notes on-issue.

No ChuggiesMart issues filed this session. Prior open items from S3 carry forward:
- [ChuggiesMart#375](https://github.com/chuggies510/ChuggiesMart/issues/375) — feature-dev Step 15/16 scaling for multi-wave epics
- [ChuggiesMart#374](https://github.com/chuggies510/ChuggiesMart/issues/374) — systematic review-findings validator skill
- [ChuggiesMart#369](https://github.com/chuggies510/ChuggiesMart/issues/369) — feature-dev version-bump strategy for multi-sub-issue epics
- [ChuggiesMart#368](https://github.com/chuggies510/ChuggiesMart/issues/368) — feature-dev:code-reviewer needs Write tool
