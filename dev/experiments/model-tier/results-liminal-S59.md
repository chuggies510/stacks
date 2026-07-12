# Extraction-benchmark results — local models (from liminal S59, for win5 / stacks #95)

Harness: local ollama on the 3900x (RTX 3090), greedy (temperature 0), `num_ctx=16384`
(the cliff source is ~5k tokens; ollama's 4096 default would have truncated it and faked
an over-mint — set high on purpose). 3 passes per item for the determinism check.
Raw per-pass JSON: `/tmp/.../scratchpad/result_*.json` on the 3900x (transient); the raw
lines are reproduced at the foot of this file.

## Verdict: no local model clears the bar as-is.

Every model fails the cliff mint-discipline floor (≤1 excess new slug). The floors that
DO hold everywhere: tier accuracy (all ~1.0 — tiering is a solved problem here) and reuse
recall on the easy items. The wall is slug **granularity**, not tiering and not recall.

| Model | Item 1 (easy) | Item 2 (easy) | Item 3 (cliff) | Determinism | tok/s |
|---|---|---|---|---|---|
| **gemma4-31b** | recall 1.0, **0 mints ✓**, tier 1.0 | recall 1.0, **0 mints ✓**, tier 1.0 | recall 0.90–1.0 ✓, **mints 7–8 ✗ (allow 1)**, tier 1.0 | item1 DET; items 2,3 **NONDET** | ~35 |
| **qwen3-30b-a3b-instruct** | recall 1.0, **mints 4 ✗**, tier 1.0 | recall 0.0–1.0 ✗, **mints 1 ✗**, tier 0.0 | recall 0.80–1.0, **mints 0–19** (pass0 +18 ✗, pass1–2 OK ✓), tier 1.0 | item1 DET; items 2,3 **NONDET** | ~185 |
| **gpt-oss-20b** | recall 1.0, **mints 5–8 ✗**, tier 1.0 | recall 1.0, **mints 3 ✗**, tier 1.0 | **recall 0.20 ✗**, mints 6 ✗, tier 1.0 | item1 NONDET(3); items 2,3 DET | ~130 |

## Two opposite failure modes, and why my prediction was wrong

I predicted gemma's podly precision (0.999) would transfer to slug restraint. It did not.
Podly is binary flag-or-not with a confident argmax; extraction asks "is this concept
already covered by one of 42 existing articles, or is it genuinely new" — a
granularity/aggregation judgment, a different axis than precision.

- **Over-mint (fragmentation):** gemma minted 7–8 new slugs on the cliff, and **every one
  is a sub-topic of an article it correctly emitted as reuse in the same pass** —
  `just-in-time-context`, `tool-masking-schema-shrinking`, `context-compaction-vs-summarization`,
  `file-system-as-context` are all inside the existing `context-engineering-production`;
  `dual-embeddings-retrieval` ⊂ RAG; `shadow-mode-llm-testing` ⊂ `production-eval-systems`.
  This is exactly the haiku failure you named — gemma more than doubled it (7–8 vs haiku's 3).
  qwen's pass 0 did the same, harder (19 mints).
- **Under-recall (lumping):** gpt-oss went the other way — abstracted the whole cliff into
  4 reuse + 5 coarse new umbrellas (`llmops-production-deployments`,
  `rag-based-pipelines-in-production`), recall 0.20. Deterministic and wrong.

## Determinism broke — and that refines a prior liminal finding

Earlier this session I found local greedy inference byte-deterministic (podly, 3× identical).
That held for **short per-chunk binary output**. It does **not** hold for long
variable-length extraction lists: a long list has many near-tie inclusion decisions, and at
temp 0 the GPU's non-associative float reductions flip near-ties (the cold-load first pass
diverges most). qwen item 3 is the extreme: **pass 0 minted 19 slugs, passes 1–2 minted 0**
— same model, same temp 0, three consecutive calls. Determinism is task-shape-dependent,
not a blanket property of local greedy.

## The one tantalizing signal

qwen3-30b-a3b-instruct **passes 1–2 on the cliff are the single best output any model
produced**: recall 1.0, 0 excess mints, clean, in 2.2s at 177 tok/s. The capability is
there; the reliability isn't (pass 0 blew up). That points at a fix rather than a dead end.

## Recommendation

Don't ship any of these as a drop-in extraction tier — the mint decision is the
reasoning-heavy half and it's exactly where they break (consistent with the constrained-
decoding "reasoning tax" evidence: force the structural decision inline and weak models
fragment). Three things could rescue qwen (the capable-but-unreliable one), cheap to test:
1. **Deterministic slug pre-match in code** — fuzzy-match each candidate concept against the
   42 existing slugs before the model sees it; only genuinely unmatched concepts are eligible
   to mint. Removes the fragmentation pull structurally.
2. **Few-shot anchor** — 1–2 worked cliff examples in the prompt to pin the granularity.
3. **Reason-before-decide field order** — let it justify reuse-vs-mint in prose first.

I can run the few-shot variant on qwen next if you want a number on whether it stabilizes.

## Raw per-item output lines

### gemma4-31b:latest

