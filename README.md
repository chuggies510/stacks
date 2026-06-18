# stacks

```
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║    📚  your brain,  but  it  actually  works             ║
║                                                          ║
║   sources/incoming/  ──►  agents  ──►  topic guides      ║
║                                ▲                         ║
║                         STACK.md schema                  ║
║                                                          ║
║   /stacks:lookup "how does X work"  ──►  actual answer      ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

Your LLM has read everything. It remembers nothing.

Stacks fixes that. Drop source material into a folder. Run a skill. Claude reads it, extracts what matters, and writes structured topic guides. Next time you ask "how does X work," it reads from those guides instead of confidently hallucinating a blog post from 2019.

This is [Andrej Karpathy's LLM Wiki idea](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f): curated synthesis beats bulk context every time. Stacks is the Claude Code implementation.

---

## the idea

The library is a structure Claude walks to reach an answer: `/stacks:lookup` → the library `catalog.md` → a stack's `index.md` → the article. Cataloging and auditing pay the reading cost once, up front: raw sources (PDFs, docs, web dumps) become small synthesized articles. Every later query is then a short walk to pre-digested knowledge, not a re-read of the originals and not a web search.

Two properties make that walk worth taking:

- **The path lands on the right article.** `index.md` is the routing map. The better each article is described there in the terms someone would actually ask about, the more reliably Claude recognizes the match by pattern rather than by literal keyword, and reads only what it needs.
- **The article is true.** `/stacks:lookup` reads articles, never the sources behind them, so an article that has drifted from its source becomes confident misinformation. `audit-stack` keeps the destination honest.

Everything else is optimized for one outcome: an agent in any repo reaches the exact knowledge it needs with the least friction and no false claims on the way.

---

## how it works

**Two repos. One rule.**

```
stacks/          ← this repo. the tool. public. knows nothing about you.
  skills/        ← /stacks:init-library, :new-stack, :catalog-sources, :ask, :audit-stack, :process-inbox
  agents/        ← 3 LLM workers (concept identification, synthesis, validation)
  scripts/       ← install.sh, init.sh, update.sh

~/my-library/    ← your repo. the content. private. the tool touches this.
  catalog.md     ← what stacks you have
  rust-async/
    STACK.md     ← schema: source tiers, topic template, filing rules
    index.md     ← map of contents, regenerated each catalog run
    sources/     ← raw material goes in here
    articles/    ← synthesized article-per-concept entries come out here
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
/stacks:catalog-sources rust-async           # process sources into article-per-concept wiki entries
```

Query from anywhere:

```
/stacks:lookup how does tokio schedule tasks across threads
```

---

## skills

Listed in lifecycle order: set up, route and ingest, maintain, query.

| skill | what it does | run from |
|-------|-------------|----------|
| `/stacks:init-library {path}` | create a knowledge library + private GitHub repo | anywhere |
| `/stacks:new-stack {name}` | scaffold a new stack from templates | inside the library |
| `/stacks:process-inbox` | route queued inbox files into the matching stacks | anywhere |
| `/stacks:catalog-sources {stack}` | identify concepts in new sources, write one article per concept | inside the library |
| `/stacks:audit-stack {stack}` | validate articles against sources, report drift / unsourced / stale | inside the library |
| `/stacks:lookup {query}` | answer a question from your curated articles | anywhere |

**run from** is where you can type the command, not a grouping by kind. `new-stack`, `catalog-sources`, and `audit-stack` act on the stack in your current directory, so run them inside the library. The other three don't need that: `init-library` takes a target path and writes the config, while `ask` and `process-inbox` read the library location from `~/.config/stacks/config.json`. By purpose `process-inbox` belongs with `catalog-sources`: it writes to the library and feeds the ingest. It only shares an invocation style with the read-only `ask`.

---

## the pipeline

**catalog-sources** (run when you add sources):

```
sources/incoming/  →  convert-sources (PDF/Office → text; skip+report images/scans)
                              ↓
              [source-extractor × N]  →  dev/extractions/
                              ↓
              [article-synthesizer × N]  →  articles/{slug}.md
                              ↓
              regenerate index.md (Map of Contents)
```

**audit-stack** (run when you want quality):

```
articles/  →  [validator]  →  fix source-contradictions in place + collect soft spots
           →  audit report  →  dev/audit/report.md (corrections applied / soft spots)
```

---

## agents

Three specialized agents power the pipeline:

| agent | role | used by |
|-------|------|---------|
| source-extractor | read one source, extract concepts and claims, map to article slugs, assign tiers | catalog-sources |
| article-synthesizer | write/update an article-per-concept wiki entry | catalog-sources |
| validator | verify article claims against source material, apply inline marks | audit-stack |

---

## file layout

| file | where | purpose |
|------|-------|---------|
| `STACK.md` | stack root | schema: source tiers, topic template, filing rules |
| `index.md` | stack root | source + topic catalog, regenerated on every ingest |
| `log.md` | stack root | append-only operation history |
| `catalog.md` | library root | index of all stacks |
| `{slug}.md` | `articles/` | one synthesized article-per-concept wiki entry |

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

Config lives at `~/.config/stacks/config.json`. Library path is set by `/stacks:init-library` and read by `/stacks:lookup` at runtime so it works from any repo.
