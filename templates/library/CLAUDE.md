# Library CLAUDE.md

## What This Is

This is a knowledge library managed by the stacks plugin. It contains one or more
knowledge collections ("stacks"), each with curated sources and LLM-synthesized
topic guides.

## Conventions

- **Sources are immutable.** Drop raw material in `{stack}/sources/incoming/`.
  The ingest process files them by origin and extracts knowledge into topic guides.
- **Topics are LLM-maintained.** Do not hand-edit topic guides. Use `/stacks:ingest-sources`
  to update them from sources.
- **index.md is the stack index.** Each stack's index.md lists all sources and topics
  for that stack. Ingest regenerates it. Do not edit manually.
- **log.md is append-only.** Records what operations happened and when.
- **STACK.md is the schema.** Defines source hierarchy, topic template, and filing
  rules for that stack. Edit this to change how the stack is curated.

## Workflows

- `/stacks:ingest-sources {stack}` — process new sources into topic guides
- `/stacks:refine-stack {stack}` — check quality, completeness, suggest research direction
- `/stacks:new-stack {name}` — scaffold a new empty stack
- `/stacks:ask {query}` — query this library from any repo