**item 1 pass 0** (9.0s, 35.3 tok/s):
```
llm-as-judge | reuse:llm-as-judge | tier:2
```
**item 1 pass 1** (1.1s, 36.3 tok/s):
```
llm-as-judge | reuse:llm-as-judge | tier:2
```
**item 1 pass 2** (1.1s, 36.3 tok/s):
```
llm-as-judge | reuse:llm-as-judge | tier:2
```
**item 2 pass 0** (2.7s, 34.5 tok/s):
```
token-budget-management | reuse:token-budget-management | tier:3
llm-cost-control-production | reuse:llm-cost-control-production | tier:3
```
**item 2 pass 1** (1.6s, 35.5 tok/s):
```
token-budget-management | reuse:token-budget-management | tier:3
```
**item 2 pass 2** (1.6s, 35.5 tok/s):
```
token-budget-management | reuse:token-budget-management | tier:3
```
**item 3 pass 0** (14.9s, 34.0 tok/s):
```
context-engineering | reuse:context-engineering | tier:3
multi-agent-orchestration | reuse:multi-agent-orchestration | tier:3
mcp-production-patterns | reuse:mcp-production-patterns | tier:3
llm-as-judge | reuse:llm-as-judge | tier:3
durable-execution-agent-orchestration | reuse:durable-execution-agent-orchestration | tier:3
agent-harness-engineering | reuse:agent-harness-engineering | tier:3
agent-memory-systems | reuse:agent-memory-systems | tier:3
production-eval-systems | reuse:production-eval-systems | tier:3
guardrails-infrastructure | reuse:guardrails-infrastructure | tier:3
llm-cost-control-production | reuse:llm-cost-control-production | tier:3
retrieval-augmented-generation | reuse:retrieval-augmented-generation | tier:3
context-window-management | reuse:context-window-management | tier:3
prompt-engineering | reuse:prompt-engineering | tier:3
tool-integrated-reasoning | reuse:tool-integrated-reasoning | tier:3
just-in-time-context | NEW | tier:3
tool-masking-schema-shrinking | NEW | tier:3
context-compaction-vs-summarization | NEW | tier:3
dual-embeddings-retrieval | NEW | tier:3
shadow-mode-llm-testing | NEW | tier:3
circuit-breaker-llm-ops | NEW | tier:3
session-tainting-security | NEW | tier:3
```
**item 3 pass 1** (12.5s, 34.0 tok/s):
```
context-engineering | reuse:context-engineering | tier:3
multi-agent-orchestration | reuse:multi-agent-orchestration | tier:3
mcp-production-patterns | reuse:mcp-production-patterns | tier:3
llm-as-judge | reuse:llm-as-judge | tier:3
durable-execution-agent-orchestration | reuse:durable-execution-agent-orchestration | tier:3
agent-harness-engineering | reuse:agent-harness-engineering | tier:3
agent-memory-systems | reuse:agent-memory-systems | tier:3
production-eval-systems | reuse:production-eval-systems | tier:3
guardrails-infrastructure | reuse:guardrails-infrastructure | tier:3
llm-cost-control-production | reuse:llm-cost-control-production | tier:3
context-window-management | reuse:context-window-management | tier:3
retrieval-augmented-generation | reuse:retrieval-augmented-generation | tier:3
tool-integrated-reasoning | reuse:tool-integrated-reasoning | tier:3
prompt-engineering | reuse:prompt-engineering | tier:3
context-engineering-production | reuse:context-engineering-production | tier:3
just-in-time-context | NEW | tier:3
tool-masking-schema-shrinking | NEW | tier:3
context-compaction-vs-summarization | NEW | tier:3
file-system-as-context | NEW | tier:3
dual-embeddings-retrieval | NEW | tier:3
shadow-mode-llm-testing | NEW | tier:3
circuit-breaker-llm-ops | NEW | tier:3
session-tainting-security | NEW | tier:3
```
**item 3 pass 2** (15.0s, 33.8 tok/s):
```
context-engineering | reuse:context-engineering | tier:3
multi-agent-orchestration | reuse:multi-agent-orchestration | tier:3
mcp-production-patterns | reuse:mcp-production-patterns | tier:3
llm-as-judge | reuse:llm-as-judge | tier:3
durable-execution-agent-orchestration | reuse:durable-execution-agent-orchestration | tier:3
agent-harness-engineering | reuse:agent-harness-engineering | tier:3
agent-memory-systems | reuse:agent-memory-systems | tier:3
production-eval-systems | reuse:production-eval-systems | tier:3
guardrails-infrastructure | reuse:guardrails-infrastructure | tier:3
llm-cost-control-production | reuse:llm-cost-control-production | tier:3
retrieval-augmented-generation | reuse:retrieval-augmented-generation | tier:3
context-window-management | reuse:context-window-management | tier:3
prompt-engineering | reuse:prompt-engineering | tier:3
tool-integrated-reasoning | reuse:tool-integrated-reasoning | tier:3
just-in-time-context | NEW | tier:3
tool-masking-schema-shrinking | NEW | tier:3
context-compaction-vs-summarization | NEW | tier:3
dual-embeddings-retrieval | NEW | tier:3
shadow-mode-llm-testing | NEW | tier:3
circuit-breaker-llm-ops | NEW | tier:3
session-tainting-security | NEW | tier:3
```

