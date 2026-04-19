# Your knowledge library as a pattern-threshold oracle

**Session**: 2 (2026-04-18)
**Project**: stacks
**Status**: Draft — needs development

## The Discovery

I keep a personal knowledge library of software-engineering patterns — one topic guide per concept, ingested from Fowler standards and session extracts. It lives at `~/2_project-files/library-stack/` and I query it with `/stacks:ask swe <question>`. In the middle of validating 23 plan-review findings this session, I hit a judgment call: when are convergent parallel reviewers trustworthy enough to skip independent verification? I almost improvised an answer. Instead I asked the library. The swe/multi-agent-pipeline-design guide had the exact threshold: "convergence must be verified by an independent mechanism (cross-file grep, upstream context inspection), not just tallied." Two minutes of lookup replaced twenty minutes of rationalization and produced a better disposition.

A reader who finishes this post will understand how a personal knowledge library changes the shape of in-session reasoning: it turns "what do I think about X?" into "what has the library already settled about X?", which is both faster and less biased toward recent-memory.

## Key Insights

### 1. Libraries answer meta-questions cleanly, object-level questions messily

Object-level SWE questions — "how should I structure this plan", "what are the edge cases in this DAG" — are better answered by reading the actual spec and code. Meta-level questions — "when should I trust this reviewer", "what's the threshold for acting on a single-reviewer finding", "when is consequence scan mandatory" — generalize across projects and live comfortably in a library topic guide. The ROI of building a library is highest on meta-questions, because those are the ones I'd otherwise improvise.

In this session the library supplied three thresholds I would not have recalled correctly:

- Convergence requires independent verification, not tallying
- Single-reviewer at <80% confidence is discussion, not action
- Reviewer disagreement resolves by consequence scan (blast radius), not majority

Object-level answers — what T15 should contain, which files reference old pipeline names — came from `grep`, not the library.

### 2. The library is feed-forward context, not post-hoc justification

When I asked the library mid-session, the guide's answer surprised me in one small way: it distinguished between applying convergence and applying single-reviewer findings, which I had been treating as a spectrum rather than a bright line. That distinction changed two of my dispositions from "probably apply" to "reject by default, unless consequence scan says otherwise." If I had improvised the threshold and then gone back to the library afterward, I would have used the library to justify what I already decided. Asking first made the library a steering input rather than a rubber stamp.

Rule: consult the library at the decision point, not after the decision. If you only use it to validate in retrospect, you've built a justification engine, not a thinking aid.

### 3. The cost of asking is the binding constraint

A library that takes 30 seconds to query is used; one that takes 10 minutes is not. `/stacks:ask swe <question>` runs in a few seconds — find config, read catalog, match stack, read index, read topic guide, synthesize answer. No vector DB, no embeddings, no MCP server. Just direct-load retrieval from markdown files. The absence of machinery is the feature.

This constrains library size: the whole SWE stack has 8 topic guides totaling under 60k tokens of direct-load context. If the library outgrew direct-load retrieval, the query cost would rise and usage would drop.

### 4. Convergent coverage across sessions compounds

The thresholds I asked about today came from a topic guide synthesized from 11 sources — two Fowler standards (harness engineering, feature toggles) and nine session-extract writeups from prior ChuggiesMart and meap2-it sessions. None of those sessions individually produced the threshold; the synthesis across them did. Today's session extract will feed the next synthesis. The library compounds — not linearly with source count, but through the cross-topic patterns that only emerge when 8-10 sources describe the same failure mode from different angles.

This is why filing every substantive session extract back to the library is load-bearing, not housekeeping. Today's "I rejected S-02 because single-reviewer threshold" becomes part of next month's "single-reviewer rule is robust across 15 sessions of practice."

## Evidence

### The mid-session library query that changed dispositions

```
/stacks:ask swe when should you override or de-prioritize a finding
that three parallel code-reviewers converged on? Convergence normally
signals apply-it, but what are the failure modes where convergent
reviewers are wrong in the same way?
```

Library returned the multi-agent-pipeline-design guide. Two specific passages were load-bearing:

> Convergent-reviewer override mechanics: The threshold: both at >80%
> confidence with the finding verifiable via cross-file grep or
> equivalent. Critical caveat (s776): if both reviewers failed to read
> the same upstream file, convergence on a false positive is still a
> false positive.

> Convergence on a false positive is still a false positive: the
> verification step (cross-file grep, upstream context inspection) is
> mandatory before acting on convergence, not optional.

### Library structure

```
~/2_project-files/library-stack/
├── catalog.md                  # index of all stacks
├── swe/
│   ├── STACK.md
│   ├── index.md                # topic list
│   └── topics/
│       ├── engineering-practices/guide.md
│       ├── evolutionary-design/guide.md
│       ├── git-github-workflow/guide.md
│       ├── knowledge-system-design/guide.md
│       ├── multi-agent-pipeline-design/guide.md     # answered today's question
│       ├── release-management/guide.md
│       ├── schema-migration-data-integrity/guide.md
│       └── skill-prompt-engineering/guide.md
├── mep-stack/                  # MEP engineering patterns
├── svelte/                     # Svelte 5 / SvelteKit patterns
├── sysops/                     # bash / PowerShell / homelab
└── inbox/                      # session extracts awaiting routing
```

### Measurements

- Library size: 4 stacks, 8 topic guides in swe alone, ~60k tokens direct-load
- Query time: ~3 seconds from invocation to answer
- Sources feeding the multi-agent-pipeline-design guide: 11 (2 Fowler Tier 2, 9 session-extract Tier 3)
- Library contribution this session: 2 dispositions changed from "apply" to "reject" after threshold lookup

### References

- Session 2 handoff: `.claude/memory-bank/active-context-S3.md`
- SWE topic guide: `library-stack/swe/topics/multi-agent-pipeline-design/guide.md` (the guide that answered the question)
- Session extract filed: `library-stack/inbox/stacks-s2-plan-review-dispositions.md`

## Blog Post Angles

1. **The tool-agnostic post** — why a personal knowledge library is the right shape for meta-questions (as opposed to an object-level RAG over your codebase). Frame for engineers who've tried RAG-over-code and found it underwhelming; the insight is that meta-patterns generalize while object-level specifics don't.
2. **The stacks tool showcase** — lead with this concrete moment (mid-session lookup during disposition work), then introduce the `stacks` tool, catalog structure, direct-load retrieval philosophy, and Karpathy-style article-per-concept design decision. Promotional but grounded in a real use case.
3. **The karpathy-loop post** — how the feedback flywheel works end-to-end. Source article → topic guide → mid-session query answered by guide → session extract filed back to inbox → next synthesis folds it in. One concrete trip around the loop, with the stacks S2 inbox file as the closing artifact.

## Visual Ideas

A split-panel diagram: left side shows the improvisation path ("I think convergence is probably trustworthy... let me just apply these three findings"), right side shows the library-oracle path (query → topic guide excerpt → "convergence requires verify" rule → dispositions change). Emphasize the threshold crossing — same set of findings, different output, depending on whether the library was consulted at the decision point or not.

## TODO

- [ ] Expand insight #2 — the "steering vs rubber-stamp" distinction is the most important and least obvious
- [ ] Add a second concrete session example (ideally one where the library contradicted what I would have done)
- [ ] Decide angle (1/2/3) — #3 is most cohesive but longest
- [ ] Draft post: /writing-tools:blog
