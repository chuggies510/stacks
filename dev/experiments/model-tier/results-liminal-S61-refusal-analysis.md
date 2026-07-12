# Item-4 false-refusal analysis — it's prompt-fragility, not calibration (liminal S61, #109)

The peer's synth-shadow pilot refused item-4 (production-agent-autonomy-controls) deterministically.
Requested: a refusal-rate calibration curve to set a floor. There is no clean curve — the refusal
is prompt-fragile, not a count/style threshold.

## What the model actually does

| Condition (qwen3-30b-a3b-instruct, temp 0) | Result |
|--------------------------------------------|--------|
| Verbatim benchmark prompt, item-4 @ 2, 3, 4, 5 claims | WRITE (all) |
| 5-claim block from item-1 (survey) and item-2 (company-practice) | WRITE |
| **Exact pilot assembly** (benchmark rubric L17-41 + "Allowed tags:" vocab + block, no preamble) | **REFUSE** (both `-2507-q4km` and `:latest`, same id 19e422b02313) |
| Pilot assembly **+ a "Here is the concept block:" preamble line** | **WRITE** |
| Preamble but no tag-vocab / tag-vocab but no preamble | REFUSE |

So: the model writes item-4 fine under most framings. The refusal reproduces ONLY under the exact
pilot prompt assembly, and a single cosmetic preamble line flips it back to WRITE. The sensitivity is
non-monotonic (tags-alone → refuse, preamble-alone → refuse, tags+preamble → write).

## Conclusion: same fragility class as the validator

This is not model calibration (no count/style floor exists — it writes 2-5 claims, all styles) and not
the block being genuinely thin. It is the model's thin-vs-substantive META-JUDGMENT being unstable to
small prompt perturbations — the same signature as the validator's one-token 1→6 flag flip. Weak-tier
meta-judgments (refuse-or-write, clean-or-flag) are prompt-chaotic.

## Recommended fix: take the judgment out of the loop (don't calibrate it)

A prompt tweak (adding the preamble) makes item-4 write, but it is fragile — the next block may flip
again. The ROBUST fix mirrors the validator conclusion (per-claim harness beats whole-article batch):
gate refusal DETERMINISTICALLY in the harness, not in the model.

- In `synth-shadow.sh`, count the block's claims (or grounded words) before the call.
- If above a hard floor (e.g. >= 2 claims / >= ~100 words), STRIP the "if too thin, do NOT write"
  clause from the prompt for that call — force a write. Keep the refusal clause only for blocks below
  the floor (the genuinely thin item-3 case).
- Result: refusal becomes a deterministic harness decision on a countable property, and the model's
  unstable thin-judgment is removed from the loop.

Under the live-diff net this is not a safety issue (cloud ships), but a false refusal means the local
tier contributes nothing on that item, so the deterministic gate is what makes the local draft
reliably present.
