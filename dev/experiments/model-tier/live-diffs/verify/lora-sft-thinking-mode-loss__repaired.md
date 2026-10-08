---
last_verified: ""
sources:
  - sources/incoming/liminal-2026-07-30-sft-destroys-thinking-mode.md
title: SFT/LoRA on Reasoning-Free Completions Destroys the Base Model's Thinking Mode
routing: SFT/LoRA adapters trained on reasoning-free completions silently disabling the base model's thinking mode — why capability flags and template checks fail to detect it, how to probe for it behaviorally, and the cost of losing the thinking lever
tags: [llm, fine-tuning, reasoning, context-engineering, evals]
---

## Overview

Fine-tuning a base model with LoRA on plain input-to-completion pairs that contain no reasoning traces can permanently disable the base model's thinking mode. The adapter appears to have learned to emit an empty think block, and the loss is invisible to static checks. This article covers the failure mode, why standard diagnostics miss it, how to detect it behaviorally, and the strategic cost of losing the thinking lever.

## Key Concepts

Three LoRA adapters at three sizes, from three separate training runs (qwen3-4b-extract-v8, qwen3-8b-extract-v9, qwen3-14b-extract-v10), all emit 0 characters of `message.thinking` on a request where their base models emit reasoning (762 characters on the probe request for the 14B). 3 of 3, no partials. On a 50-source extraction bench, 0/50 rows thought on the adapter versus 50/50 on its base [liminal-2026-07-30-sft-destroys-thinking-mode].

The training data was plain input-to-completion pairs with no reasoning traces; the adapter appears to have learned to emit an empty think block [liminal-2026-07-30-sft-destroys-thinking-mode].

No static signal detects the loss. All three read green on a model that cannot think: (1) the Ollama API accepts `think: true` without error, (2) `ollama show` advertises the `thinking` capability, (3) the chat template is byte-identical to the base's (verified via `ollama show --template`) [liminal-2026-07-30-sft-destroys-thinking-mode].

The template was the original suspect (an afterburn/Modelfile chain was stripping `/think` tokens). That drift was real, but the repair was built, verified byte-equal, and changed nothing: still 0 characters against the base's 762 on the identical request. The cause is the weights; no rebuild recovers it [liminal-2026-07-30-sft-destroys-thinking-mode].

## Patterns

Only behaviour detects it: the guard is a probe that reads `message.thinking` and asserts non-empty, run against every adapter build before any thinking arm is trusted [liminal-2026-07-30-sft-destroys-thinking-mode].

A thinking arm on such an adapter is a silent no-op that still lands a plausible F1. Two runs of the same adapter differing only in `THINK=1` took 1126s and 1135s of real GPU time, produced byte-identical output files (md5-equal, 151,540 bytes) and identical scores to four decimals. Nothing in the result JSON flagged it; a metric-diff tool caught it only because every metric was identical, which two arms differing in a flag cannot be [liminal-2026-07-30-sft-destroys-thinking-mode].

## Cost & Latency

Strategic cost, on a 50-source, 132-gold-slug extraction bench (qwen3-14b): base no thinking F1 0.2203 (recall 0.1894, tp 25, mints 64, 1032s); LoRA adapter v10 no thinking F1 0.5048 (recall 0.4015, tp 53, mints 7, 1135s); base + `THINK=1` F1 0.4549 (recall 0.4015, tp 53, mints 38, 1656s) [liminal-2026-07-30-sft-destroys-thinking-mode].

The adapter beats base-plus-thinking by only +0.0499 F1 while costing a GPU-night of training and foreclosing the thinking lever permanently. Thinking is free at inference and is worth +0.1017 F1 on a 27B and +0.2278 F1 on this 14B base on the same task [liminal-2026-07-30-sft-destroys-thinking-mode].

Adapter and base+thinking are near-orthogonal levers: each recovers 53 true positives (recall 0.4015) but they share only 34 (Jaccard 0.472), with an oracle union of 72 (recall 0.5455). The "do training and thinking stack?" question is closed by the training recipe, since the trained model cannot think [liminal-2026-07-30-sft-destroys-thinking-mode].

## Pitfalls

Relation to existing failure classes: converse of the schema-coupling failure (adding a thinking field to an adapter trained without one collapsed recall 0.934 to 0.218; here the thinking request is inert rather than destructive). Both are the same class (adapter weights coupled to the shape of what they were trained to emit) and both are distinct from the Tam et al. base-model reasoning tax [liminal-2026-07-30-sft-destroys-thinking-mode].

## Field Notes

Open question, untested: whether training on completions that carry reasoning traces preserves the thinking mode. A library lookup returned only a partial hit; it is the next training run's question, not a settled answer [liminal-2026-07-30-sft-destroys-thinking-mode].

Practical guidance: probe every adapter build behaviourally before trusting any thinking arm; price the reasoning-mode loss into the decision to fine-tune at all (here the adapter's entire margin over base+thinking was 0.05 F1); never read template equality, capability flags, or a non-erroring API as evidence that thinking works [liminal-2026-07-30-sft-destroys-thinking-mode].
