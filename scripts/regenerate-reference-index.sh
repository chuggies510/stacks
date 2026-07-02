#!/usr/bin/env bash
set -euo pipefail
# Deep-reference index generator: rebuild reference/{book-slug}/index.md from the
# provenance frontmatter of every chapter .md in that book dir.
# Usage: regenerate-reference-index.sh <stack_root> <book-slug>
# Reads:  <stack_root>/reference/<book-slug>/*.md (except index.md)
# Writes: <stack_root>/reference/<book-slug>/index.md
#
# The emitted `## Chapters` map is the recognition surface /stacks:lookup greps —
# it mirrors an article index.md's `## Articles` map. Schema: references/reference-tier.md.

STACK="${1:?usage: regenerate-reference-index.sh <stack_root> <book-slug>}"
BOOK_SLUG="${2:?usage: regenerate-reference-index.sh <stack_root> <book-slug>}"

BOOK_DIR="$STACK/reference/$BOOK_SLUG"
INDEX="$BOOK_DIR/index.md"

if [[ ! -d "$BOOK_DIR" ]]; then
  echo "regenerate-reference-index: no such book dir: $BOOK_DIR" >&2
  exit 1
fi

# Extract one frontmatter scalar (strips surrounding quotes). Empty if absent.
fm_field() {
  awk -v k="$1" '
    NR==1 && /^---[[:space:]]*$/ { f=1; next }
    f && /^---[[:space:]]*$/ { exit }
    f && $0 ~ "^"k":" {
      sub("^"k":[[:space:]]*", "")
      gsub(/^"|"$/, "")
      sub(/[[:space:]]+$/, "")
      print; exit
    }
  ' "$2"
}

BOOK_NAME=""
declare -a ROWS=()

while IFS= read -r chapter; do
  [[ "$(basename "$chapter")" == "index.md" ]] && continue
  slug=$(basename "$chapter" .md)
  book=$(fm_field book "$chapter")
  vol=$(fm_field volume "$chapter")
  ch=$(fm_field chapter "$chapter")
  title=$(fm_field title "$chapter")
  topics=$(fm_field topics "$chapter")
  pages=$(fm_field printed_pages "$chapter")

  [[ -z "$BOOK_NAME" && -n "$book" ]] && BOOK_NAME="$book"
  [[ -z "$title" ]] && title="$slug"

  # Display label: prefer "Vol V Ch C: Title", degrade gracefully.
  label="$title"
  if [[ -n "$ch" ]]; then
    if [[ -n "$vol" ]]; then label="Vol ${vol} Ch ${ch}: ${title}"; else label="Ch ${ch}: ${title}"; fi
  fi

  routing="${topics:-$title}"
  suffix=""
  [[ -n "$pages" ]] && suffix=" (printed pp. ${pages})"

  # Numeric sort key: volume then chapter, missing → 0. Non-numeric coerces to 0.
  # Force base-10 (10#): a zero-padded chapter like 08/09 is otherwise read as
  # octal by printf %d and crashes ("invalid octal number").
  vnum=$(printf '%s' "${vol:-0}" | grep -oE '^[0-9]+' || echo 0)
  cnum=$(printf '%s' "${ch:-0}" | grep -oE '^[0-9]+' || echo 0)
  key=$(printf '%04d%04d' "$((10#${vnum:-0}))" "$((10#${cnum:-0}))")

  ROWS+=("${key}"$'\t'"- [[${slug}|${label}]] — ${routing}${suffix}")
done < <(find "$BOOK_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | sort || true)

[[ -z "$BOOK_NAME" ]] && BOOK_NAME="$BOOK_SLUG"

{
  echo "# ${BOOK_NAME} — Reference Index"
  echo ""
  echo "*Auto-generated from chapter frontmatter. Deep-reference tier: gated handbook chapters,"
  echo "not synthesized articles. Do not edit; run scripts/regenerate-reference-index.sh.*"
  echo ""
  echo "## Chapters"
  echo ""
  if [[ ${#ROWS[@]} -gt 0 ]]; then
    printf '%s\n' "${ROWS[@]}" | sort | cut -f2-
  else
    echo "*No chapters ingested yet.*"
  fi
} > "$INDEX"

echo "regenerate-reference-index: wrote $INDEX (${#ROWS[@]} chapter(s))"
