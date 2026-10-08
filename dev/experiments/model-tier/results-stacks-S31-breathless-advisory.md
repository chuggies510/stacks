# S31 advisory batch: breathless drafter, Sonnet reviewer (2026-10-07)

One real catalog batch on library-stack `llm` (3 sources, 7 slugs: 2 new, 5 updates,
RUN_ID_W2 1791417011), run with `STACKS_LOCAL_SHADOW=1`. The cloud articles shipped;
the local drafts and their repairs stayed in `live-diffs/`.

**Result: quality clears, the cloud saving does not.** Every draft clears the
synthesis floors after one review-and-repair pass, but that pass cost the cloud 92%
of what writing the articles from scratch did.

| Measure | Value |
|---|---|
| Drafter | breathless vLLM `qwen3.8-27b`, thinking off, 4 at a time |
| Local drafts written | 7 of 7, none refused or failed |
| Draft clears floors as written | 3 of 7 |
| Clears after one repair pass | 7 of 7 |
| Cloud article clears, same block | 6 of 7 (one over-claim) |
| Cloud tokens, write from scratch (W2) | 244,885 |
| Cloud tokens, review and repair | 226,101 |
| Wall time, local drafting | about 10.5 min for 7 (147 to 431 s each) |

Draft defects the reviewer fixed:
- **Dropped hedges, 2.** "does not reliably shorten" became "does not shorten";
  "appears to have learned" became "learns".
- **Dropped pre-update `sources:` paths, 5 in 2 updates.** The body still cited
  them. Restoring them is a deterministic union with the snapshot's `sources:`; no
  model is needed.
- **One mistyped source path.**

Why the saving is small: Claude Code reports total tokens per agent, and both agents
spend most of theirs reading the same inputs (block, pre-update article, STACK.md,
scope map), about 25,000 each. Writing is a small share, so moving it to breathless
removes little. The output-token share, which is the costlier part, was not measured
separately.

Harness defects this batch found and fixed before scoring: the tag filter deleted
the closing `---` of block-style tags (all 5 updates had unterminated frontmatter),
and `citation-normalizer.sh` never ran on macOS (BSD `sed -i -E`). Agent definitions
are frozen when a Claude Code session starts, so a reviewer edited mid-session needs
its file named in the dispatch.

Evidence: `live-diffs/synthesis.jsonl` (run 1791417011), `live-diffs/bodies/*__local.md`,
`live-diffs/verify/{slug}.json`, `{slug}.cloud.json`, `{slug}__repaired.md`, `tokens.tsv`.
