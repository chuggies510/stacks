# {Stack Name}

## Scope

*What does this stack cover? What domains, topics, or subject areas?*

### What does not belong

Pure reference material is out of scope for every stack: CLI flag listings, API reference pages, configuration-key catalogs, and step-by-step setup guides for a specific product. These belong in that tool's own documentation. The test is behavior vs. reference, not tool-name presence: knowledge of how a named tool *behaves* — documented bugs, workarounds, version quirks, performance characteristics, failure modes — is in scope even though it names the tool, because it is hard-won operating experience the vendor docs omit. Out of scope is material whose only content is *what the flags, endpoints, or settings are*: if stripping the how-to-invoke detail leaves nothing but a restatement of the reference manual, produce no concept blocks and discard it.

## Source Hierarchy

How to rank conflicting sources. Higher tiers win conflicts.

| Tier | Label | Description | Example |
|------|-------|-------------|---------|
| 1 | *Gold* | *Authoritative standards, codes* | *e.g., RFC, ISO, ASHRAE* |
| 2 | *Standard* | *Professional references, textbooks* | *e.g., O'Reilly, vendor docs* |
| 3 | *Practitioner* | *Blog posts, field notes, talks* | *e.g., conference slides* |
| 4 | *General* | *General knowledge, opinions* | *e.g., forum posts* |

## Topic Template

Sections that every topic guide in this stack should follow.

- Overview — what this is, when/why you'd use it
- Key Concepts — core principles, configurations, trade-offs, and how the system actually behaves (the terrain)
- Patterns — tested approaches, recipes, correct usage
- *Add domain-specific sections here*
- Pitfalls — behavior that surprises an experienced practitioner who already understands the design intent. Gate: would someone who read the docs and understood the system still get burned by this? If yes, it's a pitfall. If it follows directly from understanding how the system works (general language behavior, documented API semantics, resource cleanup), it belongs in Patterns or Key Concepts instead.
- Field Notes — practitioner experience, production lessons, design consequences, and observations that don't fit a prescriptive section
- Sources — which sources contributed, with tier ratings (populated by `/stacks:ingest`)

## Filing Rules

*How to decide where new knowledge goes. For example: "File by system served,
not by engineering concept" or "File by protocol layer, not by vendor."*

## Tag Vocabulary

Declare the canonical tag vocabulary for this stack here. Article-synthesizer picks tags from this list; a post-W2 drift check halts if any article acquires an out-of-vocabulary tag.

```yaml
allowed_tags:
  # - example-tag
```

## Frontmatter Convention

Topic guides use this YAML frontmatter:

```yaml
---
title: Display Name
tags: [domain-tag, topic-specific-tags]
sources: 0
last_ingested: YYYY-MM-DD
---
```