### gpt-oss-20b:latest

**item 1 pass 0** (19.3s, 135.3 tok/s):
```
llm-as-judge | reuse:llm-as-judge | tier:2  
mt-bench | NEW | tier:2  
chatbot-arena | NEW | tier:2  
position-bias | NEW | tier:2  
verbosity-bias | NEW | tier:2  
self-enhancement-bias | NEW | tier:2  
limited-reasoning-ability | NEW | tier:2  
mitigation-of-llm-judge-biases | NEW | tier:2
```
**item 1 pass 1** (8.1s, 137.1 tok/s):
```
llm-as-judge | reuse:llm-as-judge | tier:2
mt-bench | reuse:NEW | tier:2
chatbot-arena | reuse:NEW | tier:2
position-bias | reuse:NEW | tier:2
verbosity-bias | reuse:NEW | tier:2
self-enhancement-bias | reuse:NEW | tier:2
```
**item 1 pass 2** (11.2s, 136.1 tok/s):
```
llm-as-judge | reuse:llm-as-judge | tier:2  
mt-bench | reuse:NEW | tier:2  
chatbot-arena | reuse:NEW | tier:2  
position-bias | reuse:NEW | tier:2  
verbosity-bias | reuse:NEW | tier:2  
self-enhancement-bias | reuse:NEW | tier:2  
limited-reasoning-ability | reuse:NEW | tier:2  
llm-judge-bias-mitigation | reuse:NEW | tier:2  
llm-judge-agreement-with-human-preferences | reuse:NEW | tier:2
```
**item 2 pass 0** (18.8s, 134.2 tok/s):
```
token-budget-management | reuse:token-budget-management | tier:3
llm-cost-control-production | reuse:llm-cost-control-production | tier:3
api-gateway-token-budget-enforcement | reuse:NEW | tier:3
llm-cost-monitoring-metrics | reuse:NEW | tier:3
context-length-creep | reuse:NEW | tier:3
```
**item 2 pass 1** (18.9s, 133.7 tok/s):
```
token-budget-management | reuse:token-budget-management | tier:3
llm-cost-control-production | reuse:llm-cost-control-production | tier:3
api-gateway-token-budget-enforcement | reuse:NEW | tier:3
llm-cost-monitoring-metrics | reuse:NEW | tier:3
context-length-creep | reuse:NEW | tier:3
```
**item 2 pass 2** (18.9s, 132.7 tok/s):
```
token-budget-management | reuse:token-budget-management | tier:3
llm-cost-control-production | reuse:llm-cost-control-production | tier:3
api-gateway-token-budget-enforcement | reuse:NEW | tier:3
llm-cost-monitoring-metrics | reuse:NEW | tier:3
context-length-creep | reuse:NEW | tier:3
```
**item 3 pass 0** (26.0s, 129.9 tok/s):
```
llmops-production-deployments | reuse:NEW | tier:3
autonomous-agents-in-production | reuse:NEW | tier:3
context-engineering | reuse:context-engineering | tier:3
agent-memory-systems | reuse:agent-memory-systems | tier:3
mcp-production-patterns | reuse:mcp-production-patterns | tier:3
llmops-evaluation-guardrails | reuse:NEW | tier:3
rag-based-pipelines-in-production | reuse:NEW | tier:3
llmops-software-engineering-practices | reuse:NEW | tier:3
frontier-model-containment-and-harness-engineering | reuse:NEW | tier:3
```
**item 3 pass 1** (26.1s, 129.5 tok/s):
```
llmops-production-deployments | reuse:NEW | tier:3
autonomous-agents-in-production | reuse:NEW | tier:3
context-engineering | reuse:context-engineering | tier:3
agent-memory-systems | reuse:agent-memory-systems | tier:3
mcp-production-patterns | reuse:mcp-production-patterns | tier:3
llmops-evaluation-guardrails | reuse:NEW | tier:3
rag-based-pipelines-in-production | reuse:NEW | tier:3
llmops-software-engineering-practices | reuse:NEW | tier:3
frontier-model-containment-and-harness-engineering | reuse:NEW | tier:3
```
**item 3 pass 2** (26.2s, 129.0 tok/s):
```
llmops-production-deployments | reuse:NEW | tier:3
autonomous-agents-in-production | reuse:NEW | tier:3
context-engineering | reuse:context-engineering | tier:3
agent-memory-systems | reuse:agent-memory-systems | tier:3
mcp-production-patterns | reuse:mcp-production-patterns | tier:3
llmops-evaluation-guardrails | reuse:NEW | tier:3
rag-based-pipelines-in-production | reuse:NEW | tier:3
llmops-software-engineering-practices | reuse:NEW | tier:3
frontier-model-containment-and-harness-engineering | reuse:NEW | tier:3
```

### qwen3-30b-a3b-instruct:latest

