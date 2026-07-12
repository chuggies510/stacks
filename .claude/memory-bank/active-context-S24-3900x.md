---
session: 24
---

# stacks Active Context

## Current state

| | |
|-|-|
| Version | 0.60.1 (shipped this session; 0.58.0 → 0.59.0 → 0.60.0 → 0.60.1) |
| Tests | catalog 23/23, audit 18/18, enrich 13/13, dedup near-dup PASS |
| Shipped | validator gate-first (0.59.0) + 7-issue pipeline/skill cutover batch (0.60.x); codex-verified |
| In flight | none — closed clean |
| Cost | $23.51 · 6h21m |

## Open thread

None, closed clean. The 7-issue batch is fully resolved (5 closed, 2 deferred with tracked issue comments), committed, pushed, and passed a codex adversarial pass whose 3 real findings were fixed in 0.60.1.

## Next priority

| # | Item | Note |
|---|------|------|
| #109 | liminal local scoring | live layers: enrich recall, validator shadow vs sonnet |
| #102 | catalog fan-out reduction | deferred; coverage-preserving design shape in issue comment |
| #100 | audit `--only` scope | optional, low; verified.tsv half already fixed |
| #95 | extraction tier decision | parked on sonnet |
| — | backlog | #70 |

**Cross-repo follow-up:** local-model scoring + gold-scored numbers live in the peer **liminal** session (RTX 3090), committing results to shared stacks master. stacks owns benchmark design; liminal owns scores.

