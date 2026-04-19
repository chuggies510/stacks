---
name: process-inbox
description: |
  Use when the user wants to process queued inbox files from other sessions into
  the knowledge library. Reads all .md files in inbox/, classifies each against
  existing stacks using content and source metadata, moves matched files to the
  target stack's sources/incoming/, and reports unmatched files. Works from any
  repo. Examples: "/stacks:process-inbox".
---

# Process Inbox

Route inbox session extracts to the correct stack's incoming directory.

## Step 0: Telemetry

```bash
TELEMETRY_SH=$(find ~/.claude/plugins/cache -name telemetry.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
if [[ -z "$TELEMETRY_SH" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  TELEMETRY_SH="$STACKS_ROOT/scripts/telemetry.sh"
fi
SKILL_NAME="stacks:process-inbox" bash "$TELEMETRY_SH" 2>/dev/null || true
```

## Step 1: Find the library

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
  echo "Update $CONFIG or run /stacks:init-library to create a library."
  exit 1
fi
echo "Library: $LIBRARY"
```

## Step 2: Enumerate stacks

```bash
STACKS=$(find "$LIBRARY" -maxdepth 1 -mindepth 1 -type d | while read d; do
  [ -f "$d/STACK.md" ] && echo "$d"
done | sort)
```

If STACKS is empty, tell the user: "No stacks in your library yet. Run /stacks:new-stack {name} first." Stop.

For each stack in STACKS, read `{stack}/STACK.md`. Collect the stack name (basename) and its scope/domain description from the file. This context is used in Step 4 to classify inbox files.

## Step 3: Enumerate inbox

```bash
INBOX="$LIBRARY/inbox"
```

If `$INBOX` does not exist as a directory, tell the user: "No inbox/ directory found in your library at $INBOX. Create it and drop session extract files there to process them." Stop.

```bash
INBOX_FILES=$(find "$INBOX" -maxdepth 1 -name "*.md" -type f | sort)
```

If INBOX_FILES is empty, tell the user: "Inbox is empty. Drop session extract files in $INBOX to process them." Stop.

Count and report:

```bash
N=$(echo "$INBOX_FILES" | grep -c .)
echo "Found $N file(s) in inbox/"
```

## Step 4: Classify and route

For each file in INBOX_FILES, extract its header block. Use `while IFS= read -r` to handle filenames safely:

```bash
while IFS= read -r f; do
  filename=$(basename "$f")
  header_h1=$(head -1 "$f")
  header_meta=$(sed -n '3,4p' "$f")
  header_sections=$(grep "^## " "$f" | head -5)
  echo "--- $filename ---"
  echo "$header_h1"
  echo "$header_meta"
  echo "$header_sections"
done <<< "$INBOX_FILES"
```

Using the header block (filename, H1 title, Source line, Extracted from line, first 5 `##` section headings) and the stack STACK.md scope context collected in Step 2, classify each file:

- **One clear match**: the content clearly belongs to one stack based on domain (e.g., California Energy Code → mep-stack, Svelte reactivity → svelte). Route it.
- **Split content (mixed sub-topics across stacks)**: the file's `## ` sub-topics do not all point to the same stack. Count how many sub-topics match each candidate stack. If one stack wins with ≥⅔ of sub-topics (e.g., 4 of 5, 3 of 4, 2 of 3), route to that stack and record the split in the report so ingestion can flag the off-topic sub-topic. If no stack wins ≥⅔, treat as a tie.
- **Tie (no stack wins ≥⅔ of sub-topics, or no stack has a clear domain majority)**: cannot confidently route — leave in inbox, record candidate stacks and the per-stack sub-topic counts in the report.
- **No match**: content doesn't fit any existing stack — leave in inbox, record as unmatched.

For each matched file, move it to `{stack}/sources/incoming/`:

```bash
TARGET_STACK="$LIBRARY/{matched-stack}"
mkdir -p "$TARGET_STACK/sources/incoming"
# Handle filename collision:
dest="$TARGET_STACK/sources/incoming/$filename"
if [ -f "$dest" ]; then
  base="${filename%.*}"
  ext="${filename##*.}"
  counter=2
  while [ -f "$TARGET_STACK/sources/incoming/${base}-${counter}.${ext}" ]; do
    counter=$((counter + 1))
  done
  dest="$TARGET_STACK/sources/incoming/${base}-${counter}.${ext}"
fi
mv "$f" "$dest"
echo "Routed: $filename → {matched-stack}/sources/incoming/"
```

Track three lists throughout this step:
- MOVED: filename → stack pairs for all successfully routed files
- UNMATCHED: filenames with no stack home
- TIES: filename → [candidate1, candidate2] pairs where classification was ambiguous

## Step 5: Commit (conditional)

```bash
cd "$LIBRARY"
```

If MOVED is empty, tell the user: "No files routed — all files are unmatched or tied. See report below." Skip the commit and proceed to Step 6.

If any files were moved, stage both the additions in each affected stack's `sources/incoming/` directory AND the deletions in `inbox/`. Some libraries track inbox files, some gitignore them — `git add -A` on both paths handles both cases and ensures a clean tree after the commit:

```bash
cd "$LIBRARY"
git add -A inbox/ {each affected stack}/sources/incoming/
git commit -m "chore(inbox): route {N_MOVED} file(s) to stack incoming dirs"
```

Replace `{each affected stack}` with the actual stack paths from the MOVED list. Replace `{N_MOVED}` with the count of moved files.

Do NOT assume inbox is gitignored. Early versions of the skill only staged additions, which left deletions unstaged in libraries that track `inbox/` and required a second cleanup commit.

## Step 6: Report

Print a clean summary:

```
## Inbox Processing Complete

Routed (N):
  {filename} → {stack}/sources/incoming/

Unmatched — left in inbox/ (N):
  {filename}  (no clear stack home)

Tied — left in inbox/ (N):
  {filename}  (candidates: stack1 [M sub-topics], stack2 [M sub-topics])

Split — routed with off-topic sub-topic flagged (N):
  {filename} → {winning-stack}/sources/incoming/  (off-topic sub-topics: "{heading}" belongs to {other-stack})

Next steps:
  /stacks:catalog-sources {stack}    (for each stack that received files)
```

If there are no unmatched files, omit the Unmatched section. If there are no tied files, omit the Tied section. If no files were routed as splits, omit the Split section.

Note at the bottom: "process-inbox routes files to incoming/. Run /stacks:catalog-sources {stack} per affected stack to build article-per-concept wiki entries."
