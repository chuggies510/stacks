# Proposal: `/stacks:ingest-evernote` — Evernote `.enex` archive ingestion

> **STATUS: PROPOSED, NOT IMPLEMENTED.** This describes a future skill that does not
> exist in the `stacks` plugin. It does not describe current plugin behavior — do not
> read any section below as "how stacks works today."
>
> **Origin:** [chuggies510/stacks#75](https://github.com/chuggies510/stacks/issues/75),
> closed **not planned** on 2026-07-07. The two Evernote notebooks that motivated the
> issue (Taylor Engineering + CRH, ~3,250 notes) are already fully ingested into the
> `library-stack` library via the bespoke pipeline documented below — there is no
> pending archive and no live demand for the reusable skill. This document preserves
> the proven approach so the skill can be built later without re-deriving it.

## Why this exists

Building a first-class `/stacks:ingest-evernote` skill was scoped out of #75 because
nobody currently needs it — the one campaign that needed it already ran, by hand, in a
different repo. The mechanism is real and worked (grew the hvac stack 259→588 articles,
electrical 37→50, plumbing 34→41 across 38 waves), but it is throwaway scaffolding
(`dev/evernote/*.py`, gitignored `exploded/` output) inside `library-stack`, not
plugin code. If a future user brings another Evernote export, this doc is the reference
implementation to build from — re-read it, don't re-derive it from scratch.

## How we actually did it

Source: `library-stack/dev/evernote/` — `explode_recon.py`, `explode_te.py`,
`explode_crh.py`, `route.py`, `next_wave.sh`, `stage_wave.sh`, `STATE.md` (the
campaign log), and `hvac/log.md` (per-wave commit history). All verified by reading
the scripts directly, 2026-07-07.

### Stage 1 — Recon (one-time triage, `explode_recon.py`)

Before exploding anything, a cheap first pass classified every note without extracting
attachments, to size the problem and tune thresholds:

- Streams the `.enex` XML with `ET.iterparse(path, events=('start','end'))` +
  `root.clear()` after each `<note>` — bounded memory regardless of archive size (the
  two source files are multi-GB, attachment-heavy; text is a tiny fraction of the
  bytes).
- `classify(title, words, has_url, has_pdf, body)` sorts each note into one of:
  `email` (`Re:`/`Fwd:` subject or ≥2 email-header lines), `contact` (short body +
  phone number or a 1-4 word title), `attachment` (has a PDF resource, <40 words of
  body text), `clip` (has a `source-url`), or `original` (everything else — the
  valuable case: a real writeup).
- `guess_stack(text)` is a keyword-count heuristic per candidate stack (hvac,
  electrical, plumbing, swe, sysops keyword lists), highest count wins, ties/none →
  `UNSURE`. Deliberately not an LLM call — `ponytail: heuristic classifier, no LLM.
  Tighten thresholds from the TSV, not up front.`
- Output: one flat `recon.tsv` row per note (notebook, index, type, words, has-pdf,
  resource count, stack guess, title) across BOTH notebooks in one run. This TSV is
  what let the operator decide "notebook X (2,148 notes, all personal) — skip
  entirely" before spending any explode/route/catalog effort on it.

### Stage 2 — Explode (`explode_te.py` / `explode_crh.py`, one script per notebook)

Each script is a near-identical clone (only `SRC`/`OUT`/filename-prefix differ) that
does the real conversion:

- Same streaming `iterparse` + `root.clear()` pattern as recon.
- `KEEP = {"original", "email"}` — only these two classifications get written out;
  `contact`/`attachment`/`clip` notes are dropped at explode time (not filed
  anywhere, not routed — the recon classifier already decided they carry no
  extractable engineering content).
- Body HTML → markdown via the `markdownify` library (PEP 723 inline dependency,
  `# /// script ... dependencies = ["markdownify"] ///`, run via `uv run`) —
  `ponytail: markdownify over a hand-rolled HTML parser; clipped/email HTML is too
  messy to regex.`
- **Attachments are recorded, not extracted.** Each `<resource>`'s mime type and
  filename go into the output file's YAML frontmatter (`attachments: [{mime, file}]`)
  so a later pass could pull the bytes if ever needed; the explode step never
  base64-decodes them. This is most of why the step stays fast and memory-bounded on
  a multi-GB source.
- One markdown file per kept note: `exploded/<notebook>/NNNN-slugified-title.md` for
  TE, `exploded/<notebook>/crh-NNNN-slugified-title.md` for CRH — **the `crh-`
  prefix exists solely to prevent basename collisions** once notes from both
  notebooks are later copied by filename alone into a stack's `sources/incoming/`.
  Frontmatter carries `notebook`, `type`, `stack_guess` (from the recon heuristic,
  reused as a fallback), `note_index`, `words`, `created`/`updated`, `tags`,
  optional `source_url`, and the attachment list.
- `exploded/` is gitignored — fully regenerable from the source `.enex` files (which
  themselves live only in `~/Downloads`, never committed; multi-GB, not repo
  material) in about 10 seconds.

### Stage 3 — Route (`route.py`, tag-based, regex, no LLM)

- Scans `exploded/*/*.md` (both notebooks in one pass, basenames unique via the
  `crh-` prefix from stage 2).
- Routing is **tag-first, keyword-guess-fallback**: Evernote's own tag namespaces on
  the note (`REF:`, `BA:`, `ES:` prefixes seen in this archive) are joined into one
  blob and matched against per-stack regexes (`HVAC`, `ELEC`, `PLUMB`, `SWE` — e.g.
  `HVAC` matches `control_spec|energy_model|hydronic|exhaust|duct|...|leed|...`).
  First matching regex wins, in a fixed priority order (hvac checked first — the
  dominant correct sink for this archive). Only if NO tag matches does it fall back
  to the `stack_guess` frontmatter field written by the explode step.
- Output: `routing.tsv` (file → stack), plus a printed tally. For this archive:
  hvac 1084, UNSURE 379, swe 65, electrical 54, plumbing 30, sysops 6 (out of 1,618
  kept notes).
- `UNSURE` notes are NOT discarded — they sit in the TSV as their own bucket,
  triaged later by hand (the campaign log records ~15% of UNSURE were real keepers
  worth re-routing, the rest dropped).

### Stage 4 — Wave-batching (`next_wave.sh` + `stage_wave.sh`), ledger-free resume

The catalog step (`/stacks:catalog-sources`, the existing plugin skill) caps at a
modest number of sources per invocation — dumping all 1,084 hvac-routed notes into
one run would try to spawn ~1,084 extraction agents. The wave scripts batch this
without maintaining any separate progress ledger:

- **Resume key = "does this note's filename already exist under `<stack>/sources/`
  (any publisher subdir OR `.raw/`), outside `incoming/`?"** If yes, `catalog-sources`
  already filed it in a prior wave — skip. This is durable across sessions and
  machines because it reads the actual filesystem state the catalog step produces,
  not a side file that could drift or get lost.
- `next_wave.sh <stack> [N=24] [min_words=1000]`: cross-references `routing.tsv`
  (notes assigned to this stack) against the "already filed" set, then among the
  unprocessed remainder picks the **densest first** (highest `words:` frontmatter
  value, filtered to `>= min_words`), returns the top `N`. Densest-first was a
  deliberate choice — richer notes were expected to mint more new articles per agent
  dispatch, and the campaign log confirms the yield stayed real (not degrading to
  pure noise) far longer than expected as the band thinned.
- `stage_wave.sh <stack> [N] [min_words]`: calls `next_wave.sh`, copies each selected
  note's `exploded/` file into `<stack>/sources/incoming/`, ensures the stack's
  publisher directory exists (first-wave gotcha — the publisher dir doesn't exist
  yet for a stack's first Evernote wave), runs the plugin's own
  `convert-sources.sh` normalizer, and screens for a parenthesis in any staged
  filename (`PAREN_PROBLEM` — a known shell-quoting hazard downstream in
  `catalog-sources`). It then emits the `batch-N|path` dispatch list
  `catalog-sources` W1 consumes.
- Batch size held at a fixed **~24 sources/wave** for the whole 38-wave campaign
  (not tuned per-wave) — small enough that the existing `catalog-sources` article
  cap (validated separately at 3 articles/agent, per the audit-stack fix in
  0.41.1) never binds, no dynamic sizing logic was needed.
- **Null notes are a valid, expected outcome, not an error.** A note with no
  extractable engineering concept (contact card, logistics thread, vendor
  announcement) makes `catalog-sources`' W1 write-gate report a false
  `AGENT_WRITE_FAILURE` — STATE.md flags this explicitly as "it's a valid null,
  proceed." These notes get moved to `<stack>/sources/.raw/` (which still counts as
  "filed" for the resume key, so they're never re-selected). Null rate rose from
  ~15% to ~35% as the densest band drained across the campaign but never made the
  wave yield collapse to zero.

### What ran, for scale calibration

38 waves, ~24 sources/wave, ~1–1.5M tokens per wave, over ~1,618 routed notes (out of
3,250 raw notes across two notebooks; one notebook — 2,148 personal notes — was
recon'd and skipped entirely, never exploded). Final: hvac 259→588 articles,
electrical 37→50, plumbing 34→41. Full log: `library-stack/dev/evernote/STATE.md`
and `library-stack/hvac/log.md`.

## Proposed plugin shape

**Fork: a new `/stacks:ingest-evernote` skill vs. teaching `catalog-sources --from`
to understand `.enex` archives.**

Recommend the **new skill**, not extending `catalog-sources --from`. Reasons:

- `catalog-sources --from <dir>` stages a directory of already-discrete files
  (`.md`/`.pdf`/`.docx`) 1:1 into `sources/incoming/`. An `.enex` is a single opaque
  container that must first explode into N candidate files, THEN get routed to a
  stack (potentially several stacks, since one archive here spanned hvac/electrical/
  plumbing/swe/sysops) — that's a materially different shape than "stage what's
  already there," and bolting archive-awareness onto `--from` would mean
  `catalog-sources` also owns explode/classify/route logic it has no other reason to
  know about.
  a per-stack CLI would also need to fan the same archive out across stacks in one
  invocation, which `--from <stack> <path>`'s single-stack signature doesn't fit.
- A dedicated skill mirrors `ingest-book`'s existing precedent: a format-specific
  front door (PDF chapter map / `.enex` note archive) that does its own prep, then
  hands normalized sources to the shared machinery.

**The wave-batching + resume mechanics should be SHARED with `ingest-book`, not
reinvented.** `skills/ingest-book/SKILL.md` Step 3B ("Workflow batch") already solves
the identical problem for a different unit of work (PDF chapters instead of Evernote
notes): pre-run deterministic mechanical prep for every unit in Bash, fan only the
model work out via a `Workflow`, gate and file outside it, skip-not-abort on a
per-unit failure, resume by re-deriving state from the filesystem rather than a
side-ledger (ingest-book: "chapter already gated PASS under `reference/{book}/`";
Evernote: "note's filename already under `sources/` outside `incoming/`"). Building a
second, differently-shaped batching layer for Evernote would duplicate that logic
under a new name. Concretely: extract the pre-run-prep → per-unit-manifest →
`Workflow` fan-out → gate-or-skip → resume-by-filesystem-state pattern into a shared
helper (script or reference doc) both skills' Step-3-equivalent calls, parameterized
by "what is a unit" (chapter vs. note) and "what is the per-unit model work" (patch+
audit vs. article synthesis). Don't design that extraction now — flag it as the
shared dependency this skill's implementation should resolve first, likely as its own
small refactor of `ingest-book` Step 3B before `ingest-evernote` is built on top of it.

**Proposed skill shape**, mapping the proven stages onto plugin surfaces:

1. **Explode**: a generic `.enex` → per-note-markdown converter (streaming
   `iterparse`, `markdownify` for ENML→markdown, attachments recorded in frontmatter
   not extracted), parameterized by input file and output dir — no notebook-specific
   script per archive (the TE/CRH split was two near-identical clones only because
   this was a one-off; a real skill takes one `.enex` path and one output dir, run
   once per archive the operator points it at).
2. **Classify** (recon): keep the `classify()` heuristic (email/contact/attachment/
   clip/original) as a pre-filter — only `original`+`email` notes get exploded to
   files; the rest are dropped before routing, matching what actually ran.
3. **Route**: tag-first (Evernote tag namespace → stack) with keyword-guess fallback.
   Generic stacks have no fixed taxonomy, so the tag regex map and keyword lists
   cannot be hardcoded HVAC/electrical/plumbing/swe/sysops — this needs to become an
   **optional per-library routing config** (a small mapping file the operator edits
   for their own tag vocabulary and stack set), falling back to a generic keyword
   guesser only if no config is present. An `UNSURE` bucket stays a first-class
   output, not silently dropped.
4. **Wave-batch**: reuse the shared batching helper (see above) with "note" as the
   unit and `catalog-sources` article synthesis as the per-unit model work; resume
   key = filename present under `<stack>/sources/` outside `incoming/`.
5. **Null handling**: preserve the "no-concept note is a valid null, not a failure"
   rule explicitly in the skill's gate logic (don't let a future implementer
   rediscover the false-`AGENT_WRITE_FAILURE` gotcha the hard way) — route null/
   declined notes to `sources/.raw/` so they count as filed and are never
   re-selected.

## Goals

- A stacks user can point the plugin at an `.enex` export and get per-note sources
  routed into the right stack(s) and catalogued into articles, in resumable batches,
  without hand-writing explode/route/wave scripts.
- Reuse `ingest-book`'s batching/resume pattern rather than re-deriving it.
- Preserve the non-obvious mechanics from the proven run: bounded-memory streaming
  parse, attachment-metadata-not-extraction, `crh`-style basename collision
  prevention across multi-file archives, tag-first routing with keyword fallback,
  null notes as valid resume-eligible outcomes.

## Non-goals

- Extracting/embedding attachment bytes (images, PDFs) into articles — out of scope
  now as it was in the proven run; frontmatter records attachment metadata only.
- A generic multi-format archive importer (`.zip`, other note-app exports) — scope
  this to `.enex` only; generalize later if a second archive format shows real demand.
- Building this now. No demand exists (see status banner) — this is a spec to build
  FROM when demand returns, not a task to schedule.

## Acceptance criteria (for whenever this is built)

- Given a `.enex` path and a target library, the skill explodes, classifies, and
  routes notes to stack(s) without operator-written code.
- Batching resumes correctly after an interrupted run using only filesystem state
  (no side-ledger), verified by killing a run mid-wave and re-invoking.
- Routing config is per-library (no hardcoded HVAC-specific regex in the shipped
  skill); a library with no routing config still works via keyword-guess fallback.
- Null/no-concept notes are filed to `.raw/` (or equivalent) and never cause a wave
  to report false failure.
- The batching/resume layer is demonstrably shared code with `ingest-book`, not a
  parallel reimplementation (i.e., a bug fixed in one path is fixed in both without a
  second edit).

## Open questions

- Should the shared batching extraction happen as a prerequisite refactor of
  `ingest-book` Step 3B, or can `ingest-evernote` be built first and the sharing
  retrofitted once both exist? (Leaning: extract first — a second copy is easier to
  avoid than to un-write.)
- Where does the per-library routing config live — a file in the library repo
  (alongside `catalog.md`) or a stacks-plugin template the operator fills in during
  `/stacks:new-stack`?
- Does `UNSURE`/no-tag-match routing warrant an LLM classification pass, or does the
  keyword-heuristic (proven adequate here, per `STATE.md`'s wave-19 note on yield
  holding) stay good enough to avoid the added cost? Proven run used no LLM for
  explode/classify/route — only `catalog-sources`' existing synthesis step used
  model calls.
