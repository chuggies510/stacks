# stacks Project Brief

## Mission

Claude Code plugin for building and maintaining curated domain knowledge libraries. Sources are cataloged into article-per-concept wiki entries (flat `articles/` directory) that can be queried with `/stacks:ask` from any repo. An audit pass validates each article against its cited sources and writes a fresh drift report.

## Core Requirements

- **Library lifecycle**: scaffold new libraries (`init-library`), create stacks within them (`new-stack`), catalog sources into articles (`catalog-sources`), audit articles for drift against their sources (`audit-stack`), and query from any repo (`ask`).
- **Source routing**: inbox files from other sessions get classified and moved to the matching stack's incoming directory (`process-inbox`, routing only).
- **Stateless audit**: `audit-stack` re-marks every article (`[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]`) against its cited sources and rebuilds `dev/audit/report.md` from those marks each run. No persistent findings ledger, no carry-forward, no convergence loop.
- **Harness engineering**: every agent dispatch is gated by `gate-batch.sh` — each expected output file must be non-empty AND freshly written (mtime newer than the captured dispatch epoch), plus a content-shape check. Sub-agents return only text, so the file-based gate is the success signal.
- **Agent-driven synthesis**: concept-identifier → article-synthesizer (catalog); validator (audit). Slug immutability prevents silent cross-file drift.
- **Template-driven**: new libraries and stacks are scaffolded from templates in `templates/library/` and `templates/stack/`.
- **Directory-source marketplace**: the plugin loads directly from this repo via `extraKnownMarketplaces`. `git pull` is the update mechanism.

## Key Constraints

- This repo is the tool. It is NOT a knowledge library. No knowledge content committed here.
- Skill frontmatter uses only `name` and `description` (no `version`, `allowed-tools`, `thinking`).
- Description lines start with "Use when..." for trigger matching.
- `plugin.json` and `marketplace.json` versions must stay in sync.
- Agents must write outputs to files, not return content in chat. Enforced by `gate-batch.sh`'s size+mtime check (size alone passes a stale pre-existing file; mtime alone passes an empty write).
- Articles are flat (no typed subdirs), 300-800 words soft cap (stretch 1200), plain markdown with inline `[source-slug]` citations.

## Success Metrics

- Libraries can be created, cataloged, audited, and queried end-to-end without editing files by hand.
- Articles are accurate against their source material (validator inline marks + the drift report surface drift each audit run).
- Users can find domain answers via `/stacks:ask` faster than searching raw sources.
