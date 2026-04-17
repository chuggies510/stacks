# Plan: stacks:process-inbox

**Issue**: chuggies510/stacks#12
**Spec**: dev/feature-dev/2026-04-17-process-inbox/spec.md

## Tasks

### Task 1: Add inbox scaffolding to library template

Files:
- `templates/library/inbox/.gitkeep` (create)
- `templates/library/.gitignore` (edit — add `inbox/` pattern)

No dependencies.

### Task 2: Write skills/process-inbox/SKILL.md

Single file implementing the full skill. Structure:

- Frontmatter: name + description only, "Use when..." trigger
- Step 0: Telemetry (boilerplate from existing skills)
- Step 1: Find the library (config-based, Pattern A from `ask`)
- Step 2: Enumerate stacks — find subdirs with STACK.md, gate on zero stacks
- Step 3: Enumerate inbox — list `$LIBRARY/inbox/*.md`, gate on no inbox dir, gate on empty inbox
- Step 4: Read stack scopes — read STACK.md from each stack (for LLM classification context)
- Step 5: Classify and route — for each inbox file, read header block (H1 + Source + Extracted from + first 5 `##` headings), apply semantic reasoning against stack scopes:
  - One clear match: `mkdir -p {stack}/sources/incoming/ && mv` with collision handling (counter-append)
  - Tie (two+ equal matches): leave in place, record both candidate stacks
  - No match: leave in place, record as unmatched
- Step 6: Commit (if any files moved) or skip commit (if none moved)
- Step 7: Report — table of routed files, list of unmatched files with tie candidates, per-stack next-step suggestions (`/stacks:ingest-sources {stack}`)

No dependencies.

### Task 3: Version bump and CHANGELOG

Files:
- `.claude-plugin/plugin.json` — bump version to `0.8.0`
- `.claude-plugin/marketplace.json` — bump plugins[0].version to `0.8.0`
- `CHANGELOG.md` — prepend entry

No dependencies on Task 1 or 2 logically, but should run after both to capture the full change in the CHANGELOG entry.

Depends on: Task 1, Task 2.
