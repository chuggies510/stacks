---
last_verified: ""
sources:
  - sources/arxiv/arxiv-2507.13334-context-engineering-survey.md
title: LLM Evaluation Frameworks
routing: How do I measure component versus system performance, what benchmarks cover retrieval and agents, where do evaluation frameworks fail in production, and how do I track token costs and latency?
tags: [llmops, evals, rag, agents, hallucination, cost-economics]
---

## Overview
Evaluation frameworks operate across two distinct levels to address different measurement needs. Component-level evaluation measures retrieval quality, prompt effectiveness, and compression efficiency in isolation so that failures localize to specific modules [arxiv-2507.13334-context-engineering-survey]. System-level evaluation measures end-to-end task performance and resource efficiency on the integrated pipeline to catch interaction effects between components [arxiv-2507.13334-context-engineering-survey]. Emerging paradigms move beyond static benchmark accuracy toward interactive evaluation environments and long-horizon task assessment [arxiv-2507.13334-context-engineering-survey].

## Key Concepts
Foundational component benchmarks cover retrieval, prompt effectiveness, long-context understanding, and multimodal integration [arxiv-2507.13334-context-engineering-survey]. System implementation benchmarks focus on RAG pipeline quality, agent task performance, multi-agent coordination, and tool-use effectiveness [arxiv-2507.13334-context-engineering-survey]. Safety and robustness assessment functions as a distinct target that requires purpose-built evaluation cases rather than repurposed accuracy benchmarks [arxiv-2507.13334-context-engineering-survey]. These purpose-built cases address adversarial robustness including prompt injection and jailbreaks, hallucination detection, attribution and grounding verification, and agent-behavior safety [arxiv-2507.13334-context-engineering-survey].

## Pitfalls
Practitioners encounter recurring failure modes when deploying evaluation frameworks. A benchmark-vs-real-world gap frequently appears between controlled test results and production behavior [arxiv-2507.13334-context-engineering-survey]. Memory-system isolation causes metrics to fail transferring across subsystem boundaries [arxiv-2507.13334-context-engineering-survey]. Pairwise or full-context-reread approaches hit O(n^2) scaling limits [arxiv-2507.13334-context-engineering-survey]. Transactional-integrity failures introduce state bleed between test cases [arxiv-2507.13334-context-engineering-survey]. Self-validation dependency occurs when a model grades its own outputs without a ground-truth anchor [arxiv-2507.13334-context-engineering-survey]. Context-handling failures often remain hidden until they surface in long-horizon tasks [arxiv-2507.13334-context-engineering-survey].

## Cost & Latency
System-level evaluation incorporates resource-efficiency measurement to track token consumption, latency, and cost per correct answer across the integrated pipeline [arxiv-2507.13334-context-engineering-survey].
