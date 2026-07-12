# Result — sonnet validator, buried contradiction, full-article context

## Setup

Ran the shipped `validator` agent prompt (`/home/chris/chungus/dev/stacks/agents/validator.md`, sonnet-pinned, verbatim, no edits) as sonnet myself over one synthetic article (`test-article.md`) built from real content in `arxiv-2306.05685-llm-as-judge-mt-bench.md` (the MT-bench / Chatbot Arena LLM-as-judge paper). One pass over the whole article (7 body claims together), matching how the real batch validator sees a full article — not claim-by-claim isolation.

Planted defects (key in `planted-key.md`, never shown to the validation pass): P1 contradiction (buried 4th of 7 paragraphs), P2 overstatement (5th of 7), P3 uncited/unsupported claim (7th of 7, last paragraph).

## Verdicts

| ID | Type | Planted text | Caught? | Action taken |
|----|------|--------------|---------|--------------|
| P1 | Contradiction | "roughly 300 expert votes" (source: ~3K) | **CAUGHT** | CORRECTION: "300" → "~3,000 (~3K) expert votes" |
| P2 | Overstatement | "consistently outperforms human raters ... preferred grader" (source: matches, not outperforms) | **CAUGHT** | CORRECTION: trimmed to "matches human preferences at over 80% agreement" |
| P3 | Softspot (uncited, unsupported) | "two-week evaluation window sufficient" | **CAUGHT** | SOFTSPOT: verbatim claim + "no scoped source covers evaluation-window duration" |

All 4 unplanted control claims (80% agreement, three biases, MT-bench description, Chatbot Arena description) were left unchanged — no false-positive corrections.

## P1 exact correction text produced

Before: `The public MT-bench release was validated against roughly 300 expert votes collected across the question set, ... [arxiv-2306.05685-llm-as-judge-mt-bench]`

After: `The public MT-bench release was validated against roughly 3,000 (~3K) expert votes collected across the question set, ... [arxiv-2306.05685-llm-as-judge-mt-bench]`

Audit row: `CORRECTION	llm-as-a-judge-evaluation-method	"roughly 300 expert votes" → "~3,000 (~3K) expert votes" per [arxiv-2306.05685-llm-as-judge-mt-bench]`

## Verdict

**Sonnet catches buried contradictions (no prod regression).** The figure mismatch (300 vs ~3K) was caught and fixed even buried in the middle of a 7-claim article, alongside a separate overstatement and a separate uncited softspot in the same pass — no evidence of attention dilution causing a rubber-stamp on this run.

## Caveat (n=1, judgment calls noted for transparency)

This is a single run, single article, single planted-defect set — not a statistical sample. Two of the four "clean" control claims (MT-bench's stated purpose, Chatbot Arena's description) carry mild elaboration beyond the terse source excerpt (e.g., "anonymized model outputs" is true of Chatbot Arena but not stated in the provided excerpt); I judged these as reasonable connective description rather than overstatement since they don't invert a figure or add a mechanism/rationale the source contradicts, consistent with the prompt's Example 1 leniency. A stricter reading could flag those two as additional overstatement corrections — it would not change the P1/P2/P3 result, which is the regression question this test targets. Single n=1 result; does not rule out attention dilution at higher claim density or with a subtler contradiction (e.g., a percentage-point difference instead of a 10x figure mismatch).
