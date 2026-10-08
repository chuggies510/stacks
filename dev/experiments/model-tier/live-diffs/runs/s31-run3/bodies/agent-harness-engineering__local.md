---
last_verified: ""
sources:
  - sources/zenml/zenml-2025-12-llmops-1200-deployments.md
  - sources/arxiv/arxiv-2605.26731-harness-nonmonotone.md
  - sources/incoming/anthropic-prompting-claude-opus-5.md
title: Agent Harness Engineering and Model Adaptation
routing: agent harness engineering — how to structure tool spaces, preserve reasoning traces, tune few-shot counts, apply progressive autonomy, layer formal verification, avoid surface attribution errors, validate harness complexity per model type, and what to strip or re-sweep when moving to a new model (Opus 5 verification instructions, re-check prompts, scope-expansion constraints, carried-over effort defaults)
tags:
  - llm
  - llmops
  - agents
  - tool-use
  - fine-tuning
  - reinforcement-learning
  - reasoning
  - latency
  - prompt-engineering
---

## Overview

Each frontier model arrives with distinct behavioral patterns that require bespoke harness engineering to get reliable production behavior [zenml-2025-12-llmops-1200-deployments]. The harness is the layer of tooling, prompt scaffolding, action space design, and training choices that sits between the raw model API and the deployed agent. Getting it wrong manifests as degraded task success, inflated latency, or systematic attribution failures that don't show up until real traffic hits.

The bottleneck distinguishing production agents from demos is engineering discipline — infrastructure, failure-mode rigor, and evaluation practice — not model access [zenml-2025-12-llmops-1200-deployments].

## Key concepts

**Action space design.** Manus implemented a layered action space with three levels: atomic functions at the base, sandbox utilities in the middle, and an API-calling layer at the top [zenml-2025-12-llmops-1200-deployments]. This separation keeps low-level operations composable without exposing the full surface area as a flat list of tools.

**Tool count vs. reasoning quality.** Cubic found that performance degraded as agents were given more tools. The fix was to remove tools and force explicit reasoning logs [zenml-2025-12-llmops-1200-deployments].

**Reasoning trace preservation.** Cursor's Codex adaptation renamed tools to align with shell conventions. When reasoning traces were dropped, task performance fell by 30% [zenml-2025-12-llmops-1200-deployments]. Intermediate reasoning steps are load-bearing for accuracy, not just diagnostic output.

**Progressive autonomy.** Rather than removing humans from the loop entirely, one architecture pattern starts with AI outputs as suggestions, then graduates high-confidence cases to autonomous action [zenml-2025-12-llmops-1200-deployments]. This limits blast radius while the system earns its reliability record.

**Task decomposition on rails.** Stripe compliance agents decompose complex reviews into bite-sized tasks on strict "rails" that prevent the agent from rabbit-holing into irrelevant paths [zenml-2025-12-llmops-1200-deployments]. Constrained scope per sub-task is the mechanism; the harness enforces it, not the model.

**Harness sensitivity by model type.** The assumption that higher-capability models need proportionally less structural guidance is empirically false [arxiv-2605.26731-harness-nonmonotone]. A controlled 432-run experiment crossed six models across four capability tiers with three harness conditions (light, balanced, strict) on HEAT-24, a 24-task synthetic benchmark with git-based workspace verification. The directional effect of adding harness structure depends on model type (chat vs. reasoning), not on capability tier alone. Because each tier in the study is represented by a single model, results are model-specific observations, not tier-level generalizations; directional effects must be re-validated when models change [arxiv-2605.26731-harness-nonmonotone].

**Model-specific prompt stripping.** When moving to a new model, the harness must be re-audited for instructions that the new model performs natively. For Claude Opus 5, explicit verification instructions ("include a final verification step for any non-trivial task", "use a subagent to verify") should be removed: they cause over-verification, and removing them reduces wasted tokens with no loss in quality [anthropic-prompting-claude-opus-5]. The same applies to legacy harness scaffolding that adds separate verification steps: scaffolding built for a weaker model compounds with the new model's built-in behavior and adds cost without improving results [anthropic-prompting-claude-opus-5]. Re-check instructions the model already performs ("double-check your answer", "re-verify before responding") likewise add cost without improving results; the model catches and fixes its own mistakes without prompting [anthropic-prompting-claude-opus-5].

