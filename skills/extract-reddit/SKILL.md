---
name: extract-reddit
description: |
  Use when the user wants to capture a Reddit thread into the knowledge library
  as a stacks-style inbox source. Fetches the thread (post + comments) via the
  public Reddit JSON endpoint, follows the linked article when present, runs a
  critical wheat-vs-chaff filter on the comments to keep only first-hand cost
  data, technical claims, policy facts, and verifiable specifics, then writes a
  single inbox markdown file. Drops into the library's inbox/ by default, or
  into a named stack's sources/incoming/ when the user specifies a stack.
  Examples: "/stacks:extract-reddit https://reddit.com/r/sub/comments/abc123",
  "/stacks:extract-reddit https://old.reddit.com/r/bayarea/comments/1t775ax/foo plumbing".
---

# Extract Reddit Discussion

Turn a Reddit thread URL into one inbox file the rest of the stacks pipeline can ingest.

## Step 0: Telemetry

```bash
LOCATE=$(find ~/.claude/plugins/cache -name locate-plugin-root.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
[[ -z "$LOCATE" ]] && LOCATE="$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)/scripts/locate-plugin-root.sh"
STACKS_ROOT=$(bash "$LOCATE" 2>/dev/null)
SKILL_NAME="stacks:extract-reddit" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

## Step 1: Find the library and parse args

```bash
CONFIG="$HOME/.config/stacks/config.json"
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: No stacks config found at $CONFIG"
  echo "Run /stacks:init-library to create a library first."
  exit 1
fi
LIBRARY=$(jq -r '.library // empty' "$CONFIG")
LIBRARY="${LIBRARY/#\~/$HOME}"
if [[ -z "$LIBRARY" || ! -d "$LIBRARY" ]]; then
  echo "ERROR: Library not found at '$LIBRARY'"
  exit 1
fi
```

The skill takes a URL (required) and an optional stack name. Both come from the user's invocation (`/stacks:extract-reddit <url> [stack]`). The full argument string is `$ARGUMENTS`.

Note on positional refs: the skill harness substitutes `$0`/`$1`/`$N` literals inside awk/sed/perl bodies before rendering, so `awk '{print $1}'` would break. Parse via `read` instead — it splits on `IFS` without exposing positional refs to substitution.

```bash
ARGS="$ARGUMENTS"
URL=""
STACK=""
read -r URL STACK _ <<< "$ARGS"
if [[ -z "$URL" ]]; then
  echo "Usage: /stacks:extract-reddit <reddit-thread-url> [stack-name]"
  echo "  no stack-name → file lands in {library}/inbox/ (use /stacks:process-inbox after)"
  echo "  stack-name    → file lands in {library}/{stack}/sources/incoming/"
  exit 1
fi
```

If a stack name is given, validate it exists before fetching anything (cheaper to fail early than after a 30-second fetch):

```bash
if [[ -n "$STACK" ]]; then
  if [[ ! -f "$LIBRARY/$STACK/STACK.md" ]]; then
    echo "ERROR: stack '$STACK' not found in library at $LIBRARY"
    echo "Available stacks:"
    find "$LIBRARY" -maxdepth 2 -name STACK.md -exec dirname {} \; | xargs -n1 basename | sort
    exit 1
  fi
