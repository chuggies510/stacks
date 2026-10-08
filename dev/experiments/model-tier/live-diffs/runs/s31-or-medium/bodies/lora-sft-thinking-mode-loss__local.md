---
last_verified: ""
sources:
  - sources/incoming/liminal-2026-07-30-sft-destroys-thinking-mode.md
title: SFT/LoRA on Reasoning-Free Completions Destroys the Base Model's Thinking Mode
routing: LoRA/SFT adapter trained on plain completions silently loses the base model's thinking mode, how to detect it behaviourally, what it costs in F1 and GPU time, whether training and thinking stack, and what to probe before trusting a thinking arm
tags: [llm, fine-tuning, evals, llmops]
---

## Overview

Training a LoRA adapter on plain input-to-completion pairs (no reasoning traces) causes the adapter to emit 0 characters of `message.thinking` on requests where its base model emits reasoning [liminal-2026-07-30-sft-destroys-thinking-mode]. Three adapters at three sizes from three separate training runs—qwen3-4b-extract-v8, qwen3-8b-extract-v9, and qwen3-14b-extract-v10—all showed this: 3 of 3, no partials. On a 50-source extraction bench, 0/50 rows thought on the adapter versus 50/50 on its base [liminal-2026-07-30-sft-destroys-thinking-mode].

The failure is silent: no static signal (API flag, capability advertisement, template diff) reveals it, and a thinking arm run against the adapter produces byte-identical output to a no-thinking run while still landing a plausible F1 score [liminal-2026-07-30-sft-destroys-thinking-mode].

## Key Concepts

The training data for all three adapters was plain input-to-completion pairs with no reasoning traces; the adapter appears to have learned to emit an empty think block [liminal-2026-07-30-sft-destroys-thinking-mode].

No static signal detects the loss. All three adapters read green on a model that cannot think: (1) the Ollama API accepts `think: true` without error, (2) `ollama show` advertises the `thinking` capability, and (3) the chat template is byte-identical to the base's (verified via `ollama show --template`) [liminal-2026-07-30-sft-destroys-thinking-mode].

The template was the original suspect—an afterburn/Modelfile chain was stripping `/think` tokens. That drift was real, but the repair was built, verified byte-equal, and changed nothing: still 0 characters against the base's 762 on the identical request. The cause is the weights; no rebuild recovers it [liminal-2026-07-30-sft-destroys-thinking-mode].

Only behaviour detects the loss: a probe that reads `message.thinking` and asserts non-empty, run against every adapter build before any thinking arm is trusted [liminal-2026-07-30-sft-destroys-thinking-mode].

## Patterns

The detection guard is a behavioural probe: send a request known to elicit reasoning on the base model, read `message.thinking`, and assert the field is non-empty. Run this against every adapter build before any thinking arm is trusted [liminal-2026-07-30-sft-destroys-thinking-mode].

A metric-diff tool caught the silent no-op in one case: two runs of the same adapter differing only in `THINK=1` produced byte-identical output files (md5-equal, 151,540 bytes) and identical scores to four decimals. Nothing in the result JSON flagged it; the metric-diff tool caught it only because every metric was identical, which two arms differing in a flag cannot be [liminal-2026-07-30-sft-destroys-thinking-mode].

## Pitfalls

A thinking arm on such an adapter is a silent no-op that still lands a plausible F1. Two runs of the same adapter differing only in `THINK=1` took 1126 s and 1135 s of real GPU time, produced byte-identical output files (md5-equal, 151,540 bytes) and identical scores to four decimals [liminal-2026-07-30-sft-destroys-thinking-mode].

Never read template equality, capability flags, or a non-erroring API as evidence that thinking works [liminal-2026-07-30-sft-destroys-thinking-mode].

## Cost & Latency

On a 50-source, 132-gold-slug extraction bench (qwen3-14b):

| Configuration | F1 | Recall | TP | Mints | Time |
|---|---|---|---|---|---|
| Base, no thinking | 0.2203 | 0.1894 | 25 | 64 | 1032 s |
| LoRA adapter v10, no thinking | 0.5048 | 0.4015 | 53 | 7 | 1135 s |
| Base + `THINK=1` | 0.4549 | 0.4015 | 53 | 38 | 1656 s |

[liminal-2026-07-30-sft-destroys-thinking-mode]

The adapter beats base-plus-thinking by only +0.0499 F1 while costing a GPU-night of training and foreclosing the thinking lever permanently. Thinking is free at inference and is worth +0.1017 F1 on a 27B and +0.2278 F1 on this 14B base on the same task [liminal-2026-07-30-sft-destroys-thinking-mode].

Adapter and base+thinking are near-orthogonal levers: each recovers 53 true positives (recall 0.4015) but they share only 34 (Jaccard 0.472), with an oracle union of 72 (recall 0.5455). The "do training and thinking stack?" question is closed by the training recipe, since the trained model cannot think [liminal-2026-07-30-sft-destroys-thinking-mode].

## Eval Strategy

The 50-source extraction bench serves as the behavioural test: 0/50 rows thought on the adapter versus 50/50 on its base, making the loss unambiguous at bench scale [liminal-2026-07-30-sft-destroys-thinking-mode].

The probe (read `message.thinking`, assert non-empty) is the minimal regression check to run on every adapter build before any thinking arm is trusted [liminal-2026-07-30-sft-destroys-thinking-mode].

The metric-diff approach—comparing two arms that differ only in a flag and flagging if every metric is identical—catches the silent no-op when the result JSON itself carries no warning [liminal-2026-07-30-sft-destroys-thinking-mode].

## Field Notes

The template was the original suspect (an afterburn/Modelfile chain was stripping `/think` tokens). That drift was real, but the repair was built, verified byte-equal, and changed nothing: still 0 characters against the base's 762 on the identical request. The cause is the weights; no rebuild recovers it [liminal-2026-07-30-sft-destroys-thinking-mode].

Relation to existing failure classes: this is the converse of the schema-coupling failure described in [[lora-output-schema-coupling]] (adding a thinking field to an adapter trained without one collapsed recall 0.934 to 0.218; here the thinking request is inert rather than destructive). Both are the same class—adapter weights coupled to the shape of what they were trained to emit—and both are distinct from the Tam et al. base-model reasoning tax [liminal-2026-07-30-sft-destroys-thinking-mode].

Open question, untested: whether training on completions that carry reasoning traces preserves the thinking mode. A library lookup returned only a partial hit; it is the next training run's question, not a settled answer [liminal-2026-07-30-sft-destroys-thinking-mode].

Practical guidance from the runs: probe every adapter build behaviourally before trusting any thinking arm; price the reasoning-mode loss into the decision to fine-tune at all (here the adapter's entire margin over base+thinking was 0.05 F1); never read template equality, capability flags, or a non-erroring API as evidence that thinking works [liminal-2026-07-30-sft-destroys-thinking-mode].