**item 1 pass 0** (24.3s, 186.3 tok/s):
```
llm-as-judge | reuse:llm-as-judge | tier:2
mt-bench | reuse:NEW | tier:2
chatbot-arena | reuse:NEW | tier:2
llm-as-judge-biases | reuse:NEW | tier:2
llm-as-judge-scalability | reuse:NEW | tier:2
```
**item 1 pass 1** (0.9s, 199.1 tok/s):
```
llm-as-judge | reuse:llm-as-judge | tier:2
mt-bench | reuse:NEW | tier:2
chatbot-arena | reuse:NEW | tier:2
llm-as-judge-biases | reuse:NEW | tier:2
llm-as-judge-scalability | reuse:NEW | tier:2
```
**item 1 pass 2** (0.6s, 199.0 tok/s):
```
llm-as-judge | reuse:llm-as-judge | tier:2
mt-bench | reuse:NEW | tier:2
chatbot-arena | reuse:NEW | tier:2
llm-as-judge-biases | reuse:NEW | tier:2
llm-as-judge-scalability | reuse:NEW | tier:2
```
**item 2 pass 0** (0.5s, 191.8 tok/s):
```
context-budget-enforcement-infrastructure | reuse:NEW | tier:3
token-budget-management | reuse:token-budget-management | tier:1
```
**item 2 pass 1** (0.3s, 212.9 tok/s):
```
context-budget-enforcement-infrastructure | reuse:NEW | tier:3
```
**item 2 pass 2** (0.3s, 211.0 tok/s):
```
context-budget-enforcement-infrastructure | reuse:NEW | tier:3
```
**item 3 pass 0** (3.9s, 177.5 tok/s):
```
context-engineering | reuse:context-engineering | tier:3  
context-engineering-production | reuse:context-engineering-production | tier:3  
llm-cost-control-production | reuse:llm-cost-control-production | tier:3  
llm-evaluation-frameworks | reuse:llm-evaluation-frameworks | tier:3  
guardrails-infrastructure | reuse:guardrails-infrastructure | tier:3  
durable-execution-agent-orchestration | reuse:durable-execution-agent-orchestration | tier:3  
multi-agent-orchestration | reuse:multi-agent-orchestration | tier:3  
llm-as-judge | reuse:llm-as-judge | tier:3  
llm-judge-gate-wiring | reuse:llm-judge-gate-wiring | tier:3  
shadow-mode-testing | NEW | tier:3  
circuit-breakers-production | NEW | tier:3  
user-controllable-guardrails | NEW | tier:3  
red-teaming-continuous-practice | NEW | tier:3  
model-context-protocol | NEW | tier:3  
agent-harness-engineering | reuse:agent-harness-engineering | tier:3  
agent-memory-systems | reuse:agent-memory-systems | tier:3  
reinforcement-learning-agent-training | NEW | tier:3  
software-engineering-bottleneck | NEW | tier:3  
distributed-systems-llm-ops | NEW | tier:3  
networking-infrastructure-llm-ops | NEW | tier:3  
security-compliance-llm-ops | NEW | tier:3  
prompt-caching-architecture | NEW | tier:3  
context-pollution-management | NEW | tier:3  
choice-entropy-management | NEW | tier:3  
tool-masking-techniques | NEW | tier:3  
compaction-vs-summarisation | NEW | tier:3  
dual-embeddings-retrieval | NEW | tier:3  
file-system-as-context | NEW | tier:3  
just-in-time-context-assembly | NEW | tier:3  
autonomous-agent-workflows | NEW | tier:3  
retrieval-augmented-generation | reuse:retrieval-augmented-generation | tier:3
```
**item 3 pass 1** (2.2s, 177.3 tok/s):
```
context-engineering | reuse:context-engineering | tier:3  
context-engineering-production | reuse:context-engineering-production | tier:3  
llm-cost-control-production | reuse:llm-cost-control-production | tier:3  
llm-evaluation-frameworks | reuse:llm-evaluation-frameworks | tier:3  
guardrails-infrastructure | reuse:guardrails-infrastructure | tier:3  
durable-execution-agent-orchestration | reuse:durable-execution-agent-orchestration | tier:3  
multi-agent-orchestration | reuse:multi-agent-orchestration | tier:3  
llm-as-judge | reuse:llm-as-judge | tier:3  
production-eval-systems | reuse:production-eval-systems | tier:3  
llm-judge-gate-wiring | reuse:llm-judge-gate-wiring | tier:3  
llm-output-validation-pipeline | reuse:llm-output-validation-pipeline | tier:3  
retrieval-augmented-generation | reuse:retrieval-augmented-generation | tier:3  
rag-chunking-strategy-selection | reuse:rag-chunking-strategy-selection | tier:3  
agent-harness-engineering | reuse:agent-harness-engineering | tier:3  
agent-memory-systems | reuse:agent-memory-systems | tier:3  
mcp-production-patterns | reuse:mcp-production-patterns | tier:3  
token-budget-management | reuse:token-budget-management | tier:3  
context-window-management | reuse:context-window-management | tier:3  
prompt-engineering | reuse:prompt-engineering | tier:3
```
**item 3 pass 2** (2.2s, 177.8 tok/s):
```
context-engineering | reuse:context-engineering | tier:3  
context-engineering-production | reuse:context-engineering-production | tier:3  
llm-cost-control-production | reuse:llm-cost-control-production | tier:3  
llm-evaluation-frameworks | reuse:llm-evaluation-frameworks | tier:3  
guardrails-infrastructure | reuse:guardrails-infrastructure | tier:3  
durable-execution-agent-orchestration | reuse:durable-execution-agent-orchestration | tier:3  
multi-agent-orchestration | reuse:multi-agent-orchestration | tier:3  
llm-as-judge | reuse:llm-as-judge | tier:3  
production-eval-systems | reuse:production-eval-systems | tier:3  
llm-judge-gate-wiring | reuse:llm-judge-gate-wiring | tier:3  
llm-output-validation-pipeline | reuse:llm-output-validation-pipeline | tier:3  
retrieval-augmented-generation | reuse:retrieval-augmented-generation | tier:3  
rag-chunking-strategy-selection | reuse:rag-chunking-strategy-selection | tier:3  
agent-harness-engineering | reuse:agent-harness-engineering | tier:3  
agent-memory-systems | reuse:agent-memory-systems | tier:3  
mcp-production-patterns | reuse:mcp-production-patterns | tier:3  
token-budget-management | reuse:token-budget-management | tier:3  
context-window-management | reuse:context-window-management | tier:3  
prompt-engineering | reuse:prompt-engineering | tier:3
```


