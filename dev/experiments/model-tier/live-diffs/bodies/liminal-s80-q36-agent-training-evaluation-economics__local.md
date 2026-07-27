---
last_verified: ""
sources:
  - sources/zenml/zenml-2025-12-llmops-1200-deployments.md
title: Agent Training and Evaluation Economics
routing: Covers RL fine-tuning costs, regression dataset creation, offline evaluation workflows, and production failure modes for agent systems.
tags: [llmops, evals, fine-tuning, cost-economics]
---

## Overview
Agent training and evaluation economics addresses the compute requirements for fine-tuning models, the construction of regression datasets, and offline evaluation workflows used before deployment. Practitioners apply these practices to validate agent capabilities, prevent performance regressions, and manage training budgets across iterative development cycles. [zenml-2025-12-llmops-1200-deployments]

## Cost & Latency
Fine-tuning agents can operate within constrained compute budgets while still achieving competitive results. OpenPipe's ART·E trained Qwen-14B with GRPO and outperformed OpenAI's o3 on an email-research task, training on a single H100 for roughly $80. [zenml-2025-12-llmops-1200-deployments]

## Eval Strategy
Organizations implement structured evaluation pipelines to catch issues before agents reach users. Ramp turns every user-reported failure into a regression test case and created "golden datasets" carefully reviewed by an internal team. [zenml-2025-12-llmops-1200-deployments] GitHub runs comprehensive offline evaluations that catch regressions before production. [zenml-2025-12-llmops-1200-deployments] Cox Automotive generates test conversations and uses a separate LLM to evaluate quality against standards. [zenml-2025-12-llmops-1200-deployments]

## Pitfalls
Modifying agent tooling or removing intermediate reasoning steps can introduce significant performance drops. When Cursor adapted to Codex it renamed tools to align with shell conventions; dropping reasoning traces caused a 30% performance degradation. [zenml-2025-12-llmops-1200-deployments]
