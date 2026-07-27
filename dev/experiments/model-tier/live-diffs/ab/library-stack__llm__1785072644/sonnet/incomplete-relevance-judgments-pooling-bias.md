---
last_verified: ""
updated: 2026-07-26
sources:
  - sources/incoming/llms-patch-missing-relevance-judgments.md
title: Incomplete Gold-Standard Relevance Judgments and Pooling Bias in Retrieval Evaluation
tags:
  - llm
  - evals
  - retrieval
  - rag
routing: Why hand-annotated relevance judgment sets for retrieval/extraction benchmarks are structurally incomplete at scale, how pooling creates the gaps and its own systemic bias, why unjudged "holes" make measured scores a lower bound and cross-model comparisons unfair, and using an LLM assessor to patch holes with measured correlation to ground truth
---

## Overview

The Cranfield paradigm for IR evaluation originally assumed relevance judgments were complete — every document in the corpus reviewed for every query. As collection size grew this completeness assumption became "increasingly impossible to maintain," making ground-truth relevance judgments "inevitably incomplete in IR test collections" at scale (citing Buckley and Voorhees, 2004) [llms-patch-missing-relevance-judgments]. This concept covers why that gap exists, how the standard mitigation (pooling) itself introduces bias, and what an incomplete gold set does to measured scores and cross-model comparisons. This is distinct from [[production-eval-systems]]'s golden regression datasets and from [[llm-evaluation-frameworks]]'s benchmark-vs-production coverage — this article is specifically about relevance-judgment completeness in retrieval/extraction reference sets.

## Key Concepts

**Pooling** is the standard mitigation for judgment completeness at scale: rather than judging the whole corpus, only the top results from one or more retrieval systems are selected for manual judgment. Pooling's reliability "heavily rests on the depth of the selected documents, and the choice of retrieval systems" [llms-patch-missing-relevance-judgments].

Pooling introduces its own bias: "if the retrieval systems leveraged for relevance judgment were all based on BM25, chances are test models that use BM25 score higher in the test collection" [llms-patch-missing-relevance-judgments]. Diversifying the contributing systems and judging deeper reduces this risk, but costs more manual labor and slower judgment turnaround [llms-patch-missing-relevance-judgments].

**What unjudged "holes" do to metrics.** Standard IR metrics (nDCG@k, MAP, Pr@k) handle documents that were never judged by either ignoring them or treating them as non-relevant — both approaches "miss the true essence of the complete judgment" and can miss relevant-but-unjudged documents, yielding no measured gain for genuinely relevant results the annotator never saw [llms-patch-missing-relevance-judgments]. This is the same failure mode as a hand-annotated gold set that's under-inclusive: a defensible answer absent from the reference set scores as a false positive/non-relevant rather than as correct [llms-patch-missing-relevance-judgments].

**Why measured scores are a lower bound.** These shortcomings collectively produce "an inaccurate assessment of retrieval models, giving us a misleading sense of progress" — measured precision/effectiveness against an incomplete reference set is a lower bound on true effectiveness, not an accurate estimate [llms-patch-missing-relevance-judgments].

**Why cross-model comparison is unfair.** Different retrieval models have different degrees of sparsity in their judgments — they return different volumes of unjudged items — which "renders their comparison unfair, particularly for models returning many unjudged documents" [llms-patch-missing-relevance-judgments]. A shared incomplete gold set is not apples-to-apples when systems differ in how many out-of-pool items they surface.

## Patterns

The paper's proposed fix is to use an LLM as an automated relevance assessor to fill holes in the judgment set. The assessor is instructed with detailed guidelines to assign fine-grained (not binary) TREC-style relevance labels — 0 (nothing to do with the query), 1 (related but doesn't answer), 2 (has some answer but unclear/buried), 3 (dedicated answer) — rather than the binary relevant/non-relevant labels used in prior LLM-assessor work [llms-patch-missing-relevance-judgments]. This is a specific application of the general LLM-as-judge approach to patching missing relevance judgments; see [[llm-as-judge]] for judge biases and mitigation techniques in general, and [[factscore-atomic-fact-decomposition]] for a different sub-claim-level scoring approach.

To validate the assessor, the authors simulated varying degrees of holes by randomly dropping relevant documents from existing gold judgments on TREC DL datasets, then ran the LLM assessor to patch the holes and compared its labels against the original ground-truth judgments [llms-patch-missing-relevance-judgments].

**Measured result:** the LLM-assessor labels correlate strongly with ground-truth relevance judgments even under extreme hole rates — retaining only 10% of original judgments, the method achieves a Kendall τ correlation of 0.87 with Vicuña-7B (open-source) and 0.92 with GPT-3.5 Turbo (proprietary), averaged across three TREC DL datasets [llms-patch-missing-relevance-judgments]. This suggests LLM-filled holes are a viable way to de-bias an under-inclusive gold set without full re-annotation [llms-patch-missing-relevance-judgments].

## Practitioner Implication

For an internal, hand-annotated extraction/retrieval benchmark built by pooling (or any partial manual review) that is under-inclusive: precision/accuracy measured against it should be read as a lower bound, not the true score, and "false positives" flagged against the gold set may simply be unjudged-but-correct items. An LLM-assessor pass to fill the gaps, using fine-grained rather than binary labels, is a validated way to recover a more accurate effectiveness estimate without redoing full manual annotation [llms-patch-missing-relevance-judgments]. For measuring retrieval quality more broadly, see [[retrieval-augmented-generation]].

## Gaps in the Source

The fetched source text truncated partway through the Methodology section (cutting off mid-prompt-template), so the Experimental Setup, full Results tables, and Data Contamination Testing sections were not available for extraction. The Kendall τ figures above come from the Abstract and are citable, but no further detail on the experimental setup or full results tables is reported here beyond what's stated above — that detail was not present in the fetched text.

## Sources

- sources/incoming/llms-patch-missing-relevance-judgments.md (tier 2) — Upadhyay, Kamalloo, Lin, arXiv preprint, 2024-05-08
