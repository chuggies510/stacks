# liminal S80 — qwen3.6-27b across synthesis, enrichment, and the extraction decision surface

Run on breathless (RTX 3090, 24GB), local ollama, `TEMP=0`, via this repo's own
`harness/local-infer.sh` so every substrate call matches the other stages' measurements.
Graded by this repo's own `article-verifier` (cloud sonnet) where a grade was needed.

Session 80. (Artifacts written into `live-diffs/` this session are tagged
`liminal-s81-*` — that tag is wrong, the session is 80. Ids left stable rather than
renamed under a peer that may already reference them.)

---

## 1. Synthesis — one draft clears the floors, and every failure is one operation

Post-#127 prompt (the section skeleton, `df289cd`). Five blocks, `MODEL=qwen3.6-27b`,
`NUM_CTX=16384`.

| block | source type | sections | over-claims | recall | citation fixes | clears floors |
|---|---|---|---|---|---|---|
| `llm-evaluation-frameworks` | arXiv survey | 4 | **0** | 6/6 | 0 | **TRUE** |
| `production-eval-systems` | zenml case studies | 5 | 1 | 6/7 | 0 | false |
| `agent-training-evaluation-economics` | zenml case studies | 4 | 4 | 5/5 | 0 | false |
| `production-agent-autonomy-controls` | zenml case studies | 5 | 4 | 5/5 | 0 | false |
| `judge-verbosity-monitoring` | 1 claim | — | — | — | — | correct refusal |

Drafts: `live-diffs/bodies/liminal-s81-q36-*__local.md`.
Grades: `live-diffs/verify/liminal-s81-q36/*.json`.

### Every over-claim widens the subject and preserves the predicate

| block says | draft writes |
|---|---|
| "Ramp exposes an autonomy slider" | "Platforms expose an autonomy slider" |
| Ramp, GitHub, Cox each did X | "Organizations implement structured evaluation pipelines" |
| OpenPipe's one $80 ART-E run | "Fine-tuning agents can operate within constrained compute budgets" |
| Dropbox hit analysis paralysis once | "Exposing too many tools can trigger analysis paralysis" |
| Ramp's raw report **is** reviewed | the raw report **must** be reviewed |

No invented predicate appears in any of the four drafts. Recall is 6/6, 5/5, 5/5, 6/7
and `citation_fixes` is 0 on all four: the facts arrive intact and correctly sourced.
The failure is that a subject cannot be kept narrow.