---

# ROUND 2 — pressing on the negative (liminal S59, same session)

The round-1 fail was a harness bug, not a model limit. Two fixes tested.

## The bug: the prompt fed a BARE list of 42 slug strings, no scope.

The models fragmented because they could not SEE that `just-in-time-context` already
lives inside `context-engineering-production` — they only had the slug string, never the
article's scope. Proof: the index.md routing line for `context-engineering-production` reads
"just-in-time loading, tool masking, compaction strategies, filesystem-as-context" — which is
*verbatim* the four slugs gemma minted as NEW. Information starvation, not weak restraint.

**Fix:** replace the bare slug list with `slug — one-line scope` (pulled from index.md
routing lines) and tell the model to reuse if a concept falls within an existing article's
described scope. One prompt change, no model change, no thinking enabled.

## Result: over-minting eliminated across the board.

| Model + described slugs | Cliff recall | Cliff mints (allow 1) | Determinism | tok/s | Verdict |
|---|---|---|---|---|---|
| **qwen3-30b-a3b-instruct** | 0.90–1.0 | **0** | nondet (every pass still ≥0.90) | ~170 | **CLEARS ALL FLOORS, ALL PASSES** |
| gemma4-31b | 0.80 | 0 | **byte-DET ×3** | ~34 | 0 over-mint, recall 1 notch short |
| qwen3.6-27b | 0.80 | 0 | **byte-DET ×3** | ~34 | 0 over-mint, recall 1 notch short |
| qwen3-14b-claude-distill | 0.80 | 3–78 | nondet | ~50 | still over-mints; Opus-distill made it *chattier*, not more disciplined |

Baseline → described-slugs delta: gemma 7–8 mints → **0**; qwen-instruct 0–19 → **0**;
qwen3.6 (untested baseline) → 0. The fix is the information, not the model.

## What's left is a determinism-vs-recall trade, not an over-mint problem.

- **qwen3-30b-a3b-instruct** is the passing pick: recall ≥0.90 with 0 mints on every one of 9
  passes, fastest (170 tps, cliff in 1.6–3.1 s). Cost: cliff output varies 0.90↔1.0 pass to
  pass (both pass). If you want a reproducible stage, run it twice and intersect, or seed it.
- **gemma4-31b / qwen3.6-27b** give byte-identical output across 3 passes and never over-mint,
  but cap at 0.80 cliff recall — they drop `multi-agent-orchestration` + `retrieval` (qwen3.6)
  or `production-eval-systems` + `retrieval` (gemma) as non-substantive. A recall-nudge prompt
  line did NOT lift qwen3.6 (held at exactly 8 concepts, deterministically). Closing that last
  notch needs a few-shot anchor, not an instruction.

## Answers to the three questions

1. **Right tests?** Yes — the benchmark caught a real harness bug. Two suggestions: the cliff
   is n=1, so add 1–2 more rich sources before trusting the granularity metric; and consider
   whether a mechanical post-filter (a minted NEW slug whose concept overlaps an article the
   model reused in the same pass → auto-collapse) makes the bar less strict than the pipeline
   truly needs — that structural error may be catchable after all.
2. **Smartest models?** Capability was never the bottleneck. Newer (qwen3.6) and Opus-distilled
   (qwen3-14b-distill) did NOT beat the mid qwen3-30b-a3b-instruct; the distill was the worst.
3. **Right prompts/outputs?** This was the whole bug. Bare slugs → described slugs flips
   over-minting off universally. The one-line output format is fine as-is once the INPUT carries
   article scope. Feeding the reuse-target's scope is the load-bearing change.

**Bottom line:** a local model DOES clear your extraction bar — qwen3-30b-a3b-instruct with
scope-described slugs — at ~$0 marginal and 170 tok/s. Give it the article scopes and it stops
fragmenting.

## Addendum: gemma4-26b-a4b-it-qat (4B-active MoE, quant-aware trained)

