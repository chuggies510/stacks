---
last_verified: ""
sources:
  - sources/zenml/zenml-2025-12-llmops-1200-deployments.md
  - sources/evidentlyai/evidentlyai-llm-as-a-judge-guide.md
title: Production Eval Systems: Regression Datasets, LLM-as-Judge, Shadow Mode, Red Teaming
routing: How to set up regression datasets, shadow deployments, LLM judges, and continuous red teaming for production model validation.
tags: [llmops, evals, shadow-mode, llm-as-judge]
---

## Overview
Golden datasets are curated inputs with human-reviewed expected outputs; the failure cases that seed them come from production incidents, not synthetic generation. [zenml-2025-12-llmops-1200-deployments]

## Key Concepts
Routing generation and evaluation to different providers is a documented practice that prevents a model from grading its own test. [zenml-2025-12-llmops-1200-deployments] User-reported failures are converted into regression test cases, but the raw report must be reviewed and canonicalized under human oversight first. [zenml-2025-12-llmops-1200-deployments]

## Patterns
Shadow mode runs the new system alongside production on the same input while only serving the current system's output; the shadow output is logged and compared after the fact. [zenml-2025-12-llmops-1200-deployments] Red teaming is adversarial testing meant to break the system, and production teams run it continuously throughout the lifecycle, not as a one-time pre-launch gate. [zenml-2025-12-llmops-1200-deployments]

## Pitfalls
Using raw reports directly introduces affinity bias because users report the failures that affect them. [zenml-2025-12-llmops-1200-deployments] An LLM judge fills the gap where pass/fail metrics don't capture quality — tone, completeness, factual framing — at volumes human review can't match. [evidentlyai-llm-as-a-judge-guide]

## Eval Strategy
Live execution of a shadow agent is enabled only once shadow accuracy reaches a defined threshold over a validation window; this threshold makes the gate auditable rather than a deploy-time judgment call. [zenml-2025-12-llmops-1200-deployments]
