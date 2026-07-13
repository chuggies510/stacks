# Extraction "non-determinism" — refuted; the real state is deterministic-at-floor (liminal S62, stacks #109)

The epic's extraction row read "Local qwen3-30b-a3b clears all floors behind a pal-chat harness;
**cliff-recall NONDET (0.90↔1.0)**." Chris asked liminal to attack that non-determinism directly.
**It does not reproduce.**

Harness: local ollama on the 3900x, native `/api/chat`, `qwen3-30b-a3b-instruct:latest` (digest
19e422b02313), greedy (temp 0), the verbatim `extract_bench2_ctx8k.py` described-slug prompt, item-3
cliff (10-concept zenml source). Server config: `OLLAMA_NUM_PARALLEL=1`, `OLLAMA_FLASH_ATTENTION=1`.

## Determinism: byte-identical, 6/6

```
pass0..5: 12 slugs, sha=d1163a89 (all six identical)
byte-identical: True   flip slugs: []
```

No flicker. The "0.90↔1.0" was almost certainly a **concurrent-load or config artifact** (a live
sweep hitting ollama alongside the extraction, or the pre-`OLLAMA_FLASH_ATTENTION` server before it
was flipped false→true on 2026-07-08). At `num_parallel=1` + greedy, request batching can't interleave,
so there's no FP-reduction-order variance to flip a near-tie argmax. My prime hypothesis (flash-attn
atomics) is **dead** — flash-attn is enabled and it's still byte-DET. Determinism is not an extraction
blocker.

Note (methodology, per chris S62): byte-determinism is REPORTED here, not a success criterion — a
model can be byte-deterministically wrong. It's noted because it refutes the NONDET claim, not because
identity is a floor.

## The real state byte-identity was hiding: recall 0.90 exactly, 0 over-mint, one stable miss

Scored vs `score_one.py` GOLD[3] (10 reuse concepts, mint_allow=1):

```
recall=0.90 (9/10)   mints=0 (allow 1, excess 0)   rows=12
MISSED: retrieval-augmented-generation
```

Extraction clears the ≥0.90 floor deterministically, but **by exactly one concept, zero margin.**

## The miss is a conservatism boundary call, not scope-wording, not capacity

`retrieval-augmented-generation` is offered (scope: "RAG architecture — pipeline stages, modular vs.
agentic vs. graph-enhanced…") and the source has a **dedicated section** for it ("Search and Retrieval
Remains Central": *"sophisticated retrieval architectures remain essential. LinkedIn rebuilt their GenAI
stack with RAG-based pipelines…"*). The concept is squarely present and in-scope — so it is NOT a
scope-description mismatch (I checked; that was the cheap hypothesis and it's wrong).

What the model did: grabbed `multi-agent-orchestration` (named in the same sentence) and the
`context-engineering-production` / `context-window-management` concepts from the section that follows,
but dropped RAG. The section is 3 sentences and framed defensively ("Despite 'RAG is dead'
declarations"). The extraction prompt tells the model to be **CONSERVATIVE** (don't fragment, don't
invent) — and that same conservatism, which zeroed over-mint, costs it a thinly-covered but real
concept. Recall-vs-over-mint is a single dial here.

**This reframes the 4B wall.** The tuned-4B thread (`podly/extract_bench/STATE.md`) walls at recall
0.60, missing 4 concepts incl. RAG. The zero-shot 30B recovers 3 of those 4 (`agent-memory-systems`,
`agent-harness-engineering`, `production-eval-systems` all HIT) and shares only the thinnest one (RAG).
So the wall is not purely capacity — it's that conservative extraction trades recall on briefly-covered
concepts, and capacity buys back the less-thin ones first.

## Verdict for the tier decision

Extraction on zero-shot qwen3-30b is a **deterministic 0.90 / 0-over-mint tier** — it clears the floor,
reproducibly, today. It clears by one concept, so there's no headroom: if margin above floor is wanted,
the lever is a prompt nudge on the conservatism dial (recover thin-but-real concepts) traded against
over-mint — stacks' prompt lane, a real precision/recall experiment, not a determinism knob. The
determinism concern that blocked this row is closed.

Reproduce: `scratchpad/extract_det/repro.py` on the 3900x (transient).
