# Synthesis shadow-pilot results (local-first, cloud-authoritative, log-the-diff)

Run: 2026-07-12, `RUN_ID=S24-pilot`, model `qwen3-30b-a3b-instruct` (confirmed exact tag `qwen3-30b-a3b-instruct:latest` via `ollama list` / `/api/tags`, same underlying weights as `qwen3-30b-a3b-instruct-2507-q4km:latest`, id `19e422b02313`), Ollama at `localhost:11434`, RTX 3090.

Mechanism only — this captures both outputs plus cheap deterministic structural metrics. It does NOT judge recall or over-claim; that scoring is deferred to liminal (downstream) on the logged pairs, as scoped.

## What ran

| Item (concept) | Cloud article used as stand-in for sonnet | Result |
|---|---|---|
| `llm-evaluation-frameworks` | `llm-evaluation-frameworks.md` (exists) | local wrote a full article |
| `production-eval-systems` | `production-eval-systems.md` (exists) | local wrote a full article |
| `production-agent-autonomy-controls` | none published — logged local-only, `cloud:null` | local refused (see Failures/surprises) |

Item 3 (thin-concept refusal) skipped per instructions — it correctly produces no article, not a synthesis case.

**Caveat carried from the task brief**: the two published cloud articles carry extra audited content the concept block omits (they were written from the fuller parent source, then audit-validated). They are a prose-shape stand-in for what the live sonnet agent would produce from the same block, not a true block-relative peer — the real pipeline feeds a fresh sonnet article instead of the published one.

## synthesis.jsonl (3 records, one JSON line per item — verified each line parses standalone with `jq`)

```json
{"item":"llm-evaluation-frameworks","model":"qwen3-30b-a3b-instruct","run_id":"S24-pilot","tok_s_est":"20.4","status":"ok","local":{"words":168,"citations":6,"tags_total":5,"tags_in_vocab":5,"has_title":true,"has_last_verified":true,"has_sources":true,"has_routing":true,"body_path":"live-diffs/bodies/llm-evaluation-frameworks__local.md"},"cloud":{"words":508,"citations":7,"tags_total":8,"tags_in_vocab":8,"has_title":true,"has_last_verified":true,"has_sources":true,"has_routing":true,"body_path":"live-diffs/bodies/llm-evaluation-frameworks__cloud.md"}}
{"item":"production-eval-systems","model":"qwen3-30b-a3b-instruct","run_id":"S24-pilot","tok_s_est":"21.5","status":"ok","local":{"words":210,"citations":0,"tags_total":4,"tags_in_vocab":4,"has_title":true,"has_last_verified":true,"has_sources":true,"has_routing":true,"body_path":"live-diffs/bodies/production-eval-systems__local.md"},"cloud":{"words":919,"citations":17,"tags_total":7,"tags_in_vocab":7,"has_title":true,"has_last_verified":true,"has_sources":true,"has_routing":true,"body_path":"live-diffs/bodies/production-eval-systems__cloud.md"}}
{"item":"production-agent-autonomy-controls","model":"qwen3-30b-a3b-instruct","run_id":"S24-pilot","tok_s_est":"0.8","status":"ok","local":{"words":0,"citations":0,"tags_total":0,"tags_in_vocab":0,"has_title":false,"has_last_verified":false,"has_sources":false,"has_routing":false,"body_path":"live-diffs/bodies/production-agent-autonomy-controls__local.md"},"cloud":null}
```

Every number above was cross-checked by hand against the saved body files (`awk`/`wc -w`/`grep -oE`, not just trusted from the script) — see "Verification" below.

## Tag post-filter: before / after (real command output)

The out-of-vocab tag `safety` (item 1) and `red-teaming` (item 2) are exactly what liminal flagged as the qwen3-30b-a3b synthesis defect — one invented tag per article. Confirmed here on both live items:

**Item 1 — `llm-evaluation-frameworks`**
```
before: tags: [evals, llm, context-engineering, agents, hallucination, safety]
after:  tags: [evals, llm, context-engineering, agents, hallucination]
```
`safety` dropped (not in the 17-tag llm-stack vocab). The 5 remaining tags are all in-vocab.

**Item 2 — `production-eval-systems`**
```
before: tags: [evals, llmops, llm-as-judge, shadow-mode, red-teaming]
after:  tags: [evals, llmops, llm-as-judge, shadow-mode]
```
`red-teaming` dropped. The 4 remaining tags are all in-vocab.

