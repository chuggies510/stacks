# Stacks

A stacks library turns sources into one cited article per concept, so an agent answers from
the article instead of re-reading the source.

## Language

### Writing an article

**Concept block**:
The merged extraction for one slug: its source paths with tiers and the claims the article may state.
_Avoid_: extraction, block file

**Claim**:
One bullet under a concept block's `### Claims` heading; the unit an article restates and a reviewer counts.
_Avoid_: fact, finding

**Subject**:
Who a claim is about: the named company, product, study or standard.
_Avoid_: actor, entity

**Hedge**:
How sure or how often a claim is: "can", "may", "appears to", "not reliably", "in one run".
_Avoid_: qualifier, caveat

**Over-claim**:
A sentence that says more than the claim it rests on, most often by widening its subject or dropping its hedge.
_Avoid_: hallucination, overstatement

**Article template**:
The section list in a stack's STACK.md that every article in the stack follows.
_Avoid_: Topic Template (the older heading some stacks still use)

### The local-writer trial

**Draft**:
An article written by the local model, kept out of `articles/` and graded but never shipped.
_Avoid_: shadow, local article

**Pre-update article**:
The article as it stood before a catalog run rewrote it; drafts and reviews of an update are judged against it.
_Avoid_: prior, old version

**Repair**:
A reviewer's copy of a draft with only its listed fixes applied, never a rewrite.
_Avoid_: fix pass, regeneration
