# Stacks source-enrichment benchmark (for local-model tier eval — issue #109)

From: stacks session (S22). For: liminal, to score gemma4-31b / qwen3-30b-a3b / gpt-oss-20b (or others) against the accuracy bar the stacks pipeline needs on the **source-enrichment** stage (agent `enrichment`, currently pinned `model: sonnet`).

The enrichment agent takes a **soft spot** (a claim in an article with no cited source) and finds a web source that grounds it — then rates the source's tier, dedups against filed sources, and emits a verdict (`CANDIDATE` / `WEAK` / `DUP` / `NOSOURCE`). The stage's one hard judgment, and the one #95 names as the accuracy axis, is **false-CANDIDATE rate**: accepting a source that is *topically related* to the claim but does not actually *state* it. A bad source stamped `CANDIDATE` and approved becomes a citation in the article — model-grounded-in-model, served to `/stacks:lookup` as fact. The agent's own bias rule: "Verify the source grounds the specific claim, not merely the topic. Default to NOSOURCE when unsure."

**Scope: the grounding decision, not the web search.** The live half of this stage (`WebSearch` → `WebFetch` to *find* a candidate) is non-deterministic and uses the same search tool across tiers, so it is not what separates a cheap tier from sonnet. What separates them is the **grounding judgment**: given a claim and a fetched passage, does the passage support the claim, and at what tier? This benchmark isolates that judgment — each item supplies the claim and the candidate passage, so it is self-contained and deterministic (the offline layer). A supplementary live search-recall check can follow, but the discrimination floor is set here.

## The task the model must do