Faster than dense gemma (~115 tps vs 34) but **fails the cliff**: recall 0.70–0.80 and it
creeps back to over-minting (+2) on 2 of 3 passes, nondet. Perfect on the easy items. The 4B
active budget isn't enough to hold the 42-article scope map AND recall thoroughly on a rich
source. Note: the winner (qwen3-30b-a3b-instruct) is ALSO a low-active MoE (3B active) — so
it's not active-param count that decides it, it's the specific model (qwen's 30B total + training).

## Addendum: Qwen3.5-122B-A10B MoE straddle, run locally on one 3090 (24GB) + 64GB RAM

The "other idea" from the S59 relay, measured. A 122B-total / 10B-active MoE (48 layers,
256 experts, top-8 routing → 3.1% active) doesn't fit in 24GB VRAM, so it straddles: attention
+ KV cache on the GPU, expert FFN weights in system RAM, via llama.cpp `--n-cpu-moe`. Native
CUDA build (sm_86, gcc-12 host compiler), `unsloth/Qwen3.5-122B-A10B-GGUF` **Q3_K_M** (56GB,
imatrix-calibrated), thinking **off** (`enable_thinking=false` — apples-to-apples with the
qwen3-30b winner, also measured thinking-off), `-ngl 99 --n-cpu-moe 36 -fa -c 32768`.

Same described-slug harness (the shipped 0.57.0 fix), same 3 sources, cliff = the zenml
1200-deployments source.

| Metric | Result |
|--------|--------|
| Mint discipline (cliff) | **0 over-mints** — all 18 in-scope concepts reuse existing slugs |
| Tier accuracy | consistent (all cliff concepts tier 3) |
| Determinism, 3 serial passes | **byte-identical** (1 unique of 3, every item) |
| Determinism, 4 concurrent (batched) | **byte-identical** (1 unique of 5, serial + 4 concurrent share one md5) |
| Throughput, cliff serial | 44–46s / source (~7.5 tok/s decode at N=36 offload) |
| Throughput, 4 concurrent | 171s wall vs 185s pure-serial — **~7% amortization, effectively none** |

**Two things the other candidates couldn't both do, this does at once.** Cloud haiku's failure
was over-minting on rich sources; qwen3-30b-a3b's was nondeterminism on the cliff (recall
flips 0.90↔1.0 pass to pass). The 122B straddle has **0 over-mints AND byte-determinism** — and
the determinism holds under 4-way continuous batching, which was expected to break it (GPU
float non-associativity + changed GEMM batch shape → moved near-ties). It didn't move.

**The catch is throughput, not correctness.** Concurrency buys ~7% (171s for 4 requests vs
185s serialized), because the straddle is RAM-bandwidth-bound on the expert reads and a sparse
MoE routes 4 concurrent requests to a near-disjoint union of experts — batching multiplies the
RAM working set instead of sharing it, so the GPU idles on the memory bus. **Practical
concurrency = 1.** The real shape of this path: one deterministic request at a time, ~46s/source,
$0 marginal, on hardware already owned. A determinism monster, not a throughput monster.

**Where it fits.** This only matters under a local pal-chat harness (the determinism is the
whole reason to reach for it); it does nothing for a no-harness cloud path. But if the extraction
stage commits to local, this clears every floor the 30B does *plus* byte-determinism the 30B
can't — at 46s/source instead of 170 tok/s.

**Quality-headroom check RESOLVED — UD-Q4_K_XL is dominated, Q3_K_M stays the pick.** Re-ran
the identical 3-source / 3-pass harness on `UD-Q4_K_XL` (Unsloth Dynamic 4-bit, selective
per-layer upcasting, 77GB combined, N=44). More bits + dynamic quant bought nothing on the two
axes already maxed and regressed on the third:

| | Q3_K_M (56GB, N=36) | UD-Q4_K_XL (77GB, N=44) |
|---|---|---|
| Determinism, 3 passes | byte-DET | byte-DET (no gain, already maxed) |
| Mint discipline, cliff | 0 over-mints | 0 over-mints (no gain, already clean) |
| Cliff concepts recalled | **18** | **15** (net −2 real articles) |
| Speed, cliff item | 7.5 tps / 44s | 3.9 tps / 73s (~1.7× slower) |

UD-Q4 dropped 4 real in-scope articles Q3 caught (`llm-as-judge`, `context-window-management`,
`self-correction-loops`, `token-budget-management`) and added only 2 (`llm-judge-gate-wiring`,
`production-eval-systems`) — no hallucinated slugs either side, a pure recall comparison. The
extra bits reduced recall while determinism/mint were already saturated at Q3.

**Controlled follow-up — `UD-Q3_K_XL` (Unsloth Dynamic at the SAME Q3 bit budget, 57GB, N=34)
isolates the dynamic-allocation variable UD-Q4 confounded.** Full 3-way across all three sources:

