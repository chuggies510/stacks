# Stacks article-validation benchmark (for local-model tier eval — issue #109)

From: stacks session (S22). For: liminal, to score gemma4-31b / qwen3-30b-a3b / gpt-oss-20b (or others) against the accuracy bar the stacks pipeline needs on the **article-validation** stage (agent `validator`, currently pinned `model: sonnet`).

This is the **highest-stakes discrimination stage.** The validator reads each article against its cited sources and fixes any claim that overstates or contradicts its source *in place* — because `/stacks:lookup` reads articles, never the sources behind them, so a claim that wears a citation while asserting past its source is served to users as fact. A missed overstatement poisons the product silently; there is no downstream stage that catches it. Two errors matter symmetrically:

- **Miss (false negative):** the validator leaves an overstated/contradicted claim unfixed → poison shipped to lookup. Per #95 this is the strict-bar axis (recall of known overstatements).
- **False correction (false positive):** the validator "fixes" a claim its source *does* support → it corrupts truthful content just as badly. A cheaper tier that over-trims is not safe either.

The gold set below is the **offline** layer (a golden regression dataset, per the llm stack's `production-eval-systems` article). The **shadow** layer #95 asks for — a cheaper tier scored against sonnet's catch-rate over a live audit window — sits above it: offline golden regression first, then shadow mode against real traffic. Settle the offline floor here before shadowing.

## The task the model must do

For each item: read one article **claim** (as it appears in the body) and the **cited source excerpt**, and decide the verdict, using the benchmark's five classification labels below. These map to what the `validator` agent does — CLEAN (leave, emit only a VALIDATED receipt), the three CORRECTION classes, and SOFTSPOT — but the agent emits a **generic** `CORRECTION` audit row, not the subtype token; the subtypes here are scoring labels that name *which* correction the model should make:

- **CLEAN** — the source supports the claim as stated. Leave it. (No CORRECTION, no SOFTSPOT.)
- **CORRECTION / contradiction** — the source states something *different* (a different figure, a reversed claim). Rewrite the claim to match the source.
- **CORRECTION / overstatement** — the source is cited and covers the topic but the claim says **more** than it states (an added mechanism, a rationale "because…", an invented number, or a stronger generalization "consistently"/"outperforms"/"eliminates"). Trim the claim to what the source supports. **This is the dominant real defect in this corpus.**
- **CORRECTION / add-citation** — the claim carries no inline citation, but one of the article's own already-listed sources (in frontmatter `sources:`) states it. Add the `[source-slug]` citation; leave the wording.
- **SOFTSPOT** — the claim can be tied to **no** source at all (not cited, not listed). Leave the text in place and flag it verbatim. Never invent a citation or a fix.

The two boundaries a cheaper tier fails: **overstatement vs. CLEAN** (miss → poison) and **overstatement vs. SOFTSPOT** (a claim whose source is cited but overstated gets *trimmed*; a claim with no source at all gets *flagged, not trimmed*).

### Prompt to feed your model (verbatim, per item)

```
You are a knowledge validator. You are given ONE article claim and the CITED SOURCE
EXCERPT it rests on (plus, when relevant, the article's frontmatter `sources:` list).
Decide the verdict:

- CLEAN — the source supports the claim as stated. Leave it.
- CORRECTION/contradiction — the source states something different (figure, direction).
  Give the corrected claim text.
- CORRECTION/overstatement — the source covers the topic but the claim says MORE than it
  states (added mechanism, rationale "because…", invented number, or a stronger
  generalization like "consistently"/"outperforms"/"eliminates"/"any"/"zero"). Give the
  trimmed claim text (what the source actually supports).
- CORRECTION/add-citation — no inline citation, but a source already in the article's
  `sources:` list states it. Output the citation to add; leave wording unchanged.
- SOFTSPOT — the claim ties to NO source (not cited, not listed). Leave the text, flag it.
  Do NOT invent a citation or a fix.

Do NOT rewrite for wording, tone, or style — only for the four defects above.
OUTPUT one line, exactly one of:
  CLEAN
  CORRECTION/contradiction | {corrected claim text}
  CORRECTION/overstatement | {trimmed claim text}
  CORRECTION/add-citation  | {source-slug to add}
  SOFTSPOT
```

## Test items (claim + verbatim source excerpt inline — self-contained)

Each item gives the article **claim**, the **source excerpt** (verbatim from the cited source on this machine — path noted for audit), and the article's `sources:` frontmatter where it matters. Items marked **[planted]** carry a deliberately injected defect (a real claim amplified or altered against its real source); the rest are the article's real claims. Gold verdict follows each.

Source files (for audit): `llm/sources/arxiv/arxiv-2306.05685-llm-as-judge-mt-bench.md`, `llm/sources/zenml/zenml-2025-12-llmops-1200-deployments.md`.

---

**Item 1 — CLEAN** (restraint / true negative)
- Claim: `GPT-4 acting as judge reaches over 80% agreement with human preferences, the same level of agreement seen between two human raters. [arxiv-2306.05685-llm-as-judge-mt-bench]`
- Source: *"strong LLM judges like GPT-4 can match both controlled and crowdsourced human preferences well, achieving over 80% agreement, the same level of agreement between humans."*
- **Gold: CLEAN.** Any correction here is a false correction.

**Item 2 [planted] — OVERSTATEMENT** (cliff — the dominant defect)
- Claim: `GPT-4 acting as judge consistently outperforms human raters on open-ended evaluation. [arxiv-2306.05685-llm-as-judge-mt-bench]`
- Source: *"…can match both controlled and crowdsourced human preferences well, achieving over 80% agreement, the same level of agreement between humans."*
- **Gold: CORRECTION/overstatement.** Source says *match / same level*, not "consistently outperforms." Trim to e.g. `GPT-4 as judge matches human-rater agreement (~80%) on open-ended evaluation`. A tier that returns CLEAN here **misses a poison** — the failure the strict bar targets.

**Item 3 [planted] — CONTRADICTION**
- Claim: `The authors publicly released MT-bench questions, roughly 300 expert votes, and 30,000 conversations. [arxiv-2306.05685-llm-as-judge-mt-bench]`
- Source: *"Public release: MT-bench questions, ~3K expert votes, ~30K conversations."*
- **Gold: CORRECTION/contradiction.** `300` contradicts `~3K`. Fix the figure to ~3,000 (≈30,000 conversations is correct — do not touch it).

**Item 4 — CLEAN** (restraint / multi-fact true negative)
- Claim: `The paper documents three judge biases — position bias (favoring the first answer shown), verbosity bias (favoring longer answers), and self-enhancement bias (a judge favoring its own outputs). [arxiv-2306.05685-llm-as-judge-mt-bench]`
- Source: *"Known biases: position bias (favoring the first answer shown), verbosity bias (favoring longer answers), and self-enhancement bias (a judge favoring its own outputs); plus limited reasoning ability."*
- **Gold: CLEAN.** Every parenthetical matches the source. Trimming any of it is a false correction.

**Item 5 [planted] — OVERSTATEMENT** (added generalization + dropped gate)
- Claim: `Shadow mode lets a team deploy any new agent live with zero risk. [zenml-2025-12-llmops-1200-deployments]`
- Source: *"Ramp: Runs agents in shadow mode on transactions before live actions; LLM Judge compares predictions to actual outcomes. Only enables live actions once shadow accuracy hits specific threshold."*
- **Gold: CORRECTION/overstatement.** "any … zero risk" overstates and drops the threshold gate. Trim to e.g. `Shadow mode runs the new agent on real transactions before live actions; live actions are enabled only once shadow accuracy hits a defined threshold`. (The section is titled "Testing at Scale Without Risk," which baits a CLEAN verdict — but the body gates live deployment on a threshold, so "any/zero-risk" is unsupported.)

**Item 6 — UNCITED-BUT-GROUNDED** (add-citation, not softspot)
- Article `sources:` frontmatter lists `[zenml-2025-12-llmops-1200-deployments, evidentlyai-llm-as-a-judge-guide]`.
- Claim (no inline citation): `Cox Automotive runs continuous red teaming throughout its development lifecycle, not as a one-time pre-launch assessment.`
- Source (zenml, already listed): *"Cox Automotive: Continuous red teaming (not one-time assessment) integrated throughout development lifecycle."*
- **Gold: CORRECTION/add-citation → `zenml-2025-12-llmops-1200-deployments`.** The claim is attributed and stated exactly as the listed source has it, so the ONLY defect is the missing inline citation (no generalization to defend, so not an overstatement; a source ties to it, so not a softspot). The correct action adds the citation and leaves the wording unchanged — trimming the wording here is a false correction (see metric 2).

**Item 7 — SOFTSPOT** (no source ties to it — restraint on the overstatement/softspot boundary)
- Article `sources:` frontmatter lists `[zenml-2025-12-llmops-1200-deployments, evidentlyai-llm-as-a-judge-guide]`.
- Claim (no inline citation): `In practice, most teams find a two-week shadow-mode window sufficient before enabling live execution.`
- Source: neither listed source states any window length; no cited source covers it.
- **Gold: SOFTSPOT.** Leave the sentence, flag it verbatim. Returning CORRECTION/overstatement (trimming a claim no source bounds) OR inventing a citation is the **false-correction failure** on this boundary — the claim is connective inference, not an overstatement of a cited source.

## Gold summary

| # | Class | Gold verdict | Failure that poisons |
|---|---|---|---|
| 1 | clean | CLEAN | false correction (trim a supported claim) |
| 2 | overstatement | CORRECTION/overstatement | **miss (return CLEAN)** |
| 3 | contradiction | CORRECTION/contradiction | miss (return CLEAN) |
| 4 | clean | CLEAN | false correction |
| 5 | overstatement | CORRECTION/overstatement | **miss (return CLEAN)** |
| 6 | uncited-grounded | CORRECTION/add-citation | leave uncited, or mis-flag softspot |
| 7 | no source | SOFTSPOT | false correction (trim) or invented citation |

## Metric + the bar we need

1. **Poison recall** = of the overstatement/contradiction items {2, 3, 5}, the fraction the model catches AND corrects *properly* — returns a CORRECTION whose replacement text removes the unsupported assertion and matches the cited source excerpt. A CORRECTION token whose replacement is hallucinated or still overstated does NOT count as caught (it swaps one poison for another); CLEAN or SOFTSPOT on these items is a miss. **Floor ≥ 0.90** — with 3 items, all three. The bar is strict because nothing downstream catches a claim served to lookup as fact.
2. **False-correction rate** = over the fixed set **{1, 4, 6, 7}** (denominator 4), the fraction the model wrongly alters: a trim/fix on the clean items 1 or 4; on item 6, changing the wording instead of only adding the citation; on item 7, a trim/fix or invented citation (its only correct action is flag-as-SOFTSPOT). **Floor: 0.** Over-correction corrupts truthful content, as damaging as a miss.
3. **Action accuracy** (all 7) = fraction with the exact gold verdict-action from the table. Report. The two signatures that disqualify a tier are a {2,3,5} item returned CLEAN/SOFTSPOT (miss) and a {1,4,7} item trimmed/fixed (false correction) — a within-CORRECTION class swap (calling an overstatement a contradiction) still trims the poison, so it is a minor error, not a floor breach.
4. **Determinism** (report, not gated) = identical verdict set across 3 greedy passes.

A model that clears floors 1–2 is a viable validation tier. The likely weak-tier signature is **either** direction: a rubber-stamp tier returns CLEAN on the planted overstatements (misses poison — floor 1 breach), or an over-eager tier trims the clean/softspot items (corrupts truth — floor 2 breach). The stage needs a model that discriminates *supported* from *overstated* without doing either — the same restraint the synthesis stage needs, applied to judging instead of writing.

## What to send back

Per model: poison recall (with any missed item quoted), false-correction rate (with any wrongly-altered item quoted), the per-item verdict line, and the determinism result. If a model clears floors 1–2 deterministically it is a candidate validation tier; note its tok/s. This is the offline gold set — the shadow test against sonnet's live catch-rate (#95) is the next layer once a candidate clears here. Enrichment (false-CANDIDATE rate) is the remaining stage.
