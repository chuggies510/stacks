# stacks

A Karpathy-inspired knowledge base system for Claude Code. Andrej Karpathy's LLM Wiki concept holds that LLMs work best when given curated, well-structured knowledge rather than raw dumps — organized synthesis beats bulk context every time. Stacks applies that principle to your personal knowledge: you build a library of topic guides synthesized from real sources, and any Claude Code session can query them directly, getting dense, relevant knowledge instead of raw links.

## Two-repo model

The `stacks` repo is the *tool*: skills, agents, scripts, and templates. It is public and FOSS. It knows nothing about your knowledge.

Your library repo is the *content*: stacks, topic guides, source logs, and the catalog. It is private and personal. The tool operates on it; the tool never contains it.

## Quick start

```bash
# 1. Install the plugin
git clone https://github.com/chuggies510/stacks ~/path/to/stacks
cd ~/path/to/stacks
bash scripts/install.sh

# 2. Initialize your library
bash scripts/init.sh ~/knowledge

# 3. Create a new stack
/stacks:new rust-async

# 4. Drop source files into the stack
# Add markdown, text, PDFs, etc. to {stack}/sources/incoming/

# 5. Ingest sources
/stacks:ingest

# 6. Query your library
/stacks:lookup how does tokio schedule tasks
```

## Skills

| Skill | Description |
|-------|-------------|
| `/stacks:ingest` | Process raw sources in `sources/incoming/`, extract topics, update guides |
| `/stacks:refine` | Re-synthesize one or more topic guides from accumulated source extractions |
| `/stacks:lookup` | Query the library and surface relevant topic guides for a question |
| `/stacks:new` | Scaffold a new stack directory from the stack template |

## File conventions

| File | Location | Purpose |
|------|----------|---------|
| `STACK.md` | Stack root | Stack schema: name, domain, description, config |
| `index.md` | Stack root | Source and topic catalog for this stack |
| `log.md` | Stack root | Operation history: ingests, refines, lookups |
| `catalog.md` | Library root | Library-level index of all stacks |
| `guide.md` | `topics/{name}/` | Synthesized topic guide for one topic |

