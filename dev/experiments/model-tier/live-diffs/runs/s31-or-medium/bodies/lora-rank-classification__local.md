---
last_verified: ""
sources:
  - sources/liminal/liminal-s27-lora-recall-techniques.md
  - sources/arxiv/rslora-rank-stabilized-scaling.md
  - sources/incoming/liminal-2026-07-03-lora-rank-binary-classification.md
title: LoRA rank selection for classification tasks
routing: LoRA rank hyperparameter for classification — why r=4-16 saturates early, what the alpha=2×rank convention actually does (and why it breaks rank sweeps), overfitting risk at small dataset sizes, rsLoRA as the fix for high-rank training, and Park's NTK-regime result that eliminates rank thresholds for binary classification specifically
tags:
  - llm
  - fine-tuning
---

## Overview

LoRA (Low-Rank Adaptation) inserts trainable low-rank matrices into a frozen model's weight layers. The `rank` hyperparameter (`r`) controls the capacity of those matrices: higher rank means more trainable parameters, more expressive adaptation, and more risk of overfitting on small datasets. For classification tasks specifically, the empirical consensus is that rank saturates early, making this a case where the default aggressive value hurts more than it helps.

## Key concepts

**Rank saturation.** For classification tasks, rank r=4-16 is sufficient. Literature across QLoRA, Databricks fine-tuning guides, Raschka hyperparameter sweeps, and a Frontiers in Big Data 2025 study consistently finds very little statistical difference between rank 8 and rank 256 on classification benchmarks [liminal-s27-lora-recall-techniques]. The extra parameters in high-rank adapters do not translate into measurably better accuracy on held-out classification labels.

**Park's NTK-regime result for binary classification.** Prior work prescribes LoRA rank >=12 for binary classification. Park (arXiv:2605.03724, submitted 2026-05-05) argues, under an NTK-regime cross-entropy-loss analysis, that the Polyak-Lojasiewicz inequality eliminates rank thresholds for binary classification specifically [liminal-2026-07-03-lora-rank-binary-classification]. The mechanism is that the bias term saturates fast, so rank r=1 is empirically competitive with r=12 on GLUE-style binary tasks; rank beyond what is needed to saturate bias buys nothing but added variance [liminal-2026-07-03-lora-rank-binary-classification]. For multi-class (K>2) the optimal rank shifts above 1; the paper leaves this as future work [liminal-2026-07-03-lora-rank-binary-classification].

**Alpha convention and what it actually does.** The `lora_alpha` scaling parameter is typically set to 2x the rank value (e.g., r=8, alpha=16; r=16, alpha=32). The reason practitioners follow this convention is to keep adapter outputs on a comparable scale across runs — but the standard implementation divides the adapter output by rank (effective scale = alpha/r), and the rsLoRA paper (arXiv:2312.03732) proves mathematically that this progressively suppresses higher-rank adapters: as rank increases, the adapter's contribution to the forward pass is scaled down, slowing learning and stunting performance [rslora-rank-stabilized-scaling]. The scaling does not hold the contribution constant; it penalizes it. This is the mechanism behind LoRA's historically poor performance at high rank — not a theoretical limitation of rank itself.

The correct scaling that stabilizes adapter contribution across ranks is alpha/sqrt(r), which the paper calls rank-stabilized LoRA (rsLoRA) [rslora-rank-stabilized-scaling]. With rsLoRA scaling, larger ranks become a viable compute/performance trade-off: higher rank improves fine-tuning quality at the cost of training compute, with no change to inference compute.

**Overfitting at small dataset sizes.** Higher ranks increase the adapter parameter count. At dataset sizes below approximately 500 examples, this extra capacity is absorbed by noise rather than signal, degrading generalization [liminal-s27-lora-recall-techniques]. On small classification datasets, staying at r=4-8 reduces overfitting risk without sacrificing task coverage.

## Patterns

