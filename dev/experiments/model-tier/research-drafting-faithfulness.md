# Reducing over-claiming when a small LLM drafts from a fixed claim list

Session S31, 2026-10-07. Primary sources only; where I could not reach a paper's full text I say so.

## Answer

Your measured pattern (thinking off is safest, "readable prose" prompts backfire, a stronger reviewer repairs everything) matches the published evidence, and the published evidence says to keep that setup. The best-measured extra lever is lower temperature, and the one most likely to hurt is more reasoning or a generic "be accurate" instruction. There is no published faithfulness ceiling for a 27B model on a claim-list-to-article task; the nearest evidence says small open models stay imperfect, and verification by a stronger model is the only lever with consistent support.

Your four error types map onto one published taxonomy (Peters and Chin-Yee): widened subject = "generic" generalization, dropped hedge or past-to-present shift = "present tense" generalization, added verdict = "action guiding" generalization ([paper](https://arxiv.org/abs/2504.00025)). That gives a concrete checklist for prompts and reviewers.

## Decoding settings

- Measured: In a regression over the paper's LLM summaries of science abstracts, temperature 0 made summaries with generalized conclusions 76% less likely than temperature 0.7 (coefficient -1.432, p < .001; I checked this in the paper text). [Peters and Chin-Yee 2025](https://arxiv.org/abs/2504.00025).
- Measured: On fine-tuned summarizers, large-beam search was most faithful and nucleus sampling least ([Wan et al., EACL 2023](https://aclanthology.org/2023.eacl-main.210/)). Context-aware decoding (contrast output with and without the source) raised LLaMA summary factuality by 14.3% ([Shi et al.](https://arxiv.org/abs/2305.14739)).
- Qwen3.8-27B card: instruct mode `temperature=0.7, top_p=0.80, top_k=20, presence_penalty=1.5`; thinking mode `temperature=1.0`, and it thinks by default ([card](https://huggingface.co/Qwen/Qwen3.8-27B)). I found no study of presence penalty on faithfulness. My guess is that a penalty on reused words pushes the model to reword claims, but that is untested.
- Applies to us: **already in place.** The harness sends temperature 0, and breathless's served `generation_config.json` sets no presence penalty (temperature 1.0, top_k 20, top_p 0.95, all overridden by greedy decoding); checked 2026-10-07. **No** for context-aware decoding and lookahead: old models, custom decoding code, no vLLM-era evidence.

## Thinking or reasoning effort

- Measured: Vectara found DeepSeek-R1 at 14.3% hallucination versus V3 at 3.9% on summaries, and QwQ-32B-Preview 16.1% versus Qwen2.5-32B-Instruct 3.0% ([Vectara](https://vectara.com/blog/why-does-deepseek-r1-hallucinate-so-much)). Their diagnosis: the reasoning is not the culprit. Feeding R1's thinking to V3 gave 3.3%, and "step-by-step" gave 1.5%. R1 "overhelps," adding information not in the text even when true.
- Measured elsewhere: reasoning can overturn a correct direct answer ([MARGO paper](https://arxiv.org/abs/2607.05861)), and reasoning under strict constraints produced fewer rule violations but more distorted facts ([Distortion Instead of Hallucination](https://arxiv.org/abs/2601.01490)). Hallucination in reasoning models depends on the training recipe ([Yao et al.](https://arxiv.org/abs/2505.23646)).
- Applies to us: **yes**. Your 1/2/5 trend (off/low/medium) fits the "overhelp" account. Vectara's results say the damage sits in the final writing step, so a cheap test is thinking on for planning only and a separate thinking-off write step. Nobody has tested effort levels on claim-grounded drafting.

## Prompting

- Measured: telling models to avoid inaccuracies made things worse. Accuracy prompt versus plain prompt: odds ratio about 1.9 (coefficient .640, p = .020). Share of summaries with a generalized conclusion, simple to accuracy prompt: DeepSeek 46% to 87%, GPT-4 Turbo 50% to 56%, Llama 3.3 70B 89% to 93% ([Peters and Chin-Yee](https://arxiv.org/abs/2504.00025)). Claude 3.5 Sonnet was the exception (31% to 24%). I found no tested mechanism.
- The authors propose forcing past tense in prompts but did not test it.
- Vectara's leaderboard prompt says "Summarize using only the information in the given passage. Do not infer" ([README](https://github.com/vectara/hallucination-leaderboard)). Anthropic's guidance: allow "I don't know," extract word-for-word quotes first, then retract any claim with no supporting quote ([docs](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations)). Neither page gives numbers.
- Applies to us: **yes**. Your "prefer restating plainly" result agrees with Peters's backfire finding. Concrete rules that name the three error classes are untested but cheap to try. Generic exhortations are the thing shown to fail.

## Constrained or extract-then-abstract generation

- Measured: faithfulness and extractiveness trade off, and many "faithfulness" methods only move along that curve ([Ladhak et al., ACL 2022](https://aclanthology.org/2022.acl-long.100/)). So "restate plainly" is a legitimate lever, not a trick.
- Pick sources, then plan, then write each sentence from its chosen sources: more concise citations, quality and attribution kept or improved ([Slobodkin et al., ACL 2024](https://aclanthology.org/2024.acl-long.182/)). Question-answer blueprints made summaries more factual ([Narayan et al., TACL 2023](https://aclanthology.org/2023.tacl-1.55/)). I read only abstracts, no numbers.
- Applies to us: **partly**. Your claim list already does the extraction. The remaining step to copy is sentence-to-claim-ID tagging, which would let a script check each sentence against only its own claims. No measured gain for a 27B drafter.

## Verify and repair with a larger model

- Measured: prompted self-correction does not reliably help; no prior work shows success with feedback from prompted LLMs outside tasks suited to it, while reliable external feedback or fine-tuning does ([Kamoi et al., TACL 2024](https://arxiv.org/abs/2406.01297)). Performance sometimes drops after self-correction ([Huang et al., ICLR 2024](https://arxiv.org/abs/2310.01798)).
- Detect, then critique, then refine beat end-to-end refinement on document-grounded summaries, using a MiniCheck detector ([Wadhwa et al.](https://arxiv.org/abs/2407.02397)). In their table 4, prompted Llama-2-7B as critic and refiner scored below zero on both metrics (-0.03, -0.27) while prompted Llama-3-8B scored above zero (+0.07, +0.27).
- Applies to us: **yes**. A Sonnet reviewer is external feedback. Give it the three-class checklist and per-sentence claim lists. Add a cheap detector only to rank sentences for the reviewer, never to skip it. Your own validation run agrees: local judges labeled poison correctly but their fixes removed it far less often (dev/experiments/model-tier/README.md).

## Is there a ceiling?

Not as a published number for this task. What exists:

- Short news summaries, Vectara HHEM-2.3: best model 1.8% hallucination, Qwen3-8B 4.8%, Qwen3-32B 5.9%, Qwen3.5-27B 12.1%. The newest Qwen is worse, and size does not order the results ([leaderboard](https://github.com/vectara/hallucination-leaderboard)). Qwen3.8 is not listed. HHEM is itself a model judge.
- Newer is not safer: Peters found newer models overgeneralize more than older ones.
- TofuEval: LLMs hallucinate "regardless of the model's size" ([paper](https://arxiv.org/abs/2402.13249)). Open Llama 2, Mistral and Zephyr put at least one semantic error in more than 80% of data-to-text outputs, the closest task to yours, though old models ([Kasner and Dusek](https://arxiv.org/abs/2401.10186)).
- Detection is also capped: the best detectors score near 50% on FaithBench ([paper](https://arxiv.org/abs/2410.13210)); LLM-AggreFact top balanced accuracy is about 77% ([board](https://llm-aggrefact.github.io/)). That fits your local-judge finding.
- Longer output is worse: hallucinations concentrate in the last part of long summaries ([paper](https://arxiv.org/abs/2505.15291)). Draft per section.
- Quantization: I found no study on summarization faithfulness at W4A16, so treat it as unmeasured.

Your 1 to 2 over-claims per 7 articles is too few to separate settings; use repeated samples.

## Try next, ranked

1. Keep thinking off and the plain-restatement prompt. Add three concrete rules from Peters: keep each claim's subject and quantifier, keep its modal verb and tense, add no recommendation.
2. Sweep temperature (0, 0.3, 0.7) and presence penalty (0 versus 1.5) on the same 7 blocks, 3 or more samples each.
3. Require each sentence to list its claim IDs, then check mechanically.
4. Keep Sonnet as the full reviewer with the three-class checklist. Do not replace it with a local judge.
5. Skip context-aware decoding, lookahead, and effort tuning unless 1 to 4 fail.
