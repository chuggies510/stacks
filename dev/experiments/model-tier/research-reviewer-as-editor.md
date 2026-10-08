# Reviewer as editor versus critic loop for grounded prose

Session S31 follow-up, 2026-10-08. Builds on [research-drafting-faithfulness.md](research-drafting-faithfulness.md) (the "sibling note"), which already covers self-correction failing without outside feedback (Kamoi, Huang) and Wadhwa's detect, critique, refine result. "Abstract only" marks papers whose full text I did not read.

## Answer

No published study compares (A) a stronger model editing in place against (B) a critique-and-revise loop on grounded prose, on accuracy and cost together. The indirect evidence favors (A), with guards. The hard part is finding errors, not fixing them, so letting the reviewer that found an error also fix it saves a round without losing accuracy. Most of a loop's gain comes in its first round. Writers that revise from critique ignore some of it and add new errors. The editor's risks are real and measured: it over-edits unless it is told to edit only where it found a defect, its own list of changes can be wrong, and it rates its own work too kindly. So use (A) as one pass: find the defects, edit only those, then run a mechanical diff and an independent check of the changed sentences. Do not loop.

## 1. Critique then revise versus direct editing

- Measured, finding versus fixing: on BIG-Bench Mistake (logic traces), the best model, GPT-4, located the first mistake only 52.87% of the time. Given the true location, PaLM 2 fixed its own traces. Share of wrong answers made right: +18 to +44 points across 5 tasks. Share of right answers made wrong: 0 to -11 points. A random location gave about half the gain ([Tyen et al., ACL Findings 2024](https://arxiv.org/abs/2311.08516), full text). The authors conclude that finding the mistake is the bottleneck, not fixing it.
- Measured, editing gated by detection: RARR is an editor that checks text against retrieved evidence, then edits only where the evidence disagrees. It kept the original meaning (intent) more than 90% of the time and changed only 10 to 20% of the text. Two baseline editors, EFEC and LaMDA, kept intent only 6 to 40% of the time. EFEC gained more attribution, meaning the share of text backed by evidence, by rewriting most of the passage ([Gao et al., ACL 2023](https://arxiv.org/abs/2210.08726), full text, table 1).
- Measured, a strong post-editor: GPT-4 post-editing machine translation (WMT-22) fixed more than half of the error spans that human annotators had marked, and quality scores rose ([Raunak et al., EMNLP Findings 2023](https://arxiv.org/abs/2305.14878), full text).
- Measured, editing creative prose: rated by experts, writer-edited text beat LLM-edited text, which beat unedited text. The best LLM span detector reached precision 0.46, against 0.57 agreement between experts ([Chakrabarty et al., CHI 2025](https://arxiv.org/abs/2409.14509), read in part).
- FRUIT ([Logan et al.](https://arxiv.org/abs/2112.08634), abstract only) defines updating an article from new evidence. It says faithful editing "requires new capabilities", but the abstract gives no editor-versus-loop comparison.
- Applies to us: **yes**. The value lies in the reviewer finding defects. When the strong model has already found a defect, sending it back to the 27B writer adds a round and a chance for a new error, and the published data show no accuracy gain from doing so.

## 2. Risks of an editor

- Over-editing, measured: with RARR's gate removed, so that the model edits on every piece of evidence, the share of text kept unchanged on NQ fell from 89.6 to 82.6, and the combined score fell from 68.1 to 62.8. The paper shows an unsupported edit made this way. ChatGPT over-corrects grammar and ignores the minimal-edit rule ([Fang et al.](https://arxiv.org/abs/2304.01746), abstract only).
- Drift, measured: in iterative translation refinement, a pure paraphrase loop with no source text declined on every metric. The authors say that anchoring each round to the source prevents meaning drift ([Chen et al.](https://arxiv.org/abs/2306.03856), full text).
- A wrong change list, measured: GPT-4 listed its proposed edits, then wrote the new text. Human raters found that the listed edits were not always made, and some proposals were hallucinated, more often from German or Chinese into English (Raunak, figure 1, counts given only as a chart).
- New errors from revising, measured: in Self-Refine's dialogue error analysis, the reviser ignored the feedback 25% of the time and introduced a new problem 20% of the time ([Madaan et al., NeurIPS 2023](https://arxiv.org/abs/2303.17651), full text, table 12).
- Self-preference, measured: GPT-4 recognized its own summaries 73.5% of the time and scored them higher than humans judged them to be ([Panickssery et al.](https://arxiv.org/abs/2404.13076), full text). GPT-4o and Claude 3.5 Sonnet rate their own outputs, and outputs from their own model family, higher ([Spiliopoulou et al.](https://arxiv.org/abs/2508.06709), abstract only). Self-refinement improves fluency but amplifies this bias ([Xu et al., ACL 2024](https://arxiv.org/abs/2402.11436), abstract only).
- Does editing in place hide errors? **No direct study.** The mechanism is plausible: the editor's own fixes get no second reader, and an editor judging its own fix is biased, as shown above. I found no study that counted errors left in edited text against errors left after a critique loop.
- Applies to us: **yes**. An S31 reviewer fix that adds an unsupported claim would pass unseen today. Guard the edited sentences, not the whole article.

## 3. Cost and rounds

- Measured, diminishing returns: Self-Refine (GPT-3.5/4, up to 4 rounds) gained per round as follows. Code optimization: +5.0, +0.9, +0.9. Constrained generation: +11.3, +6.4, +3.0. Sentiment reversal: +1.0, +1.2, +0.7. Quality does not always rise from round to round on tasks with several goals. Generic feedback scored lower than specific feedback, for example 31.2 against 43.2 on sentiment reversal.
- Over-correction from extra rounds is named as a problem by [MAgICoRe](https://arxiv.org/abs/2409.12147) (abstract only), whose one-round method beat Self-Refine by 4.0% using less than half the samples.
- Context grows each round: Self-Refine's revise prompt carries the input plus every earlier draft and every earlier critique (its equation 4), so input tokens grow with the round count. Anthropic reports that multi-agent systems use about 15 times the tokens of chat, and that token use explains 80% of the variance in its research eval ([Anthropic engineering](https://www.anthropic.com/engineering/multi-agent-research-system)).
- Re-reading cost, vendor doc: a cache read costs 0.1 times the base input price, or 0.05 times on Sonnet 5.5 and Opus 5.5, if the shared prefix is identical and reused within the cache lifetime, 5 minutes by default ([prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)).
- **No published evidence** on rounds to convergence for writer and critic loops on reports, or on a fresh reviewer's per-round cost.
- Applies to us: **yes**. The meap2-it figure (457M tokens over 9 rounds) fits both mechanisms: context that grows and gets re-read in full, and rounds well past the point of diminishing returns. Our own split is not measured. Log tokens per round before blaming either one.

## 4. Safeguards that measurably help

- Gate the edit on a detected defect: measured (the RARR ablation above). Add a final "keep the original or the revision?" decision step: measured, +5 points over Self-Refine on GSM8K and StrategyQA ([ART, Shridhar et al.](https://arxiv.org/abs/2311.07961), abstract only).
- Make the editor list its changes: measured as a mixed result. Listing edits before editing slightly lowered translation quality but kept the output closer to the original (Raunak section 5), and the list itself was not fully reliable. So the list helps to bound edits, but a mechanical diff, not the list, must be the record of what changed. No study tests a diff-based review directly.
- Anchor every pass to the source: measured (Chen).
- Cap rounds: supported by Self-Refine's curve and by the MAgICoRe abstract. No study sets an optimal cap for writing.
- Calibrate the judge against human labels: measured. Judges with high percent agreement can still differ by up to 5 points from human scores, so use Cohen's kappa (agreement corrected for chance), not percent agreement ([Thakur et al.](https://arxiv.org/abs/2406.12624), abstract only). Grading criteria shift as people read outputs ([Shankar et al.](https://arxiv.org/abs/2404.12272), abstract only, qualitative).
- Use a different model family to verify: measured indirectly. Judges favor their own family (Spiliopoulou). Mistakes grow more alike across models as capability rises ([Goel et al.](https://arxiv.org/abs/2502.04313), abstract only). A panel of judges from different families showed less bias and cost 7 times less than one large judge ([Verga et al.](https://arxiv.org/abs/2404.18796), abstract only).
- Applies to us: **yes**. The cheap, measured guards are the gate, the source anchor and the cap. The diff check costs nothing and closes the known gap that change lists are unreliable.

## 5. Batching items in one call

- Measured, harm at large batches: in BatchPrompt on BoolQ, GPT-4 scored 90.6% with one item per call, 89.1% at 16 items per call, 87.8% at 32, and 72.8% at 64, all in a single pass. Accuracy depended on an item's position in the batch, and shuffling the order and voting across runs recovered it ([Lin et al., ICLR 2024](https://arxiv.org/abs/2309.00384), full text).
- Measured, position: GPT-3.5's multi-document question answering fell by more than 20% when the relevant document sat in the middle of the context, in the worst case below its 56.1% score with no documents at all ([Liu et al., TACL 2024](https://arxiv.org/abs/2307.03172), full text). Judges reversed pairwise choices when the order was swapped: GPT-4 25%, GPT-3.5 58%, Llama 2 89% (Panickssery).
- Measured the other way: batches of about 6 cut tokens up to 5 times with comparable accuracy ([Cheng et al.](https://arxiv.org/abs/2301.08721), abstract only). For scoring, BatchEval reported Pearson correlation with human ratings 10.5% higher at 64% of the cost ([Yuan et al., ACL 2024](https://aclanthology.org/2024.acl-long.846), abstract only).
- Applies to us: **probably fine at 7 items, risky past about 16.** Nobody has measured batching for editing long articles, where each item is far longer than a BoolQ question.

## Try next, ranked

1. Keep (A) as one pass. Make the reviewer list each defect with its claim ID and a quote from the evidence first, then edit only those spans. Covers: over-editing (RARR). About 0 extra calls.
2. Add a script that diffs the draft against the edited text and flags any changed sentence that is not on the defect list or has no claim ID. Covers: hallucinated or unlisted edits (Raunak). About 1 hour to build, no tokens per run.
3. Send only the flagged or changed sentences, with their claims, to a check by a different model family. Covers: the editor approving its own fixes (self-preference). Small token cost.
4. Calibrate the reviewer's pass/fail against your labeled validation set using kappa before it gates anything. Covers: a gate that reads green on wrong verdicts. About one run.
5. For meap2-it: log tokens per round, cache the shared prefix, and cap the loop at 2 rounds, or switch it to steps 1 to 3. Covers: the 457M-token spend. Test on one building.

Note (S31 operator decision): spec #155 excludes sentence-to-claim tagging as a stand-in for content judgment. Apply items 1 and 2 without claim IDs: the reviewer quotes the evidence for each defect, and the diff flags any changed sentence not on the reviewer's fix list.