**Scope-expansion constraints.** The model can expand task scope: adding unrequested steps or applying its own judgment about what the task should be. A constraining prompt should direct the model to deliver what was asked at the intended scope; make routine judgment calls itself, check in only when readings would lead to materially different work; if the request seems mistaken, say so in one sentence and continue as asked rather than quietly narrowing, widening, or transforming it; finish the whole task, stop short of clearly out-of-scope actions [anthropic-prompting-claude-opus-5].

**Carried-over defaults.** Defaults carried over from a prior model (including effort settings) deserve a fresh sweep rather than assumed carry-over [anthropic-prompting-claude-opus-5].

## Pitfalls

**Surface Attribution Error.** Zalando encountered a failure mode where models blamed technologies simply because they appeared in the input context, not because of any causal signal. Around 10% of attributions remain wrong even with Claude Sonnet [zenml-2025-12-llmops-1200-deployments].

**Few-shot overfitting.** Amazon Alexa found that adding more few-shot examples decreased accuracy. The model overfit to the distribution of examples rather than generalizing to the task [zenml-2025-12-llmops-1200-deployments]. More examples in context is not a monotonically safe move for accuracy.

**Harness-complexity paradox.** For frontier chat models, increasing harness verbosity can actively degrade performance. Gemini 2.5 Flash's task success rate dropped 29-38 percentage points under a strict harness compared to a light one [arxiv-2605.26731-harness-nonmonotone]. The directional effect reverses for reasoning models: Qwen3.5-122B with extended thinking enabled achieved its highest success rate (91.7%) and lowest latency under the strict harness condition — the opposite of the chat-model result [arxiv-2605.26731-harness-nonmonotone].

**Failure mode taxonomy by tier.** A six-label failure taxonomy shows that `format_violation` dominates capable-model failures while `wrong_file` dominates low-capability model failures [arxiv-2605.26731-harness-nonmonotone].

## Cost and latency

Robinhood cut latency by 50% through a staged tuning hierarchy: prompt optimization first, then trajectory tuning, then LoRA — without requiring frontier models at inference time [zenml-2025-12-llmops-1200-deployments].

## Verification layer

Harnesses can layer formal verification on top of probabilistic LLM outputs. PwC moved beyond probabilistic validation to mathematical verification using Automated Reasoning checks, treating the LLM output as a candidate to be proven rather than a result to be trusted [zenml-2025-12-llmops-1200-deployments].

## Field notes

Reinforcement learning for harness adaptation has become accessible at smaller budgets. OpenPipe's ART-E trained a Qwen-14B model using GRPO (group relative policy optimization) on a single H100 for approximately $80 and outperformed OpenAI o3 on an email research task [zenml-2025-12-llmops-1200-deployments]. Model-specific fine-tuning is now within reach for teams that have labeled trajectory data, not just organizations with large ML infrastructure.

The recurring cross-team pattern is that harness behavior is non-monotonic: adding more (tools, examples, context, structure) often hurts before it helps, and the direction of that effect differs by model [arxiv-2605.26731-harness-nonmonotone]. A small-model outlier from the same study underscores this: a 2B model (Gemma4:e2B) matched strong-open-tier stability at 91.7% VTSR across all three harness conditions, regardless of harness complexity [arxiv-2605.26731-harness-nonmonotone]. Per-model empirical validation is not optional — results from one model do not transfer even within the same capability tier.

## Sources

| Source | Tier | Notes |
|--------|------|-------|
| zenml-2025-12-llmops-1200-deployments | 3 — Practitioner | ZenML LLMOps Database production case studies |
| arxiv-2605.26731-harness-nonmonotone | 2 — Standard | Controlled experiment: 432 runs, 6 models, 3 harness conditions, HEAT-24 benchmark |
| anthropic-prompting-claude-opus-5 | 1 — Official | Anthropic prompting guidance for Claude Opus 5 |
