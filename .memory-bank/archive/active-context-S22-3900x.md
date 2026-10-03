---
session: 22
---

# stacks Active Context

## Current state

| | |
|-|-|
| Version | 0.58.0 (unchanged — this session was benchmark/dev work, no plugin bump) |
| Tests | prompt/markdown only; no pipeline `--self-check` touched |
| Shipped | four-stage offline model-tier benchmark suite complete (#109); codex-review fixes on the 3 new benchmarks |
| In flight | none — closed clean |
| Peer | liminal (tmux win 3) landed a local-model result (306948b, UD-Q4_K_XL dominated by Q3_K_M) on shared master during this session |

## Open thread

None, closed clean. The #109 program continues as Next priority (local scoring), not an open fork.

## Next priority

| # | Item | Note |
|---|------|------|
| #109 | liminal local scoring | 4 offline benchmarks ready to hand over |
| #109 | live layers | enrich search-recall; validator shadow vs sonnet |
| #95 | extraction tier decision | still parked on sonnet pending harness |
| — | backlog | #98 #106 #70 #100 #102 #104 #107 #108 |

**Cross-repo follow-up:** local model scoring runs in the peer **liminal** session (RTX 3090), not stacks. stacks owns benchmark design + the pal-chat harness if a local tier is promoted; liminal owns the scores.

## Session log
- DECIDED: benchmarked synthesis, validation, and enrichment this session (extraction was the template), completing the four-stage offline suite (#109). Each scored on a stage-specific discrimination axis: synthesis over-claim, validation poison-recall + false-correction, enrichment false-CANDIDATE.
- DECIDED: scoring must be input-relative, not output-relative — synthesis scores against the concept BLOCK, not the audited published article (a superset with last_verified set). Metric denominators fixed so a wrong answer cannot game them.
- FACT: every stage's cheap-tier failure is the same shape — restraint under surface similarity, not transcription; a weak tier writes/judges fluently but over-reaches when a topic is nearby.
- FACT: codex adversarial review (background haiku courier, xhigh, danger-full-access) found 10 defects across the 3 new benchmarks; all 10 valid — false-gold, gameable denominators, a reversed assert-structure.sh arg order, a dash/dot slug typo. Verified the two checkable ones empirically before acting.
- ADR-ABSORBED: suite-complete state written into system-patterns.md (no ADR log in stacks; #109 program line reconciled from "only extraction benchmarked" to all four).
- superseded: standing fact "extraction is the only benchmarked stage" → all four stages now have an offline benchmark (S22); fact updated in place.

<!-- ═══ JOURNAL — derived view, carried forward by /stop, regenerable from archive/ ═══ -->

## Standing facts
- Local models cannot be dispatched via the Agent tool (reaches only sonnet/haiku/opus/fable); a local worker tier needs a pal-chat harness (read source → call local model via pal MCP `localhost:11434` → write output), an architecture change, not a frontmatter edit. (as-of: 2026-07-11) (rode: S22)
- liminal is the peer Claude session (local-LLM / fine-tuning expert) on **tmux window 3** (NOT 4 — window 4 is meap2-it); it scores local models against stacks benchmarks on a local RTX 3090. Walkie-talkie: `send-keys -t %1 "msg" Enter` then a separate `send-keys -t %1 Enter`. (as-of: 2026-07-11) (rode: S22)
- The `dev/experiments/model-tier/` dir (epic #109) is the first-class model-tier test area. **All four pipeline stages now have an offline gold-set benchmark** (extraction, synthesis, validation, enrichment); front-door `README.md` maps them. Local scoring by liminal + the live layers (enrich search-recall, validator shadow test) are the remaining epic work. (as-of: 2026-07-11) (rode: S22)

## Recent arc
- S22 (07-11): model-tier program (#109) — built the synthesis, validation, and enrichment offline benchmarks (extraction was the template), completing the four-stage suite; ran a codex adversarial review that caught 10 real scoring defects (all fixed: input-relative scoring, non-gameable denominators). Grounded the metric design via a `/stacks:lookup` into the llm-eval stack.
- S21 (07-11): model-tier program (#95→#109) — built the extraction benchmark, found the over-mint was scope-starvation not weak tier, shipped the `index.md` scope-map fix to all 4 worker agents (0.57.0–0.58.0) with a 0.57.1 anti-lumping counterweight; earlier in the window, an enrich/audit hardening batch (0.52.0–0.56.3). Collaboration with liminal on local-model scoring.

## Theme index
- model-tier-eval: S21, S22
- corpus-context-to-agents: S21
- enrich-audit-hardening: S21

<!-- journal:cold -->

## Arcs
(none yet)

## Milestones
(none yet)

## CONTEXT HANDOFF - 2026-07-11 (Session 22)

### Session summary
Single-arc session continuing the #109 model-tier program from S21. Started from a clean tree at 0.58.0 with S21's next-priority: benchmark the synthesis, enrichment, and validation stages (extraction was already done and is the template). Built all three, one per user go-ahead, routing through `/using-agent-skills` and `/stacks:lookup` (into the llm-eval stack: production-eval-systems, llm-as-judge, llm-judge-gate-wiring) for the metric design as the mandatory entry points require. Each benchmark isolates the stage's discrimination axis and keeps the non-deterministic/live half out of the offline layer: synthesis scores over-claim against the concept block; validation is a 7-item labeled set with symmetric poison-recall + false-correction floors (offline layer, shadow test vs sonnet above it); enrichment is a 6-item grounding-decision set with a false-CANDIDATE floor (offline layer, live search-recall above it). Gold answers anchored in verbatim source excerpts from real llm-stack sources. Then, at the user's request, ran a codex adversarial review via a background haiku courier (xhigh, danger-full-access per the codex gotcha) — it found 10 defects across the three new files, all valid; I verified the two checkable ones (assert-structure.sh signature, the arxiv slug separator) empirically before applying. Root cause was one class: a scoring key drifting from the actual input (published article as synthesis gold; gameable metric denominators; overclaimed structural-check coverage). All fixed and committed. Peer session liminal landed a local-model result commit (306948b) on shared master mid-session. 5 commits total (4 mine + liminal's). No version bump — `dev/experiments/` is planning-tier, not a shipped plugin artifact.

### Chat
S22-model-tier-benchmark-suite

### Changes made
| Change | Status |
|--------|--------|
| synthesis-benchmark.md (2f888ae) | committed |
| validation-benchmark.md (97aa361) | committed |
| enrichment-benchmark.md — completes offline suite (dc300df) | committed |
| codex-review fixes across all 3 new benchmarks (5f5ed26) | committed |
| README.md model-tier table + files list (each commit) | committed |
| system-patterns.md: #109 line reconciled to suite-complete | this handoff |
| liminal local-model result (306948b, UD-Q4_K_XL) | landed in-repo (peer) |

### Knowledge extracted
system-patterns.md: the #109 "Known Weak Spots" line updated from "only extraction benchmarked" to all four stages, with each stage's discrimination axis and the codex-hardening note. Standing fact 3 superseded to match. Three GitHub comments on #109 record the per-stage progress.

### Decisions recorded
No formal ADR (stacks has no decision-log). Two calls worth carrying: (1) scoring is input-relative — the concept block / claim+source pair is the gold, never the post-audit published article; (2) the offline gold-set is the settle-first layer, with live/shadow layers stacked above each stage's offline floor.

### Next session priority
#109 — hand the four offline benchmarks to liminal for local scoring on the RTX 3090 (the design half is done). Then the live layers: enrichment search-recall and the validator shadow test vs sonnet's live catch-rate. #95 extraction tier decision stays parked on sonnet pending the harness/variance resolution.

### Open issues
10 open: #70 #95 #98 #100 #102 #104 #106 #107 #108 #109.
