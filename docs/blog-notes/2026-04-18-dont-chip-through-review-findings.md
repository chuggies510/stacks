# Don't chip through review findings — validate the batch

**Session**: 2 (2026-04-18)
**Project**: stacks
**Status**: Draft — needs development

## The Discovery

Three parallel AI reviewers produced 23 findings on a wiki-pivot plan. The default move is to walk each finding top-to-bottom and apply the reviewer-recommended disposition. Instead I ran each finding through a five-step filter — grep the actual repo, empirical test for tool-behavior claims, consult the SWE library for severity thresholds, consequence scan for disagreements, pressure test for what the reviewers missed. The 23 compressed to 7 apply / 9 reject / 1 new catch. Chipping would have implemented 9 false positives and missed the one the reviewers all skipped.

A reader who finishes this post will understand how to turn a batch of parallel-reviewer findings into a verified disposition table, and why "reviewer said so" is a candidate disposition, not an action.

## Key Insights

### 1. Reviewer confidence is orthogonal to correctness

A finding tagged `confidence: 95%` is not 95% likely to be correct. It's 95% likely that the reviewer believes it, conditioned on the files the reviewer read. If the claim depends on a file the reviewer didn't read, the confidence score measures nothing useful. The fix: grep/read the actual repo to verify the concrete claim before treating it as true.

Worked example in this session: one cluster of findings claimed T15 (the cutover task) was missing scope expansion for 8 files. A `grep -rn` across the repo confirmed old pipeline names were present in 6 of the 8, validating most of the cluster and surfacing two that didn't need changes.

### 2. Convergence doesn't exempt you from the verify step

Two or three reviewers with distinct framings landing on the same finding is a strong signal. It is not a sufficient signal. The SWE guide on multi-agent-pipeline-design calls this out explicitly: "convergence must be verified by an independent mechanism (cross-file grep, upstream context inspection), not just tallied." If all reviewers share the same upstream read gap, they can confidently converge on a false positive.

In this session a convergent-adjacent finding (V-5/V-12) claimed `git add {deleted-file}` would fail to stage the deletion. I ran a four-line reproducer in `/tmp`:

```bash
cd /tmp && rm -rf t && mkdir t && cd t
git init -q && echo x > f.txt && git add f.txt && git commit -qm init
rm f.txt && git add f.txt
git status --short
# D  f.txt
```

The claim was wrong. Three-reviewer-adjacent support did not change that.

### 3. Single-reviewer findings are discussion, not action

When only one reviewer flags a concern at moderate confidence with no independent corroboration, the default disposition is discussion. Consequence scan supplies the decision criterion — name the downstream failure of applying the finding, name the downstream failure of rejecting it, larger blast radius wins.

In this session two medium-severity single-reviewer findings proposed refactoring — splitting a documentation file across two tasks, and collapsing vocabulary-based verify commands to structural-only. Consequence scan showed applying would introduce coordination edges the unified form avoided, and rejecting cost at most minor doc inconsistency. Both rejected.

### 4. Pressure-test for what the reviewers missed

Parallel reviewers share a structural blind spot with parallel implementation agents — each operates within a file-local scope. A canonical change in one file is invisible to sibling reviewers whose scope excludes that file. After applying the reviewer-sourced findings, run inversion / scale-game / simplification-cascades against the plan state to surface findings the reviewers could not have caught.

In this session the pressure test surfaced one finding all three reviewers missed: three agent-reshape tasks needed a "remove old pipeline references" clause, or a late verify at the final task would fail with a cryptic error. Added as a safeguard on each task.

### 5. One batch commit beats N micro-commits

The dispositions for a review batch are a unified edit of the plan. Commit them as one artifact with the disposition table (APPLY / MODIFY / REJECT + one-line reason per finding) in the commit message. Rescue value later: when someone asks "why did you reject V-5?", the answer is `git show {sha}`.

## Evidence

### Commits

```
3480ca6 plan: wiki pivot review-gate dispositions (#17)
7e1a199 docs(memory-bank): Session 2 handoff — plan-review dispositions applied
46a204a docs: Session 2 chat name
```

### Key measurements

- 23 plan-review findings in the input batch
- 3 parallel reviewers (simplicity / correctness / conventions framings)
- 7 dispositions applied, 9 rejected, 1 new caught via pressure test
- ~10 minutes of systematic validation vs an estimated 60-90 minutes to walk 23 findings one-at-a-time with higher error rate
- 82 insertions / 48 deletions across 2 files (plan.md + tasks.json)
- 1 empirical test in `/tmp` disproved one convergent-adjacent claim

### Commit message excerpt

```
Apply 7 of 23 plan-review findings after systematic validation against
actual repo state and swe/multi-agent-pipeline-design guidance.

Rejected after verification:
- V-5/V-12 "git add won't stage deletions" — empirically disproven:
  rm + git add stages D correctly
- S-02/S-04 wave-engine split and agent-verify restructure — single-
  reviewer findings; per swe guide, single reviewer at <80% confidence
  is discussion not action
```

### References

- Session 2 handoff: `.claude/memory-bank/active-context-S3.md`
- SWE library guide: `library-stack/swe/topics/multi-agent-pipeline-design/guide.md`
- Inbox-captured pattern: `library-stack/inbox/stacks-s2-plan-review-dispositions.md`
- Follow-up issue: ChuggiesMart#374 (skill request to encode this method)

## Blog Post Angles

1. **The methodology post** — walk the five steps with the real 23-finding example. Structure: problem (reviewer batch lands), wrong move (chipping), right move (five-step filter with this session's concrete artifacts), outcome (7/9/1 with specific rejects). Primary audience: engineers running AI code reviewers.
2. **The empirical-test vignette** — zoom in on the V-5/V-12 moment. Three reviewers pattern-match to a concerning finding. Four-line reproducer in `/tmp` disproves it. Lesson: tool-behavior claims are verifiable in seconds; the cost of the test is always less than the cost of believing it. Shorter post, sharper hook.
3. **The contrarian post** — "Your AI code reviewer is lying to you at 95% confidence" — lead with the confidence-vs-correctness distinction, cover the three disposition classes (convergent-verified, single-reviewer-discussion, pressure-test-gap), close with the disposition table as the deliverable.

## Visual Ideas

A hero image showing a funnel: 23 findings entering at the wide end, five filter stages (grep, empirical test, library lookup, consequence scan, pressure test), and 7/9/1 emerging at the narrow end with labels apply/reject/new. Secondary visual: a four-line terminal screenshot of the `rm f.txt && git add f.txt` reproducer showing `D  f.txt` — the moment a convergent-adjacent claim died.

## TODO

- [ ] Expand key insights with detail (especially #4 pressure-test, which is the least-discussed)
- [ ] Add raw evidence: actual finding text for the 9 rejects, not just their IDs
- [ ] Decide angle (1/2/3) and cut the others
- [ ] Draft post: /writing-tools:blog
