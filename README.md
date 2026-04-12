# stacks

```
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║    📚  your brain,  but  it  actually  works            ║
║                                                          ║
║   sources/incoming/  ──►  agents  ──►  topic guides      ║
║                                ▲                         ║
║                         STACK.md schema                  ║
║                                                          ║
║   /stacks:lookup "how does X work"  ──►  actual answer   ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

Your LLM has read everything. It remembers nothing.

Stacks fixes that. Drop source material into a folder. Run a skill. Claude reads it, extracts what matters, and writes structured topic guides. Next time you ask "how does X work," it reads from those guides instead of confidently hallucinating a blog post from 2019.

This is [Andrej Karpathy's LLM Wiki idea](https://github.com/karpathy/llm-wiki) — curated synthesis beats bulk context every time. Stacks is the Claude Code implementation.

---

## how it works

**Two repos. One rule.**

```
stacks/          ← this repo. the tool. public. knows nothing about you.
  skills/        ← /stacks:new, :ingest, :lookup, :refine
  agents/        ← 7 LLM workers (extractors, synthesizers, validators)
  scripts/       ← install.sh, init.sh, update.sh

~/my-library/    ← your repo. the content. private. the tool touches this.
  catalog.md     ← what stacks you have
  rust-async/
    STACK.md     ← schema: source tiers, topic template, filing rules
    index.md     ← what's been ingested
    sources/     ← raw material goes in here
    topics/      ← synthesized guides come out here
```

The tool never knows what's in your library. Your library doesn't care what version of the tool you're running. They're just files.

---

## quick start

```bash
# clone and install
git clone https://github.com/chuggies510/stacks ~/stacks
bash ~/stacks/scripts/install.sh
# restart claude code

# create your library
bash ~/stacks/scripts/init.sh ~/knowledge

# in your library repo, create a stack
/stacks:new rust-async

# edit rust-async/STACK.md — define your source hierarchy and topic template
# drop sources into rust-async/sources/incoming/

# process them
/stacks:ingest rust-async

# ask questions from any repo, ever
/stacks:lookup how does tokio schedule tasks across threads
```

---

## skills

| skill | what it does |
|-------|-------------|
| `/stacks:new {name}` | scaffold a new stack from templates |
| `/stacks:ingest {stack}` | process incoming sources → topic guides (2-wave pipeline) |
| `/stacks:lookup {query}` | answer a question from your curated guides |
| `/stacks:refine {stack}` | cross-reference, validate, synthesize glossary + findings (4-wave pipeline) |

---

## the pipeline

**ingest** (run when you add sources):

```
sources/incoming/  →  [topic-clusterer]  →  plan.md
                              ↓
              [topic-extractor × N]  →  dev/curate/extractions/
                              ↓
              [topic-synthesizer × N]  →  topics/{name}/guide.md
```

**refine** (run when you want quality):

```
topic guides  →  [cross-referencer]  →  contradictions
              →  [validator]         →  drift from sources
              →  [synthesizer]       →  glossary + invariants
              →  [findings-analyst]  →  gaps + research direction
```

---

## file layout

| file | where | purpose |
|------|-------|---------|
| `STACK.md` | stack root | schema: source tiers, topic template, filing rules |
| `index.md` | stack root | source + topic catalog, regenerated on every ingest |
| `log.md` | stack root | append-only operation history |
| `catalog.md` | library root | index of all stacks |
| `guide.md` | `topics/{name}/` | one synthesized topic guide |

---

## why not just use RAG

You could. RAG gives you chunks. Stacks gives you synthesis.

A topic guide written by a domain expert (even a synthetic one) is more useful than the top-3 cosine-similar paragraphs from a PDF you uploaded eight months ago and forgot about. Stacks forces structure up front. The payoff is lookup quality that doesn't degrade as your library grows.

Also you don't have to run a vector database.

---

## install

```bash
bash scripts/install.sh    # register plugin
bash scripts/init.sh ~/knowledge   # create library
bash scripts/uninstall.sh  # remove registration (library untouched)
bash scripts/update.sh     # git pull + refresh cache
```

Config lives at `~/.config/stacks/config.json`. Library path is set by `init.sh` and read by `/stacks:lookup` at runtime so it works from any repo.
