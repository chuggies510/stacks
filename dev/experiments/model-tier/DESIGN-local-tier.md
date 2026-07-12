# Local-tier worker design: one object-level judgment per call

**Status:** design principle for the #109 local-model pilot. Confirmed across all four
worker stages by two independent derivations (stacks S25 meta-pattern pass + liminal S61
per-stage measurement). Governs how each stage is wired to a local model; inherit it
rather than re-benchmarking each stage from scratch.

**Durable decision:** ADR-002 (`docs/decisions/decision-log.md`) is the indexed, long-lived
record of this recipe; this file is its backing detail (the per-stage table and evidence).

## Aim (rebased S25): good output, not identical output

The goal is a cheap tier that produces GOOD output — clears the accuracy floors — not one
that reproduces the authoritative model byte for byte. Byte-determinism (temp 0, identical
across passes) was a **testing scaffold**: a cheap, brutal way to detect "did the output
change" while we proved the harness works. It is now relaxed as a production criterion. A
good article that differs from sonnet's wording is a success, not a diff to chase.

Two consequences of the S25 measurements:

- **Tier choice is cost/ops, not capability.** Behind the harness, both a local tier
  (qwen3-30b, ~$0) and a cheaper subscription tier (haiku) clear the synthesis and
  validation floors. Determinism no longer breaks the tie; cost and operational fit do.
  (And "cloud" here is subscription tokens, not metered API credits — so the local-vs-cloud
  cost gap is throughput/quota, not a dollar meter.)
- **The authoritative step becomes verify-and-fix, not rewrite-from-scratch.** "Log the
  identity diff" made sense only while determinism was the lens. With good-output as the
  goal, the cloud pass should CHECK the local draft against the floors and fix only what
  fails — cheaper than re-synthesizing every article. That is where the cloud-token savings
  the pilot was built for actually live.

## The principle

A weak local model (qwen3-30b-a3b on a 24GB card) is **strong at bounded content
generation and chaotic at meta-judgments** — decisions *about* the work rather than the
work itself. Every failure observed this session was a meta-judgment left inside the
model; every fix was the same move:

> Give the weak tier **exactly one object-level judgment per call** (extract this concept /
> write this article / verify this claim / ground this gap). Pull **every mechanical or
> meta decision around it** (refuse-or-write, aggregate-across-items, dedup, format-conform)
> **out of the model into a deterministic harness gate.**

The harness owns the meta-decisions because they are cheap, deterministic, and exactly
where the weak tier is unstable. The model owns only the content, where it is excellent.

## Per-stage application

| Stage | The ONE object judgment (model) | Meta/mechanical gates (harness) | Evidence | Status |
|-------|--------------------------------|--------------------------------|----------|--------|
| **Synthesis** | write the article from the block | refusal gate (claim-count floor), tag-vocab filter, `[source: X]`→`[X]` normalizer | recall 13/13, 0 over-claims; refusal was prompt-chaotic, tags/citations mechanical | **shipped 0.61.0** |
| **Validation** | judge ONE claim vs its cited source | run **per-claim** (isolate the across-article aggregation) + **citation-presence gate** (STEP 1 as code: `claim-citation-gate.sh` decides CITED/UNCITED, so an uncited claim can never be judged CLEAN) | per-claim: recall 1.00 / false-corr 0.00 / byte-DET; the qwen item-6 add-citation miss is **closed by the gate** (gated, qwen returns add-citation not CLEAN — S25) | gate built (S25); shadow+verifier pending |
| **Extraction** | describe a concept | deterministic **slug pre-match** (isolate reuse-vs-mint) before the model sees it | over-mint was the granularity meta-judgment; described-slugs fixed most, pre-match closes it | recipe known |
| **Enrichment** | ground ONE gap in a source | **URL dedup as `candidate_url in filed_urls` set-membership**, emit DUP in code, skip the call when the URL is already filed | grounding 3/3, false-CANDIDATE 0/2, byte-DET; the ONLY miss was the dedup it was handed | recipe known; full local loop (search+fetch+judge) proven S59/S60, re-verified S25 |

Enrichment is the sharpest illustration: its grounding (the object judgment) is genuinely
good, and its single failure was a containment check a probabilistic model should never
have run. The fix isn't a better prompt — it's not asking the model.

### The harness is model-agnostic (haiku ≈ qwen behind it)

The principle predicts the harness makes ANY adequate-content tier pass, not just the local
one. Confirmed (S25, `results-stacks-S25-haiku.md`): `claude-haiku-4-5` run behind the same
harness clears the **synthesis** floors (recall 23/23, 0 over-claims on all three over-claim
cliffs) and the **validation** floors (poison recall 1.00, false-correction 0, and it catches
the item-6 add-citation class under the gate-first prompt — the same lever qwen needed). The
earlier "haiku fails, qwen passes" read was an artifact of comparing *raw* haiku to *harnessed*
qwen: on extraction the raw over-mint was haiku 3 vs qwen 19 (qwen worse), and that meta-judgment
is the harness's job for both. The two cheap tiers differ on **determinism** (qwen byte-identical
at temp 0; haiku, cloud, not) and **cost** (qwen ~$0 local), not capability on these roles.

## What this principle eliminates (dead ends, do not revisit)

Each abandoned approach was an attempt to fix a meta-judgment *inside* the model. The
principle says that is impossible; these were doomed by construction:

- **Validator prompt-split** — tried to fix an unstable judgment with a better prompt.
- **Refusal calibration curve** — tried to *tune* a chaotic judgment (liminal: no curve exists).
- **Byte-determinism / temp-0 chasing** — tried to *stabilize* it via sampling; but the
  failures reproduce deterministically at temp 0 (refusal flips on a cosmetic preamble,
  enrichment dedup flips on instruction ordering), so they were never sampling noise and
  stabilizing sampling cannot touch them.
- **Majority-vote-of-N on the validator** — voting fixes a coin-flip, not a deterministic
  or ordering-dependent miss.

## Wiring recipe (for the remaining stages)

```
local wiring for stage S =
    (content prompt: the ONE object judgment S makes, fed to the local model)
  + (a deterministic harness gate for EACH meta/mechanical decision S makes)
  + (log local-vs-cloud diff; cloud ships, local is graded downstream)
```

Under the live-diff pilot architecture (local-first, cloud-authoritative, log-the-diff),
this makes each stage a **mechanical application**, not a research project: wire it on the
recipe, ship the cloud output, let the accumulated diff grade the local tier over real
runs. Extraction (slug pre-match) and validation (per-claim) are the next two. Enrichment
fits the same recipe end to end: its acquisition half (form a query, search, fetch) runs
local too — liminal proved the full loop S59/S60 and re-verified it live this session
(gemma4-31b forms its own query → Brave Search API → fetch → CANDIDATE/tier verdict, $0
marginal, no cloud). Giving the local model `web_search`/`web_fetch` via ollama `/api/chat`
tools is a tool-wiring task, not a reason to keep the stage on Claude.

## Provenance

Object-level metric evidence lives in the four `results-liminal-S61-*.md` files and the
offline benchmarks (`extraction/synthesis/validation/enrichment-benchmark.md`). The
synthesis gates are implemented in `harness/{synth-shadow,tag-postfilter,citation-normalizer}.sh`
and wired opt-in via `STACKS_LOCAL_SHADOW=1` (0.61.0).
