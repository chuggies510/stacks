# stacks Project Brief

## Mission

Claude Code plugin for building and maintaining curated domain knowledge libraries. Sources are ingested into topic guides that can be queried with `/stacks:ask` from any repo.

## Core Requirements

- **Library lifecycle**: scaffold new libraries (`init-library`), create stacks within them (`new-stack`), ingest sources into topic guides (`ingest-sources`), refine via cross-reference and validation (`refine-stack`), and query from any repo (`ask`).
- **Source routing**: inbox files from other sessions get classified and moved to the matching stack's incoming directory (`process-inbox`).
- **Agent-driven synthesis**: topic-clusterer → topic-extractor → topic-synthesizer → cross-referencer → validator → findings-analyst pipeline.
- **Template-driven**: new libraries and stacks are scaffolded from templates in `templates/library/` and `templates/stack/`.
- **Directory-source marketplace**: the plugin loads directly from this repo via `extraKnownMarketplaces` — `git pull` is the update mechanism.

## Key Constraints

- This repo is the tool. It is NOT a knowledge library. No knowledge content committed here.
- Skill frontmatter uses only `name` and `description` (no `version`, `allowed-tools`, `thinking`).
- Description lines start with "Use when..." for trigger matching.
- `plugin.json` and `marketplace.json` versions must stay in sync.
- Agents must write outputs to files, not return content in chat (open bugs: findings-analyst #15, validator #11).

## Success Metrics

- Libraries can be created, populated, and queried end-to-end without editing files by hand.
- Topic guides are accurate against their source material (validator catches drift).
- Users can find domain answers via `/stacks:ask` faster than searching raw sources.
