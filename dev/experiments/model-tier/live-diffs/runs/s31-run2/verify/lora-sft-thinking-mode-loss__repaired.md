---
last_verified: ""
sources:
  - sources/incoming/liminal-2026-07-30-sft-destroys-thinking-mode.md
title: SFT/LoRA on Reasoning-Free Completions Destroys the Base Model's Thinking Mode
routing: LoRA/SFT adapters trained on plain input-to-completion pairs lose the base model's thinking mode, how to detect the silent loss, why think:true and template equality don't reveal it, what it costs versus base plus thinking, whether training and thinking stack
tags: [llm, fine-tuning, chain-of-thought, reasoning, evals]
---

## Overview

When you fine-tune a reasoning-capable model with LoRA or SFT on plain input-to-completion pairs that carry no reasoning traces, the resulting adapter silently destroys the base model's thinking mode. Three LoRA adapters at three sizes, from three separate training runs (qwen3-4b-extract-v8, qwen3-8b-extract-v9, qwen3-14b-extract-v10), all emit 0 characters of `message.thinking` on a request where their base models emit reasoning (762 characters on the probe request for the 14B) — 3 of 3, no partials [liminal-2026-07-30-sft-destroys-thinking-mode]. On a 50-source extraction bench, 0/50 rows thought on the adapter versus 50/50 on its base [liminal-2026-07-30-sft-destroys-thinking-mode].

The training data was plain input-to-completion pairs with no reasoning traces; the adapter appears to have learned to emit an empty think block [liminal-2026-07-30-sft-destroys-thinking-mode]. This is a silent failure: no static signal on the model reveals the loss, and a thinking arm wired against the adapter becomes a no-op that still produces plausible scores.

## Key Concepts

**The mechanism is in the weights, not the template.** The original suspect was the chat template — an afterburn/Modelfile chain was stripping `/think` tokens. That drift was real, but the repair was built, verified byte-equal, and changed nothing: still 0 characters against the base's 762 on the identical request. The cause is the weights; no rebuild recovers it [liminal-2026-07-30-sft-destroys-thinking-mode].

**No static signal detects the loss.** All three adapters read green on a model that cannot think: (1) the Ollama API accepts `think: true` without error, (2) `ollama show` advertises the `thinking` capability, (3) the chat template is byte-identical to the base's (verified via `ollama show --template`) [liminal-2026-07-30-sft-destroys-thinking-mode].

**Only behaviour detects it.** The guard is a probe that reads `message.thinking` and asserts non-empty, run against every adapter build before any thinking arm is trusted [liminal-2026-07-30-sft-destroys-thinking-mode].

## Patterns

**Behavioural probe as the sole detection mechanism.** The only reliable check is a probe request that reads `message.thinking` and asserts the field is non-empty. This must run against every adapter build before any thinking arm is trusted [liminal-2026-07-30-sft-destroys-thinking-mode].

**Silent no-op in a thinking arm.** A thinking arm on such an adapter is a silent no-op that still lands a plausible F1. Two runs of the same adapter differing only in `THINK=1` took 1126s and 1135s of real GPU time, produced byte-identical output files (md5-equal, 151,540 bytes) and identical scores to four decimals. Nothing in the result JSON flagged it; a metric-diff tool caught it only because every metric was identical, which two arms differing in a flag cannot be [liminal-2026-07-30-sft-destroys-thinking-mode].

## Pitfalls

**The thinking arm is a silent no-op, not an error.** The adapter does not reject the `think: true` parameter and does not change its output. The result is a plausible F1 that looks like a valid thinking run [liminal-2026-07-30-sft-destroys-thinking-mode].

**Template byte-equality is not evidence of thinking capability.** The template was verified byte-identical to the base's, yet the model still emitted 0 characters of thinking. The template is a surface property; the weights determine whether the model actually generates reasoning content [liminal-2026-07-30-sft-destroys-thinking-mode].

**This is the converse of the schema-coupling failure.** Adding a thinking field to an adapter trained without one collapsed recall from 0.934 to 0.218; here the thinking request is inert rather than destructive. Both are the same class — adapter weights coupled to the shape of what they were trained to emit — and both are distinct from the Tam et al. base-model reasoning tax. See [[lora-output-schema-coupling]] for the schema-coupling failure in detail [liminal-2026-07-30-sft-destroys-thinking-mode].

## Cost & Latency

**Strategic cost on a 50-source, 132-gold-slug extraction bench (qwen3-14b):**

| Configuration | F1 | Recall | TP | Mints | Time |
|---|---|---|---|---|---|
| Base, no thinking | 0.2203 | 0.1894 | 25 | 64 | 1032s |
| LoRA adapter v10, no thinking | 0.5048 | 0.4015 | 53 | 7 | 1135s |
| Base + `THINK=1` | 0.4549 | 0.4015 | 53 | 38 | 1656s |

[liminal-2026-07-30-sft-destroys-thinking-mode]

The adapter beats base-plus-thinking by only +0.0499 F1 while costing a GPU-night of training and foreclosing the thinking lever permanently. Thinking is free at inference and is worth +0.1017 F1 on a 27B and +0.2278 F1 on this 14B base on the same task [liminal-2026-07-30-sft-destroys-thinking-mode].

**Adapter and base+thinking are near-orthogonal levers.** Each recovers 53 true positives (recall 0.4015) but they share only 34 (Jaccard 0.472), with an oracle union of 72 (recall 0.5455). The "do training and thinking stack?" question is closed by the training recipe, since the trained model cannot think [liminal-2026-07-30-sft-destroys-thinking-mode].

## Eval Strategy

The only eval that catches this failure is a behavioural probe: send a request with `think: true` (or the equivalent) and assert that `message.thinking` is non-empty. Run this against every adapter build before any thinking arm is trusted [liminal-2026-07-30-sft-destroys-thinking-mode]. Static checks — API acceptance of the flag, capability advertisement, template byte-equality — all pass on a model that cannot think and provide no signal [liminal-2026-07-30-sft-destroys-thinking-mode].

A metric-diff tool caught the no-op only because every metric was identical, which two arms differing in a flag cannot be [liminal-2026-07-30-sft-destroys-thinking-mode].

## Field Notes

**The template was the original suspect, and the repair changed nothing.** An afterburn/Modelfile chain was stripping `/think` tokens. That drift was real, but the repair was built, verified byte-equal, and changed nothing: still 0 characters against the base's 762 on the identical request. The cause is the weights; no rebuild recovers it [liminal-2026-07-30-sft-destroys-thinking-mode].

**Open question, untested:** whether training on completions that carry reasoning traces preserves the thinking mode. A library lookup returned only a partial hit; it is the next training run's question, not a settled answer [liminal-2026-07-30-sft-destroys-thinking-mode].

**Practical guidance:** probe every adapter build behaviourally before trusting any thinking arm; price the reasoning-mode loss into the decision to fine-tune at all (here the adapter's entire margin over base+thinking was 0.05 F1); never read template equality, capability flags, or a non-erroring API as evidence that thinking works [liminal-2026-07-30-sft-destroys-thinking-mode].

## Sources

- [liminal-2026-07-30-sft-destroys-thinking-mode] — Tier 3 (practitioner), 2026-07-30. Three LoRA adapter training runs (qwen3-4b/8b/14b) on extraction tasks; behavioural probe results, cost analysis, and detection methodology.
