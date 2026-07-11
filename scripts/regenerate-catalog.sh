#!/usr/bin/env bash
set -euo pipefail
# Root-catalog count refresher: rewrite the "(N articles, N sources)" tail on each
# stack row of the library's root catalog.md to live filesystem counts. Nothing
# else in the pipeline touches this file after new-stack appends a row, so its
# counts froze at scaffold time (a cataloged stack still read "0 articles, 0
# sources"). Idempotent; preserves each row's link + authored description.
#
# Usage: regenerate-catalog.sh <library_root>
# Reads:  <library_root>/catalog.md and each <library_root>/<dir>/{articles,sources}
# Writes: <library_root>/catalog.md

LIBRARY="${1:?Usage: regenerate-catalog.sh <library_root>}"
CATALOG="$LIBRARY/catalog.md"
[[ -f "$CATALOG" ]] || { echo "regenerate-catalog.sh: no catalog.md at $LIBRARY" >&2; exit 1; }

# Count a stack's articles (articles/*.md) and filed sources (everything under
# sources/ except the incoming queue, the .raw conversion archive, trash, and
# .gitkeep placeholders) — the same exclusions the session-start enumerator uses.
count_articles() { find "$1/articles" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }
count_sources()  { find "$1/sources" -type f ! -name '.gitkeep' ! -path '*/incoming/*' ! -path '*/.raw/*' ! -path '*/trash/*' 2>/dev/null | wc -l | tr -d ' '; }

TMP=$(mktemp)
while IFS= read -r line || [[ -n "$line" ]]; do
  # A stack row is `- [Label](dir/) — description …`. Pull the dir from the link
  # target; anything else (headers, blanks) passes through verbatim.
  dir=$(printf '%s' "$line" | sed -nE 's/^- \[[^]]*\]\(([^)/]+)\/\).*/\1/p')
  if [[ -n "$dir" && -d "$LIBRARY/$dir" ]]; then
    a=$(count_articles "$LIBRARY/$dir"); s=$(count_sources "$LIBRARY/$dir")
    count="($a articles, $s sources)"
    # Replace only the FINAL parenthetical (the count) — descriptions contain
    # their own parens, so anchor to end-of-line and forbid nested parens.
    if printf '%s' "$line" | grep -qE '\([^()]*\)[[:space:]]*$'; then
      line=$(printf '%s' "$line" | sed -E "s/\([^()]*\)[[:space:]]*$/$count/")
    else
      line="$line $count"   # row never had a count tail — append one
    fi
  fi
  printf '%s\n' "$line"
done < "$CATALOG" > "$TMP"
mv "$TMP" "$CATALOG"
