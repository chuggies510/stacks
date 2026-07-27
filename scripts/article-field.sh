#!/usr/bin/env bash
# article-field.sh <field> <article.md>
#
# THE definition of how a stacks article's frontmatter field is read. Prints the
# value on stdout and exits 0; exits 1 printing nothing when the field is absent
# or written in a shape this format does not support.
#
# Source it to get `article_field` as a shell function (no subprocess per call):
#   source scripts/article-field.sh
#   title=$(article_field title "$f") || title=""
#
# Article frontmatter LOOKS like YAML but is not: 27 of the 1,174 articles in the
# live library fail a real YAML parse (unquoted `: ` inside values, a leading `@`).
# It is a line-oriented format — `key: value`, first occurrence wins — and treating
# it as YAML is what makes a reader disagree with the corpus.
#
# It exists because there were two readers. regenerate-moc.sh built index.md with a
# one-line awk, and the extraction harness grew a second, stricter one that refused
# frontmatter the pipeline renders happily — the same drift #136 was about, one layer
# down. Two readers of one format will diverge; the only question is when you notice.
# One extraction, and each caller decides its own policy on a refusal: regenerate-moc.sh
# emits a bare wiki-link, the menu builder refuses to run.
#
# NOT a bug-for-bug clone of the old inline awk. It is identical on all 1,174 corpus
# articles (verified: every index.md regenerates byte-for-byte), and deliberately
# STRICTER on shapes the corpus does not contain, because each of those made the old
# reader emit text that was wrong rather than absent:
#   - a field found outside the frontmatter block  -> absent  (was: the body's value)
#   - `title:NoSpace`                              -> absent  (was: "oSpace", a mid-word slice)
#   - a whitespace-only value                      -> absent  (was: a dangling em dash)
#   - no closing delimiter                         -> absent  (was: read on into the body)
# A missing description makes a caller refuse or degrade. A wrong one gets believed.

article_field() {
  local field="${1:?usage: article_field <field> <article.md>}"
  local article="${2:?usage: article_field <field> <article.md>}"
  [[ -r "$article" ]] || return 1

  # The whole frontmatter block must be present and closed before any value is
  # trusted: without a closing delimiter there is no way to tell frontmatter from
  # body, so a `title:` further down the file is body prose, not the article's title.
  # Nothing is printed until the closing delimiter is reached. The field name is
  # passed through the environment rather than -v, because -v processes backslash
  # escapes in the value.
  FIELD="$field" awk '
    BEGIN { k = ENVIRON["FIELD"]; status = 1 }
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }   # delimiter must be line 1
    /^---[[:space:]]*$/ { closed = 1; exit }                # end of frontmatter
    index($0, k ":") == 1 && !have {
      # The single space after the colon is part of the format. Without it the
      # historical substr() sliced mid-word and produced a plausible-looking value.
      if (substr($0, length(k) + 2, 1) != " ") { malformed = 1; exit }
      v = substr($0, length(k) + 3)
      sub(/\r$/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      have = 1
    }
    END {
      if (closed && have && !malformed && v != "") { print v; status = 0 }
      exit status
    }
  ' "$article"
}

# Only run as a script when executed directly, so the file can also be sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  article_field "$@"
fi
