---
last_verified: ""
sources:
  - sources/incoming/liminal-2026-07-30-sft-destroys-thinking-mode.md
title: SFT/LoRA on Reasoning-Free Completions Destroys the Base Model's Thinking Mode
routing: What happens to a model's thinking mode after LoRA/SFT fine-tuning on plain completions, how to detect the loss, what it costs strategically, and whether training and thinking can stack
tags: [llm, fine-tuning, chain-of-thought, reasoning, evals]
---

## Overview

When a LoRA adapter is trained on plain input-to-completion pairs that carry no reasoning traces, the adapter appears to learn to emit an empty `message.thinking` field, permanently disabling the base model's thinking mode [liminal-2026-07-30-sft-destroys-thinking-mode]. This article documents the failure across three adapter sizes, the absence of any static detection signal, the silent no-op behaviour of a thinking arm on such an adapter, and the strategic cost of the loss on a concrete extraction benchmark.

## Key Concepts

Three LoRA adapters at three sizes, from three separate training runs (qwen3-4b-extract-v8, qwen3-8b-extract-v9, qwen3-14b-extract-v10), all emit 0 characters of `message.thinking` on a probe request where their base models emit reasoning (762 characters on the 14B base). The result is 3 of 3 with no partials. On a 50-source extraction bench, 0 of 50 rows produced thinking on the adapter versus 50 of 50 on the base [liminal-2026-07-30-sft-destroys-thinking-mode].

The training data for all three adapters was plain input-to-completion pairs with no reasoning traces; the adapter appears to have learned to emit an empty think block [liminal-2026-07-30-sft-destroys-thinking-mode].

No static signal detects the loss. All three adapters read green on a model that cannot think: (1) the Ollama API accepts `think: true` without error, (2) `ollama show` advertises the `thinking` capability, and (3) the chat template is byte-identical to the base's, verified via `ollama show --template` [liminal-2026-07-30-sft-destroys-thinking-mode].

The chat template was the original suspect: an afterburn/Modelfile chain was stripping `/think` tokens. That drift was real, but the repair was built, verified byte-equal, and changed nothing: the adapter still emitted 0 characters against the base's 762 on the identical request. The cause is the weights; no rebuild recovers it [liminal-2026-07-30-sft-destroys-thinking-mode].

## Patterns

The only detection method is behavioural: a probe that reads `message.thinking` and asserts non-empty, run against every adapter build before any thinking arm is trusted [liminal-2026-07-30-sft-destroys-thinking-mode].

## Pitfalls

A thinking arm on such an adapter is a silent no-op that still lands a plausible F1. Two runs of the same adapter differing only in `THINK=1` took 1126 s and 1135 s of real GPU time, produced byte-identical output files (md5-equal, 151,540 bytes), and produced identical scores to four decimals. Nothing in the result JSON flagged the issue; a metric-diff tool caught it only because every metric was identical, which two arms differing in a flag cannot be [liminal-2026-07-30-sft-destroys-thinking-mode].

This failure is the converse of the schema-coupling failure documented in [[lora-output-schema-coupling]]: there, adding a thinking field to an adapter trained without one collapsed recall from 0.934 to 0.218; here, the thinking request is inert rather than destructive. Both are the same class—adapter weights coupled to the shape of what they were trained to emit—and both are distinct from the Tam et al. base-model reasoning tax [liminal-2026-07-30-sft-destroys-thinking-mode].

## Cost & Latency

On a 50-source, 132-gold-slug extraction bench (qwen3-14b):

| Configuration | F1 | Recall | TP | Mints | Time |
|---|---|---|---|---|---|
| Base, no thinking | 0.2203 | 0.1894 | 25 | 64 | 1032 s |
| LoRA adapter v10, no thinking | 0.5048 | 0.4015 | 53 | 7 | 1135 s |
| Base + `THINK=1` | 0.4549 | 0.4015 | 53 | 38 | 1656 s |

The adapter beats base-plus-thinking by only +0.0499 F1 while costing a GPU-night of training and foreclosing the thinking lever permanently. Thinking is free at inference and is worth +0.1017 F1 on a 27B model and +0.2278 F1 on this 14B base on the same task [liminal-2026-07-30-sft-destroys-thinking-mode].

Adapter and base+thinking are near-orthogonal levers: each recovers 53 true positives (recall 0.4015) but they share only 34 (Jaccard 0.472), with an oracle union of 72 (recall 0.5455). The question "do training and thinking stack?" is closed by the training recipe, since the trained model cannot think [liminal-2026-07-30-sft-destroys-thinking-mode].

## Field Notes

Practical guidance from this observation: probe every adapter build behaviourally before trusting any thinking arm; price the reasoning-mode loss into the decision to fine-tune at all (here the adapter's entire margin over base+thinking was 0.05 F1); and never read template equality, capability flags, or a non-erroring API as evidence that thinking works [liminal-2026-07-30-sft-destroys-thinking-mode].

An open question remains untested: whether training on completions that carry reasoning traces preserves the thinking mode. A library lookup returned only a partial hit; it is the next training run's question, not a settled answer [liminal-2026-07-30-sft-destroys-thinking-mode].
