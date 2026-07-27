---
last_verified: ""
sources:
  - sources/arxiv/arxiv-2507.13334-context-engineering-survey.md
title: LLM Evaluation Frameworks
routing: What are the different levels of LLM evaluation, what benchmarks exist for components vs systems, and what pitfalls occur in production?
tags: [llm, llmops, evals, agents, hallucination, context-engineering, prompt-engineering, multi-agent, cost-economics]
---

## Overview
Evaluation operates at two levels: component-level and system-level [arxiv-2507.13334-context-engineering-survey].

## Key Concepts
Component-level evaluation measures retrieval quality, prompt effectiveness, and compression efficiency in isolation so failures localize [arxiv-2507.13334-context-engineering-survey]. System-level evaluation measures end-to-end task performance and resource efficiency on the integrated pipeline to catch interaction effects [arxiv-2507.13334-context-engineering-survey]. Safety and robustness assessment is a distinct target needing purpose-built cases, not repurposed accuracy benchmarks [arxiv-2507.13334-context-engineering-survey].

## Patterns
Foundational component benchmarks cover retrieval, prompt effectiveness, long-context understanding, and multimodal integration [arxiv-2507.13334-context-engineering-survey]. System implementation benchmarks cover RAG pipeline quality, agent task performance, multi-agent coordination, and tool-use effectiveness [arxiv-2507.13334-context-engineering-survey].

## Pitfalls
Recurring pitfalls include a benchmark-vs-real-world gap; memory-system isolation where metrics don't transfer across subsystem boundaries; O(n^2) scaling limits on pairwise or full-context-reread approaches; transactional-integrity failures such as state bleed between test cases; self-validation dependency where the model grades its own outputs without a ground-truth anchor; and context-handling failures that only surface in long-horizon tasks [arxiv-2507.13334-context-engineering-survey].

## Cost & Latency
Emerging paradigms include resource-efficiency measurement of tokens, latency, and cost per correct answer [arxiv-2507.13334-context-engineering-survey].

## Eval Strategy
Safety and robustness assessment requires purpose-built cases for adversarial robustness (prompt injection, jailbreaks), hallucination detection, attribution/grounding verification, and agent-behavior safety [arxiv-2507.13334-context-engineering-survey]. Emerging paradigms move toward interactive evaluation environments and long-horizon task assessment [arxiv-2507.13334-context-engineering-survey].
