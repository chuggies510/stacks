---
name: enrich-stack
description: |
  Use when the user wants to close a stack's audit soft spots by acquiring
  sources. Reads dev/audit/soft-spots.tsv (produced by audit-stack), drops
  stale gaps, dispatches the enrichment agent to web-search one grounding
  source per claim, then presents what it found for operator approval and
  stages only approved sources into sources/incoming/ — never auto-ingests.
  Slots between audit-stack and catalog-sources. Must be run from a library repo.
---

# Enrich Stack

Acquire sources for a stack's **soft spots** — article claims that the audit
flagged as having no cited source. This is the missing acquisition step between
the two existing skills:

```
audit-stack   →   enrich-stack   →   catalog-sources
(finds gaps)      (acquires sources)   (ingests them)
```

For each soft spot the `enrichment` agent web-searches one source that grounds
the exact claim, verifies it (not just topically related), rates its tier, and
dedups against already-filed sources. This skill batches the gaps, gates the
agents, dedups by URL, then **presents the findings for operator approval and
stages only what the operator approves** into `sources/incoming/`. Nothing is
ever auto-ingested without an operator decision, but once the operator approves
staging it closes the loop itself: it runs `catalog-sources` + `audit-stack` in
the same session and reports which gaps cleared, rather than handing the operator
two more commands. Each run
derives its work from the latest audit artifact; there is no persistent
enrichment ledger.

## Step 0: Telemetry

```bash
STACKS_ROOT="$CLAUDE_PLUGIN_ROOT"
SKILL_NAME="stacks:enrich-stack" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

## Step 1: Gate check

```bash
if [[ ! -f "catalog.md" ]]; then
  echo "ERROR: Not in a library repo (no catalog.md)."
  exit 1
fi
STACK="$ARGUMENTS"
if [[ -z "$STACK" ]]; then
  echo "ERROR: Specify a stack name. Usage: /stacks:enrich-stack {stack-name}"
  exit 1
fi
if [[ ! -f "$STACK/STACK.md" ]]; then
  echo "ERROR: Stack '$STACK' not found (no STACK.md)."
  exit 1
fi
TSV="$STACK/dev/audit/soft-spots.tsv"
if [[ ! -f "$TSV" ]]; then
  echo "ERROR: No soft-spots.tsv. Run /stacks:audit-stack $STACK first."
  exit 1
fi
if [[ ! -s "$TSV" ]]; then
  echo "No soft spots to enrich (soft-spots.tsv is empty — the stack audited clean). Nothing to do."
  exit 0
fi
SCRIPTS_DIR="$STACKS_ROOT/scripts"
```

## Step 2: Read STACK.md + build the filed-sources listing

Read `$STACK/STACK.md` — the **source-hierarchy** section (the tier table the
agent rates candidates against) and the **scope** section (what the stack
covers, so the agent disambiguates an ambiguous query). Both are passed to every
agent.

Build the filed-sources listing the agents dedup against — `slug<TAB>url` for
every already-filed source (a candidate whose URL is already here is a `DUP`,
not a new fetch). Read the URL from each source's `**Source:**` header line (or
`source_url:` frontmatter); exclude `incoming/`, `trash/`, and `.raw/`.

```bash
mkdir -p "$STACK/dev/enrich"
LISTING="$STACK/dev/enrich/_filed-sources.tsv"
: > "$LISTING"
while IFS= read -r f; do
  url=$(grep -m1 -oiE '(\*\*Source:\*\*|source_url:)[[:space:]]*https?://[^[:space:]]+' "$f" 2>/dev/null \
        | grep -oE 'https?://[^[:space:]]+' | head -1)
  [[ -n "$url" ]] && printf '%s\t%s\n' "$(basename "$f" .md)" "$url" >> "$LISTING"
done < <(find "$STACK/sources" -type f -name '*.md' \
           ! -path '*/incoming/*' ! -path '*/trash/*' ! -path '*/.raw/*' 2>/dev/null)
echo "Filed-sources listing: $(wc -l < "$LISTING") sources with URLs (for dedup)."
```

## Step 3: Stale-check — drop gaps the articles no longer contain

`soft-spots.tsv` is a snapshot from the last audit; articles can change after.
Keep only gaps whose **verbatim claim still occurs** in the article (and whose
article still exists), and assign each survivor a stable `gap-N` id. Searching
for a claim that no longer exists wastes web calls and stages irrelevant sources.

```bash
GAPS="$STACK/dev/enrich/_gaps.tsv"   # gap_id<TAB>slug<TAB>claim<TAB>reason
: > "$GAPS"
i=0; STALE=0; TOTAL=0
while IFS=$'\t' read -r slug claim reason; do
  [[ -z "$slug" ]] && continue
  TOTAL=$((TOTAL+1))
  art="$STACK/articles/$slug.md"
  # The validator collapsed the claim's internal whitespace (tabs/newlines) to
  # single spaces, but the article body still has the original line breaks — so a
  # claim that wrapped across two lines would never `grep -Fq` against the raw
  # file. Flatten the article's whitespace the same way before matching so the
  # round-trip holds for multi-line claims.
  if [[ ! -f "$art" ]] || ! tr -s '[:space:]' ' ' < "$art" | grep -Fq "$claim"; then
    STALE=$((STALE+1)); continue
  fi
  printf 'gap-%s\t%s\t%s\t%s\n' "$i" "$slug" "$claim" "$reason" >> "$GAPS"
  i=$((i+1))
done < "$TSV"
N_GAPS=$i
echo "Soft spots: $TOTAL total, $STALE stale (claim no longer in article), $N_GAPS to enrich."
if [[ "$N_GAPS" -eq 0 ]]; then
  echo "All soft spots are stale — the articles changed since the audit. Re-run /stacks:audit-stack $STACK."
  rm -f "$GAPS"
  exit 0
