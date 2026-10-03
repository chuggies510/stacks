# stacks Project Brief

## Mission

Claude Code plugin for building and maintaining curated domain knowledge libraries. Sources are cataloged into article-per-concept wiki entries (flat `articles/` directory) that can be queried with `/stacks:lookup` from any repo. An audit pass validates each article against its cited sources and writes a fresh drift report.

## Design principle (north star)

The library is a structure an LLM walks to reach knowledge: `lookup` → `catalog.md` → stack `index.md` → article. Catalog and audit pay the source-reading cost once, so every later query is a cheap walk to pre-digested, cited knowledge instead of re-reading sources or searching the web. Design the whole system to maximize two things:

- **Frictionless path** — each hop is encoded so the LLM lands on the right article by recognition (its native pattern-matching), not literal keyword match. `index.md` is the routing map; the design goal is per-article routing lines (what the article covers, the questions it answers) so retrieval is recognition-based.
- **Truthful destination** — `lookup` reads articles, not the sources behind them, so the article must stay accurate to its sources. `audit-stack` guards this.

Recognition-based retrieval shipped in #59: `lookup` walks the per-article `routing:` lines projected into `index.md`. The remaining truthful-destination gaps are durable audit findings for cross-article structural problems (#148) and systematic source-to-source contradictions (#149).

## Core Requirements

- **Library lifecycle**: scaffold new libraries (`init-library`), create stacks within them (`new-stack`), catalog sources into articles (`catalog-sources`), audit articles for drift against their sources (`audit-stack`), and query from any repo (`lookup`).
- **Source routing**: inbox files from other sessions get classified and moved to the matching stack's incoming directory (`process-inbox`, routing only).
- **Stateless audit**: `audit-stack` re-checks every article against its cited sources, fixes any claim that contradicts its source in place, collects soft spots (claims not tied to a source), and rebuilds `dev/audit/report.md` from this run's findings. No inline body marks, no persistent findings ledger, no carry-forward, no convergence loop.
- **Harness engineering**: every agent dispatch is gated by `gate-batch.sh` — each expected output file must be non-empty AND freshly written (mtime newer than the captured dispatch epoch), plus a content-shape check. Sub-agents return only text, so the file-based gate is the success signal.
- **Agent-driven synthesis**: source-extractor → article-synthesizer (catalog); validator (audit). Slug immutability prevents silent cross-file drift.
- **Template-driven**: new libraries and stacks are scaffolded from templates in `templates/library/` and `templates/stack/`.
- **Directory-source marketplace**: the plugin loads directly from this repo via `extraKnownMarketplaces`. `git pull` is the update mechanism.

## Key Constraints

- This repo is the tool. It is NOT a knowledge library. No knowledge content committed here.
- Skill frontmatter uses only `name` and `description` (no `version`, `allowed-tools`, `thinking`).
- Description lines start with "Use when..." for trigger matching.
- `plugin.json` and `marketplace.json` versions must stay in sync.
- Agents must write outputs to files, not return content in chat. Enforced by `gate-batch.sh`'s size+mtime check (size alone passes a stale pre-existing file; mtime alone passes an empty write).
- Articles are flat (no typed subdirs), length follows the grounded claims (no word-count target, soft cap ~1200 words for complex topics), plain markdown with inline `[source-slug]` citations.

## Success Metrics

- Libraries can be created, cataloged, audited, and queried end-to-end without editing files by hand.
- Articles are accurate against their source material (the validator fixes source-contradictions in place; the audit report surfaces corrections applied + soft spots each run).
- Users can find domain answers via `/stacks:lookup` faster than searching raw sources.