| item | Q3_K_M (56GB) | UD-Q4_K_XL (77GB) | UD-Q3_K_XL (57GB) |
|---|---|---|---|
| arxiv-judge | 3 concepts, 0 mints | 3 concepts, **3 over-mints** | 3 concepts, 0 mints |
| tianpan-token | 2 concepts, 0 mints | 1 concept, 0 mints | 1 concept, 1 mint |
| zenml **cliff** | **18**, 0 mints | 15, 0 mints | **18**, 0 mints |
| determinism | byte-DET | byte-DET | byte-DET |

On the discriminating cliff, **UD-Q3_K_XL == Q3_K_M exactly** (identical 18 slugs, same order),
recovering all 5 concepts UD-Q4 dropped; on item1 it reuses correctly like Q3 where UD-Q4
over-minted 3. **This pins the cause: the dynamic per-layer scheme is a wash at fixed bits (it
reproduces standard imatrix Q3 almost exactly, one stray item2 mint aside) — the UD-Q4
regression was the PRECISION LEVEL, not the dynamic allocation.** Mechanism (now supported, not
just inferred): this is a consolidation task (reward = lumping sub-concepts into existing
articles). Higher-precision Q4 discriminates finer, so it fragments — mints `mt-bench`/
`chatbot-arena` as NEW and splits the cliff set — where coarser Q3 correctly lumps them into
`llm-evaluation-frameworks`/`llm-as-judge`. **For this workload more bits is worse; the sweet
spot is the cheapest coherent quant, Q3_K_M.** UD-Q3_K_XL is an equal alternative (no upside),
UD-Q4 is dominated.

**Speed note (correcting the N-tuning expectation):** wall-clock is prefill-dominated on this
task (long source in, ~300 tokens out), so tuning `--n-cpu-moe` down — which speeds *decode* —
barely moves end-to-end time. UD-Q3_K_XL at N=34 ran ~43-46s/cliff-source, essentially identical
to Q3_K_M at N=36 (~44s). The ~22 tok/s "fast N" figure is pure-decode (llama-bench); this
extraction workload doesn't exercise decode enough to show it. Real cost stays ~44s/source
regardless of N. **Verdict: Q3_K_M is the straddle keeper**; the "more bits widens the margin"
hypothesis is falsified — on a consolidation task, lower precision carves more correctly.

Config for reproduction: `llama-server -m Qwen3.5-122B-A10B-Q3_K_M-00001-of-00003.gguf
-ngl 99 --n-cpu-moe 36 -fa 1 -c 32768 --parallel 4 --jinja
--chat-template-kwargs '{"enable_thinking":false}'`.

## CORRECTION (S59, same session) — the quant RECALL rankings above were raw-line-count, not gold-scored. Retracting the "more bits hurts / Q3 keeper" conclusion.

The three straddle addendums above ranked quants by **raw concept-line count** (18 vs 15),
never by the gold scorer (`score.py`, cliff gold = 10 concepts, mint_allow=1). Re-scored against
that gold, the ranking **inverts**:

| model | gold recall (/10) | raw lines | excess mints | determinism |
|---|---|---|---|---|
| 122B Q3_K_M | 0.90 | 18 | 0 | byte-DET |
| 122B UD-Q4_K_XL | **1.00** | 15 | 0 | byte-DET |
| 122B UD-Q3_K_XL | 0.90 | 18 | 0 | byte-DET |

UD-Q4 is **not** dominated — gold-scored it caught all 10 golds (Q3/UD-Q3 each missed
`production-eval-systems`). Q3's extra *lines* were non-gold concepts (`llm-as-judge`,
`self-correction-loops`, `token-budget-management`, `context-window-management`,
`rag-chunking-strategy-selection` — none in the gold set); they inflated the raw count while Q3
missed an actual gold. **The "more bits over-fragments / lower precision carves more correctly"
story is a raw-count artifact and is retracted.** What survives, gold-scored: all 122B quants
cluster **0.90-1.00 gold recall — within one concept on a hand-made gold, no defensible ranking
between them**; all are byte-DET; all 0 excess mints. Quant choice does not clearly move recall
for the 122B on this task.

**Robust, proxy-independent findings (unchanged):** determinism (all 122B DET, all 30B NONDET)
and mint discipline (0 excess everywhere). **Caveats:** the harness is a reproduction of the
extraction *decision*, not the production `catalog-sources` pipeline (which uses a Claude
subagent); the gold set is a liminal-side reconstruction (10 concepts), validated only by
reproducing win5's own relayed numbers (Q4_K_M 0.90-1.0, gemma4-31b ~0.80) — an authoritative
recall ranking needs win5's real scoring, not this. Treat the earlier raw-count recall deltas as
withdrawn.

## 30B quant sweep (gold-scored) — standard Q4_K_M is fine; no quant fixes determinism.

Swept `qwen3-30b-a3b-instruct` across quants on the cliff (5 passes, gold-scored):

| quant | gold recall (/10) | excess mints | determinism (5×) | tps |
|---|---|---|---|---|
| Q4_K_M (std, deployed) | 0.90-1.00 | 0 | NONDET(2/5) | 174 |
| UD-Q4_K_XL | 0.80 | 0 | NONDET(2/5) | 152 |
| UD-Q5_K_XL | 0.80-0.90 | 0 | NONDET(2/5) | 144 |
| UD-IQ2_M | 0.60-1.00 | 0 | NONDET(2/5) | 135 |

