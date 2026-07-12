---
last_verified: 2026-07-10
sources:
  - sources/zenml/zenml-2025-12-llmops-1200-deployments.md
  - sources/evidentlyai/evidentlyai-llm-as-a-judge-guide.md
title: Production Eval Systems: Regression Datasets, LLM-as-Judge, Shadow Mode, Red Teaming
routing: LLM production evals — how to catch regressions before deployment using golden datasets, shadow mode, LLM-as-judge scoring, and continuous red teaming at scale
tags:
  - llm
  - llmops
  - evals
  - llm-as-judge
  - shadow-mode
  - observability
  - hallucination
---

## Overview

Production eval systems are the runtime feedback infrastructure that decides whether a new model version, prompt change, or agent modification is safe to deploy. They sit downstream of offline benchmarks (covered in [[llm-evaluation-frameworks]]) and upstream of production traffic: their job is to catch regressions before they reach users and to measure quality where pass/fail labels don't exist. This article covers the four core mechanisms — golden regression datasets, shadow mode, LLM-as-judge, and continuous red teaming — with concrete examples from teams operating at production scale.

## Key concepts

**Golden datasets** are curated sets of inputs and expected outputs that represent known-correct or known-failure cases. The term "golden" means the expected answers have been reviewed by humans, not generated automatically. They function as integration tests for model behavior: a new prompt or model must pass the dataset before reaching users. The failure cases that seed these datasets come from production incidents, not from synthetic generation [zenml-2025-12-llmops-1200-deployments].

**Shadow mode** (also: parallel run) deploys the new agent or model alongside the current production system. Both systems process the same input; only the current system's output is served. The shadow output is logged and compared against actual outcomes after the fact. This eliminates production risk during validation while using real traffic distributions rather than synthetic test cases [zenml-2025-12-llmops-1200-deployments].

**LLM-as-judge** uses a separate model to score outputs automatically. "Separate" is load-bearing: routing generation to one provider and evaluation to a different provider prevents the model from effectively grading its own test [zenml-2025-12-llmops-1200-deployments]. LLM-as-judge fills the gap where pass/fail metrics don't capture quality — conversational tone, completeness, factual framing — at volumes that human review can't match [zenml-2025-12-llmops-1200-deployments][evidentlyai-llm-as-a-judge-guide].

**Red teaming** is adversarial testing whose goal is to break the system, distinct from standard testing whose goal is to confirm it works. Production red teaming runs continuously throughout the development lifecycle, not as a one-time pre-launch gate [zenml-2025-12-llmops-1200-deployments].

## Patterns

**Failure-driven dataset growth.** Ramp converts every user-reported failure into a regression test case. The raw user feedback is not used directly: user feedback alone introduces affinity bias (users report failures that affect them, not failures that are representative). The failure is reviewed, canonicalized, and added to the golden dataset under human oversight [zenml-2025-12-llmops-1200-deployments].

**Shadow mode with a numeric gate.** Ramp runs agents in shadow mode on financial transactions before allowing live execution. An LLM judge compares shadow predictions to actual outcomes over a validation window. Live execution is only enabled once shadow accuracy reaches a defined threshold — the threshold makes the gate concrete and auditable, not a judgment call at deploy time [zenml-2025-12-llmops-1200-deployments].

**Time-travel evaluation.** Incident.io replays historical incidents against the agent, then checks whether the agent correctly identifies the actual root cause without hallucinating fixes that were not available at the specific moment the incident occurred. This pattern isolates temporal hallucination (the model "knows" a fix that was released later) [zenml-2025-12-llmops-1200-deployments].

**Synthetic traffic generation from real distributions.** Trainline built a user context simulator that generates synthetic support tickets for real trains, sampling from actual historical query distributions. The synthetic queries look like real user traffic without exposing real user data [zenml-2025-12-llmops-1200-deployments].

**Validation without exposing data to the model.** DoorDash's "Zero-Data Statistical Query Validation" uses automated linting, EXPLAIN-based query checking (the database's query planner, not the LLM), and metadata validation to gate SQL outputs. Sensitive data never enters the model's context; traditional ML and rule-based checks constrain and gate LLM-generated queries [zenml-2025-12-llmops-1200-deployments].

**Offline regression before every deployment.** GitHub runs comprehensive offline evaluations as a pre-production gate to catch regressions before they reach users [zenml-2025-12-llmops-1200-deployments].

## Pitfalls

**Affinity bias in user-reported failures.** Users report failures that affect them: high-frequency users report high-frequency failure modes, niche users are underrepresented. Building a golden dataset directly from raw user reports without curation skews toward over-indexing common cases and missing edge cases [zenml-2025-12-llmops-1200-deployments].

**Self-grading evaluators.** An LLM grading its own outputs tends to rate them highly even when they are wrong. Routing generation and evaluation to different providers is the production fix [zenml-2025-12-llmops-1200-deployments].

**One-time red teaming.** A single pre-launch red team engagement finds the vulnerabilities that exist at that moment. Prompt changes, model updates, and new data paths open new attack surfaces. Red teaming scoped to launch is not a substitute for continuous post-deployment adversarial testing [zenml-2025-12-llmops-1200-deployments].

**Temporal hallucination in replay evals.** When replaying historical events, the model may draw on knowledge (a post-incident fix, a later patch, updated documentation) that did not exist at the time of the original event. Time-travel evaluations must pin the model's context to what was available at the moment being replayed, not at eval time [zenml-2025-12-llmops-1200-deployments].

## Eval strategy

These patterns are themselves the eval strategy for production systems. The sequencing that emerges from the case studies is roughly: offline golden dataset regression runs on every candidate change; shadow mode against real traffic once the offline gate passes; LLM-as-judge (separate provider) for quality dimensions that pass/fail metrics can't capture; continuous red teaming as a background process after every deployment. Amazon Prime Video uses this framing explicitly: separate evaluator LLMs are applied selectively for cases where deterministic metrics are insufficient [zenml-2025-12-llmops-1200-deployments].

For related taxonomy and framework comparisons, see [[llm-evaluation-frameworks]]. For compiled-AI and operational metric design, see [[llm-output-validation-pipeline]].

## Sources

| Source | Tier | Notes |
|--------|------|-------|
| zenml-2025-12-llmops-1200-deployments | 3 | ZenML LLMOps Database; production case studies from Ramp, GitHub, DoorDash, Cox Automotive, Amazon Prime Video, Incident.io, Digits, Trainline |
| evidentlyai-llm-as-a-judge-guide | 3 | EvidentlyAI LLMOps practitioner guide; taxonomy of LLM-as-judge quality dimensions including tone, completeness, hallucination, relevance, and bias |
