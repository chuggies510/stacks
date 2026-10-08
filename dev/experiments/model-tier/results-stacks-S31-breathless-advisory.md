# S31 advisory batches: local drafter, Sonnet reviewer (2026-10-07)

One real catalog batch on library-stack `llm` (3 sources, 7 slugs: 2 new, 5 updates),
drafted repeatedly by the local model while the cloud articles shipped. Same 7 concept
blocks and pre-update snapshots every time.

**Result: with harness-owned frontmatter, thinking off and one batched reviewer, review
plus repair costs 41% of what the cloud writer spends, and 7 of 7 articles clear the
floors after repair (the cloud writer: 6 of 7).** Whether to make the local draft the
shipped article is the owner's call.

## Final configuration (run 5, breathless 4-bit, thinking off)

| Measure | Value |
|---|---|
| Drafts clean as written | 4 of 7 (5 of 7 with the `sources:` step added after it) |
| After one review-and-repair pass | 7 of 7 |
| Cloud articles, same reviewer | 6 of 7 |
| Cloud tokens, write from scratch (7 one-slug agents) | 244,885 |
| Cloud tokens, review and repair (one batched agent) | 99,349 (41%) |
| Drafting time | 5.5 min for 7, 4 at a time |

The remaining over-claims are topic sentences that widen a claim ("the harness prompt
must be re-tuned", "the first cost control" for "primary"); the reviewer repairs them.

## All runs, same reviewer, graded as written

| Run | Drafter | Writer prompt | Thinking | Clean | Over-claims |
|---|---|---|---|---|---|
| 1 | breathless 4-bit | original | off | 4/7 | 1 |
| 2 | breathless | first rewrite | medium | 1/7 | 5 |
| 3 | breathless | first rewrite | off | 2/6 + 1 refusal | 6 |
| 4 | breathless | first rewrite | low | 4/7 | 8 |
| OR-off | OpenRouter bf16 | repaired | off | 6/7 | 1 |
| OR-low | OpenRouter bf16 | repaired | low | 6/7 | 2 |
| OR-medium | OpenRouter bf16 | repaired | medium | 5/7 | 5 |
| 5 | breathless 4-bit | repaired | off | 4/7 | 2 |

What the runs show:
- **Thinking does not help drafting.** Over-claims rose with effort (1, 2, 5 on OpenRouter);
  more reasoning adds more of the model's own conclusions. Off is also fastest.
- **The first prompt rewrite was worse than the original.** Pruning removed "prefer
  restating a claim plainly to making it read well" and added "organize and connect the
  claims into readable prose"; over-claims rose about five times. The repaired prompt
  restores the original rules and adds a hedge rule and "headings are labels".
- **Mechanical defects belong to the harness.** Dropped pre-update `sources:` paths (5 in
  run 1), copied `last_verified` dates (4 in run 2) and a mistyped path the 4-bit model
  wrote twice (`sources/inimal/`) are all fixed by the harness writing those fields.
- **Batching the reviewer is the cost lever.** One reviewer for 7 slugs used 90,000 to
  117,000 tokens against about 30,000 per slug when each had its own agent.

Limits: 7 slugs from one stack; the reviewer's count varies by about one over-claim
between runs; OpenRouter served bf16, breathless serves 4-bit. Run 1 was first graded by
an older reviewer prompt (cost then 92%); its row above is the regrade.

Harness defects found and fixed during the runs: the tag filter deleted the closing `---`
of block-style tags; `citation-normalizer.sh` never ran on macOS (BSD `sed -i -E`); the
catalog step that reset `live-diffs/verify/` deleted tracked evidence. Agent definitions
are frozen when a Claude Code session starts, so a reviewer edited mid-session needs its
file named in the dispatch.

Evidence: `live-diffs/runs/` (one folder per run: drafts, grades, repairs, token rows; runs
1 to 4 and the OpenRouter runs carry a grade-only `regrade/`).