fi
```

## Step 4: Dispatch the enrichment agent over gap batches

Dispatch the `stacks:enrichment` agent over the surviving gaps. One agent unless
the gap count exceeds the cap. **CAP=12** — smaller than the validator's 25
because each gap is several web round-trips; web calls within an agent are
serial, so peak concurrency is roughly the agent count (≈3 agents for 35 gaps),
not the gap count. No wave machinery is needed.

```bash
mapfile -t GAP_ROWS < "$GAPS"
CAP=12
DISPATCH_EPOCH=$(date +%s)
rm -f "$STACK"/dev/enrich/_enrich-*.md   # clear any stale per-batch files from a prior run
```

**Dispatch.** In a single message, emit one `Agent` tool call per slice
`${GAP_ROWS[@]:i:CAP}` (i = 0, CAP, 2·CAP, …), `subagent_type` =
`stacks:enrichment`, with `BATCH_TAG` = the slice ordinal (`0`, `1`, `2`, …; use
`0` for the single-agent case). Each agent prompt names: its assigned gap rows
(`gap_id<TAB>slug<TAB>claim<TAB>reason`), the path to `$STACK/STACK.md`
(source-hierarchy + scope), the filed-sources listing `$LISTING`, the stack root
`$STACK`, and its `$BATCH_TAG`. Tell each agent to write its findings to
`$STACK/dev/enrich/_enrich-${BATCH_TAG}.md`. Parallel dispatch — never sequential.

**Gate.** After all agents return, gate every expected batch file (write-or-fail
+ the `enrichment-findings` shape). Build the expected paths from the same slice
ordinals you dispatched:

```bash
BATCHFILES=()
n=${#GAP_ROWS[@]}
for ((i=0, tag=0; i<n; i+=CAP, tag++)); do BATCHFILES+=("$STACK/dev/enrich/_enrich-${tag}.md"); done
bash "$SCRIPTS_DIR/gate-batch.sh" "$DISPATCH_EPOCH" "enrichment" enrichment-findings "${BATCHFILES[@]}"
```

A non-zero exit means an agent did not write a well-formed findings file —
surface the failing paths and stop.

## Step 5: Aggregate findings + dedup by URL

Read every `_enrich-*.md` batch file and parse each row's 8 tab fields
(`KIND, gap_id, slug, source_ref, url, tier, title, quote`). Then **dedup by
URL — only over `CANDIDATE`/`WEAK` rows with a non-empty `url`** (never group
`NOSOURCE` rows, whose `url` is empty, or they collapse into one bogus group): if
two gaps picked the same URL, you will stage that source once and note every gap
it serves (a single staged file can ground multiple claims). Group the rows by
verdict for the operator:

- `CANDIDATE` / `WEAK` — a fetchable URL that grounds the claim (WEAK = tier 4 only).
- `DUP` — already-filed source; no fetch, the operator just adds a citation.
- `NOSOURCE` — nothing grounds it; the operator tightens the claim or accepts it.

## Step 6: Operator approval (no writes before this)

**No source is staged into the library until the operator approves.** (The
transient working files under `dev/enrich/` — the listing, `_gaps.tsv`, and the
batch findings — are scratch, written before this point and cleaned up below;
nothing enters `sources/` before approval.) Present a compact table — one row per
gap — so the operator can see what would be staged:

| verdict | article (slug) | tier | source | grounds the claim? (quote) |
|---------|----------------|------|--------|-----------------------------|

The default proposal: **stage all `CANDIDATE`s**; list `WEAK`s separately for
explicit opt-in (tier-4 sources are weak grounding); never stage `DUP`/`NOSOURCE`.
Ask the operator to confirm — approve all candidates, select a subset, also
include weak ones, or cancel. (Per the 4-option `AskUserQuestion` cap, present
the table in prose and take a free-text confirmation rather than a per-source
picker.) On **cancel**: clean up and write nothing —

```bash
rm -f "$STACK"/dev/enrich/_enrich-*.md "$STACK/dev/enrich/_gaps.tsv" "$STACK/dev/enrich/_filed-sources.tsv"
```

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
**Supports gap:** {slug(s) this source grounds}

---

{fetched text / the relevant excerpt}
```

Generate the filename with `collision-dest.sh` (it returns a non-colliding path
in the target dir):

```bash
TODAY=$(date +%Y-%m-%d)
DEST=$(bash "$SCRIPTS_DIR/collision-dest.sh" "$STACK/sources/incoming" "{slug-or-title}.md")
# write the staged markdown to "$DEST"
```

**Re-verify after fetch (codex #8):** a `CANDIDATE` verdict does not guarantee a
clean re-fetch (pages change, paywall, dynamic content). After writing each
staged file, confirm the supporting quote still appears. The agent's `quote`
field has its whitespace collapsed and carries no surrounding quotation marks, so
flatten the re-fetched file the same way before matching (a literal `grep -Fq` of
the raw quote against the raw page is brittle — line wraps differ):

```bash
QUOTE_FLAT=$(printf '%s' "{supporting quote}" | tr -s '[:space:]' ' ')
if ! tr -s '[:space:]' ' ' < "$DEST" | grep -Fq "$QUOTE_FLAT"; then
  echo "WARN: supporting quote not found in re-fetched $DEST — skipping"; rm -f "$DEST"
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

Clean up the transient working files (keep nothing but the staged sources):

```bash
rm -f "$STACK"/dev/enrich/_enrich-*.md "$STACK/dev/enrich/_gaps.tsv" "$STACK/dev/enrich/_filed-sources.tsv"
```
