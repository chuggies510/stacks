# Local-tier worker design: one object-level judgment per call

**Status:** design principle for the #109 local-model pilot. Confirmed across all four
worker stages by two independent derivations (stacks S25 meta-pattern pass + liminal S61
per-stage measurement). Governs how each stage is wired to a local model; inherit it
rather than re-benchmarking each stage from scratch.

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
| **Validation** | judge ONE claim vs its cited source | run **per-claim** (isolate the across-article aggregation) | per-claim: recall 1.00 / false-corr 0.00 / byte-DET; whole-article batch: over-flags + scan-instability | recipe known |
| **Extraction** | describe a concept | deterministic **slug pre-match** (isolate reuse-vs-mint) before the model sees it | over-mint was the granularity meta-judgment; described-slugs fixed most, pre-match closes it | recipe known |
| **Enrichment** | ground ONE gap in a source | **URL dedup as `candidate_url in filed_urls` set-membership**, emit DUP in code, skip the call when the URL is already filed | grounding 3/3, false-CANDIDATE 0/2, byte-DET; the ONLY miss was the dedup it was handed | recipe known |

Enrichment is the sharpest illustration: its grounding (the object judgment) is genuinely
good, and its single failure was a containment check a probabilistic model should never
have run. The fix isn't a better prompt — it's not asking the model.

## What this principle eliminates (dead ends, do not revisit)

Each abandoned approach was an attempt to fix a meta-judgment *inside* the model. The
principle says that is impossible; these were doomed by construction:

- **Validator prompt-split** — tried to fix an unstable judgment with a better prompt.
- **Refusal calibration curve** — tried to *tune* a chaotic judgment (liminal: no curve exists).
- **Byte-determinism / temp-0 chasing** — tried to *stabilize* it via sampling; the
  instability is in expert routing, not sampling.
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
runs. Extraction (slug pre-match) and validation (per-claim) are the next two; enrichment's
web-tool dependency is a separate problem (agentic tool use), so it stays on Claude for now.

## Provenance

Object-level metric evidence lives in the four `results-liminal-S61-*.md` files and the
offline benchmarks (`extraction/synthesis/validation/enrichment-benchmark.md`). The
synthesis gates are implemented in `harness/{synth-shadow,tag-postfilter,citation-normalizer}.sh`
and wired opt-in via `STACKS_LOCAL_SHADOW=1` (0.61.0).
