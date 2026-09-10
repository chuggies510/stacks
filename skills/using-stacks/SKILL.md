---
name: using-stacks
description: Use when work in any repo may involve querying, creating, cataloging, auditing, or enriching a knowledge library and the correct stacks skill is unclear.
---

# Using stacks

## Overview

Stacks is a knowledge library: raw sources (PDFs, docs, web dumps) become small
synthesized **articles**, one per concept, that an agent in any repo reads
instead of re-reading originals or hallucinating. Eight workflows build, query, and
maintain it. This meta-skill is the front door: it picks the right one and
carries the discipline they all share.

**Two repos, one rule.** The `stacks` plugin is the tool (loaded everywhere); a
separate library repo (e.g. `library-stack`) is the content. Seven field workflows
run from any repo; `ingest-book` runs inside the library. Most stack work happens in the field (a consuming repo, an
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
    │        → lookup
    │
    ├── Need local library setup or source staging
    │        ├── no library yet                    → init-library
    │        ├── add a topic                       → new-stack
    │        ├── route queued files                → process-inbox
    │        └── ingest a book-scale PDF           → ingest-book
    │
    └── Need cataloging, auditing, or enrichment
             → use a compatible Stacks harness
```

## Core operating behaviors

Non-negotiable, across all eight workflows.

### 1. Source-grounded, or it doesn't ship

An article states only what a cited source supports. This Hermes release can create, ingest, route, and query grounded material. Auditing, source enrichment, and cataloging require a compatible Stacks harness.

### 2. One article per concept

The library is a wiki of concepts, not a pile of sources. This Hermes release can stage and ingest material, while a compatible Stacks harness catalogs sources into deduplicated article entries.

### 3. The routing map earns its keep

`index.md` is how a lookup lands on the right article. Describe each article in
the terms someone would actually ask about, not just its title, so the match is
by meaning, not literal keyword. A true article no one can route to is dead
weight.

### 4. Hermes workflow locations

`lookup`, `process-inbox`, `new-stack`, and `init-library` run from any repo.
They resolve the configured library from `~/.config/stacks/config.json`, or the
current directory when it is itself a library. `ingest-book` runs inside the
library because it creates a chapter-level deep-reference tree. If resolution
fails, use `stacks:init-library`.

Runtime-root mechanics are provided by the native adapter, which publishes the
installed package root into the existing executable skill fences.

On Hermes, the safe native release provides these qualified skills:
`stacks:lookup`, `stacks:init-library`, `stacks:new-stack`,
`stacks:process-inbox`, `stacks:ingest-book`, and `stacks:using-stacks`.
`catalog-sources`, `audit-stack`, and `enrich-stack` are excluded because they
dispatch worker agents that Hermes does not provide. `ingest-book` also requires
the separately installed `doc-tools` package. The adapter docstring in
[`__init__.py`](../../__init__.py) owns the harness boundary.

### 5. A lookup miss is a tracked gap

When `lookup` cannot answer, it records the gap and reports that research and
cataloging need a compatible Stacks harness. Querying the library still tells
you what to grow next.

### 6. Operator approves what enters

The operator decides what the library is allowed to believe. `sources/incoming/`
is gitignored staging: files there are untracked, do not sync across machines,
and can be lost. A compatible Stacks harness must catalog approved staged
sources into tracked articles promptly.
