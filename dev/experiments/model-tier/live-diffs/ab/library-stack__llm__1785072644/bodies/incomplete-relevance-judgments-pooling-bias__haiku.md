---
last_verified: ""
updated: 2026-07-26
sources:
  - sources/incoming/llms-patch-missing-relevance-judgments.md
title: Incomplete Gold-Standard Relevance Judgments and Pooling Bias in Retrieval Evaluation
tags:
  - llm
  - evals
  - llm-as-judge
  - retrieval
  - rag
routing: Incompleteness in hand-annotated relevance judgment sets for retrieval benchmarks — why pooling creates structural gaps, how unjudged documents underestimate true effectiveness and break cross-model comparison, and using an LLM assessor with fine-grained labels to patch holes
---

## Overview

Hand-annotated relevance judgment sets are the gold standard for retrieval and extraction benchmarks. The Cranfield paradigm originally assumed relevance judgments must be complete—every document in the corpus reviewed for every query—but as collection size grew this completeness assumption became "increasingly impossible to maintain," making ground-truth relevance judgments "inevitably incomplete in IR test collections" at scale [llms-patch-missing-relevance-judgments].

The practical consequence: a measured score (precision, nDCG, MAP) against an incomplete judgment set is a lower bound on true system effectiveness, not an accurate estimate. Unjudged but relevant documents surface as false positives, and cross-model comparisons become unfair when systems differ in how many unjudged items they retrieve. This article covers why the structural incompleteness exists, how it propagates into evaluation bias, and a validated approach to repair it using an LLM assessor.

## Key Concepts

### The Pooling Process and Its Trade-offs

**Pooling** is the standard mitigation for incomplete judgments: only the top results from one or more retrieval systems are selected for manual judgment, rather than the whole corpus [llms-patch-missing-relevance-judgments]. This reduces annotation cost dramatically. However, pooling's reliability "heavily rests on the depth of the selected documents, and the choice of retrieval systems" [llms-patch-missing-relevance-judgments].

Pooling introduces its own systemic bias: "if the retrieval systems leveraged for relevance judgment were all based on BM25, chances are test models that use BM25 score higher in the test collection." Diversifying contributing systems and judging deeper reduces this risk but costs more manual labor and slower judgment turnaround [llms-patch-missing-relevance-judgments].

### The Unjudged-Holes Problem

Standard IR metrics (nDCG@k, MAP, Pr@k) handle unjudged documents by either ignoring them or treating them as non-relevant—both approaches "miss the true essence of the complete judgment" and can miss relevant-but-unjudged documents, yielding no measured gain for genuinely relevant results the annotator never saw [llms-patch-missing-relevance-judgments]. This is the failure mode of an under-inclusive reference set: a defensible answer absent from the judgment pool scores as a false positive rather than as correct.

### Cross-Model Comparison Unfairness

Different retrieval models have different degrees of sparsity in their judgments—they return different volumes of unjudged items—which "renders their comparison unfair, particularly for models returning many unjudged documents" [llms-patch-missing-relevance-judgments]. Comparing two systems against a shared incomplete gold set is not apples-to-apples when one system surfaces far more out-of-pool items than the other.

These shortcomings collectively produce "an inaccurate assessment of retrieval models, giving us a misleading sense of progress" [llms-patch-missing-relevance-judgments]—measured precision against an incomplete reference is unreliable both as an absolute estimate and as a basis for cross-system comparison.

## Patterns: LLM-Based Judgment Patching

### Fine-Grained Label Assignment

Rather than binary relevant/non-relevant labels, the proposed approach uses an LLM as an automated relevance assessor with detailed guidelines to assign fine-grained TREC-style relevance labels (0 = nothing to do with the query, 1 = related but doesn't answer, 2 = has some answer but unclear/buried, 3 = dedicated answer) [llms-patch-missing-relevance-judgments]. Fine-grained labels preserve nuance that binary judgments lose and enable more sophisticated evaluation.

### Validation Method

The validation simulates varying degrees of holes by randomly dropping relevant documents from existing gold judgments on TREC DL datasets, then runs the LLM assessor to patch the holes and compares its labels against the original (ground-truth) judgments [llms-patch-missing-relevance-judgments].

### Results

In the scenario retaining only 10% of original judgments, the method achieves a Kendall τ correlation of 0.87 (Vicuña-7B, open-source) and 0.92 (GPT-3.5 Turbo, proprietary), averaged across three TREC DL datasets [llms-patch-missing-relevance-judgments]. This suggests LLM-filled holes are a viable way to de-bias an under-inclusive gold set without full re-annotation.

## Implications for Practitioners

If your internal hand-annotated extraction or retrieval benchmark was built by pooling (or by any partial manual review) and is under-inclusive, precision and accuracy measured against it should be read as a lower bound, not the true score [llms-patch-missing-relevance-judgments]. The "false positives" flagged against the gold set may simply be unjudged-but-correct items.

An LLM-assessor pass to fill the gaps—using fine-grained rather than binary labels—is a validated way to recover a more accurate effectiveness estimate without redoing full manual annotation [llms-patch-missing-relevance-judgments]. See [[llm-as-judge]] for general LLM-judge use and bias mitigation; this article focuses specifically on relevance-judgment completeness in retrieval reference sets.