**Default starting point.** For most classification fine-tuning runs, start at r=8 with alpha=16. This covers the saturation threshold identified across multiple independent sweeps without exposing the run to overfitting risk.

**Underfitting recovery.** If the model underfits after expanding LoRA to all linear target modules (attention projections and MLP layers), move to r=16 with alpha=32. Ranks of 32 or higher are rarely justified for classification tasks [liminal-s27-lora-recall-techniques].

**When to break the ceiling.** The "ranks of 32 or higher rarely justified" claim applies to standard classification (single-label, multi-label, sequence tagging). Tasks that are structurally different — generative tasks, instruction following, style transfer — are outside this guidance and may benefit from higher ranks. For those tasks, use rsLoRA scaling (alpha proportional to sqrt(r)) rather than alpha=2r when sweeping to high rank, so the scaling artifact does not confound the comparison [rslora-rank-stabilized-scaling].

## Pitfalls

**Assuming more rank equals better results.** The intuition from full fine-tuning (more parameters = more capacity = better fit) does not transfer cleanly to LoRA classification. The low-dimensional structure of classification targets means rank saturation happens well below what practitioners expect [liminal-s27-lora-recall-techniques].

**Ignoring dataset size when picking rank.** A rank that works well on a large dataset can overfit badly on a small one. Scale rank down proportionally when dataset size is small; the overfitting threshold is around 500 examples [liminal-s27-lora-recall-techniques].

**Sweeping rank under standard alpha=2r and misreading the results.** Standard LoRA's alpha/r scaling suppresses the adapter output more aggressively at higher ranks. A higher-rank adapter may appear to perform worse than a lower-rank adapter in a sweep, not because the extra capacity is unhelpful, but purely because the scaling factor is working against it [rslora-rank-stabilized-scaling]. To isolate rank capacity from the scaling artifact, use rsLoRA (alpha proportional to sqrt(r)) across the sweep.

**Applying Park's binary-classification result to a causal LM head.** Park's setting is a literal classifier head under cross-entropy loss; a causal LM that emits JSON encoding the decision via token probabilities is not a sigmoid/softmax binary head, so the bias-saturates-fast argument may not carry over. Treat as a directional prior, not a proven transfer [liminal-2026-07-03-lora-rank-binary-classification].

## Eval strategy

Measure held-out classification accuracy and per-class F1 across ranks (r=4, 8, 16, 32) with alpha=2r at each step. Plot accuracy vs. rank: saturation is visible as a flat curve above r=16. Overfitting shows as training accuracy pulling away from validation accuracy at higher ranks on small datasets. If the sweep shows a performance dip at higher ranks that is not explained by overfitting, consider rerunning with rsLoRA scaling to determine whether the dip is a rank artifact or a true capacity ceiling. A short ablation sweep costs little compute and confirms whether the dataset and task fall within the typical saturation pattern.

## Field notes

**Podly ad-vs-content classifier (4B model, 283-chunk training set).** If Park's result transfers, doubling rank 8→16 should not recover a heldout false-positive regression and may hurt via overfitting variance, a mechanistic hint that the wall is a base-model ceiling rather than adapter capacity. This is an unrun prediction at time of writing; the rank-16 experiment was still in progress [liminal-2026-07-03-lora-rank-binary-classification].

## Sources

| Source | Tier | Role |
|--------|------|------|
| liminal-s27-lora-recall-techniques | 3 | Primary: rank saturation claims, overfitting threshold, r=16/alpha=32 fallback recipe |
| rslora-rank-stabilized-scaling | 2 | Corrects alpha/r scaling mechanism; introduces rsLoRA (alpha/sqrt(r)); explains historical low-rank bias |
| liminal-2026-07-03-lora-rank-binary-classification | 3 | Park NTK/PL result for binary classification; bias-saturation mechanism; multi-class boundary; Podly practitioner prediction; causal-LM transfer caveat |
