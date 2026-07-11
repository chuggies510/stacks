---
name: ingest-book
description: |
  Use when the user wants to convert a whole handbook, standard, or reference PDF into
  a knowledge stack chapter by chapter — "ingest this handbook", "convert the ASPE PEDH
  into the library", "add this design manual as reference", "book-scale faithful
  extraction". Parses the table of contents into a chapter page-map (operator confirms),
  runs each chapter through doc-tools extract-pdf faithful mode, and files the gated
  output into the stack's deep-reference tier with printed-page provenance. Must be run
  from within a library repo. Distinct from catalog-sources (which synthesizes articles
  from staged sources) — ingest-book produces reference-grade handbook chapters, the
  shelf lookup reads behind the articles.
---

# Ingest Book

Convert a book-scale PDF into the deep-reference tier, reusing the proven single-chapter
faithful pipeline (doc-tools `extract-pdf`). You confirm the chapter map once, then each
chapter is sliced, dual-converted, patch-agent-repaired, gated by `verify-merge.py`, and
filed.

Schema for the tier this produces (layout, chapter frontmatter, index format):
the plugin's `references/reference-tier.md`. Read it before filing.

## Run mode: serial or workflow batch

Two ways to run Step 3, same per-chapter mechanics either way:

- **Serial (Step 3)** — one chapter at a time, fully operator-visible. Correct for 1–3
  chapters, or when you want to watch each gate. A 10+ chapter book run serially will
  compact the orchestrating session's context repeatedly (many tool round-trips per
  chapter), so it is slow wall-clock for a whole volume.
- **Workflow batch (Step 3B)** — pre-run the deterministic mechanical prep for every
  chapter in Bash, then fan the model work (patch + equation audit) out across chapters
  with a `Workflow`, gate and file outside it. Right for a whole volume: fastest, keeps
  the orchestrator's context clean, one bad chapter is skipped not fatal. **Needs the
  operator's explicit multi-agent opt-in** (the harness bars launching `Workflow` without
  it) — offer it when the confirmed map has many chapters.

Pick the mode after Step 2 (map confirmed). The default for a full volume is the workflow
batch; drop to serial for a handful of chapters.

## Step 0: Telemetry

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
SKILL_NAME="stacks:ingest-book" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

## Step 1: Gate check + parse arguments

`$ARGUMENTS` is `{stack} {pdf-path} [book-slug]`.

```bash
if [[ ! -f "catalog.md" ]]; then
  echo "ERROR: catalog.md not found. Run /stacks:ingest-book from inside a library repo."
  exit 1
fi
# Parse {stack} {pdf-path} [book-slug]. Book PDFs commonly have spaces in the path
# ("ASPE PEDH Vol 2.pdf"), so don't naively word-split into three: STACK is the first
# token, and the optional trailing book-slug is a bare kebab token (no dot, no slash) —
# everything between is the PDF path, spaces and all.
STACK="${ARGUMENTS%% *}"
REST="${ARGUMENTS#"$STACK"}"; REST="${REST# }"
LAST="${REST##* }"
if [[ "$REST" == *" "* && "$LAST" =~ ^[a-z0-9][a-z0-9-]*$ && ! -e "$LAST" ]]; then
  BOOK_SLUG="$LAST"; PDF="${REST% *}"
else
  BOOK_SLUG=""; PDF="$REST"
fi
if [[ -z "$STACK" || -z "$PDF" ]]; then
  echo "ERROR: usage: /stacks:ingest-book {stack} {pdf-path} [book-slug]"; exit 1
fi
[[ -d "$STACK" && -f "$STACK/STACK.md" ]] || { echo "ERROR: no such stack: $STACK (run /stacks:new-stack $STACK first)"; exit 1; }
[[ -f "$PDF" ]] || { echo "ERROR: PDF not found: $PDF"; exit 1; }
# Default the book slug from the PDF filename if the operator did not pass one.
[[ -z "$BOOK_SLUG" ]] && BOOK_SLUG=$(basename "$PDF" .pdf | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')
echo "STACK=$STACK  PDF=$PDF  BOOK_SLUG=$BOOK_SLUG"
command -v pdftotext >/dev/null || echo "WARN: pdftotext not on PATH (poppler-utils) — TOC parse in Step 2 needs it"
```

Confirm `BOOK_SLUG` with the operator if it was derived (it names the reference dir and prefixes every chapter file). Carry `STACK`, `PDF`, `BOOK_SLUG` forward as literals — shell env does not survive between bash blocks (re-set them at the top of later fences).

## Step 2: Parse the TOC into a chapter map, operator confirms

Book conversion is expensive (~190k tokens/chapter). The chapter map is confirmed **once, before any conversion**, so a wrong page range is caught before it costs a run.

1. Find the TOC pages (usually the front matter). Extract their text:
   ```bash
   PDF="/abs/path.pdf"   # re-set
   pdftotext -f 1 -l 20 "$PDF" - | sed -n '1,400p'
   ```
   Adjust `-f/-l` until you see the full contents listing. If the operator already gave
   a chapter→page map (common for a known book), skip the parse and use theirs.

