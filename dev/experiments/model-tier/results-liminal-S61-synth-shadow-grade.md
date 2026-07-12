# Synth-shadow local bodies — recall/over-claim grade (liminal S61, stacks #109)

Downstream grade of the `live-diffs/` local bodies (S24-pilot, qwen3-30b-a3b-instruct), deferred to
liminal by the pilot. Block-relative scoring (recall + over-claim vs each concept block's own claims).

## Grades

| Item | Recall | Over-claims | Refusal | Citation format | Verdict |
|------|--------|-------------|---------|-----------------|---------|
| 1 `llm-evaluation-frameworks` | **6/6** | **0** | n/a | bare `[slug]` ✓ | **clean pass** |
| 2 `production-eval-systems` | **7/7** | **0** | n/a | `[source: slug]` ✗ | content pass, **format fail** |
| 4 `production-agent-autonomy-controls` | — | — | **FALSE REFUSAL** | — | **fail (over-restraint)** |

## Detail

- **Item 1:** all 6 block claims present verbatim-faithful, nothing added. Tags all in-vocab (the
  `safety` slip already dropped by the tag post-filter). A clean synthesis.
- **Item 2:** all 7 claims present, every company attribution and hedge intact (Ramp attributed,
  "human oversight first", "makes the gate auditable", "documented practice") — 0 over-claims, same
  clean result as the offline benchmark. The ONLY defect is citation format: `[source: zenml-...]`
  instead of bare `[zenml-...]`. Content is correct; the wrapper is wrong.
- **Item 4:** the block carries 5 substantive named-company claims (Ramp 65% autonomy, autonomy
  slider, Cox circuit breakers, Cursor RL 28%, Dropbox analysis-paralysis) — well past the ~150-word
  floor, gold expects a full article. qwen3-30b emitted "insufficient claims — article not written",
  deterministically. A genuine **false refusal / over-restraint**: the mirror of the over-write
  failure item-3 guards against. My offline 3-item run missed this because item-3 (thin) *should* be
  refused; item-4 (rich) reveals the restraint threshold is miscalibrated — it refuses substantive
  blocks too.

## Two defects, both mechanically bounded

1. **Citation normalizer (easy, deterministic).** `[source: X]` → `[X]`: one regex post-filter,
   same class of fix as the tag post-filter. Content recall/over-claim are unaffected (the citations
   are correct, just wrapped). Kills item 2's format fail.
2. **False refusal (the real quality risk).** Over-restraint means local silently produces NO draft
   on substantive blocks. Under the live-diff net that is safe (cloud writes, diff = "local refused")
   but it caps local's contribution — local only helps where it writes. Candidate fixes: raise the
   refusal bar in the prompt (refuse only below a hard floor, e.g. <2 claims / <100 grounded words),
   or a 1-shot anchor showing a 5-claim block being written. Needs a refusal-rate characterization on
   more substantive blocks before wiring — the offline 3-item set has only one refuse-item and it's
   the thin one, so the refusal calibration was never stress-tested until this pilot.

## Net

Where qwen3-30b writes, content is excellent (13/13 claims, 0 over-claims across items 1-2), matching
the offline benchmark. The live pilot surfaced what the offline set couldn't: a citation-format slip
(trivial post-filter) and a false-refusal calibration bug (the one to actually fix). Both are pre-ship
fixes on the local draft; neither is a safety issue under cloud-authoritative.
