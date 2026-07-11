---
session: 23
---

# stacks Active Context

## Current state

| | |
|-|-|
| Version | 0.58.0 (unchanged — benchmark/dev work, no plugin bump) |
| Tests | markdown/spec only; no pipeline `--self-check` touched |
| Shipped | two codex passes hardened all four model-tier benchmarks; extraction reuse-precision floor closes an emit-every-slug gaming hole (#109) |
| In flight | none — closed clean |
| Peer | liminal (tmux win 3) now committing gold-scored local-model numbers (c67ec39 retracted raw-count rankings; 6fd32de: dynamic quant is a wash) |

## Open thread

None, closed clean. A third codex confirmation pass was offered and declined; the real final check is liminal's scoring run, not another paper review.

## Next priority

| # | Item | Note |
|---|------|------|
| #109 | liminal local scoring | 4 verified benchmarks ready; scores landing |
| #109 | live layers | enrich search-recall; validator shadow vs sonnet |
| #95 | extraction tier decision | still parked on sonnet |
| — | backlog | #98 #106 #70 #100 #102 #104 #107 #108 |

**Cross-repo follow-up:** local-model scoring + the gold-scored result numbers live in the peer **liminal** session (RTX 3090), which commits results to shared stacks master. stacks owns benchmark design; liminal owns the scores.

## Session log
- FACT: a single codex pass is not "verified." The confirmation pass found the first round's fixes held (9/10) but introduced 3 adjacent defects, and the never-reviewed extraction benchmark (reused as a template) carried 4 critical defects of its own — including a gaming hole where emitting every slug scored perfect recall with no penalty. Lesson: fixes need a confirmation pass, and a template artifact reused unaudited carries its own defects.
- DECIDED: added a reuse-precision floor to the extraction benchmark (closes the emit-everything hole); made all four benchmarks per-item scored with fixed, non-gameable denominators; corrected extraction item-2 gold (two concepts, `token-budget-management` was a false target) and item-3 mint allowance (0 — the concept was already covered).
- FACT: verified every codex claim against the real corpus before applying (article routings, agent-harness-engineering's GRPO coverage, the three articles missing from the slug list) — all held.
- ADR-ABSORBED: system-patterns.md #109 line updated from one-review-of-three to two-passes-across-all-four, with the reuse-precision-floor catch noted.

<!-- ═══ JOURNAL — derived view, carried forward by /stop, regenerable from archive/ ═══ -->

## Standing facts
- Local models cannot be dispatched via the Agent tool (reaches only sonnet/haiku/opus/fable); a local worker tier needs a pal-chat harness (read source → call local model via pal MCP `localhost:11434` → write output), an architecture change, not a frontmatter edit. (as-of: 2026-07-11) (rode: S22, S23)
- liminal is the peer Claude session (local-LLM / fine-tuning expert) on **tmux window 3** (NOT 4 — window 4 is meap2-it); it scores local models against stacks benchmarks on a local RTX 3090. Walkie-talkie: `send-keys -t %1 "msg" Enter` then a separate `send-keys -t %1 Enter`. (as-of: 2026-07-11) (rode: S22, S23)
- The `dev/experiments/model-tier/` dir (epic #109) is the first-class model-tier test area. **All four pipeline stages now have an offline gold-set benchmark** (extraction, synthesis, validation, enrichment); front-door `README.md` maps them. Local scoring by liminal + the live layers (enrich search-recall, validator shadow test) are the remaining epic work. (as-of: 2026-07-11) (rode: S22, S23)

## Recent arc
- S23 (07-11): model-tier program (#109) — ran a codex confirmation pass on the S22 benchmarks: verified 9/10 first-round fixes held, fixed 3 adjacent defects, and audited the extraction benchmark for the first time (4 critical, incl. a reuse-precision gaming hole), all verified against the corpus before fixing. liminal began landing gold-scored local-model numbers.
- S22 (07-11): model-tier program (#109) — built the synthesis, validation, and enrichment offline benchmarks (extraction was the template), completing the four-stage suite; ran a codex adversarial review that caught 10 real scoring defects (all fixed: input-relative scoring, non-gameable denominators). Grounded the metric design via a `/stacks:lookup` into the llm-eval stack.
- S21 (07-11): model-tier program (#95→#109) — built the extraction benchmark, found the over-mint was scope-starvation not weak tier, shipped the `index.md` scope-map fix to all 4 worker agents (0.57.0–0.58.0) with a 0.57.1 anti-lumping counterweight; earlier in the window, an enrich/audit hardening batch (0.52.0–0.56.3). Collaboration with liminal on local-model scoring.

## Theme index
- model-tier-eval: S21, S22, S23
- corpus-context-to-agents: S21
- enrich-audit-hardening: S21

<!-- journal:cold -->

## Arcs
(none yet)

## Milestones
(none yet)

## CONTEXT HANDOFF - 2026-07-11 (Session 23)

### Session summary
Continuation of S22 after its handoff already committed: the user asked to verify the benchmarks with codex and questioned whether they were actually verified and which model ran. Ran a second codex adversarial pass via a background haiku courier (xhigh, danger-full-access per the codex gotcha, no model pin — the MCP did not surface which model ran, and pinning is rejected under the ChatGPT-account login). Two jobs: (A) confirm the S22 fixes — 9 of 10 resolved, 1 partial (a section heading still contradicted block-relative scoring) plus 3 adjacent defects the fixes had introduced (an ambiguous false-correction denominator, a second stale "floors 1-3" line, an overstated structural check); (B) first-ever audit of the S21 extraction benchmark — 7 defects, 4 critical: an emit-every-slug gaming hole (perfect recall, zero penalty), aggregate recall that could hide a fully-failed item, a false item-2 gold target (`token-budget-management` is tokenization-only; the Tianpan content is `context-engineering` + `llm-cost-control-production`), and an item-3 mint allowance for a concept `agent-harness-engineering` already covers. Every checkable codex claim was verified against the real corpus (article routings, the GRPO coverage, three articles missing from the slug list) before any edit — all held. Fixed all of it: added a reuse-precision floor, per-item scoring with fixed denominators, corrected golds. The honest status reported to the user: two passes done, converging, but the second round of fixes is itself un-reconfirmed by a third pass — the real final check is liminal's scoring run, not more paper review. 3 commits since S22 (1 mine, 2 liminal's local-model results).

### Chat
S23-benchmark-codex-verification

### Changes made
| Change | Status |
|--------|--------|
| Second codex pass fixes across all 4 benchmarks (1dedd48) | committed |
| liminal: retract raw-count recall rankings, add gold-scored numbers (c67ec39) | landed in-repo (peer) |
| liminal: UD-Q3_K_XL — dynamic quant is a wash (6fd32de) | landed in-repo (peer) |
| system-patterns.md: #109 line → two-passes/all-four + reuse-precision floor | this handoff |

### Knowledge extracted
system-patterns.md: the #109 line updated from "a codex review hardened the three new ones" to two adversarial passes across all four, with the emit-every-slug gaming hole and its reuse-precision-floor fix named.

### Decisions recorded
No formal ADR (stacks has no decision-log). Carried: a single adversarial pass is not "verified" — a confirmation pass and, for a reused template artifact, its own first audit are both required.

### Next session priority
#109 — liminal's local scoring against the four verified benchmarks is the live work (scores are already landing). Then the live layers: enrichment search-recall and the validator shadow test vs sonnet. A third codex confirmation pass on the second-round fixes is optional and low-value; the scoring run is the real check. #95 extraction tier decision stays parked on sonnet.

### Open issues
10 open: #70 #95 #98 #100 #102 #104 #106 #107 #108 #109.
