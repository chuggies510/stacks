# Source excerpts — arxiv-2306.05685-llm-as-judge-mt-bench

Verbatim lines copied from `~/chungus/dev/library-stack/llm/sources/arxiv/arxiv-2306.05685-llm-as-judge-mt-bench.md`, provided to the validator as the scoped source for this test run.

## Abstract

> Evaluating large language model (LLM) based chat assistants is challenging due to their broad capabilities and the inadequacy of existing benchmarks in measuring human preferences. To address this, we explore using strong LLMs as judges to evaluate these models on more open-ended questions. We examine the usage and limitations of LLM-as-a-judge, including position, verbosity, and self-enhancement biases, as well as limited reasoning ability, and propose solutions to mitigate some of them. We then verify the agreement between LLM judges and human preferences by introducing two benchmarks: MT-bench, a multi-turn question set; and Chatbot Arena, a crowdsourced battle platform. Our results reveal that strong LLM judges like GPT-4 can match both controlled and crowdsourced human preferences well, achieving over 80% agreement, the same level of agreement between humans. Hence, LLM-as-a-judge is a scalable and explainable way to approximate human preferences, which are otherwise very expensive to obtain.

## Key findings

- **Agreement:** "strong LLM judges like GPT-4 can match both controlled and crowdsourced human preferences well, achieving over 80% agreement" — the same level of agreement seen between humans.
- **Known biases:** position bias (favoring the first answer shown), verbosity bias (favoring longer answers), and self-enhancement bias (a judge favoring its own outputs); plus limited reasoning ability. The paper proposes mitigations for some.
- **Benchmarks introduced:** MT-bench (multi-turn questions) and Chatbot Arena (crowdsourced pairwise battles).
- **Value:** LLM-as-a-judge is "a scalable and explainable way to approximate human preferences," which are otherwise expensive to collect.
- Public release: MT-bench questions, ~3K expert votes, ~30K conversations.
