# Full-article-context validator test — suspect (b) (liminal S61, stacks #109)

Question (division with S25): does a contradictory figure buried in a FULL article get rubber-
stamped, where the isolated single-claim item catches it 1.00? If yes, the fix is claim-isolation
in the validator loop (feed one claim at a time), not the prompt.

Method: real audited article `llm/articles/llm-as-judge.md` (last_verified 2026-07-10, ~30 claims),
plant the SAME contradiction as the isolated item (`approximately 3,000 expert votes` -> `300`),
feed the WHOLE article + its cited source to qwen3-30b-a3b, temp 0, full-article validation prompt.
A clean control runs the unmodified article.

## Answer: burial does NOT hurt recall. Suspect (b) refuted for the local tier.

- **Planted article: 5/5 caught, deterministic.** The model flagged ONLY the buried votes claim and
  fixed it to ~3,000. A contradiction buried among ~30 faithful claims is caught exactly as well as
  in isolation. So claim-isolation is NOT needed for qwen3-30b, and the intermittent bare-CLEAN
  misses (fork's, and S25's shadow 5/12) are NOT explained by burial for the local model — they are
  sonnet-specific (S25's prod check) or some other state.

## But two things surfaced that are worth a clean re-test

1. **False-correction / over-flagging on the CLEAN article (6 flags).** Decomposes:
   - Flags 5-6 (the who-drifted `60/60`, `240/240` claims): **test artifact** — I fed only 1 of the
     article's 2 cited sources, so the model correctly flagged claims whose source it couldn't see.
   - Flags 1, 2, 4: editorial/connective prose. My simplified prompt lacked the SOFTSPOT class, so
     unsourced connective claims were forced into "overstatement" instead of flagged-not-trimmed.
   - Flag 3: a **genuine false correction** — invented a semantic distinction ("expert votes are
     annotations, not preference labels") against the CORRECT, source-matching votes claim.
   So the real local-tier risk is the OPPOSITE of a miss: over-correction (trimming faithful/editorial
   claims), not shipped poison. Under the live-diff pivot that is noisy-but-safe (cloud ships).
   Caveat: the flag count is inflated by my test setup (missing 2nd source + no SOFTSPOT). Needs a
   re-run with the real validator prompt (SOFTSPOT included) + BOTH sources before it is a model trait.

2. **Instability to tiny input change.** The flag SET swung from 1 (planted) to 6 (clean) on a single-
   token difference (300 vs 3,000). At temp 0 each is deterministic, but the model is not doing a
   stable systematic scan — small input changes relatch it onto a different claim subset. This lines
   up with S25's "intermittent, state/context-dependent" bare-CLEANs and is the mechanism worth
   chasing: not burial, but scan-instability.

## Net

Local (qwen3-30b): recall on buried contradictions is solid (5/5). The open risk is precision
(over-correction) and scan-stability, not misses. Under live-diff both are safe (sonnet ships, diffs
just get noisier). Recommend a proper re-test with the real validator prompt + all cited sources to
size the false-correction rate; offered to run it.