fi
```

## Step 2: Fetch the thread

Use the bundled script. It hits `reddit.com/comments/{id}/.json` with a browser User-Agent (bare curl is blocked by Reddit's edge), walks the comment tree, drops `[deleted]`/`[removed]`, sorts by score, and caps to top-N.

```bash
THREAD_JSON=$(mktemp -t reddit-thread-XXXXXX.json)
python3 "$STACKS_ROOT/scripts/extract-reddit-thread.py" "$URL" > "$THREAD_JSON" || exit $?
```

The script caps at top 100 comments by score, depth ≤ 6, drops `[deleted]`/`[removed]`. Those limits are constants in the script — if you ever need to scale up for an unusually deep thread, edit the constants there rather than threading flags through the skill.

If the script exits non-zero, surface its stderr verbatim — common cases are 403 (blocked from this IP, suggest PRAW upgrade), 429 (rate-limited, wait), or a non-Reddit URL (regex didn't match).

Read the JSON. Fields used downstream:
- post: `title`, `permalink`, `selftext`, `linked_url`, `subreddit`, `created_utc`, `score`, `upvote_ratio`, `num_comments_total`, `stats.comments_kept`
- `comments[]`: sorted by score descending, each entry is `{score, depth, author, body}`

## Step 3: Fetch the linked article (best-effort)

If `linked_url` is set and is not a self-post (i.e., not pointing back at reddit.com), try to fetch it with the WebFetch tool. Prompt: "Extract the headline, byline, publish date, and the article body as plain text. Skip ads, recommended-content sidebars, and comments."

This is best-effort. If WebFetch fails (paywall, 404, JS-only site), continue without it — the inbox file will note the linked URL and quote the post body's title only.

When the fetch succeeds, capture the headline, byline, publish date, and body text for the inbox file's "Article facts" section.

## Step 4: Critical wheat-vs-chaff filtering

This is the core judgment step. Read every comment in the JSON's `comments[]` array. Classify each as **signal** or **chaff** using the rules below. Don't summarize — pick concrete claims worth carrying forward.

**Signal — keep these:**
- First-hand cost reports with a number and a context ("I got a quote of $9k for X", "my bill went from Y to Z"). Capture the number, the scope it covers, the geography if stated, and the username + score for traceability.
- Specific technical claims with a model number, spec, code section, or measurable behavior ("Rheem ProTerra 80 gal 120V plug-in, 15A breaker, ~10A typical draw"). These are the claims a future article will cite.
- Policy or rule-text specifics that go beyond what the linked article says ("the rule covers sale not installation", "BAAQMD board is not directly elected"). Flag any claim that isn't from a primary source as needing verification.
- Maintenance, install, or operational gotchas with enough detail that a practitioner could act on them ("two-trades problem doubles labor cost", "Sanden split unit has no external refrigerant line").
- Rebate or program facts with a date or eligibility criterion ("HEEHRA fully reserved as of 2026-02-24"). These rot fast — always include the as-of date.

**Chaff — discard, but record the pattern in a small ledger so the cut is auditable:**
- Partisan venting ("Democrats X", "Republicans Y", "vote blue/red", "boot-licking pedo supporters")
- Generic doom ("depressing", "this country is cooked", "we get what we vote for")
- Defiance with no install detail ("I'll just install gas anyway", "U-Haul to Tahoe")
- Whataboutism that doesn't introduce a new specific claim ("refineries pollute more so why pick on us" — drop, unless it cites a specific number, in which case keep)
- One-line snark ("you must be fun at parties", "lol Bay Area gonna Bay Area")
- "PG&E sucks" without specifics
- Off-topic sub-debates (e.g., Prop 13 in a heat-pump thread)

When a comment carries both signal and chaff (technical claim wrapped in a partisan rant), keep the technical claim and quote only the relevant fragment.

The point of the chaff ledger is auditability — a future reader can see which categories you cut and decide if the filter was reasonable. Don't list individual comments in the ledger; just the patterns.

## Step 5: Compose the inbox file

Use this template literally — it's the shape the rest of the pipeline expects, and the section order is what makes the file scannable. Replace `{placeholders}` with content from the previous steps.

The slug is `{publisher-domain}-{topic-keywords}-{year}` for filename, all lowercase, hyphenated, no slashes. If there's no linked article, use `reddit-{subreddit}-{topic-keywords}-{post-id-suffix}`.

```markdown
# {Article title or post title}

**Source (article):** {linked_url or "n/a — Reddit self-post"}
**Source (discussion):** {permalink}
**Publisher:** {article publisher domain or "Reddit (r/{subreddit})"}
**Published:** {article date or post created_utc as YYYY-MM-DD}
**Captured:** {today YYYY-MM-DD}
**Tier:** {3 if trade press article + 4 if discussion, or 4 alone if Reddit self-post}
**Discussion stats:** {score} score, {upvote_ratio*100|round}% upvote ratio, {num_comments_total} comments ({comments_parsed} parsed after deletion); top {comments_kept} reviewed for technical signal

---

## Why this is in {stack name or "the library"}

