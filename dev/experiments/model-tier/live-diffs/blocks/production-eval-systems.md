## Concept: Production Eval Systems

slug: production-eval-systems
title: Production Eval Systems: Regression Datasets, LLM-as-Judge, Shadow Mode, Red Teaming
source_paths:
  - sources/zenml/zenml-2025-12-llmops-1200-deployments.md (tier 3)
  - sources/evidentlyai/evidentlyai-llm-as-a-judge-guide.md (tier 3)
target_article: ""

### Claims

- Golden datasets are curated inputs with human-reviewed expected outputs; the failure
  cases that seed them come from production incidents, not synthetic generation.
  [source: zenml-2025-12-llmops-1200-deployments]
- Ramp converts each user-reported failure into a regression test case, but the raw
  report is reviewed and canonicalized under human oversight first — used directly it
  introduces affinity bias (users report the failures that affect them). [source: zenml-2025-12-llmops-1200-deployments]
- Shadow mode runs the new system alongside production on the same input; only the
  current system's output is served, the shadow output is logged and compared after the
  fact. [source: zenml-2025-12-llmops-1200-deployments]
- Ramp enables live execution of a shadow agent only once shadow accuracy reaches a
  defined threshold over a validation window — the threshold makes the gate auditable
  rather than a deploy-time judgment call. [source: zenml-2025-12-llmops-1200-deployments]
- LLM-as-judge uses a separate model to score outputs; routing generation and evaluation
  to different providers is a documented practice that prevents a model grading its own
  test. [source: zenml-2025-12-llmops-1200-deployments]
- An LLM judge fills the gap where pass/fail metrics don't capture quality — tone,
  completeness, factual framing — at volumes human review can't match. [source: evidentlyai-llm-as-a-judge-guide]
- Red teaming is adversarial testing meant to break the system, and production teams run
  it continuously throughout the lifecycle, not as a one-time pre-launch gate. [source: zenml-2025-12-llmops-1200-deployments]
