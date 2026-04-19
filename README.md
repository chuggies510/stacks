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
║   /stacks:ask "how does X work"  ──►  actual answer      ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

Your LLM has read everything. It remembers nothing.

Stacks fixes that. Drop source material into a folder. Run a skill. Claude reads it, extracts what matters, and writes structured topic guides. Next time you ask "how does X work," it reads from those guides instead of confidently hallucinating a blog post from 2019.

This is [Andrej Karpathy's LLM Wiki idea](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f): curated synthesis beats bulk context every time. Stacks is the Claude Code implementation.

---

## how it works

**Two repos. One rule.**

```
stacks/          ← this repo. the tool. public. knows nothing about you.
  skills/        ← /stacks:init-library, :new-stack, :catalog-sources, :ask, :audit-stack
  agents/        ← 5 LLM workers (concept identification, synthesis, validation, findings)
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
/stacks:catalog-sources rust-async           # process sources into article-per-concept wiki entries
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
| `/stacks:catalog-sources {stack}` | identify concepts in new sources, write article-per-concept wiki entries |
| `/stacks:ask {query}` | answer a question from your curated articles (works from any repo) |
| `/stacks:audit-stack {stack}` | validate articles against sources, synthesize glossary/invariants, find gaps |

---

## the pipeline

**catalog-sources** (run when you add sources):

```
sources/incoming/  →  [concept-identifier × N]  →  dev/extractions/
                              ↓
              [article-synthesizer × N]  →  articles/{slug}.md
                              ↓
              wikilink pass  →  cross-article links resolved
```

**audit-stack** (run when you want quality):

```
articles/  →  [validator]         →  inline [VERIFIED]/[DRIFT]/[UNSOURCED] marks
           →  [synthesizer]       →  glossary.md + invariants.md + contradictions.md
           →  [findings-analyst]  →  dev/audit/findings.md (gaps + research direction)
```

---

## agents

Five specialized agents power the pipeline:

| agent | role | used by |
|-------|------|---------|
| concept-identifier | identify concepts and extract claims from one source | catalog-sources |
| article-synthesizer | write/update an article-per-concept wiki entry | catalog-sources |
| validator | verify article claims against source material, apply inline marks | audit-stack |
| synthesizer | produce glossary.md, invariants.md, contradictions.md | audit-stack |
| findings-analyst | identify gaps, write findings.md, suggest research direction | audit-stack |

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

## browse with Obsidian

A library is a directory of markdown files with frontmatter and `[[wikilinks]]` — exactly the shape [Obsidian](https://obsidian.md) is built for. Open your library as a vault and you get graph view over the articles, backlinks, Dataview queries against frontmatter (e.g. "which articles have never been validated"), and one-click source capture via the [Web Clipper](https://obsidian.md/clipper) extension pointed at `sources/incoming/`. See `references/obsidian.md` for setup, Dataview query recipes, and conventions.

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
