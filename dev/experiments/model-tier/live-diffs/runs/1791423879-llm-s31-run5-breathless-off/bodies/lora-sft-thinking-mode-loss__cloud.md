---
last_verified: ""
updated: 2026-10-07
sources:
  - sources/liminal/liminal-2026-07-30-sft-destroys-thinking-mode.md
title: SFT/LoRA on Reasoning-Free Completions Destroys the Base Model's Thinking Mode
routing: LoRA/SFT adapters trained on plain input-to-completion pairs lose the base model's thinking mode (message.thinking empty) — how to detect it, why think:true, ollama show and template equality do not reveal it, what it costs versus base plus thinking, whether training and thinking stack
tags:
  - llm
  - fine-tuning
  - reasoning
  - chain-of-thought
  - evals
---

## Overview

In the liminal runs, three LoRA adapters trained on plain input-to-completion pairs (no reasoning traces) emitted no thinking at all on requests where their base models did [liminal-2026-07-30-sft-destroys-thinking-mode]. The loss is silent: a thinking arm run against such an adapter is a no-op that still produces a plausible score [liminal-2026-07-30-sft-destroys-thinking-mode].

## Key Concepts

**What was observed.** Three adapters at three sizes from three separate training runs (qwen3-4b-extract-v8, qwen3-8b-extract-v9, qwen3-14b-extract-v10) all emitted 0 characters of `message.thinking` on a request where their base models emit reasoning (762 characters on the probe request for the 14B). That is 3 of 3, no partials. On a 50-source extraction bench, 0/50 rows thought on the adapter versus 50/50 on its base [liminal-2026-07-30-sft-destroys-thinking-mode].

**Cause.** The training data was plain input-to-completion pairs with no reasoning traces; the adapter appears to have learned to emit an empty think block [liminal-2026-07-30-sft-destroys-thinking-mode]. The cause is the weights, and no rebuild recovers it [liminal-2026-07-30-sft-destroys-thinking-mode].

**Relation to schema coupling.** This is the converse of the failure in [[lora-output-schema-coupling]]: there, adding a thinking field to an adapter trained without one collapsed recall from 0.934 to 0.218, while here the thinking request is inert rather than destructive. liminal treats both as the same class (adapter weights coupled to the shape of what they were trained to emit), and both as distinct from the Tam et al. base-model reasoning tax [liminal-2026-07-30-sft-destroys-thinking-mode].

## Pitfalls

**No static signal detects the loss.** All three adapters read green on a model that cannot think [liminal-2026-07-30-sft-destroys-thinking-mode]:

1. The Ollama API accepts `think: true` without error.
2. `ollama show` advertises the `thinking` capability.
3. The chat template is byte-identical to the base's (verified via `ollama show --template`).

**The template was the wrong suspect.** An afterburn/Modelfile chain was stripping `/think` tokens, and that drift was real. The repair was built and verified byte-equal, and it changed nothing: still 0 characters against the base's 762 on the identical request [liminal-2026-07-30-sft-destroys-thinking-mode].

**A thinking arm on such an adapter is a silent no-op.** Two runs of the same adapter differing only in `THINK=1` took 1126s and 1135s of real GPU time, produced byte-identical output files (md5-equal, 151,540 bytes), and scored identically to four decimals. Nothing in the result JSON flagged it. A metric-diff tool caught it only because every metric was identical, which two arms differing in a flag cannot be [liminal-2026-07-30-sft-destroys-thinking-mode].

## Cost & Latency

Results on a 50-source, 132-gold-slug extraction bench with qwen3-14b [liminal-2026-07-30-sft-destroys-thinking-mode]:

| Arm | F1 | Recall | TP | Mints | Time |
|-----|-----|--------|-----|-------|------|
| Base, no thinking | 0.2203 | 0.1894 | 25 | 64 | 1032s |
| LoRA adapter v10, no thinking | 0.5048 | 0.4015 | 53 | 7 | 1135s |
| Base + `THINK=1` | 0.4549 | 0.4015 | 53 | 38 | 1656s |

The adapter beats base-plus-thinking by only +0.0499 F1 while costing a GPU-night of training and foreclosing the thinking lever permanently. liminal reports thinking as free at inference and worth +0.1017 F1 on a 27B and +0.2278 F1 on this 14B base on the same task [liminal-2026-07-30-sft-destroys-thinking-mode].

The adapter and base+thinking are near-orthogonal levers. Each recovers 53 true positives (recall 0.4015), but they share only 34 (Jaccard 0.472), with an oracle union of 72 (recall 0.5455). The question of whether training and thinking stack is closed by the training recipe, since the trained model cannot think [liminal-2026-07-30-sft-destroys-thinking-mode].

## Eval Strategy

The only detector is behavioural: a probe that reads `message.thinking` and asserts it is non-empty, run against every adapter build before any thinking arm is trusted [liminal-2026-07-30-sft-destroys-thinking-mode]. Template equality, capability flags, and a non-erroring API are not evidence that thinking works [liminal-2026-07-30-sft-destroys-thinking-mode].

## Field Notes

- liminal's guidance is to price the reasoning-mode loss into the decision to fine-tune at all. In its case the adapter's entire margin over base+thinking was 0.05 F1 [liminal-2026-07-30-sft-destroys-thinking-mode].
- Open and untested: whether training on completions that carry reasoning traces preserves the thinking mode. A library lookup returned only a partial hit, so liminal treats it as the next training run's question, not a settled answer [liminal-2026-07-30-sft-destroys-thinking-mode].

## Sources

- liminal-2026-07-30-sft-destroys-thinking-mode (tier 3, practitioner)
