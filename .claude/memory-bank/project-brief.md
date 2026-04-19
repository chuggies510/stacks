# stacks Project Brief

## Mission

Claude Code plugin for building and maintaining curated domain knowledge libraries. Sources are cataloged into article-per-concept wiki entries (flat `articles/` directory, `[[wikilink]]` cross-links) that can be queried with `/stacks:ask` from any repo. An audit loop validates articles against sources and closes via a persistent `findings.md` that drives the next catalog cycle.

## Core Requirements

- **Library lifecycle**: scaffold new libraries (`init-library`), create stacks within them (`new-stack`), catalog sources into articles (`catalog-sources`), audit articles for drift and gaps (`audit-stack`), and query from any repo (`ask`).
- **Source routing**: inbox files from other sessions get classified and moved to the matching stack's incoming directory (`process-inbox`).
- **Feedback flywheel**: `audit-stack` produces `dev/audit/findings.md` with structured items (status enum including terminal `failed`, carry-forward by id); `catalog-sources` consumes that same findings.md at W0b to drive next-pass acquisitions and skip already-synthesized content. A5 archives by `cp`, not `mv`, so the active findings.md persists across cycles.
- **Harness engineering**: every agent dispatch has a `test -s` + mtime-newer-than-dispatch write-or-fail gate via `scripts/assert-written.sh`. Empty or stale pre-existing files halt the pipeline with a named error.
- **Agent-driven synthesis**: concept-identifier → article-synthesizer (catalog); validator → synthesizer → findings-analyst (audit). Slug immutability prevents silent cross-file drift.
- **Template-driven**: new libraries and stacks are scaffolded from templates in `templates/library/` and `templates/stack/`.
- **Directory-source marketplace**: the plugin loads directly from this repo via `extraKnownMarketplaces`. `git pull` is the update mechanism.

## Key Constraints

- This repo is the tool. It is NOT a knowledge library. No knowledge content committed here.
- Skill frontmatter uses only `name` and `description` (no `version`, `allowed-tools`, `thinking`).
- Description lines start with "Use when..." for trigger matching.
- `plugin.json` and `marketplace.json` versions must stay in sync.
- Agents must write outputs to files, not return content in chat. Enforced by the write-or-fail gate; assert-written.sh's mtime check catches stale pre-existing files that would otherwise pass `test -s` silently.
- Articles are flat (no typed subdirs), 300-800 words soft cap (stretch 1200), `[[wikilinks]]` via deterministic post-write bash pass (not agent output).

## Success Metrics

- Libraries can be created, cataloged, audited, and queried end-to-end without editing files by hand.
- Articles are accurate against their source material (validator inline marks + findings-analyst carry-forward surface drift across cycles).
- Users can find domain answers via `/stacks:ask` faster than searching raw sources.
- Audit findings queue closes rather than accumulating: every open item reaches a terminal status across catalog → audit → catalog cycles.
