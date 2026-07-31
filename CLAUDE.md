# CLAUDE.md

Claude Code plugin for building and maintaining curated domain knowledge libraries.
Sources are ingested into topic guides queryable with `/stacks:lookup` from any repo.

This repo is the **stacks tool**. It is NOT a knowledge library, so no knowledge content
goes here. Libraries are created with `/stacks:init-library`. Front door for the
commands: `/stacks:using-stacks`.

Repo: git@github.com:chuggies510/stacks.git (private)

## Conventions

Skills live at `skills/{name}/SKILL.md`, frontmatter `name` + `description` only,
description starting "Use when...". Agents live in `agents/`, frontmatter `tools`
(comma-separated), `model`, `description`, with 3+ worked examples in the body.

Version bumps must land in all three manifests together, or the launcher shows a stale
version: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`,
`.codex-plugin/plugin.json`. Directory-source plugins load straight from the repo, so
`git pull` is the update mechanism, not `claude plugin update`.

Test by `bash scripts/install.sh`, restarting, then running init-library → new-stack →
catalog-sources → lookup against a throwaway path. Never commit test library content.

## Gotchas

Silent traps that exit 0.

**A gate that asks whether a record has the right SHAPE answers nothing about its
CONTENT, and the fix is never a better grep.** This repo's dominant self-inflicted
failure, hit five times in one session including inside gates written to prevent it: a
`grep -qE '^routing:'` asking whether a field exists, a count of returned concepts, a
`>= 15` line assertion, a guard asking whether *any* article carried a description (54
of 55 passed and the run was labelled good), a mutation sweep reporting SURVIVED when
the escaping had silently failed to apply the mutation at all. Every one reads green
with the exact defect it was written to catch sitting in the file. Three habits close
it: assert an anchor PHRASE plus explicit absent-classes, never a size; quantify
"every" by counting the population, never "any"; and prove a negative test is really
negative before believing it (an aborted run leaves the file unchanged exactly like a
correct run does). Real-corpus verification catches what fixtures cannot.

**Article frontmatter is not YAML — parse it with `article_field`, never a YAML
library.** 27 of the 1,174 corpus articles fail a real YAML parse (an unquoted `: ` in a
value, a leading `@`). The format is line-oriented `key: value` between two `---`, first
occurrence wins; `scripts/article-field.sh` is the single definition. The failure it
closes is WRONG text, not absent text: a scan not bounded by the closing `---` walks
into the body and returns body prose as a title, which then gets written into a stack
index and believed. Do not write a second reader, and do not reach for `yq`.

**`\t` in a single-quoted grep pattern behaves differently inside a script than through
the Bash tool.** The Bash tool wraps `grep` as a function running `ugrep`, which reads
`'\t'` in an ERE as a tab, so a pattern tested interactively MATCHES. That function is
not exported into the child bash a script spawns, where real GNU grep reads `'\t'` as a
literal `t` and the pattern never matches a tab-separated line. Always write a tab as
ANSI-C `$'\t'`, and verify a self-check by running the script, not by pasting the grep.
`awk -F'\t'` is unaffected.

**Shell env does not persist between a skill's Bash blocks; cwd does.** A `STACK=`,
`SCRIPTS_DIR=`, or `$(date +%s)` set in one block is EMPTY in the next. Re-derive it in
the block that needs it, or pass it through `$ARGUMENTS` of a nested skill, never an env
var. The three fan-out pipelines avoid this structurally by crossing state through
`dev/<phase>/{run.env,dispatch.tsv}` files; the trap still applies to any new skill prose.

**A sub-agent's success is observable only as returned text, never an exit code.** Gate
on the file it was told to write (size, mtime, content shape) — a hallucinated "success"
line cannot fake a freshly-written file.

**A verify/grade sub-agent over a large batch blows the 64K output cap and dies
mid-write**, having written NO file, silent to the orchestrator except the failure
notification. The cap scales with items × note verbosity, not a fixed count. Split at an
article boundary (N files aggregate the same as one) and instruct terse per-item notes.
Budget 150-200 records per agent for a grade-every-item pass.

**A template `.gitignore` self-shadows its own `.gitkeep`.** A bare `sources/trash/`
matches the placeholder too, so `git add` refuses, the template ships without it, and
downstream scaffolding has no empty dir to seed. Use `dir/*` plus `!dir/.gitkeep`, which
ignores contents while leaving the directory entry traversable. Diagnose with
`git check-ignore -v`.
