---
last_verified: ""
sources:
  - sources/zenml/zenml-2025-12-llmops-1200-deployments.md
title: Agent Training and Evaluation Economics: RL Fine-Tuning, Regression Datasets, Offline Eval
routing: How do companies train and evaluate AI agents economically? What methods are used for fine-tuning, regression testing, and offline evaluation?
tags: llmops evals llm-as-judge rag agents cost-economics
---
OpenPipe's ART·E trained Qwen-14B with GRPO and outperformed OpenAI's o3 on an email-research task, training on a single H100 for roughly $80 [zenml-2025-12-llmops-1200-deployments]. When Cursor adapted to Codex it renamed tools to align with shell conventions; dropping reasoning traces caused a 30% performance degradation [zenml-2025-12-llmops-1200-deployments]. Ramp turns every user-reported failure into a regression test case and created "golden datasets" carefully reviewed by an internal team [zenml-2025-12-llmops-1200-deployments]. GitHub runs comprehensive offline evaluations that catch regressions before production [zenml-2025-12-llmops-1200-deployments]. Cox Automotive generates test conversations and uses a separate LLM to evaluate quality against standards [zenml-2025-12-llmops-1200-deployments].
