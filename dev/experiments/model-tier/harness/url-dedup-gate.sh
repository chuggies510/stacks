#!/usr/bin/env bash
# url-dedup-gate.sh  (enrichment stage, verify-and-fix recipe — #109)
#
# The DETERMINISTIC meta-gate for enrichment's dedup decision. Given a candidate
# source URL and the set of already-filed source URLs, answer: is this URL
# already in the stack? Prints exactly `DUP` or `NEW`.
#
# Why this is a gate and not a model judgment: per DESIGN-local-tier.md, the
# model's ONE object judgment is grounding (does this passage state the claim,
# at what tier); URL de-duplication is pure SET-MEMBERSHIP after normalization —
# no content understanding required — so it is exactly the meta-decision the
# harness should own instead of asking a local model to notice "haven't I seen
# this URL before" (the dedup miss the enrichment benchmark names as the
# model's only failure mode).
#
# Normalization: lowercase the host, strip scheme (http/https), strip a leading
# `www.`, strip a trailing slash, strip any `#fragment`. Path is kept as-is
# (case-sensitive) since paths can legitimately be case-sensitive.
#
#   bash url-dedup-gate.sh <candidate-url> <filed-urls-file>
#   bash url-dedup-gate.sh <candidate-url> -          # filed list on stdin
#   bash url-dedup-gate.sh --self-check
set -euo pipefail

normalize_url() { # <url> -> normalized host+path[+query]
  local u="$1" query="" base host rest=""
  u="${u%%#*}"                    # strip #fragment
  u=$(sed -E 's#^[Hh][Tt][Tt][Pp][Ss]?://##' <<<"$u")  # strip scheme, case-insensitive
  # Split off the query BEFORE any path/slash handling so (a) a query on a
  # slash-less URL (example.com?x=A) is not swallowed into the host and
  # lowercased, and (b) the trailing-slash strip applies to the PATH, not to a
  # path that happens to precede a query (path?q vs path/?q must match). Query
  # values are kept case-sensitive — they can be (codex #109).
  case "$u" in *\?*) query="?${u#*\?}"; base="${u%%\?*}" ;; *) base="$u" ;; esac
  base="${base%/}"                 # strip one trailing slash from the path
  host="${base%%/*}"
  case "$base" in */*) rest="/${base#*/}" ;; esac
  host="${host,,}"                 # lowercase host only
  host="${host#www.}"              # strip leading www.
  printf '%s%s%s' "$host" "$rest" "$query"
}

is_dup() { # <candidate-url> <filed-newline-list> -> 0 if a normalized match exists
  local cand; cand=$(normalize_url "$1")
  local filed="$2" f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ "$cand" == "$(normalize_url "$f")" ]] && return 0
  done <<<"$filed"
  return 1
}

gate() { if is_dup "$1" "$2"; then echo DUP; else echo NEW; fi; }

load_filed() { # <file-or-dash> -> newline url list
  if [[ "$1" == "-" ]]; then cat
  elif [[ -f "$1" ]]; then grep -vE '^\s*$' "$1"
  else echo "ERROR: filed-urls source not found: $1" >&2; return 1; fi
}

self_check() {
  local filed; filed=$(printf '%s\n' "https://example.com/article" "https://arxiv.org/abs/2306.05685" "https://example.com/search?q=Cats")
  local fail=0
  chk() { local got; got=$(gate "$1" "$filed"); [[ "$got" == "$2" ]] || { echo "FAIL: '$1' -> got '$got' want '$2'"; fail=1; }; }
  chk "http://example.com/article"              "DUP"  # scheme differs
  chk "https://www.example.com/article"         "DUP"  # www differs
  chk "https://example.com/article/"            "DUP"  # trailing slash differs
  chk "https://example.com/article#section"     "DUP"  # fragment differs
  chk "HTTPS://EXAMPLE.COM/article"              "DUP"  # host case differs
  chk "https://example.com/other-article"       "NEW"  # different path
  chk "https://arxiv.org/abs/2306.05686"         "NEW"  # different id, near-miss path
  chk "https://example.com/search/?q=Cats"      "DUP"  # trailing slash BEFORE the query still normalizes (codex #109)
  chk "https://example.com/search?q=cats"       "NEW"  # query VALUE case differs -> fail-closed to NEW, not lowercased to DUP
  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS"; else echo "SELF-CHECK FAIL"; return 1; fi
}

case "${1:-}" in
  --self-check) self_check ;;
  "") echo "Usage: url-dedup-gate.sh <candidate-url> <filed-urls-file|-> | --self-check" >&2; exit 2 ;;
  *) [[ -n "${2:-}" ]] || { echo "Usage: url-dedup-gate.sh <candidate-url> <filed-urls-file|->" >&2; exit 2; }
     # Capture the loader separately so a missing filed-set FAILS (exit 1) rather
     # than being masked in a command substitution and falling through to NEW —
     # a masked failure would authorize a duplicate URL as new (codex #109).
     filed=$(load_filed "$2") || exit 1
     gate "$1" "$filed" ;;
esac
