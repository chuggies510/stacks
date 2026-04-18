#17 wiki pivot as an epic. Rebuild the stacks plugin so the unit is concept
articles under {stack}/articles/{slug}.md, with closed loop between catalog
and audit operations.

SCOPE
- Absorb into #17: #1 (trash), #3 (source filing), #4 (gitignore incoming),
  #16 (obsoleted, no clusterer in article-per-concept shape)
- Close as obsoleted at epic end (SHA ref): #11, #15, #6 (the new agent-write
  pattern subsumes these)
- Defer, do not absorb: #7 (page types). Single article shape ships first.
- Out of scope: #18, #10, #5, #8, #9, #14

CONSTRAINTS (locked, do not re-ask)
- Pre-1.0 personal tool. Hard-cut rename inside the work, not a cutover
  sub-issue. ingest-sources -> catalog-sources, refine-stack -> audit-stack,
  dev/curate/ -> dev/audit/ + dev/extractions/.
- No migration. Rebuild articles from source. Existing topics/*/guide.md stay
  read-only until user deletes.
- Single flat article shape. No typed subdirs (concepts/entities/...) yet.
- Cross-links: standard markdown [text](path.md). Not [[wikilinks]]. Karpathy
  gist is deliberately abstract; wikilinks are a follower convention, skip for
  portability.
- Article size: no hard bound. Matuschak: one complete idea, finishable in
  under 30min. Do not set a word target.
- Direct-load retrieval only. No vector/MCP/qmd (deferred).
- Agent write-or-fail: every agent's final action is a successful file write.
  Chat-only return is a hard failure. Bash `-s` gate after every dispatch.
  Subsumes #11/#15.
- Agent count goes 7 -> 6. Drop cross-referencer. Cross-link application is a
  deterministic post-write pass inside audit-stack, not a dedicated agent.
- Fix version mismatch as part of the epic: plugin.json=0.8.3 vs
  marketplace.json=0.8.0.

FINDINGS SCHEMA (locked)
- YAML frontmatter: audit_date, stack_head (git rev-parse HEAD), pass_counter,
  schema_version.
- Items: id = {article}:{finding_type}:{content-hash} for idempotency across
  audit re-runs. status (open|applied|closed|deferred|stale). action
  (fetch_source|cross_link|manual_review|none).
- Convergence: audit loop stops at 2 consecutive empty passes OR cost budget
  cap, whichever first.
- Article frontmatter gains extraction_hash so catalog detects stale articles
  without re-synthesizing everything.

ARCHITECTURE (already decided, do not re-architect)
- Shape: fork ingest-sources -> catalog-sources and refine-stack -> audit-stack
  with minimal edits. Reuse wave-engine, existing agent prompts where they work.
- Loop closure: catalog-sources reads prior findings.md at run start, consumes
  open items (fetch new acquisitions, re-synthesize flagged articles),
  annotates per-item status, archives completed audits to
  dev/audit/closed/{date}.md.
- Patron-visible at stack root: glossary.md, invariants.md, contradictions.md.
- Retrieval: /stacks:ask reads articles first, falls back to guides during
  transition. MoC-style index.md. No dual-read flag, no config toggle.
- last_verified (human-ack) distinct from updated (any write). catalog-sources
  sets updated; audit-stack sets last_verified.

SUB-ISSUES (file these three on GitHub, this is the DAG)
- 17.1 article pipeline (catalog-sources + new agents + filing)
- 17.2 retrieval (/stacks:ask + MoC index), blockedBy 17.1
- 17.3 audit loop closure (audit-stack + findings contract + post-write
  cross-link + loop back to catalog), blockedBy 17.1

Rename ships inside 17.1-17.3 as part of the work, no 17.4.

REQUIRED RESEARCH INPUT FOR ARCHITECTS
Pass direct file paths, not summaries:
- ~/2_project-files/library-stack/swe/topics/knowledge-system-design/guide.md
- ~/2_project-files/library-stack/swe/topics/multi-agent-pipeline-design/guide.md
- ~/2_project-files/library-stack/swe/topics/skill-prompt-engineering/guide.md
- ~/2_project-files/library-stack/swe/sources/standards/fowler-knowledge-priming.md
- ~/2_project-files/library-stack/swe/sources/standards/fowler-feedback-flywheel.md
- ~/2_project-files/library-stack/swe/sources/standards/fowler-harness-engineering.md
- https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

Architects read these themselves. Do not synthesize them into the context
package; cite paths and move on.

PROCESS
- Skip Step 6a swe-stack synthesis agent. Architects read the guide paths
  above.
- Skip Step 6b web research. The gaps are already mapped; Karpathy gist is the
  only web source and it is cited above.
- Skip Step 7 problem-solving. Approach is locked.
- Step 8 clarifying questions: none expected. Do not prompt.
- Step 9: dispatch architects per open sub-issue with the three framings. Give
  each agent the constraints above and the file paths to read. Do not restate
  anything listed here as "for consideration."