A softer form the verifier flagged without counting: two Ramp claims kept their content
but dropped "Ramp" into a passive ("User-reported failures are converted into regression
test cases"). No false statement; attribution simply gone. Same axis, one notch down.

### Bearing on #126 — a floor of 0 does not forbid synthesis

`llm-evaluation-frameworks` is the counterexample: four sections, 248 words of prose, a
coherent Overview, 8-gram overlap 0.105 against its own block (inside the cloud band of
0.028–0.101), and zero over-claims. A real article that meets the floor.

So two failure modes are separable, and this substrate exhibits only the second:

- **Addition** — inventing a mechanism, number, or rationale absent from the block: **0**
- **Widening** — keeping the predicate, enlarging the subject: **9**

The block that clears has an academic survey as its source, so its claims arrive already
general and there is no named actor to widen. That predicts a corpus split worth checking
on blocks liminal has not run: survey- and doc-sourced blocks should clear unmodified;
case-study-sourced blocks should fail until a prompt clause forbids widening.

### The section skeleton is NOT the cause

Over-claims 0, 1, 4, 4 against section counts 4, 5, 4, 5. No relationship. An earlier
liminal hypothesis that the skeleton manufactured topic-sentence over-claims was written
down after two grades and falsified by the third and fourth. `df289cd` should stand.

### Transcription, post-fix

8-gram overlap against own block, same instrument, calibrated first against this repo's
published points (reproduces 0.906 and 0.099 exactly; 0.313 against a published 0.337):

| condition | overlap |
|---|---|
| old prompt, local | 0.906, 1.000, 1.000, 1.000 |
| fixed prompt, qwen3.6-27b | 0.105, 0.234, 0.410, 0.415 |
| cloud | 0.028, 0.099 |

Transcription is dead. Cloud parity is one block of four, not the pattern.

### Restraint

Wrote all four gold-write blocks, refused the 1-claim block (below `CLAIM_FLOOR=2`, no
WRITE directive fired). **5/5.** The prior local candidate false-refused 3 of 4 gold-write;
that failure mode is absent on this substrate.

---

## 2. Enrichment — all four floors, 6/6, deterministic

`MODEL=qwen3.6-27b`, `NUM_CTX=8192`, unmodified benchmark prompt, 3 greedy passes.

| floor | value | bar | result |
|---|---|---|---|
| false-CANDIDATE rate | 0.00 | 0 | PASS |
| grounding recall | 1.00 | ≥ 0.90 | PASS |
| tier accuracy | 3/3 | 3/3 | PASS |
| DUP detection | true | binary | PASS |
| determinism | identical across 3 passes | report only | — |

Per item, verdict **and** tier exact on all six, including both cliff traps (items 2 and 3)
that `enrichment-benchmark.md:107` predicts a fluent weak tier will fail by pattern-matching
topic to grounding.

DUP passed on the **unmodified** prompt, where the prior candidate needed benchmark variant B.
This is not an argument for keeping DUP as a model call — a lookup against structured data the
harness already holds should be deterministic by construction (#135).

**n=6.** A floor clear on a six-item hand-built benchmark, not a capability result, and the
live search-recall half is unmeasured. Validation is the cautionary case: it cleared a 7-item
gold and then scored 0.379 recall / 0.217 precision at 1,717 claims.

Runner: `liminal/stacks/enrich_bench.py` (liminal `76709868`). The stage had six data points
because it was the only one of four with no runner.

---

## 3. Extraction — the decision surface, at both stages

Production's reuse-vs-mint surface has been `index.md`'s `## Articles` scope map since
2026-07-11 (`7922e37`, #109). liminal's harness fed `slug — Title`, which names an article
without saying what falls inside it. `retrieval_gate.py` ranks against the same field, so
the shortlist stage was starved on the same surface.

Retrieval ceiling, same gate/seed/population (n=179, fan-out ≥2, full-breadth index), only
the candidate text changed:

| K | title recall | scope recall | title precision | scope precision |
|---|---|---|---|---|
| 25 | 0.6940 | 0.8542 | 0.0757 | 0.0932 |
| 50 | **0.8214** | **0.9281** | 0.0452 | 0.0511 |
| 100 | 0.9035 | 0.9651 | 0.0274 | 0.0293 |

0.8214 reproduces the published R@50 = 0.821 exactly. Precision rises with recall, which is
the control against the gain being spurious lexical padding.

Per-stack, the entire gain is one stack:

| stack | index | gold | title@50 | scope@50 | Δ |
|---|---|---|---|---|---|
| hvac | 613 | 300 | 0.713 | 0.887 | **+0.173** |
| sysops | 103 | 19 | 1.000 | 1.000 | 0.000 |
| swe | 87 | 18 | 1.000 | 1.000 | 0.000 |
| svelte | 72 | 38 | 1.000 | 1.000 | 0.000 |
| electrical | 63 | 19 | 1.000 | 1.000 | 0.000 |
| llm | 55 | 33 | 0.970 | 0.970 | 0.000 |
| plumbing | 49 | 29 | 1.000 | 1.000 | 0.000 |
| writing | 40 | 14 | 1.000 | 1.000 | 0.000 |
| go-charm-tui | 36 | 12 | 1.000 | 1.000 | 0.000 |
| hardware | 15 | 5 | 1.000 | 1.000 | 0.000 |

hvac does not converge; it stays the tail, higher up. Nine stacks were already at 1.000 on
titles at K=50 and gained nothing. **K is capped by index size**, so at K=150 nine of ten
stacks receive their whole index and retrieval is a no-op there — a global K is one number
meaning "how much of hvac do we show," not a per-stack compromise.

hvac alone, 126 sources / 300 gold / 613-slug index (char counts exact; token figures are
chars/4 estimates, and the full-index menu should be treated as 50–70k, not a precise figure):

| K | recall | menu chars | ~tok |
|---|---|---|---|
| 25 | 0.7800 | 18,215 | ~4.6k |
| 50 | 0.8867 | 29,671 | ~7.4k |
| **150** | **0.9733** | **67,451** | **~16.9k** |
| 300 | 0.9900 | 117,123 | ~29.3k |
| 613 | 1.0000 | 210,368 | ~52.6k |

K=150 is the knee: 0.973 for 32% of the full-index prompt, inside a 32k window on a 24GB card.
Tracked as #133.

Compounded arm (retrieval loss × model loss, gold deliberately **not** trimmed to what the
retriever kept) is queued in liminal as `shortlist-k150-am-qwen36-27b`; pin ceiling 0.9836.

---

## Stage status on this substrate

| stage | state |
|---|---|
| extraction | config identified (K=150, scope surface); compounded number pending |
| synthesis | 1/4 clears; 3/4 fail on subject-widening only; blocked on a prompt clause |
| enrichment | 4/4 floors, 6/6 items, deterministic, n=6 |
| validation | cloud by design; not reopened |
