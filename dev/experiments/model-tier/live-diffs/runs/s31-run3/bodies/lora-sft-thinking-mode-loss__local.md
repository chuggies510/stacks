---
last_verified: ""
sources:
  - sources/incoming/liminal-2026-07-30-sft-destroys-thinking-mode.md
title: SFT/LoRA on Reasoning-Free Completions Destroys the Base Model's Thinking Mode
routing: SFT/LoRA adapters trained on plain completions losing the base model's thinking mode, how to detect the loss, why static checks fail, and the cost of foreclosing the thinking lever
tags: [llm, fine-tuning, reasoning, context-engineering]
---

## Overview

Supervised fine-tuning (SFT) or LoRA adapters trained on plain input-to-completion pairs can silently destroy the base model's thinking mode. When the training data lacks reasoning traces, the adapter learns to emit an empty think block, rendering the model's extended thinking capability inert. This failure is distinct from schema-coupling issues and base-model reasoning taxes; it is a direct consequence of the adapter weights being coupled to the shape of the training data. The loss is not detectable through static configuration checks or API capability flags, requiring behavioral probing to identify.

## Key Concepts

The mechanism of failure is that the adapter learns to emit an empty think block when trained on data without reasoning traces. In a specific case, three LoRA adapters at three sizes (qwen3-4b-extract-v8, qwen3-8b-extract-v9, qwen3-14b-extract-v10) from three separate training runs all emitted 0 characters of `message.thinking` on a request where their base models emitted reasoning (762 characters on the probe request for the 14B) [liminal-2026-07-30-sft-destroys-thinking-mode]. This was consistent across 3 of 3 adapters with no partials. On a 50-source extraction bench, 0/50 rows thought on the adapter versus 50/50 on its base [liminal-2026-07-30-sft-destroys-thinking-mode]. The training data consisted of plain input-to-completion pairs with no reasoning traces, and the adapter appears to have learned to emit an empty think block [liminal-2026-07-30-sft-destroys-thinking-mode].

This failure is the converse of the schema-coupling failure, where adding a thinking field to an adapter trained without one collapsed recall from 0.934 to 0.218. In that case, the thinking request was destructive; here, the thinking request is inert. Both belong to the same class of failure: adapter weights coupled to the shape of what they were trained to emit. Both are distinct from the Tam et al. base-model reasoning tax [liminal-2026-07-30-sft-destroys-thinking-mode].

## Patterns

The only reliable detection method is behavioral probing. A guard must be a probe that reads `message.thinking` and asserts non-empty, run against every adapter build before any thinking arm is trusted [liminal-2026-07-30-sft-destroys-thinking-mode]. Static signals do not detect the loss. All three adapters read green on a model that cannot think: (1) the Ollama API accepts `think: true` without error, (2) `ollama show` advertises the `thinking` capability, and (3) the chat template is byte-identical to the base's (verified via `ollama show --template`) [liminal-2026-07-30-sft-destroys-thinking-mode].

The chat template was the original suspect, as an afterburn/Modelfile chain was stripping `/think` tokens. That drift was real, but the repair was built, verified byte-equal, and changed nothing: still 0 characters against the base's 762 on the identical request. The cause is the weights; no rebuild recovers it [liminal-2026-07-30-sft-destroys-thinking-mode].

## Pitfalls

A thinking arm on such an adapter is a silent no-op that still lands a plausible F1. Two runs of the same adapter differing only in `THINK=1` took 1126s and 1135s of real GPU time, produced byte-identical output files (md5-equal, 151,540 bytes) and identical scores to four decimals. Nothing in the result JSON flagged it; a metric-diff tool caught it only because every metric was identical, which two arms differing in a flag cannot be [liminal-2026-07-30-sft-destroys-thinking-mode].

Practitioners must never read template equality, capability flags, or a non-erroring API as evidence that thinking works [liminal-2026-07-30-sft-destroys-thinking-mode].

## Cost & Latency

The strategic cost of losing the thinking mode is significant. On a 50-source, 132-gold-slug extraction bench (qwen3-14b), the base model without thinking achieved F1 0.2203 (recall 0.1894, tp 25, mints 64, 1032s). The LoRA adapter v10 without thinking achieved F1 0.5048 (recall 0.4015, tp 53, mints 7, 1135s). The base model with `THINK=1` achieved F1 0.4549 (recall 0.4015, tp 53, mints 38, 1656s) [liminal-2026-07-30-sft-destroys-thinking-mode].

The adapter beats base-plus-thinking by only +0.0499 F1 while costing a GPU-night of training and foreclosing the thinking lever permanently. Thinking is free at inference and is worth +0.1017 F1 on a 27B and +0.2278 F1 on this 14B base on the same task [liminal-2026-07-30-sft-destroys-thinking-mode].

## Eval Strategy

Adapter and base+thinking are near-orthogonal levers. Each recovers 53 true positives (recall 0.4015) but they share only 34 (Jaccard 0.472), with an oracle union of 72 (recall 0.5455). The "do training and thinking stack?" question is closed by the training recipe, since the trained model cannot think [liminal-2026-07-30-sft-destroys-thinking-mode].

An open question, untested, is whether training on completions that carry reasoning traces preserves the thinking mode. A library lookup returned only a partial hit; it is the next training run's question, not a settled answer [liminal-2026-07-30-sft-destroys-thinking-mode].

## Field Notes

Practical guidance includes probing every adapter build behaviorally before trusting any thinking arm, pricing the reasoning-mode loss into the decision to fine-tune at all (here the adapter's entire margin over base+thinking was 0.05 F1), and never reading template equality, capability flags, or a non-erroring API as evidence that thinking works [liminal-2026-07-30-sft-destroys-thinking-mode].