2. Establish the **printed→PDF page offset**. The number printed on a page rarely equals
   its position in the PDF (front matter shifts it). Pick one chapter's known printed
   start page, find that page in the PDF (`pdftotext -f N -l N`), and compute
   `offset = pdf_page - printed_page`. Confirm the offset holds for a second chapter — a
   single constant offset is the normal case (e.g. ASPE PEDH Vol 2: constant +20).

3. Present the map for confirmation as a table the operator can correct:

   | # | Chapter title | Slug | Printed pp. | PDF pp. (printed+offset) |
   |---|---------------|------|-------------|--------------------------|
   | 4 | Piping Systems | vol2-ch04-piping-systems | 90–120 | 110–140 |

   - Slug form: `[vol{V}-]ch{NN}-{kebab-title}` (drop the `vol` segment for a single-volume book).
   - Each chapter's end is the next chapter's start minus one — EXCEPT the last content
     chapter, which has no next chapter. Pin its end explicitly against where back matter
     begins (Index, glossary, appendices), and do NOT ingest that back matter as a chapter.
     A cumulative index often starts a few pages before you'd guess from a single probe, so
     confirm the exact boundary by probing the pages just before the presumed end for
     index/glossary bleed (alphabetized entries, "V1:NNN" page refs). Getting this wrong
     pulls index pages into the last chapter — which then produces zero page anchors, the
     first visible symptom.
   - The operator may narrow the run to a subset ("just Ch 4 and 5") — honor it; the map is the work-list for Step 3.

   **Do not proceed to Step 3 until the operator confirms the map.**

## Step 3: Convert + file each chapter (sequential)

For **each** chapter in the confirmed map, in order:

### 3a. Run doc-tools faithful mode for this chapter

Invoke the **doc-tools `extract-pdf` skill in faithful mode** for this one chapter, with:
- `INFILE` = the book PDF (absolute path)
- `CHAPTER` = the chapter slug (so each chapter gets its own working dir)
- `FIRSTPAGE` / `LASTPAGE` = the chapter's **PDF** page range (printed + offset)
- `FIRSTPRINTED` = the chapter's first **printed** page (pins page arithmetic + citations)

Run faithful mode's full pipeline (slice F1 → dual convert F2 → prep F3 → seed F4 →
patch agent F5 → equation audit F5.5 → external gate F6). Do not reimplement it — the
extract-pdf skill owns those mechanics, including the `verify-merge.py` gate and the
single sonnet escalation on a FAIL. It writes the gated result to a deterministic path:

```bash
INFILE="/abs/path.pdf"; CHAPTER="vol2-ch04-piping-systems"   # re-set per chapter
OUTDIR="${HOME}/.cache/doc-tools/extract-pdf/$(basename "$INFILE" .pdf)-${CHAPTER}-faithful"
echo "gated output: $OUTDIR/merged.md"
```

**Gate policy:** file a chapter only if faithful mode reported `GATE: PASS`. If a chapter
FAILs the gate twice (patch + one sonnet escalation), **skip it, record it in a
failed-chapters list, and continue** — one bad chapter must not abort the book. Report
skipped chapters at the end so the operator can re-run them individually.

### 3b. File the gated chapter into the reference tier

Prepend provenance frontmatter to the gated `merged.md` and write it into the tier.
Frontmatter fields and their meaning are defined in `references/reference-tier.md`; emit
exactly these (fill from the chapter map + the run):

```yaml
---
book: {full book title}
book_slug: {BOOK_SLUG}
volume: {N, omit for single-volume books}
chapter: {N}
title: {chapter title}
topics: {short keyword phrase — what the chapter covers, in an asker's words}
edition: {edition/year if known}
printed_pages: "{first}-{last}"
pdf_pages: "{first}-{last}"
converters: pymupdf4llm layout-on + layout-off + pdfplumber
merge_model: {haiku/low, or sonnet/low if escalated}
gate: PASS
last_ingested: {today YYYY-MM-DD}
---
```

- `topics` is load-bearing: it is the routing line `/stacks:lookup` recognizes against in
  the reference index. Write it from the chapter's actual headings/content, not the title alone.
- Write to `{STACK}/reference/{BOOK_SLUG}/{slug}.md`:
  ```bash
  STACK="..."; BOOK_SLUG="..."; SLUG="vol2-ch04-piping-systems"   # re-set
  mkdir -p "$STACK/reference/$BOOK_SLUG"
  # then Write the frontmatter + gated body to "$STACK/reference/$BOOK_SLUG/$SLUG.md"
  ```

## Step 3B: Workflow batch (parallel, opt-in) — alternative to Step 3

Same mechanics as Step 3, reorganized so the model work runs concurrently. The pipeline
splits into three parts by WHERE each runs: mechanical prep and the gate are Bash you run
in the orchestrator (a `Workflow` script has no filesystem or Bash access); only the two
model passes go inside the workflow.

