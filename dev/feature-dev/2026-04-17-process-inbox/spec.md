# Spec: stacks:process-inbox

**Issue**: chuggies510/stacks#12

## What we're building

A `stacks:process-inbox` skill that reads all files in a library's `inbox/` directory, classifies each against existing stacks using content and source metadata, moves matched files to the target stack's `sources/incoming/`, and reports unmatched files without moving them.

## Exploration findings

**Skill format** (`skills/{name}/SKILL.md`):
- Frontmatter: `name` and `description` only. Description starts with "Use when...".
- Body: `## Step N: Title` headings. Bash for deterministic logic, prose for judgment.
- Step 0 is always the telemetry boilerplate (identical across all skills).

**Library discovery**: two patterns in existing skills.
- Pattern A (config-based): reads `~/.config/stacks/config.json` → `library` field. Used by `ask`, which runs from any repo. Correct for `process-inbox` — inbox processing is a library-management operation that makes sense from any working directory.
- Pattern B (cwd-based): checks `catalog.md` exists in `$PWD`. Used by `ingest-sources`, `refine-stack`. Wrong here — would require the user to `cd` to the library first.

**Stack discovery**: `find "$LIBRARY" -maxdepth 1 -type d` filtered by existence of `STACK.md` in each subdir. STACK.md contains the stack's scope, source hierarchy, and filing rules — the primary classification signal.

**Inbox file format** — consistent metadata at the top of every file:
- **Filename**: `{repo}-s{session}-{topic-slug}.md` (e.g., `la-posada-s20-dhw-scope-gpr-brief-drawing-review.md`)
- **H1 title** (line 1): `# {Repo} — S{N} — {human-readable topic}`
- **Source line** (line 3): `Source: {repo} S{N} (YYYY-MM-DD)`
- **Extracted from** (line 4): names the artifact (CLAUDE.md Gotchas, decision log, GitHub issue, etc.)
- **Section headings**: `## {Principle}` — the most semantically dense classification signal

No explicit `stack:` YAML tag exists in inbox files. Classification is semantic.

**Classification signals** (in decreasing specificity):
1. Section heading content — most reliable (e.g., "California Energy Code: DHW Replacement as Alteration" → mep-stack)
2. Topic slug in filename (e.g., `dhw-scope-gpr-brief-drawing-review` → MEP domain)
3. H1 human-readable topic
4. Source repo name (`la-posada`, `meap2-it` → engineering; `ChuggiesMart`, `chuggies` → plugin tooling)
5. Full body prose

**Versioning**: `plugin.json` (0.7.2) and `marketplace.json` plugins[0].version (0.6.0) are currently out of sync. Both must be bumped to the same value. No `sync-versions.sh` in the stacks repo — bump both manually.

## Architecture decision

Single `skills/process-inbox/SKILL.md` file. Config-based library discovery (Pattern A). Bash for path resolution and file operations; LLM prose for semantic classification judgment. No helper script — the judgment step cannot be scripted.

**Classification approach**: read each inbox file's header block (H1 + Source + Extracted from + first 5 `##` headings via `grep "^## " | head -5`). Read STACK.md from each stack for scope context. Apply semantic reasoning to match file → stack. Low-confidence cases stay in inbox and are reported.

**Unmatched handling**: leave file in place, report it clearly. No silent drops, no guessing.

**Tie-break policy**: if a file matches two stacks with equal confidence, leave it in inbox and report both candidate stacks so the user can decide. Never guess on a tie.

**Filename collisions**: before moving, check if a file with the same name already exists in `{stack}/sources/incoming/`. If yes, append a counter (`-2`, `-3`, etc.) following the same pattern as `ingest-sources` Step 1.5. Never overwrite.

**`sources/incoming/` creation**: `mkdir -p {stack}/sources/incoming/` before each move. Don't assume the directory exists.

**Commit**: after routing, if any files were moved, commit the moves (inbox removals + incoming additions) in one commit. If nothing was moved (all unmatched or inbox was empty), skip the commit and tell the user.

**`inbox/` not found**: if `$LIBRARY/inbox/` does not exist, tell the user "No inbox/ directory found in your library. Create inbox/ and drop session extract files there to process them." Do not create the directory — that is the scaffolding concern (see Done when). Stop.

**Zero stacks**: if no stacks are found in the library, tell the user "No stacks in your library yet. Run /stacks:new-stack {name} first." Stop.

**Relationship to ingest**: `process-inbox` is the missing link in a two-command sequence. It routes files to `sources/incoming/`. The user must still run `/stacks:ingest-sources {stack}` per affected stack to synthesize guides. The skill output must make this clear.

## Constraints

- Must follow existing skill frontmatter rules exactly (name + description only, "Use when..." trigger)
- Step 0 telemetry is mandatory and must match existing boilerplate exactly
- Only reads header block for classification — not full file body (efficiency)
- Never moves a file unless classification confidence is clear; never overwrites on collision
- Must run from any working directory (config-based library discovery)
- Version bump required: `plugin.json` and `marketplace.json` both to `0.8.0`; verify both match after editing

## Scaffolding change

Add `templates/library/inbox/.gitkeep` so that `init-library` creates the inbox directory on every new library. Add `inbox/` to `templates/library/.gitignore` (the files are transient routing artifacts, not permanent library content).

## Done when

- [ ] `skills/process-inbox/SKILL.md` exists with correct frontmatter and step structure
- [ ] Skill finds the library via `~/.config/stacks/config.json`
- [ ] Skill gates on zero stacks and missing inbox/ with clear user messages
- [ ] Skill enumerates stacks by finding subdirs with `STACK.md`, reads STACK.md scope for each
- [ ] Skill reads header block (H1 + Source + Extracted from + first 5 `##` headings) per inbox file
- [ ] Skill applies semantic classification: one stack = move; tie = leave + report candidates; no match = leave + report
- [ ] Skill uses `mkdir -p` before each move; handles filename collisions with counter-append
- [ ] Skill skips commit if nothing was moved; commits moves otherwise
- [ ] Skill reports: what was moved where, what was left behind (with tie candidates if applicable), next steps
- [ ] `templates/library/inbox/.gitkeep` added; `inbox/` added to `templates/library/.gitignore`
- [ ] `plugin.json` and `marketplace.json` both at `0.8.0`, verified equal
- [ ] CHANGELOG updated
- [ ] Committed and pushed
