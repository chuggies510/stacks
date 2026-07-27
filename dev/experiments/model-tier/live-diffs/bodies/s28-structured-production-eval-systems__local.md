---
last_verified: ""
sources:
  - sources/zenml/zenml-2025-12-llmops-1200-deployments.md
  - sources/evidentlyai/evidentlyai-llm-as-a-judge-guide.md
title: Production Eval Systems: Regression Datasets, LLM-as-Judge, Shadow Mode, Red Teaming
routing: What are the components and patterns of production evaluation systems for LLMs?
tags: [llmops, evals, agents]
---

## Overview
Production evaluation systems utilize methods such as golden datasets, shadow mode, LLM-as-judge, and red teaming to validate model performance [zenml-2025-12-llmops-1200-deployments].

## Key Concepts
Golden datasets are curated inputs with human-reviewed expected outputs; the failure cases that seed them come from production incidents rather than synthetic generation [zenml-2025-12-llmops-1200-deployments]. Shadow mode runs a new system alongside production on the same input, where only the current system's output is served while the shadow output is logged and compared after the fact [zenml-2025-12-llmops-1200-deployments]. Red teaming is adversarial testing meant to break the system, which production teams run continuously throughout the lifecycle rather than as a one-time pre-launch gate [zenml-2025-12-llmops-1200-deployments].

## Patterns
One approach involves converting each user-reported failure into a regression test case, but raw reports must be reviewed and canonicalized under human oversight first because using them directly introduces affinity bias where users report the failures that affect them [zenml-2025-12-llmops-1200-deployments]. Another pattern is enabling live execution of a shadow agent only once shadow accuracy reaches a defined threshold over a validation window, which makes the gate auditable rather than a deploy-time judgment call [zenml-2025-12-llmops-1200-deployments]. To prevent a model from grading its own test, routing generation and evaluation to different providers is a documented practice for LLM-as-judge systems [zenml-2025-12-llmops-1200-deployments].

## Pitfalls
Using raw user reports directly as regression tests can introduce affinity bias because users report the failures that affect them [zenml-2025-12-llmops-1200-deployments]. Red teaming should not be treated as a one-time pre-launch gate but must be run continuously throughout the lifecycle [zenml-2025-12-llmops-1200-deployments].

## Eval Strategy
LLM-as-judge uses a separate model to score outputs, filling the gap where pass/fail metrics do not capture quality—such as tone, completeness, and factual framing—at volumes human review can't match [evidentlyai-llm-as-a-judge-guide] [zenml-2025-12-llmops-1200-deployments].
