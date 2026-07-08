#!/usr/bin/env bash
set -uo pipefail

# Mine /stacks:lookup misses from telemetry and emit them as enrichment gap rows.
#
# A miss is a `stacks:lookup` telemetry record with empty `articles` (the lookup
# searched a stack but recognized no article) whose searched `stacks` set
# includes the target stack. These are the highest-signal gaps: live demand the
# library could not answer (#68). enrich-stack appends the emitted rows to its
# gap list and the enrichment agent searches the query directly.
#
# Usage:
#   lookup-misses.sh <stack> [<telemetry_file>] [<library>]
#
# <library> (optional): when given, only misses recorded against that exact
# library path are mined (stacks#73) — a shared global telemetry log serves many
# libraries, so a miss logged in library A must not seed library B's gap list.
# Records with no `.library` field (pre-#73) match no library filter and age out.
# A recency window (LOOKUP_MISS_WINDOW_DAYS, default 30) drops stale misses so the
# gap list tracks live demand, not every query ever run.
#
# Output (stdout): zero or more rows, one per distinct miss query, in the same
# tab layout enrich-stack reads (slug<TAB>claim<TAB>reason). The slug is the
# literal sentinel `lookup-miss` — a miss has no home article, and an empty slug
# field cannot survive a `read`/IFS=$'\t' round-trip (a leading tab is stripped
# as IFS whitespace, shifting every field left). Downstream keys on this slug:
#   lookup-miss<TAB>{query}<TAB>lookup miss
#
# Always exits 0 (missing/empty/garbled telemetry → no rows, never an error):
# this feeds an enrich run, and a telemetry hiccup must not break it.
MISS_SLUG="lookup-miss"

STACK="${1:?usage: lookup-misses.sh <stack> [telemetry_file] [library]}"
LOG="${2:-$HOME/.chuggiesmart/telemetry.jsonl}"
LIB="${3:-}"                                    # empty = no per-library scoping (legacy callers)
WINDOW_DAYS="${LOOKUP_MISS_WINDOW_DAYS:-30}"    # recency floor in days
[[ -f "$LOG" ]] || exit 0

# Recency cutoff as an ISO8601 UTC string. `.ts` is ISO8601 UTC, which sorts
# lexically == chronologically, so a string `>=` IS a correct time compare — no
# `date -d`/`date -v` host-portability trap. Computed with jq's `now` (portable).
CUTOFF=$(jq -rn --argjson w "$WINDOW_DAYS" '(now - ($w*86400)) | gmtime | strftime("%Y-%m-%dT%H:%M:%SZ")')

# -R reads each line raw so a malformed line can't abort the stream; fromjson?
# drops it silently. Membership test lowercases both sides and trims the spaces
# in a comma-joined set ("swe, llm"). Query whitespace (incl. tabs/newlines) is
# collapsed to single spaces so the emitted row stays exactly 3 tab-fields.
jq -rR --arg stack "$STACK" --arg lib "$LIB" --arg cutoff "$CUTOFF" '
  fromjson?
  | select(.skill == "stacks:lookup" and ((.articles // "") == ""))
  | select($lib == "" or (.library // "") == $lib)   # per-library scoping (#73)
  | select((.ts // "") >= $cutoff)                    # recency window (#73)
  | select(
      [ (.stacks // "") | ascii_downcase | split(",")[] | gsub("^ +| +$"; "") ]
      | index($stack | ascii_downcase) != null
    )
  | (.query // "") | gsub("[[:space:]]+"; " ") | gsub("^ +| +$"; "")
  | select(length > 0)
' "$LOG" | sort -u | while IFS= read -r q; do
  printf '%s\t%s\tlookup miss\n' "$MISS_SLUG" "$q"
done
