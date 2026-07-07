---
name: enrich-stack
description: |
  Use when the user wants to close a stack's audit soft spots by acquiring
  sources. Reads dev/audit/soft-spots.tsv (produced by audit-stack), drops
  stale gaps, dispatches the enrichment agent to web-search one grounding
  source per claim, then presents what it found for operator approval and
  stages only approved sources into sources/incoming/ — never auto-ingests,
  except under --auto (lookup's hands-free path, #69) which auto-stages the
  agent's CANDIDATE sources. Also consumes lookup misses as gaps, not just audit
  soft spots. Slots between audit-stack and catalog-sources. Run from a library repo.
---

# Enrich Stack

Acquire sources for a stack's **soft spots** — article claims that the audit
flagged as having no cited source. This is the missing acquisition step between
the two existing skills:

```
audit-stack   →   enrich-stack   →   catalog-sources
(finds gaps)      (acquires sources)   (ingests them)
```

For each gap the `enrichment` agent web-searches one source that grounds the
exact claim, verifies it (not just topically related), rates its tier, and dedups
against already-filed sources. This skill batches the gaps, gates the agents,
dedups by URL, then stages sources into `sources/incoming/`.

**Two staging modes, by invocation:**
- **Interactive (default):** presents the findings and **stages only what the
  operator approves**. Nothing enters the library without an operator decision.
- **`--auto` (lookup's hands-free path, #69):** no operator prompt — auto-stages
  the agent's `CANDIDATE` verdicts only (tier 1-3, quote re-verified after fetch;
  never `WEAK`/`DUP`/`NOSOURCE`). This trades the human gate for the agent's
  verdict, so it is deliberately narrow: lookup invokes it with `--query` to scope
  the run to the single query that missed, never a bulk backlog sweep.

Either way it then closes the loop itself — runs `catalog-sources` + `audit-stack`
in the same session and reports which gaps cleared. A batch run derives its work
from the latest audit artifact plus mined lookup misses; a `--query` run derives
exactly one gap. There is no persistent enrichment ledger.

## Step 0: Telemetry

```bash
STACKS_ROOT="$CLAUDE_PLUGIN_ROOT"
SKILL_NAME="stacks:enrich-stack" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

## Step 1: Prep — resolve, parse args, assemble gaps (`enrich.sh prep`)

`enrich.sh prep` does everything deterministic in one call: resolve+cd the
library, parse args (the first non-flag token is the stack; `--auto` = hands-free
staging, no operator prompt at Step 6; `--query <text>` scopes the run to ONE gap
and must come last so a multi-word query survives), build the filed-sources
listing, stale-check the audit soft spots, mine telemetry misses, shard the
survivors into `CAP=5` batches, and write the run-state files
(`dev/enrich/dispatch.tsv`, `dev/enrich/run.env`, `_filed-sources.tsv`). It
prints a per-batch summary and the paths the dispatch below reads. `--auto`/
`--query` come from lookup's live auto-path (#69); a manual run passes neither
and gets the full batch.

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/pipeline/enrich.sh" prep $ARGUMENTS
```

If it prints **"Nothing to enrich"** (no live gaps — soft spots all stale/absent
and no lookup misses), stop here. Otherwise note the printed `AUTO=` value (it
drives Step 6) and the manifest/listing/stack-root paths (they feed the dispatch).

## Step 2: Read STACK.md

Read `$STACK/STACK.md` (the stack root path is in prep's output) — the
**source-hierarchy** section (the tier table the agent rates candidates against)
and the **scope** section (what the stack covers, so the agent disambiguates an
ambiguous query). Both are passed to every agent. (The filed-sources listing the
agents dedup against was already built by `prep` at the `Listing:` path it
printed.)

## Step 3: Dispatch the enrichment agent over the gap batches

`prep` already sharded the gaps into `CAP=5` batches — **CAP=5** is the measured
sweet spot from the batch-size experiment (#76): batch~5 beat batch~12 on source
quality, wall-clock, and blast radius per agent death, at +15% tokens; below 5
doubles per-gap cost for no gain and batch=1 regresses on scope-exclusion. It is
specific to this web-search-heavy agent, not the validator's or catalog's caps.
(Change the cap in `enrich.sh`'s `CAP=` constant, not here.)

Read the manifest `dev/enrich/dispatch.tsv` (`Manifest:` path from prep) — each
row is `batch_tag<TAB>gap_id<TAB>slug<TAB>claim<TAB>reason`. **In a single
message, emit one `Agent` tool call per distinct `batch_tag`**, `subagent_type` =
`stacks:enrichment`. Each agent prompt names: its assigned gap rows as
`gap_id<TAB>slug<TAB>claim<TAB>reason` (columns 2-5 of that batch's manifest
rows), the path to `$STACK/STACK.md` (source-hierarchy + scope), the filed-sources
listing (the `Listing:` path), the stack root `$STACK`, and its `BATCH_TAG` (the
`batch_tag` value). Tell each agent to write its findings to
`$STACK/dev/enrich/_enrich-${BATCH_TAG}.md`. Parallel dispatch — never sequential.

## Step 4: Gate — every dispatched gap must be receipted (`enrich.sh gate`)

After all agents return, gate the batch. `enrich.sh gate` re-reads the run-state
from disk (the `RUN_ID` freshness floor and the manifest), runs `gate-batch.sh`
(write-or-fail + `enrichment-findings` shape) on every expected `_enrich-<tag>.md`,
then `check-coverage.sh` (reconciles the dispatched `gap_id`s against the `gap_id`
column of the findings rows). A dropped, duplicated, unknown, or missing findings
row fails **by name**.

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/pipeline/enrich.sh" gate $ARGUMENTS
```

A non-zero exit means an agent did not write a well-formed findings file, or a
gap it was assigned has no receipt row — surface the named failure and stop.

## Step 5: Consolidate findings — dedup by URL (`enrich.sh finish`)

`enrich.sh finish` reads every `_enrich-*.md`, dedups `CANDIDATE`/`WEAK` rows by
URL (never `NOSOURCE` — its url is empty and would collapse into one bogus group),
merges the `gap_id`s/`slug`s a single URL serves, prints the consolidated rows,
then removes the transient run files (the deduped view is now in your context;
nothing on disk is needed for the approval/staging below, so an operator cancel
at Step 6 already leaves a clean end state).

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/pipeline/enrich.sh" finish $ARGUMENTS
```

Each printed row is `KIND<TAB>gap_ids<TAB>slugs<TAB>source_ref<TAB>url<TAB>tier<TAB>title<TAB>quote`.
Group them by verdict for the operator:

- `CANDIDATE` / `WEAK` — a fetchable URL that grounds the claim (WEAK = tier 4 only);
  a single row may list several `gap_ids`/`slugs` (one source grounds several claims).
- `DUP` — already-filed source; no fetch, the operator just adds a citation.
- `NOSOURCE` — nothing grounds it; the operator tightens the claim or accepts it.

## Step 6: Operator approval (no writes before this)

**Auto mode (`AUTO=1` from Step 1, the `--auto` flag — lookup's hands-free path, #69):**
skip the operator prompt entirely. Approve **every `CANDIDATE`** and nothing else
— never `WEAK` (tier-4, weak grounding), `DUP`, or `NOSOURCE`. Go straight to
Step 7. The enrichment agent's `CANDIDATE` verdict (tier 1-3, quote-verified)
stands in for the operator's judgment, and Step 7 still re-verifies the quote
against the re-fetched page, so a bad source is still caught. Print the table
below for the record, then proceed. The rest of this step (the interactive
prompt) applies only when `AUTO=0`.

**No source is staged into the library until the operator approves** (interactive
runs, `AUTO=0`). (The transient working files under `dev/enrich/` — the listing,
`_gaps.tsv`, and the batch findings — are scratch, written before this point and
cleaned up below; nothing enters `sources/` before approval.) Present a compact
table — one row per gap — so the operator can see what would be staged:

| verdict | article (slug) | tier | source | grounds the claim? (quote) |
|---------|----------------|------|--------|-----------------------------|

The default proposal: **stage all `CANDIDATE`s**; list `WEAK`s separately for
explicit opt-in (tier-4 sources are weak grounding); never stage `DUP`/`NOSOURCE`.
Ask the operator to confirm — approve all candidates, select a subset, also
include weak ones, or cancel. (Per the 4-option `AskUserQuestion` cap, present
the table in prose and take a free-text confirmation rather than a per-source
picker.) On **cancel**: write nothing — `finish` (Step 5) already removed the
transient run files, so cancelling leaves the library untouched.

## Step 7: Stage approved sources into incoming/

For each approved `CANDIDATE`/`WEAK` (deduped by URL), `WebFetch` the URL and
write it into `$STACK/sources/incoming/` using the **same bold-field header that
filed sources already use** — NOT YAML frontmatter — so `source-extractor` reads
`**Source:**` and `**Tier:**` straight from the header and the staged file is
indistinguishable from a hand-dropped source:

```markdown
# {title}

**Source:** {url}
**Published:** {date if known, else omit}
**Tier:** {N} ({tier label from STACK.md})
**Fetched:** {today}
**Supports gap:** {slug(s) this source grounds, or the query for a `lookup-miss` gap}
**Excerpt:** {yes — only if you truncated; omit the line when the body is the full fetched text}

---

{verbatim fetched text — see grounding discipline below}
```

**Grounding discipline (stacks#79).** The body below the `---` is publication text, not your writing. Otherwise the grounding chain becomes model-grounded-in-model: a future validator would "verify" a claim against text this step wrote to match that claim.

- **Store the full fetched text by default.** Paste the page's main content verbatim. Do not hand-pick a claim-sized snippet — a model-selected excerpt bakes in selection bias the later quote re-verify cannot catch.
- **Excerpt only above a size cap.** If the fetched text exceeds ~1500 words, take a generous *contiguous* span (the whole section the supporting passage sits in, headings included), not a claim-tailored sentence. When you truncate, add `**Excerpt:** yes` to the header so the source is honestly labeled as partial.
- **No commentary in the body, ever.** No arithmetic, restatement, or framing tailored to the claim (e.g. "737 chars ≈ 184 tokens, within the 180–220 range"). Everything you want to say about *why* this grounds the claim lives in the header (`**Supports gap:**`) or the findings row, never interleaved into the source text.

Generate the filename with `collision-dest.sh` (it returns a non-colliding path
in the target dir). Substitute `{stack-root}` with the absolute stack path from
prep's `Stack root:` line — do not rely on a `$STACK` variable, shell state does
not survive across these blocks:

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/collision-dest.sh" "{stack-root}/sources/incoming" "{slug-or-title}.md"
```

Write the staged markdown (the header block above) to the path it printed.

**Re-verify after fetch (codex #8):** a `CANDIDATE` verdict does not guarantee a
clean re-fetch (pages change, paywall, dynamic content). After writing each
staged file, confirm the supporting quote still appears. The agent's `quote`
field has its whitespace collapsed and carries no surrounding quotation marks, so
flatten the re-fetched file the same way before matching (a literal `grep -Fq` of
the raw quote against the raw page is brittle — line wraps differ):

Substitute `{dest-path}` with the path you just wrote (not a `$DEST` variable —
shell state does not survive between these blocks):

```bash
QUOTE_FLAT=$(printf '%s' "{supporting quote}" | tr -s '[:space:]' ' ')
if ! tr -s '[:space:]' ' ' < "{dest-path}" | grep -Fq "$QUOTE_FLAT"; then
  echo "WARN: supporting quote not found in re-fetched {dest-path} — skipping"; rm -f "{dest-path}"
fi
```

If the fetch fails or the quote is gone, warn and skip that source (do not stage
a file that no longer supports the claim).

## Step 8: Report, then close the loop

First report what staged:
- **Staged**: N sources now in `sources/incoming/` (list filename → gap(s) served).
- **DUP** (manual action — enrich-stack did NOT close these): for each, print
  `slug → existing-source-slug → quote`. The operator adds that citation to the
  article; a catalog run will not add it automatically for an already-filed source.
- **NOSOURCE**: list the gaps nothing grounded, for the operator to tighten the
  claim or accept it as inference.

**Then close the loop — don't ask, just do it.** The operator already made the
only real decision (the Step 6 staging approval); catalog + audit is mechanical
from here. Invoke `/stacks:catalog-sources $STACK` then `/stacks:audit-stack
$STACK` in this session and report the end state (which gaps the re-audit
cleared, which remain). `catalog-sources` commits the staged sources — that is
the intended outcome, and it is reversible; the re-audit is the real check that
synthesis handled the sources correctly, so no pre-catalog confirmation adds
anything. Carry forward any caveats on the staged sources (edition notes,
unverified sub-claims, claims to reword) into the final report so the operator
sees what synthesis baked in and can edit the article if needed.

(No cleanup step here — `finish` at Step 5 already removed every transient working
file, so the only thing this run leaves behind is the staged sources.)
