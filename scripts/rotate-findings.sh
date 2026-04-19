#!/usr/bin/env bash
set -euo pipefail

# rotate-findings.sh — move terminal findings items that have aged past
# ROTATION_CYCLES distinct audit cycles out of the active findings.md into
# findings-archive.md. Invoked by /stacks:audit-stack Step 8.5 on convergence.
#
# Usage: rotate-findings.sh <STACK> <audit_date>
#   <STACK>       absolute path to stack root
#   <audit_date>  YYYY-MM-DD of the current (converging) audit

STACK="${1:-}"
audit_date="${2:-}"

if [[ -z "$STACK" || -z "$audit_date" ]]; then
  echo "usage: rotate-findings.sh <STACK> <audit_date>" >&2
  exit 2
fi

FINDINGS="$STACK/dev/audit/findings.md"
ARCHIVE="$STACK/dev/audit/findings-archive.md"
CLOSED_DIR="$STACK/dev/audit/closed"

if [[ ! -f "$FINDINGS" ]]; then
  echo "rotate-findings: no active findings.md at $FINDINGS, nothing to rotate"
  echo "rotated_items=0"
  exit 0
fi

# Parse ROTATION_CYCLES from STACK.md, default 3
ROTATION_CYCLES=$(grep -oP '(?<=ROTATION_CYCLES:\s)\d+' "$STACK/STACK.md" 2>/dev/null || echo "3")
if [[ -z "$ROTATION_CYCLES" ]] || ! [[ "$ROTATION_CYCLES" =~ ^[0-9]+$ ]]; then
  ROTATION_CYCLES=3
fi

# Build the list of archived audit_dates from dev/audit/closed/ filenames.
# Filename form: YYYY-MM-DD-findings.md
CLOSED_DATES_FILE=$(mktemp)
trap 'rm -f "$CLOSED_DATES_FILE" "$KEEP_FILE" "$ROTATE_FILE" "$TMP_FINDINGS" "$COUNT_FILE" 2>/dev/null || true' EXIT

if [[ -d "$CLOSED_DIR" ]]; then
  # Extract leading date from each closed-findings filename
  find "$CLOSED_DIR" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-findings.md' 2>/dev/null \
    | sed -E 's#.*/([0-9]{4}-[0-9]{2}-[0-9]{2})-findings\.md$#\1#' \
    | sort -u > "$CLOSED_DATES_FILE"
fi

# Split findings.md into a preamble (frontmatter + headers leading up to
# first item) and an item list. Items begin with `- id:` at column 0.
TMP_FINDINGS=$(mktemp)
KEEP_FILE=$(mktemp)
ROTATE_FILE=$(mktemp)
COUNT_FILE=$(mktemp)

# Use awk to split the file into item chunks, then per-chunk decide keep vs rotate.
awk -v closed_dates_file="$CLOSED_DATES_FILE" \
    -v audit_date="$audit_date" \
    -v rotation_cycles="$ROTATION_CYCLES" \
    -v keep_file="$KEEP_FILE" \
    -v rotate_file="$ROTATE_FILE" \
    -v tmp_findings="$TMP_FINDINGS" \
    -v count_file="$COUNT_FILE" '
  BEGIN {
    # Load closed dates into an array
    n_closed = 0
    while ((getline line < closed_dates_file) > 0) {
      if (line != "") {
        closed_dates[n_closed++] = line
      }
    }
    close(closed_dates_file)
    in_item = 0
    preamble = ""
    item_buf = ""
    rotated_count = 0
  }

  function flush_item(   cycles, i, d, status, ttoon, is_terminal) {
    if (item_buf == "") return
    # Extract status and terminal_transitioned_on from the buffered item
    status = ""
    ttoon = ""
    n_lines = split(item_buf, lines, "\n")
    for (i = 1; i <= n_lines; i++) {
      if (match(lines[i], /^[[:space:]]+status:[[:space:]]*/)) {
        s = lines[i]
        sub(/^[[:space:]]+status:[[:space:]]*/, "", s)
        gsub(/[[:space:]]+$/, "", s)
        status = s
      } else if (match(lines[i], /^[[:space:]]+terminal_transitioned_on:[[:space:]]*/)) {
        t = lines[i]
        sub(/^[[:space:]]+terminal_transitioned_on:[[:space:]]*/, "", t)
        gsub(/[[:space:]]+$/, "", t)
        ttoon = t
      }
    }

    is_terminal = (status == "applied" || status == "closed" || status == "deferred" || status == "stale" || status == "failed")

    if (!is_terminal) {
      print item_buf >> keep_file
      item_buf = ""
      return
    }

    # Terminal but missing terminal_transitioned_on: safe first-run behavior, keep.
    if (ttoon == "" || ttoon == "\"\"" || ttoon == "null") {
      print item_buf >> keep_file
      item_buf = ""
      return
    }

    # Count distinct closed-findings audit_dates strictly greater than ttoon.
    # audit_date is a lexicographically-sortable YYYY-MM-DD, so string compare works.
    cycles = 0
    for (i = 0; i < n_closed; i++) {
      d = closed_dates[i]
      if (d > ttoon) cycles++
    }

    if (cycles >= rotation_cycles + 0) {
      print item_buf >> rotate_file
      rotated_count++
    } else {
      print item_buf >> keep_file
    }
    item_buf = ""
  }

  /^- id:/ {
    if (in_item) {
      flush_item()
    } else {
      # First item encountered — flush preamble to tmp_findings
      printf "%s", preamble > tmp_findings
      in_item = 1
    }
    item_buf = $0
    next
  }

  {
    if (in_item) {
      item_buf = item_buf "\n" $0
    } else {
      preamble = preamble $0 "\n"
    }
  }

  END {
    if (in_item) {
      flush_item()
    } else {
      # No items at all — emit preamble only
      printf "%s", preamble > tmp_findings
    }
    print rotated_count > count_file
  }
' "$FINDINGS"

rotated_count=$(cat "$COUNT_FILE" 2>/dev/null || echo "0")
if ! [[ "$rotated_count" =~ ^[0-9]+$ ]]; then
  rotated_count=0
fi

# Assemble new findings.md = preamble (already in TMP_FINDINGS) + kept items
if [[ -s "$KEEP_FILE" ]]; then
  cat "$KEEP_FILE" >> "$TMP_FINDINGS"
fi

if [[ "$rotated_count" -gt 0 ]]; then
  # Ensure archive exists with header
  if [[ ! -f "$ARCHIVE" ]]; then
    printf '# Findings Archive\n\n' > "$ARCHIVE"
  fi
  # Append rotated-batch header + rotated items
  today=$(date +%Y-%m-%d)
  {
    printf '\n## rotated_on: %s\n\n' "$today"
    cat "$ROTATE_FILE"
  } >> "$ARCHIVE"

  # Atomic rewrite of findings.md
  mv "$TMP_FINDINGS" "$FINDINGS"
else
  # No rotations: leave findings.md unchanged
  rm -f "$TMP_FINDINGS"
fi

echo "rotated_items=$rotated_count"
exit 0
