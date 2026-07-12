---
last_verified: ""
sources:
  - sources/arxiv/arxiv-2507.13334-context-engineering-survey.md
title: LLM Evaluation Frameworks
routing: How are LLMs evaluated, and what frameworks support component and system-level assessment?
tags: evals llm context-engineering prompt-engineering guardrails memory observability
---
LLM evaluation operates at two levels: component-level (retrieval quality, prompt effectiveness, compression efficiency — measured in isolation so failures localize) and system-level (end-to-end task performance and resource efficiency — measured on the integrated pipeline to catch interaction effects) [arxiv-2507.13334-context-engineering-survey]. Foundational component benchmarks cover retrieval, prompt effectiveness, long-context understanding, and multimodal integration [arxiv-2507.13334-context-engineering-survey]. System implementation benchmarks cover RAG pipeline quality, agent task performance, multi-agent coordination, and tool-use effectiveness [arxiv-2507.13334-context-engineering-survey]. 

Recurring pitfalls include a benchmark-vs-real-world gap; memory-system isolation (metrics don't transfer across subsystem boundaries); O(n^2) scaling limits on pairwise or full-context-reread approaches; transactional-integrity failures (state bleed between test cases); self-validation dependency (model grading its own outputs without a ground-truth anchor); and context-handling failures that only surface in long-horizon tasks [arxiv-2507.13334-context-engineering-survey]. Safety and robustness assessment is a distinct target needing purpose-built cases, not repurposed accuracy benchmarks: adversarial robustness (prompt injection, jailbreaks), hallucination detection, attribution/grounding verification, and agent-behavior safety [arxiv-2507.13334-context-engineering-survey]. 

Emerging paradigms move beyond static benchmark accuracy toward interactive evaluation environments, long-horizon task assessment, and resource-efficiency measurement (tokens, latency, cost per correct answer) [arxiv-2507.13334-context-engineering-survey].
