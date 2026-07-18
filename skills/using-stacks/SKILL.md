---
name: using-stacks
description: |
  The universal entry point to the stacks knowledge library — discovers and
  routes to the right /stacks:* skill for the task. Use when you want to look up
  domain knowledge, turn sources into articles, check or improve a stack's
  accuracy, or set up a new library/stack — or when unsure which stacks skill
  applies, or the user runs /stacks:using-stacks. This is the meta-skill that
  governs how the seven stacks skills are chosen and the discipline they share.
  Examples: "how do I use stacks", "route me to the right stacks tool",
  "I have some PDFs to add to my knowledge base".
---

# Using stacks

## Overview

Stacks is a knowledge library: raw sources (PDFs, docs, web dumps) become small
synthesized **articles**, one per concept, that an agent in any repo reads
instead of re-reading originals or hallucinating. Seven skills build, query, and
maintain it. This meta-skill is the front door: it picks the right one and
carries the discipline they all share.

**Two repos, one rule.** The `stacks` plugin is the tool (loaded everywhere); a
separate library repo (e.g. `library-stack`) is the content. Every skill runs
**from any repo** — most stack work happens in the field (a consuming repo, an
audit or PCA), not inside the library. The build and maintain skills resolve the
target library from `~/.config/stacks/config.json` (or the current directory when
it is itself a library) and operate there; you do not `cd` into the library first.

## The one rule

**Every claim traces to a source.** `/stacks:lookup` reads articles, never the
sources behind them, so an article that drifted from its source becomes confident
misinformation. Articles cite sources; `audit-stack` finds unsourced claims;
`enrich-stack` acquires real sources to close them. Nothing enters as a bare
assertion.

## Routing

```
Working with the knowledge library?
    │
    ├── Need to KNOW something (a domain question)
    │        → lookup            (from any repo; a miss can auto-enrich)
    │
    ├── Have new SOURCES to turn into articles
    │        ├── files queued by other sessions in inbox/  → process-inbox
    │        └── a folder of source docs to ingest         → catalog-sources [--from <dir>]
    │
    ├── Quality — keep a stack honest
    │        ├── check articles against their cited sources → audit-stack
    │        └── close the soft spots it found (get sources)→ enrich-stack
    │
    └── Setup (rare)
             ├── no library yet                            → init-library
             └── have a library, add a topic              → new-stack
```

## Core operating behaviors

Non-negotiable, across all seven skills.

### 1. Source-grounded, or it doesn't ship

An article states only what a cited source supports. A claim with no source is a
**soft spot**, not a fact — `audit-stack` lists them, `enrich-stack` acquires a
grounding source, and only then does it become an article. Prefer higher-tier
sources (the `STACK.md` schema defines the tiers); a weak source is a weak claim.

### 2. One article per concept

The library is a wiki of concepts, not a pile of sources. `catalog-sources`
identifies the concepts in each source and **deduplicates** so one concept is one
article, however many sources touch it. Don't create a second article for a
concept that already has one — enrich the existing one.

### 3. The routing map earns its keep

`index.md` is how a lookup lands on the right article. Describe each article in
the terms someone would actually ask about, not just its title, so the match is
by meaning, not literal keyword. A true article no one can route to is dead
weight.

### 4. Every skill runs anywhere; the library is resolved, not your cwd

All seven skills run from any repo. `lookup` and `process-inbox` read the
configured library; `new-stack`, `catalog-sources`, `audit-stack`, and
`enrich-stack` resolve that same library (from `~/.config/stacks/config.json`, or
the current directory when it is itself a library) and operate on it in place —
you never `cd` into the library first, because fieldwork happens in the consuming
repo. If resolution fails (no config and the cwd has no `catalog.md`), the skill
prints a fix hint pointing at `/stacks:init-library`.

### 5. A lookup miss is a gap to close, not a dead end

When `lookup` can't answer, that gap feeds `enrich-stack` (its `--auto` path
stages candidate sources hands-free; otherwise it's a tracked gap for operator
review). Querying the library is also how you discover what to grow next.

### 6. Operator approves what enters

`enrich-stack` web-searches for sources but **never auto-ingests** — it presents
what it found and stages only approved sources into `sources/incoming/` (the
`--auto` fast path excepted). The human decides what the library is allowed to
believe.

`sources/incoming/` is **gitignored staging** — files there are untracked, so
they do not sync across machines and are gone if the disk is lost. `git add`
silently ignores them and `git status` reads clean, which looks like they are
safe when they are not. `catalog-sources` is what makes a staged source durable:
it extracts the concepts into articles and files the raw source into the tracked
`sources/{publisher}/`. Catalog promptly rather than leaving hand-authored
sources staged across a session or a machine switch.