{One paragraph: what specifically about this thread makes it worth keeping. Lead with the structural fit — what stack scope it touches and why a future article will reference it. Then one sentence on what the discussion adds that the linked article alone doesn't.}

---

## Article facts ({publisher})

{Bulleted facts from the linked article. Each fact gets a single bullet. Lead with the rule body / actor, dates, geography, then quantitative claims with their cited source. If the article quotes someone, attribute the quote with the speaker's role.}

---

## Filtered discussion signal

Comments scored on technical specificity, verifiable claim, or first-hand cost/install report. Partisan framing, generic doom, and "vote X" venting discarded.

### Cost data points (first-hand quotes)

{If at least 3 cost data points were captured, render as a markdown table with columns: Item | Reported cost | Notes | Source. The Source column is "username +score". Sort by absolute cost descending. If fewer than 3 cost points, drop the section.}

### Technical claims worth carrying forward

{Bulleted list. Each bullet leads with the claim in bold or a key term, then explains the mechanism, then cites the commenter as `(username +score)`. Example: "**120V plug-in HPWH exists, no panel upgrade needed.** Rheem ProTerra 120V (50/80 gal, 15A breaker, ~10A typical draw) is a drop-in for a gas WH on a standard outlet. Recovery time longer than 240V/30A units. (`nostrademons +8`)"}

### Policy / scope facts (commenter-flagged, verify against primary source)

{Bulleted facts about the rule, jurisdiction, scope, exemptions, or enforcement that came from commenters rather than the article. Each item ends with a "verify against {primary source}" note since commenters are not authoritative on rule text.}

### Rebate / time-sensitive landscape

{Optional. Include only if rebate program names, dollar amounts, or eligibility cutoffs surfaced in the thread. Always include the as-of date the commenter cited. End the section with: "These specifics are time-sensitive; refresh against current {agency} pages before citing in any deliverable."}

### Maintenance / longevity notes

{Optional. Field-report comments about reliability, longevity, or maintenance. Include even single-anecdote reports if they name a specific failure mode or product.}

### Discarded as chaff

The thread also contained content patterns with no {stack-domain} engineering signal:

{Bulleted list of patterns cut, e.g.:
- "Republicans/Democrats are X" framing
- "We get what we vote for" / "incumbents always win" generic
- "PG&E sucks" without specifics
- One-line snark}

---

## Carry-forward questions for catalog-sources

{1-5 numbered questions that the next pass should resolve. These are the actionable threads — open ambiguities, claims to verify against primary sources, missing information that would close the file. Each question should be specific enough that a future session can act on it without re-reading the full thread.}

---

## Tags (suggested)

```yaml
tags:
  - {stack-name if known}
  - {primary topic, e.g., dhw, water-heaters}
  - {specific subtype, e.g., heat-pump-water-heater}
  - {regulatory body or program if relevant, e.g., baaqmd}
  - {geography if scoped, e.g., california}
```
```

Render the template with the captured data. Keep the chaff ledger short — three to seven bullet patterns, not a comment-by-comment account. The point is auditability of the cut, not a transcript.

When in doubt about a borderline comment, keep it — the next pipeline stage (catalog-sources) does another filter, and false positives are cheaper to drop later than false negatives are to recover. A high score doesn't make a comment signal (top-of-thread snark often sits at +200), and a low score doesn't make it chaff (a first-hand cost report two layers deep at +5 is gold). Read the bodies, not the scores.

## Step 6: Write the file

Choose the destination based on whether `$STACK` was set:

```bash
if [[ -n "$STACK" ]]; then
  DEST_DIR="$LIBRARY/$STACK/sources/incoming"
  NEXT_STEP="/stacks:catalog-sources $STACK"
else
  DEST_DIR="$LIBRARY/inbox"
  NEXT_STEP="/stacks:process-inbox"
fi
mkdir -p "$DEST_DIR"
DEST="$DEST_DIR/{slug}.md"
```

Write the rendered markdown to `$DEST` using the Write tool (not heredoc — heredoc corrupts inline backticks per the workspace gotchas).

If a file with the same slug already exists, append `-2`, `-3`, etc. before the `.md`. Don't overwrite — the user may have iterated on the same URL twice intentionally.

After writing, clean up the temp JSON:

```bash
rm -f "$THREAD_JSON"
```

## Step 7: Report

Print:

```
## Reddit Extraction Complete

Source:    {URL}
Article:   {linked_url or "(none — self-post)"}
Captured:  {N} comments parsed, {M} after chaff filter
Cost data: {K} first-hand cost reports captured
Filed at:  {DEST relative to $LIBRARY}

Next step: {NEXT_STEP}
```

If `$STACK` was set, the file is gitignored at the destination (per stack convention). Tell the user: "File is in `{stack}/sources/incoming/` — gitignored until /stacks:catalog-sources promotes it. If you want it tracked durably before cataloging, drop the stack arg next time so it lands in `inbox/` instead, or commit with `git add -f`."

If `$STACK` was not set, the file is in `inbox/` (tracked by default). No special note needed.

## Notes on tier assignment

When the linked article is from a known trade press or news outlet, tier the source as **3 (Practitioner / trade press)**. The Reddit discussion itself is **Tier 4 (general / forum)**. The composite source file gets the higher of the two tiers in its frontmatter, with the discussion explicitly noted as filtered Tier 4 input. If there's no linked article (Reddit self-post), the file is Tier 4 alone.

## Failure mode worth surfacing

If the script exits with `unexpected response shape (private/quarantined subreddit?)`, Reddit's public `.json` endpoint is serving a logged-in-only stub. Stop and tell the user the thread requires authenticated access — PRAW with Reddit API creds is the upgrade path, not in scope for this skill.