## Session log
- DECIDED: near-dup metric (#106) → distinctive-token set cosine (strip template tokens in ≥3 titles, then compare remainder), replacing the raw title-string ratio that both false-flagged shared templates and missed real dups. Report-only; `--self-check` guards it; full-token fallback added so 3+ identical titles still flag (codex pass).
- DECIDED: #102 fan-out reduction deferred — packing small sources into one extractor must preserve the per-source receipt (1 source → 1 file + sentinel) that gate-w1 coverage depends on; naive merge risks silent knowledge loss. Coverage-preserving shape filed as an issue comment. #100 verified.tsv already fixed since v0.52.0 (the reported stack predates it — legacy state, self-heals); re-scoped to the optional `--only` escape hatch.
- TRAP: `\t` in a single-quoted `grep` pattern matches a tab under the Bash-tool `ugrep` wrapper (interactive) but is literal `t` under real GNU grep in a script's child bash — a self-check authored through the tool passes falsely. Use `$'\t'`. (→ CLAUDE.md gotcha, #104)
- FACT: the Bash tool's `grep` is a `ugrep`-wrapping shell function (`type grep`), NOT exported into the child bash a script spawns.
- ARC: #109 cutover-prep — validator gate-first (0.59.0) then a 7-issue pipeline/skill batch (0.60.0/0.60.1) fixed via 3 parallel agents + a codex courier; 5 issues closed, 2 deferred with tracked comments.

<!-- ═══ JOURNAL — derived view, carried forward by /stop, regenerable from archive/ ═══ -->

## Standing facts
- Local models cannot be dispatched via the Agent tool (reaches only sonnet/haiku/opus/fable); a local worker tier needs a pal-chat harness (read source → call local model via pal MCP `localhost:11434` → write output), an architecture change, not a frontmatter edit. (as-of: 2026-07-11) (rode: S22, S23, S24)
- liminal is the peer Claude session (local-LLM / fine-tuning expert) on **tmux window 3** (NOT 4 — window 4 is meap2-it); it scores local models against stacks benchmarks on a local RTX 3090. Walkie-talkie: `send-keys -t %1 "msg" Enter` then a separate `send-keys -t %1 Enter`. (as-of: 2026-07-11) (rode: S22, S23, S24)
- The `dev/experiments/model-tier/` dir (epic #109) is the first-class model-tier test area. **All four pipeline stages now have an offline gold-set benchmark** (extraction, synthesis, validation, enrichment); front-door `README.md` maps them. Local scoring by liminal + the live layers (enrich search-recall, validator shadow test) are the remaining epic work. (as-of: 2026-07-11) (rode: S22, S23, S24)

## Recent arc
- S24 (07-11): #109 cutover-prep — shipped validator gate-first prompt hardening (0.59.0), then a 7-issue pipeline/skill batch (0.60.0/0.60.1): fixed the catalog self-check `\t`/grep tab-escape (#104), rewrote near-dup detection (#106), enrich source-URL dedup (#98), a lookup web-search guardrail (#107), and background dispatch across the 3 pipeline skills (#108) — via 3 parallel agents + a codex courier that caught 3 real edge cases (fixed in 0.60.1). #102 and #100 deferred with tracked comments.
- S23 (07-11): model-tier program (#109) — ran a codex confirmation pass on the S22 benchmarks: verified 9/10 first-round fixes held, fixed 3 adjacent defects, and audited the extraction benchmark for the first time (4 critical, incl. a reuse-precision gaming hole), all verified against the corpus before fixing. liminal began landing gold-scored local-model numbers.
- S22 (07-11): model-tier program (#109) — built the synthesis, validation, and enrichment offline benchmarks (extraction was the template), completing the four-stage suite; ran a codex adversarial review that caught 10 real scoring defects (all fixed: input-relative scoring, non-gameable denominators). Grounded the metric design via a `/stacks:lookup` into the llm-eval stack.
- S21 (07-11): model-tier program (#95→#109) — built the extraction benchmark, found the over-mint was scope-starvation not weak tier, shipped the `index.md` scope-map fix to all 4 worker agents (0.57.0–0.58.0) with a 0.57.1 anti-lumping counterweight; earlier in the window, an enrich/audit hardening batch (0.52.0–0.56.3). Collaboration with liminal on local-model scoring.

## Theme index
- model-tier-eval: S21, S22, S23, S24
- corpus-context-to-agents: S21
- pipeline-hardening (was: enrich-audit-hardening): S21, S24

<!-- journal:cold -->

## Arcs
(none yet)

## Milestones
(none yet)

## CONTEXT HANDOFF - 2026-07-11 (Session 24)

### Session summary
Two arcs, both under epic #109 (cheapest-model-per-stage cutover). Opening segment (pre-compaction, commits 5d7a524/9ee9421/6e097c8/7922e37): coordinated with the liminal peer session on validator benchmark scoring — 4 local tiers cleared both gated floors deterministically with a universal item-6 (add-citation) miss — then root-caused the miss to a flat verdict list and shipped a gate-first restructure of the validator prompt AND the validation benchmark (Step 1 gates "leave unchanged" on inline-citation presence), plus a source-extractor reuse-vs-mint clarity hoist and an article-synthesizer dead-prose trim (0.59.0). Main segment (this turn, commits 47e2ebe/a0d72fa): the user batched 7 backlog issues (#104 #106 #102 #107 #98 #100 #108) to fix using /dispatching-parallel-agents. Partitioned by exclusive file ownership: 3 independent lanes (lookup #107, enrich #98+#108, audit #100+#108) ran as parallel background sonnet agents while I took the entangled catalog+dedup design cluster (#104 #106 #108-catalog) on the session model. #104's "flaky" self-check was actually a deterministic `\t`-in-single-quotes grep bug exposed only because the Bash tool's interactive grep is a ugrep wrapper (honors `\t`) while the script's child bash uses real GNU grep (doesn't) — my first "verification" matched falsely. #106 got a new distinctive-token near-dup metric. Shipped 0.60.0, then a background codex courier flagged 3 real edge cases (near-dup missing identical titles, a lookup miss/partial-hit contradiction the #107 edit introduced, an enrich regex over-match) — all fixed in 0.60.1. #102 and #100 needed no/deferred code and got tracked issue comments.

### Chat
S24-pipeline-cutover-batch

### Changes made
| Change | Status |
|--------|--------|
| Validator + benchmark gate-first, extractor hoist, synthesizer trim (7922e37, 0.59.0) | committed |
| Validator benchmark gate-first prompt (6e097c8) | committed |
| Validator ranking + local scores (9ee9421, 5d7a524, incl. liminal results) | committed |
| 7-issue cutover batch: #104 #106 #98 #107 #108 (47e2ebe, 0.60.0) | committed + pushed |
| Codex hardening: 3 edge cases (a0d72fa, 0.60.1) | committed + pushed |
| Durable reconcile: catalog 23 cases, near-dup metric, drop strip-on-rewrite, #108 dispatch, `\t` gotcha | this handoff |

### Knowledge extracted
tech-context.md: catalog `--self-check` 20→23 cases + tab-escape note; dedup-extractions.py near-dup metric + `--self-check`. system-patterns.md: dropped the removed strip-on-rewrite rule from the W2 flow; noted `run_in_background` dispatch (#108). CLAUDE.md: new gotcha — `\t` in single-quoted grep is a tab under the Bash-tool ugrep wrapper but literal under real GNU grep in child bash.

### Decisions recorded
No formal ADR (stacks has no decision-log). Carried in Session log: near-dup metric choice (#106) and the #102 deferral rationale (per-source receipt is load-bearing for coverage).

### Next session priority
#109 remains the live epic: liminal's local scoring against the four benchmarks, then the live layers (enrich search-recall, validator shadow vs sonnet). #102 (fan-out reduction) is deferred with a coverage-preserving design shape in its issue comment; #100 (`--only` scope) is optional. #95 extraction tier stays parked on sonnet.

### Open issues
5 open: #70 #95 #100 #102 #109.
