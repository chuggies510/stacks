# Shadow-proof results: local-model validator harness (issue #109)

Host: this machine (RTX 3090, Ollama at `http://localhost:11434`). Harness: `dev/experiments/model-tier/harness/local-infer.sh` + `validator-shadow.sh`. All numbers below are from actual command output captured during this session — none paraphrased.

## 1. `local-infer.sh --self-check`

```
$ bash dev/experiments/model-tier/harness/local-infer.sh --self-check
self-check: calling model 'qwen3.6-27b:latest'
PASS: model=qwen3.6-27b:latest output=HARNESS-OK
```

PASS on the first call, real model call against the resident model (`ollama ps` showed `qwen3.6-27b:latest` resident at the time, auto-discovered — no small model was hardcoded).

## 2. `validator-shadow.sh qwen3-30b-a3b-instruct` — two independent full runs

Model tag used: `qwen3-30b-a3b-instruct` (resolves to `qwen3-30b-a3b-instruct:latest`, 18GB on disk, loaded fully onto GPU per `ollama ps`: `20 GB / 100% GPU / 16384 ctx`). GPU was otherwise idle (0% util, no contending compute process) for both runs — the "3090 busy with curator training" risk flagged in the task did not materialize.

### Run 1 (pass 1, scored)

| Item | Gold | Model verdict | Match |
|---|---|---|---|
| 1 | CLEAN | CLEAN | YES |
| 2 | CORRECTION/overstatement | CORRECTION/overstatement | YES |
| 3 | CORRECTION/contradiction | CORRECTION/overstatement | NO (subtype swap — still caught as poison per benchmark's counting rule) |
| 4 | CLEAN | CLEAN | YES |
| 5 | CORRECTION/overstatement | CORRECTION/overstatement | YES |
| 6 | CORRECTION/add-citation | CORRECTION/add-citation | YES |
| 7 | SOFTSPOT | SOFTSPOT | YES |

- Poison recall (items 2,3,5, floor >=0.90): **1.00** (3/3 caught as CORRECTION)
- False-correction rate (items 1,4,6,7, floor ==0): **0.00** (0/4)
- Determinism across this run's 3 greedy passes: **NO** — item 3 alone flipped: pass1=`CORRECTION/overstatement`, pass2=`CLEAN`, pass3=`CLEAN`. All other 6 items were byte-identical across all 3 passes.

### Run 2 (pass 1, scored) — re-run of the identical harness minutes later, GPU otherwise idle

| Item | Gold | Model verdict | Match |
|---|---|---|---|
| 1 | CLEAN | CLEAN | YES |
| 2 | CORRECTION/overstatement | CORRECTION/overstatement | YES |
| 3 | CORRECTION/contradiction | CLEAN | NO — **miss** |
| 4 | CLEAN | CLEAN | YES |
| 5 | CORRECTION/overstatement | CORRECTION/overstatement | YES |
| 6 | CORRECTION/add-citation | CORRECTION/add-citation | YES |
| 7 | SOFTSPOT | SOFTSPOT | YES |

- Poison recall (floor >=0.90): **0.67** (2/3) — **floor breach**, item 3 missed on all 3 passes this run.
- False-correction rate (floor ==0): **0.00** (0/4)
- Determinism across this run's 3 greedy passes: **YES** — all 7 items byte-identical label across pass1/2/3 (including item 3, all three = `CLEAN` this time).

### Ad hoc reproduction of item 3 alone (5 additional independent calls, same prompt file, temp=0)

```
run 1: CORRECTION/overstatement | ...roughly 3K expert votes...
run 2: CORRECTION/overstatement | ...roughly 3,000 expert votes...
run 3: CORRECTION/overstatement | ...roughly 3,000 expert votes...
run 4: CORRECTION/overstatement | ...roughly 3,000 expert votes...
run 5: CORRECTION/overstatement | ...roughly 3,000 expert votes...
```

Plus one more standalone call while capturing Ollama's raw timing JSON (below): `CORRECTION/overstatement`.

**Combined tally across all 12 independent item-3 trials collected this session: 7 CORRECTION / 5 CLEAN** (run1: 1 correction + 2 clean; 5 repro calls: 5 correction; run2: 3 clean; timing-sample call: 1 correction). Roughly a coin flip.

## 3. Real finding: temperature=0 does not guarantee determinism on this model for item 3

Item 3 is the **contradiction** item (claim says "roughly 300 expert votes", source says "~3K expert votes" — the deliberately planted figure-swap). On every other item (1, 2, 4, 5, 6, 7) the model was byte-identical across every pass and every run collected in this session — fully deterministic. Item 3 alone flips between `CORRECTION/overstatement` (a subtype miss but still counted as "caught" for poison recall) and `CLEAN` (a genuine miss) from call to call, with no request-level state carried between calls (each `local-infer.sh` invocation is a fresh, independent HTTP POST). `options.temperature=0` was set on every call.

This means poison recall for this model on this benchmark is **not a fixed number** — it is ~1.00 on some runs and 0.67 (floor breach) on others, and a 3-pass "determinism" check on any single invocation of `validator-shadow.sh` can misleadingly read as "clean and deterministic" (Run 2) when a different invocation of the identical harness minutes earlier showed instability (Run 1). Likely mechanism (not confirmed): `qwen3-30b-a3b-instruct` is a mixture-of-experts model (30B total / ~3B active per token); token-level expert routing plus non-associative floating-point reduction order in the GPU attention/MoE kernels can flip a near-tied logit at a genuine decision boundary even at temp=0, when nothing else about the request changed. This is a real, reportable result, not a harness bug — the harness's own JSON body is byte-identical between calls (verified: `jq` builds it fresh each time from the same prompt file and the same options).

Practical read for issue #109: item 6 (add-citation) — the item flagged in `validation-benchmark.md` as the S24 miss to watch — was **caught correctly on every single trial across both full runs (6/6 passes)**. The gate-first prompt restructure fully closed that miss for this model, deterministically. The floor risk that showed up instead is item 3 (contradiction), which the benchmark file did not flag as a watch item going in — this is the "different finding than expected" the task asked to surface.

## 4. Sample raw model output (for audit — item 1, 2, 5, 6, single clean calls)

```
item 1: CLEAN
item 2: CORRECTION/overstatement | GPT-4 acting as judge matches human raters on open-ended evaluation, achieving over 80% agreement, the same level of agreement between humans.
item 5: CORRECTION/overstatement | Shadow mode lets a team deploy any new agent live once shadow accuracy hits a specific threshold.
item 6: CORRECTION/add-citation | zenml-2025-12-llmops-1200-deployments
```

All three trims/adds are correct and match the gold rationale in `validation-benchmark.md` (item 2 trims "consistently outperforms" back to "matches"; item 5 drops "any"/"zero risk" and restores the threshold gate; item 6 adds the exact listed source slug without touching wording).

## 5. Throughput

Single raw-API sample (item 3 prompt, `prompt_eval_count=498`, `eval_count=34` generated tokens):

```
total_duration: 525437390 ns (~0.53s)
eval_duration:  205060000 ns (~0.21s)
eval tok/s: ~166 tok/s
```

21 calls (3 passes x 7 items) completed in ~15s wall time in the first full run — well within the "free ~4h window," no cold-load stalls observed (model was already resident from the self-check / prior calls in this session by the time the full runs ran).

## 6. Failures / ambiguities hit

- No empty-response / cold-load-timeout failures occurred in this session — the 3090 was idle throughout, contrary to the "curator training" contention risk flagged in the task.
- The one real ambiguity: `validation-benchmark.md`'s Metric #4 ("Determinism (report, not gated) = identical verdict set across 3 greedy passes") implicitly assumes determinism is a run-level constant. It is not, for this model on item 3 — a single 3-pass run can show either "deterministic" or "non-deterministic," and which one you get is itself apparently non-deterministic across separate script invocations. Reporting a single run's determinism verdict without disclosing run-to-run variance would be misleading; both runs are recorded above for that reason.
- Item 6's harness prompt required assembling `sources:` frontmatter + an inline-uncited claim + its listed source excerpt into one block, since the benchmark file presents that as three separate bullet lines (article sources / claim / source excerpt) rather than a single fenced item block like 1-5. Assembled per the benchmark's own item 6/7 write-up; verified equivalent by producing the correct `CORRECTION/add-citation | zenml-2025-12-llmops-1200-deployments` verdict deterministically.

## 7. Bottom line

- Harness self-check: **PASS**.
- False-correction floor (==0): **cleared, both runs, all trials** — the model never trimmed a clean/softspot item and never invented a citation.
- Poison-recall floor (>=0.90): **cleared in Run 1 (1.00), breached in Run 2 (0.67)** — driven entirely by item 3's run-to-run instability, not by items 2 or 5 (both were CORRECTION/overstatement, correct subtype, on every single trial collected).
- Item 6 (add-citation, the S24-flagged miss): **closed deterministically** by the gate-first prompt, 6/6 passes across both runs.
- `qwen3-30b-a3b-instruct` is not an unconditional "clears both floors" tier on this offline gold set — it is right at the poison-recall floor, with one item (the contradiction/figure-swap class) genuinely unstable at temp=0. A production cutover on this tier would need either a majority-vote-of-N pass on item-3-shaped claims (figure contradictions) or a larger/different quant to close the gap; the false-correction side is solid.