Two solid results here (recall differences are within the reconstructed gold's noise, but these
two are not): **(1) no quant fixes the 30B's cliff nondeterminism** — all flip 2-of-5, so it's
intrinsic to the model+task, not the precision; and **(2) the deployed standard Q4_K_M is at
least as good as every alternative** and the fastest, so there's no reason to swap it. Don't
chase byte-determinism on the 30B via quantization; it isn't there.

## VALIDATOR stage (issue #109) — 4 local tiers clear both floors; cheapest is the 30B we already run

Scored against your `validation-benchmark.md` 7-item offline gold set (each item = one claim +
its verbatim cited-source excerpt, your validator rubric fed verbatim, `think=False`, temp 0,
3 greedy passes). Floors: **poison recall {2,3,5} ≥ 0.90** (catch+properly-correct every planted
overstatement/contradiction), **false-correction {1,4,6,7} = 0** (never alter a supported/softspot
claim). Correction *texts* on caught poisons were manually reviewed (a CORRECTION token whose
replacement still overstates does not count).

| model | poison {2,3,5} | false-corr {1,4,6,7} | action /7 | determ (3×) | floors 1-2 |
|---|---|---|---|---|---|
| **qwen3.6-27b** | **1.00** (3/3 proper) | **0.00** | 6/7 | DET | **PASS** |
| **gemma4-31b** | **1.00** (3/3 proper) | **0.00** | 6/7 | DET | **PASS** |
| **qwen3-30b-a3b** Q4_K_M | **1.00** (3/3 proper) | **0.00** | 5/7 | DET | **PASS** |
| **gpt-oss-20b** | **1.00** (3/3 proper) | **0.00** | 5/7 | DET | **PASS** |

Per-item verdict matrix (gold on top; ✓=exact, swap=within-CORRECTION subtype swap that still
removed the poison, miss6=CLEAN on the add-citation item):

| item→ | 1 CLEAN | 2 OVER | 3 CONTRA | 4 CLEAN | 5 OVER | 6 ADD-CITE | 7 SOFTSPOT |
|---|---|---|---|---|---|---|---|
| qwen3.6-27b | ✓ | ✓ | ✓ | ✓ | ✓ | CLEAN(miss) | ✓ |
| gemma4-31b | ✓ | ✓ | ✓ | ✓ | ✓ | CLEAN(miss) | ✓ |
| qwen3-30b-a3b | ✓ | ✓ | OVER(swap) | ✓ | ✓ | CLEAN(miss) | ✓ |
| gpt-oss-20b | ✓ | CONTRA(swap) | ✓ | ✓ | ✓ | CLEAN(miss) | ✓ |

Findings:
- **All four clear both gated floors deterministically.** Poison recall 3/3 on every model with
  proper replacement text (item-2 loses "consistently outperforms", item-3 fixes 300→~3,000,
  item-5 loses "any/zero-risk"). Zero false-corrections. The two subtype swaps (30B called the
  contradiction an overstatement; gpt-oss the reverse) still produced the correct fix — per your
  metric-3 note, a minor error, not a floor breach.
- **The cheapest viable validator is the model we already run for extraction.** `qwen3-30b-a3b`
  (3B active, ~170 tps VRAM-resident) clears the validator floors AND came back **byte-DET here**
  — where it is NONDET on extraction. Determinism is per-task, not per-model: these validation
  items have wide enough logit margins that nothing flips. If that holds under more passes, one
  model serves both the interactive catalog loop (extraction) and the batch audit (validation).
- **Universal add-citation miss (item 6).** All four returned CLEAN on the uncited-but-listed Cox
  claim — "source supports it" reads as CLEAN, the "…but add the inline `[slug]`" nuance is
  underweighted. Benign under-action (leaves a *true* claim uncited; not poison, not a false trim),
  but it means no cheap tier nails the add-citation class solo. Worth knowing before you pin one.
- **qwen3.6-27b wrote the best corrections** — its item-5 trim kept the "only once shadow accuracy
  hits a threshold" gate that gemma trimmed away. If action-accuracy quality (not just floor-clear)
  is the tiebreak, 27b edges gemma.

Caveats: (1) **tps deliberately omitted** — validator outputs are single ~20-token lines (too short
to measure throughput) AND this run shared the 3090 with a live podly LoRA-training job (VRAM
contention → partial CPU offload). Real throughput is the extraction-measured numbers (gemma ~34,
27b ~37, 30b ~170 tps). (2) **Single-item proxy**: the harness feeds one claim + its source per
call; the real `validator` agent reads the whole article + all cited sources and checks every claim
— this isolates the discrimination decision, same proxy shape as the extraction harness, not the
full multi-claim trajectory. (3) Determinism is for the run's placement; a fully-VRAM-resident
deploy could differ on float-order-sensitive near-ties, though these items showed wide margins.
- **122B-A10B straddle (Q3_K_M): pending.** Harness is built (llama-server endpoint); the run is
  deferred because the 3090 is currently held by a podly LoRA training run (curator-first). Will
  score it when the card frees — it is the capability-ceiling probe and the best shot at nailing
  item 6.