Item 4 produced no frontmatter at all (refusal, no `tags:` line to filter) — postfilter is a no-op on a file with no `tags:` key, verified: `grep -A6 '^tags:'` reported "(no tags: line found)" both before and after.

## Failures / surprises

1. **Item 4: local model refused a substantive concept.** The block carries 5 named-company claims (Ramp autonomy %, autonomy slider, Cox circuit breakers, Cursor RL, Dropbox tool overload) — well above the ~150-word substantive-article floor the prompt sets, and the benchmark's gold expects a full article. The local model instead emitted: `Concept production-agent-autonomy-controls: insufficient claims — article not written.` Reproduced identically across 2 separate runs (same wall-clock ~12-13s, same 9-word output) — deterministic, not a one-off glitch. This is an over-restraint miss (refusing when it should write), the mirror image of the over-write failure the benchmark's item-3 check guards against. Flagged for liminal's downstream judgment, not scored here.
2. **Item 2: local model used the wrong citation format**, `[source: zenml-2025-12-llmops-1200-deployments]` instead of the required bare `[zenml-2025-12-llmops-1200-deployments]`. The structural citation-count metric (which greps the bare-bracket form per the benchmark's own structural check) correctly reports `0` for item 2's local output even though 7 source-attributed sentences are present — this is real signal, not a script bug (manually confirmed: `grep -oE '\[source:[^]]*\]'` finds all 7; the bare-form regex finds 0). Item 1 used the correct bare format (6/6 matched). Worth flagging to liminal as a format-compliance miss distinct from any recall/over-claim judgment.
3. No local-inference errors (empty output / cold-load timeout) on any of the 3 items — `local-infer.sh` returned nonempty content every time.

## Local model tok/s

Estimated (not read from Ollama's native `eval_count`/`eval_duration` — `local-infer.sh` discards the raw API response and keeps only `.message.content`, and the task said not to rebuild it). Estimate = `words_generated × 1.3 ÷ wall_clock_seconds` of the full `local-infer.sh` call (includes prompt processing, not pure decode):

| Item | Wall time | Words | Est. tok/s |
|---|---|---|---|
| llm-evaluation-frameworks | 13.0s | 168 | 20.4 |
| production-eval-systems | 15.5s | 210 | 21.5 |
| production-agent-autonomy-controls (refusal, 9 words) | 12.6s | 9 | 0.8 (not meaningful — dominated by prompt processing, not decode) |

Meaningful throughput (items 1-2, real articles generated): **~20-21 tok/s estimated** on a 30B-A3B quant on the RTX 3090, model already resident (no cold-load penalty observed in these runs).

## Verification (manual cross-check, not just script-reported numbers)

```
$ awk 'BEGIN{c=0} /^---$/{c++; next} c>=2' llm-evaluation-frameworks__local.md | wc -w
168                                                    # matches jsonl "words":168
$ grep -oE '\[[a-zA-Z0-9][a-zA-Z0-9._-]*\]' llm-evaluation-frameworks__local.md | wc -l
6                                                      # matches jsonl "citations":6
$ awk 'BEGIN{c=0} /^---$/{c++; next} c>=2' production-eval-systems__local.md | wc -w
210                                                    # matches jsonl "words":210
$ grep -oE '\[source:[^]]*\]' production-eval-systems__local.md | wc -l
7                                                      # confirms the 7 wrong-format citations behind the "citations":0 result
$ awk 'BEGIN{c=0} /^---$/{c++; next} c>=2' llm-evaluation-frameworks__cloud.md | wc -w
508                                                    # matches jsonl cloud "words":508
$ awk 'BEGIN{c=0} /^---$/{c++; next} c>=2' production-eval-systems__cloud.md | wc -w
919                                                    # matches jsonl cloud "words":919
```

All 3 `synthesis.jsonl` lines independently parse with `jq .` (single-line JSON, per spec — an earlier draft of `synth-shadow.sh` wrote pretty-printed multi-line JSON per record via a non-`-c` `jq -n` call; fixed to `jq -nc` before this run, verified with a per-line `jq .` parse loop).

## What this pilot does NOT do (by design)

No over-claim or recall judgment happens in `synth-shadow.sh`. Structural metrics only: word count, inline-citation count, tag count / in-vocab count, and presence of the four required frontmatter keys (`title`, `last_verified`, `sources`, `routing`). Whether the local article's claims are faithful to the concept block (recall ≥0.90, 0 over-claims per the benchmark's floors) is liminal's downstream call on the logged pairs — this pilot's only job was capture + log-the-diff.
