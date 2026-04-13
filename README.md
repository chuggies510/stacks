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
║   /stacks:ask "how does X work"  ──►  actual answer   ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

Your LLM has read everything. It remembers nothing.

Stacks fixes that. Drop source material into a folder. Run a skill. Claude reads it, extracts what matters, and writes structured topic guides. Next time you ask "how does X work," it reads from those guides instead of confidently hallucinating a blog post from 2019.

This is Andrej Karpathy's LLM Wiki idea: curated synthesis beats bulk context every time. Stacks is the Claude Code implementation.

---

## how it works

**Two repos. One rule.**

```
stacks/          ← this repo. the tool. public. knows nothing about you.
  skills/        ← /stacks:init-library, :new-stack, :ingest-sources, :ask, :refine-stack
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
```

Then from any Claude Code session:

```
/stacks:init-library ~/knowledge            # create library + private GitHub repo
```

Open a session in your new library:

```
/stacks:new-stack rust-async               # scaffold a stack
# edit rust-async/STACK.md — define source hierarchy, topic template, filing rules
# drop sources into rust-async/sources/incoming/
/stacks:ingest-sources rust-async            # process sources into topic guides
```

Query from anywhere:

```
/stacks:ask how does tokio schedule tasks across threads
```

---

## skills

| skill | what it does |
|-------|-------------|
| `/stacks:init-library {path}` | create a knowledge library with private GitHub repo |
| `/stacks:new-stack {name}` | scaffold a new stack from templates |
| `/stacks:ingest-sources {stack}` | detect new sources, classify, extract, synthesize into topic guides |
| `/stacks:ask {query}` | answer a question from your curated guides (works from any repo) |
| `/stacks:refine-stack {stack}` | cross-reference, validate, synthesize glossary, find gaps |

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

## agents

Seven specialized agents power the pipeline:

| agent | role | used by |
|-------|------|---------|
| topic-clusterer | group sources into topic clusters, produce plan.md | ingest |
| topic-extractor | extract claims and data from sources for one topic group | ingest |
| topic-synthesizer | write/update a topic guide from extracted knowledge | ingest |
| cross-referencer | find contradictions and gaps across topic guides | refine |
| validator | verify topic guide claims against source material | refine |
| synthesizer | produce cross-domain artifacts (glossary, invariants) | refine |
| findings-analyst | identify gaps, suggest research direction | refine |

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
git clone https://github.com/chuggies510/stacks ~/stacks
bash ~/stacks/scripts/install.sh    # register plugin with Claude Code
# restart claude code
```

After install, everything runs through skills. No more bash commands needed.

**Other lifecycle scripts** (for maintainers):

```bash
bash scripts/uninstall.sh  # remove plugin registration (library untouched)
bash scripts/update.sh     # git pull (directory-source plugins update in place)
```

**Requirements**: [Claude Code](https://docs.anthropic.com/en/docs/claude-code), `gh` CLI (authenticated), `jq`.

Config lives at `~/.config/stacks/config.json`. Library path is set by `/stacks:init-library` and read by `/stacks:ask` at runtime so it works from any repo.
