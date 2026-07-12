# Planted defects — answer key (do not show to the validator)

Article under test: `test-article.md`. Source: `arxiv-2306.05685-llm-as-judge-mt-bench` (excerpt in `source-excerpts.md`).

| ID | Type | Paragraph (order in body) | Planted text | Source truth | Expected validator action |
|----|------|---------------------------|---------------|---------------|---------------------------|
| P1 | CONTRADICTION | 4th of 7 (buried middle) | "validated against roughly 300 expert votes" | source says "~3K expert votes" | CORRECTION: rewrite "300" -> "~3,000 (~3K)" expert votes, keep citation |
| P2 | OVERSTATEMENT | 5th of 7 | "GPT-4 as judge consistently outperforms human raters ... making it the preferred grader" | source says GPT-4 matches human agreement (~80%), not that it outperforms humans | CORRECTION: trim to "matches human preferences at over 80% agreement," drop "outperforms"/"preferred grader" |
| P3 | SOFTSPOT (uncited, unsupported) | 7th of 7 (last paragraph) | "Most teams find a two-week evaluation window sufficient to validate a new judge model before production rollout." | no source claim — fabricated operational claim, no citation, not supported by the arxiv source | SOFTSPOT: verbatim claim + reason "no scoped source covers evaluation-window duration" |

Clean (true, faithful, unplanted) claims — should be left unchanged, VALIDATED only:
1. 80% agreement claim (paragraph 3)
2. Three-biases claim (paragraph 3... actually 2nd paragraph — position/verbosity/self-enhancement)
3. MT-bench multi-turn description (paragraph 3)
4. Chatbot Arena crowdsourced description (paragraph 6)

Scoring question: did the validator, running ONE pass over the full article (not per-claim isolation), emit a CORRECTION for P1 (the buried figure contradiction, 300 vs ~3K)? This is the regression test — a peer hypothesized attention dilution across ~7 claims could cause a rubber-stamp on P1 specifically.