For each item: read one **claim** and one candidate **source passage** (verbatim, with the source's title/URL and its STACK.md tier), plus — where relevant — the **filed-sources listing** for dedup. Emit one verdict:

- **CANDIDATE** — the passage directly states or supports the claim, and the source is tier 1-3. Record its tier.
- **WEAK** — the passage supports the claim, but the source is tier 4 (forum / general).
- **DUP** — the grounding source is already in the filed-sources listing (cite the existing one, no new source needed).
- **NOSOURCE** — no supplied passage supports the *specific* claim (topically related is not enough), or nothing grounds it.

The boundary a cheaper tier fails: **CANDIDATE vs. NOSOURCE** when the passage is *on-topic but silent on the claim's specific assertion* (a figure, a mechanism, a named result). Accepting it is the false-CANDIDATE failure.

### Prompt to feed your model (verbatim, per item)

```
You acquire sources for unsourced claims. You are given ONE claim and ONE candidate
source passage (with its title, URL, and trust tier), and — when present — a
filed-sources listing.

Decide whether the passage grounds THE SPECIFIC CLAIM, not merely its topic. A passage
about the claim's subject that does not state the claim's actual assertion (its figure,
mechanism, or named result) does NOT ground it. Default to NOSOURCE when unsure — a
wrong citation is worse than an open soft spot.

Tiers: 1 vendor/official docs · 2 peer-reviewed papers / vendor research · 3 practitioner
blogs / production case studies · 4 forum / general (X, HN, Reddit).

OUTPUT one line, exactly one of:
  CANDIDATE | tier:<1-3>
  WEAK | tier:4
  DUP | <filed-source-slug>
  NOSOURCE | <short reason>
```

## Test items (claim + candidate passage inline — self-contained)

Passages are verbatim from real sources on this machine except where marked **[constructed]** (a fixture for a tier the real corpus doesn't hand us). Gold verdict follows each.

---

**Item 1 — CANDIDATE (clean grounding, tier 2)**
- Claim: `GPT-4 acting as judge reaches over 80% agreement with human preferences.`
- Candidate: *"Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena"* — https://arxiv.org/abs/2306.05685 (arXiv paper, tier 2)
- Passage: *"strong LLM judges like GPT-4 can match both controlled and crowdsourced human preferences well, achieving over 80% agreement, the same level of agreement between humans."*
- **Gold: CANDIDATE | tier:2.** The passage states the exact figure.

**Item 2 (cliff) — NOSOURCE (false-CANDIDATE trap: on-topic, silent on the claim)**
- Claim: `A two-week shadow-mode validation window is standard before enabling live execution.`
- Candidate: *"What 1,200 Production Deployments Reveal About LLMOps in 2025"* — https://www.zenml.io/blog/what-1200-production-deployments-reveal-about-llmops-in-2025 (tier 3)
- Passage: *"Ramp: Runs agents in shadow mode on transactions before live actions; LLM Judge compares predictions to actual outcomes. Only enables live actions once shadow accuracy hits specific threshold."*
- **Gold: NOSOURCE.** The passage is about shadow mode and a *threshold* gate, but says nothing about a **two-week window**. Returning CANDIDATE because the passage is "about shadow mode" is the false-CANDIDATE failure.

**Item 3 (cliff) — NOSOURCE (topic named, specific mechanism absent)**
- Claim: `Position bias in LLM judges is fully eliminated by averaging scores across three independent judge models.`
- Candidate: *"Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena"* — https://arxiv.org/abs/2306.05685 (tier 2)
- Passage: *"Known biases: position bias (favoring the first answer shown), verbosity bias (favoring longer answers), and self-enhancement bias (a judge favoring its own outputs); plus limited reasoning ability. The paper proposes mitigations for some."*
- **Gold: NOSOURCE.** The passage names position bias and says mitigations exist *for some* biases — it does **not** state the claim's specific "three-model averaging fully eliminates it" mechanism. On-topic, does not ground the assertion.

**Item 4 — CANDIDATE (tier assignment — practitioner case study, tier 3)**
- Claim: `Cox Automotive runs continuous red teaming integrated throughout its development lifecycle, not as a one-time pre-launch assessment.`
- Candidate: *"What 1,200 Production Deployments Reveal About LLMOps in 2025"* — https://www.zenml.io/blog/what-1200-production-deployments-reveal-about-llmops-in-2025 (tier 3)
- Passage: *"Cox Automotive: Continuous red teaming (not one-time assessment) integrated throughout development lifecycle. Testing checks what works; red teaming tries to break it."*
- **Gold: CANDIDATE | tier:3.** Directly states it. Tier is 3 (a practitioner LLMOps case-study aggregation), not 1 or 2 — the tier-accuracy check.

**Item 5 — WEAK (grounded, but tier 4 forum)**
- Claim: `Enabling prefix caching in vLLM roughly doubles throughput on shared-system-prompt workloads.`
- Candidate: **[constructed forum excerpt]** an r/LocalLLaMA comment thread (tier 4).
- Passage: *"Flipped on APC (automatic prefix caching) in vLLM for our RAG service where every request shares a big system prompt — throughput went from ~x to roughly 2x, basically free since the prefix is identical every call."*
- **Gold: WEAK | tier:4.** The passage supports the claim, but a forum comment is tier 4 → WEAK, not CANDIDATE. Tests the tier-4 downgrade (a model that returns CANDIDATE here mis-tiers a forum source).

**Item 6 — DUP (already-filed source grounds it)**
- Claim: `MT-bench and Chatbot Arena were introduced to verify LLM-judge agreement with human preferences.`
- Filed-sources listing (already in this stack):
  ```
  arxiv-2306.05685-llm-as-judge-mt-bench	https://arxiv.org/abs/2306.05685
  zenml-2025-12-llmops-1200-deployments	https://www.zenml.io/blog/what-1200-production-deployments-reveal-about-llmops-in-2025
  ```
- Candidate: same arXiv paper — https://arxiv.org/abs/2306.05685 — passage: *"we verify the agreement between LLM judges and human preferences by introducing two benchmarks: MT-bench, a multi-turn question set; and Chatbot Arena, a crowdsourced battle platform."*
- **Gold: DUP | arxiv-2306.05685-llm-as-judge-mt-bench.** The passage grounds the claim, but its URL is already filed — the operator cites the existing source; no new candidate. Returning CANDIDATE (a duplicate source) is the dedup miss.

## Gold summary

| # | Gold verdict | Failure that poisons / wastes |
|---|---|---|
| 1 | CANDIDATE tier:2 | NOSOURCE (over-conservative — rejects real grounding) |
| 2 | NOSOURCE | **CANDIDATE/WEAK (false-CANDIDATE — topical page accepted)** |
| 3 | NOSOURCE | **CANDIDATE/WEAK (false-CANDIDATE — mechanism not stated)** |
| 4 | CANDIDATE tier:3 | wrong tier, or NOSOURCE |
| 5 | WEAK tier:4 | CANDIDATE (mis-tiers a forum source as usable) |
| 6 | DUP | CANDIDATE (dedup miss — files a duplicate) |

## Metric + the bar we need

1. **False-CANDIDATE rate** = of the trap items {2, 3}, the fraction wrongly returned CANDIDATE or WEAK. **Floor: 0.** This is the #95 axis — a topical-but-non-grounding source accepted becomes a wrong citation lookup serves as fact.
2. **Grounding recall** = of the real-grounding items {1, 4, 6}, the fraction correctly returned CANDIDATE or DUP (not NOSOURCE). **Floor ≥ 0.90.** A tier so timid it rejects genuine grounding leaves every soft spot open — the opposite failure.
3. **Tier accuracy** = over the **fixed tier-bearing set {items 1, 4, 5}**, the fraction returned with BOTH the exact gold verdict AND tier (CANDIDATE tier:2, CANDIDATE tier:3, WEAK tier:4). Scored on a fixed set, not on "items the model returned CANDIDATE/WEAK for" — otherwise a wrong NOSOURCE shrinks the denominator and inflates the score. DUP (item 6) carries no tier and is excluded here (scored by floor 4). **Floor: 3/3.**
4. **DUP detection** = item 6 returned DUP (not CANDIDATE), deduped against the filed listing. **Floor: correct** (binary) — filing a duplicate as a new CANDIDATE is a real waste, so this gates viability, not report-only.
5. **Determinism** (report, not gated) = identical verdict set across 3 greedy passes.

A model that clears floors 1–4 is a viable enrichment tier. The likely weak-tier signature is **false-CANDIDATE on {2, 3}** — a fluent model pattern-matches "passage is about the topic" to "passage grounds the claim" and stamps CANDIDATE, exactly the discrimination the stage exists to hold. This is the enrichment analog of the validator's poison-recall and the synthesizer's over-claim: the cheap tier fails on *restraint under topical similarity*, not on transcription.

## What to send back

Per model: false-CANDIDATE rate (with any wrongly-accepted trap item quoted), grounding recall, tier accuracy, the DUP verdict, the per-item verdict line, and the determinism result. If a model clears floors 1–3 deterministically, note its tok/s. This completes the four-stage offline benchmark suite (extraction, synthesis, validation, enrichment); the live layers — haiku/local search-recall for enrichment, the sonnet shadow test for validation — sit above the offline floors each stage now has.
