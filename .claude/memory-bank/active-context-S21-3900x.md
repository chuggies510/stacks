---
session: 21
---

# stacks Active Context

## Current state

| | |
|-|-|
| Version | 0.58.0 (shipped this session, from 0.51.0) |
| Tests | prompt/markdown changes; pipeline `--self-check`s unaffected, not re-run |
| Shipped | scope-map fix across all 4 worker agents (0.57.0–0.58.0, #95/#109); enrich/audit hardening batch (0.52.0–0.56.3) |
| In flight | none — closed clean |
| Peer | liminal (tmux win 3) scoring local models for #109; committed a 122B-A10B result (d8a6ebe) |

## Open thread

None, closed clean. The #109 program continues as Next priority, not an open fork.

## Next priority

| # | Item | Note |
|---|------|------|
| #109 | benchmark synth/enrich/validator stages | extraction done; next unit |
| #95 | extraction tier decision | sonnet stays; haiku variance / local behind harness |
| #98 | enrich staging URL-dedup script bug | agent-half shipped 0.58.0 |
| #106 | strengthen W1b near-dup dedup | advisory shipped 0.58.0 |
| — | backlog | #70 #100 #102 #104 #107 #108 |

**Cross-repo follow-up:** local extraction tier is gated on a **pal-chat harness** (the Agent tool reaches only sonnet/haiku/opus/fable). liminal owns local-model scoring; stacks owns the harness + per-stage benchmarks.

## Session log
- DECIDED: the extractor scope-map fix generalized to all 4 worker agents (0.57.0–0.58.0), not just extraction — the shared lever is feeding the `index.md ## Articles` scope map.
- DECIDED: sonnet stays the extraction tier for now — haiku clears the cliff only on some passes; local models clear behind a pal-chat harness (#95).
- FACT: over-mint (fragmentation) and under-recall (lumping) are one granularity axis; a scope map moves a model from the fragment side to the lump side (measured: haiku 0.80↔1.0 cliff recall, 0 over-mint).
- FACT: liminal's cross-model benchmark showed the over-mint was information starvation, not weak tier — scoped slugs drop excess mints to 0 on every tier (gemma 7-8→0, qwen 0-19→0).
- TRAP: a scope-map/reuse instruction over-corrects a weaker tier into lumping distinct articles — needs a paired "keep distinct articles distinct" guard (shipped 0.57.1).
- ARC: model-tier program (#109) — context layer now in for all 4 stages; per-stage gold-set benchmarks (synthesis, enrichment, validation) are the next unit, scored on cloud tiers + liminal's locals.

<!-- ═══ JOURNAL — derived view, carried forward by /stop, regenerable from archive/ ═══ -->

## Standing facts
- Local models cannot be dispatched via the Agent tool (reaches only sonnet/haiku/opus/fable); a local worker tier needs a pal-chat harness (read source → call local model via pal MCP `localhost:11434` → write output), an architecture change, not a frontmatter edit. (as-of: 2026-07-11)
- liminal is the peer Claude session (local-LLM / fine-tuning expert) on **tmux window 3** (NOT 4 — window 4 is meap2-it); it scores local models against stacks benchmarks on a local RTX 3090. Walkie-talkie: `send-keys -t %1 "msg" Enter` then a separate `send-keys -t %1 Enter`. (as-of: 2026-07-11)
- The `dev/experiments/model-tier/` dir (epic #109) is the first-class model-tier test area: per-stage gold-set benchmark + local/cloud scores + a decision. Front-door `README.md`; extraction is the only benchmarked stage. (as-of: 2026-07-11)

## Recent arc
- S21 (07-11): model-tier program (#95→#109) — built the extraction benchmark, found the over-mint was scope-starvation not weak tier, shipped the `index.md` scope-map fix to all 4 worker agents (0.57.0–0.58.0) with a 0.57.1 anti-lumping counterweight; earlier in the window, an enrich/audit hardening batch (0.52.0–0.56.3). Collaboration with liminal on local-model scoring.

## Theme index
- model-tier-eval: S21
- corpus-context-to-agents: S21
- enrich-audit-hardening: S21

<!-- journal:cold -->

## Arcs
(none yet)

## Milestones
(none yet)

## CONTEXT HANDOFF - 2026-07-11 (Session 21)

### Session summary
Two arcs in this session's window (17 commits since S20's 0.51.0 handoff). **(1) Enrich/audit hardening (0.52.0–0.56.3):** incremental audit skip (re-validate only changed articles), validator CAP 3→5, enrich staging fixes (real page text not WebFetch summary, publisher-slug filing, quote re-verify tolerance, NOSOURCE empty-field gate tolerance), cold-start fixes for a scaffolded stack, root catalog.md auto-refresh, and the `$CLAUDE_PLUGIN_ROOT` fallback across 8 skills. **(2) Model-tier program (#95→#109, the session's main arc):** built a gold-set extraction benchmark and handed it to the peer session liminal; liminal's cross-model run revealed the slug over-minting (the #106 fragmentation) was information starvation — the extractor got a bare slug list, never the `index.md` scope map. Shipped the scope-map fix to the extractor (0.57.0), added an anti-lumping counterweight after a benchmark showed the fix over-corrects a weaker tier into merging distinct articles (0.57.1), then generalized the same lever to the synthesizer, enrich, and validator via three parallel sonnet agents (0.58.0, #110/#98/#106). Filed epic #109 (cheapest-model-per-stage) and reconciled #95/#98/#106/#110 to what actually shipped (each a partial except #110, closed).

### Chat
S21-model-tier-scope-map

### Changes made
| Change | Status |
|--------|--------|
| Enrich/audit hardening batch (0.52.0–0.56.3, 10 commits) | shipped |
| Extraction model-tier benchmark + local results (#95, dev/experiments/model-tier/) | committed |
| 0.57.0 extractor scoped-slug fix | shipped |
| 0.57.1 anti-lumping counterweight | shipped |
| 0.58.0 scope map → synthesizer/enrich/validator (3 parallel sonnet agents) | shipped |
| liminal's 122B-A10B straddle result (d8a6ebe) | landed in-repo (peer) |
| system-patterns.md: scope-map pattern + model-tier weak-spot | this handoff |

### Knowledge extracted
system-patterns.md: new "Corpus scope map to worker agents (0.57.0–0.58.0)" section + a Known Weak Spots bullet on the uniform-sonnet tier now being measured (#109). Standing facts seeded (pal-chat harness constraint, liminal on win 3, the model-tier test area).

### Decisions recorded
No formal ADR (stacks has no decision-log); the scope-map pattern lives in system-patterns.md + CHANGELOG + issues.

### Next session priority
#109 — build a gold-set benchmark for the synthesis, enrichment, and validation stages (extraction is the template), scored on cloud tiers + liminal's local models. Offer liminal a per-stage spec the way the extraction one was handed over. #95 extraction tier decision stays parked on sonnet pending the harness/variance resolution.

### Open issues
10 open: #70 #95 #98 #100 #102 #104 #106 #107 #108 #109.