**1. Pre-run mechanical prep (F1–F4) for every confirmed chapter, in one Bash loop.** For
each chapter run the faithful steps F1 slice → F2 dual-convert → F3 `faithful-prep.py` →
F4 seed `merged.md`, into that chapter's deterministic `OUTDIR`. Drive the doc-tools
scripts from SOURCE if the plugin cache may lag the fix you need (a `/reload-plugins`
updates the cache on disk but a running session keeps the old copy until restart). After
prep, read each `worklist.json` and emit a manifest row per chapter carrying: `outdir`,
`firstprinted`, `offset`, and the `tables` / `equations` / `figures` / `hotspot_tables` /
`pdfplumber_crosscheck` id lists. This manifest is the workflow's input.

**2. Split prose-only chapters out.** A chapter with zero tables, equations, AND figures
has no model work — the patch agent would do nothing. Gate it directly (it passes on
prose alone) and file it in Step 3b; keep it OUT of the workflow. Only chapters with at
least one table/equation/figure go to the workflow.

**3. Fan the model work out with a `Workflow`.** Pass the model-work manifest rows as
`args` (defensively `JSON.parse` if it arrives stringified). `pipeline` over the chapters,
two stages, each chapter independent:
- stage 1 — `agent(patchPrompt(ch), {model:'haiku', effort:'low', agentType:'general-purpose', phase:'Patch'})`.
  Build `patchPrompt` from the doc-tools F5 template with this chapter's slots filled;
  DROP a task whose inventory is empty (no tables → no TABLES task, etc.), keep TASK
  SELF-CHECK always.
- stage 2 — only if `ch.equations.length`, `agent(auditPrompt(ch), {model:'sonnet', effort:'low', agentType:'general-purpose', phase:'Audit'})`
  from the F5.5 template. Equations are the one element the gate cannot verify, so this
  pass is mandatory for equation-bearing chapters.

Agents edit each chapter's own `merged.md` in place — different files, so no worktree
isolation is needed. The workflow does NOT gate (never trust an agent self-report).

**4. Gate and file each chapter yourself (Bash), after the workflow returns.** Run
`verify-merge.py` on every chapter (prose-only ones from step 2 included). `PASS` → file
per Step 3b. `FAIL` → escalate once with sonnet, by FAIL class:
- **A count FAIL** (`tables N/M`, `figures N/M`, an equation body) — the agent under-did
  its work. Re-dispatch a sonnet patch on the CURRENT `merged.md` so rebuilt tables and
  the equation audit survive; tell it exactly which count is short.
- **A prose or anchor FAIL** (`paraphrased`, `verbatim N/M`, `anchors N/M` where the
  chapter had more) — the agent edited outside its scope and corrupted the file. Re-seed
  `merged.md` from `draft.md` FIRST (Step F4), then re-dispatch. Re-dispatching on the
  damaged file cannot recover dropped anchors or un-paraphrase prose.

A second `FAIL` after escalation → skip the chapter, record it, continue. Then Step 4.

Gate policy is unchanged: file only `GATE: PASS`, never write `gate: PASS` for a chapter
the gate failed.

## Step 4: Stash the raw PDF + regenerate the book index

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
STACK="..."; BOOK_SLUG="..."; PDF="..."   # re-set
mkdir -p "$STACK/reference/$BOOK_SLUG"
# Keep the source PDF next to its chapters for local re-pull, but never commit it.
# Write a per-book .gitignore so this holds even on a stack scaffolded BEFORE the
# reference tier existed (its stack-level .gitignore lacks the reference/**/*.pdf rule).
printf '*.pdf\n' > "$STACK/reference/$BOOK_SLUG/.gitignore"
cp -n "$PDF" "$STACK/reference/$BOOK_SLUG/" 2>/dev/null || true
bash "$STACKS_ROOT/scripts/regenerate-reference-index.sh" "$STACK" "$BOOK_SLUG"
```

The generator rebuilds `reference/{BOOK_SLUG}/index.md` — the `## Chapters` recognition
map lookup greps — from the chapter frontmatter you just wrote.

## Step 5: Log + commit

```bash
STACK="..."; BOOK_SLUG="..."   # re-set
N=$(find "$STACK/reference/$BOOK_SLUG" -maxdepth 1 -name '*.md' ! -name 'index.md' | wc -l | tr -d ' ')
printf -- '- %s  ingest-book: %s → reference/%s (%s chapters)\n' "$(date +%Y-%m-%d)" "$BOOK_SLUG" "$BOOK_SLUG" "$N" >> "$STACK/log.md"
git add "$STACK/reference/$BOOK_SLUG"/*.md "$STACK/log.md"
git commit -m "feat($STACK): ingest $BOOK_SLUG — $N reference chapters"
```

Report: chapters filed, chapters skipped (gate FAIL) with their page ranges, and the
reference index path. Tell the operator they can re-run a skipped chapter with the same
command narrowed to that chapter, or promote any chapter into articles by copying it into
`{STACK}/sources/incoming/` and running `/stacks:catalog-sources {STACK}`.
