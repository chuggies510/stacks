#!/usr/bin/env bash
set -uo pipefail

# Fetch a URL and emit its main text as faithful publication text — NOT a
# model summary. enrich-stack Step 7 stages the result as a source body, where
# the grounding-discipline rule (#79) requires real published text (a model
# summary would make the grounding chain model-grounded-in-model, and the
# post-stage quote re-verify would fail on the reworded text).
#
# WebFetch cannot be used here: it "answers a prompt using a small fast model",
# so it always returns generated text, never the raw page. This helper does the
# raw fetch (curl) + tag strip instead.
#
# Size: by default the whole cleaned page is emitted (store-full-by-default).
# Above --max-words, a HEAD span would risk dropping a supporting passage that
# sits late on the page (a shortlog, a diffstat), so when --quote is given the
# span is centered on the quote — the grounding passage is always included, and
# it is a contiguous excerpt (headings and surrounding text intact), not a
# claim-tailored sentence. Print "EXCERPTED" / "QUOTE_FOUND=..." to stderr so
# the caller can set the header's `**Excerpt:**` line honestly.
#
# Usage:
#   fetch-source-text.sh <url> [--quote "<supporting quote>"] [--max-words N]
#
# Output (stdout): cleaned publication text.
# Output (stderr): WORDS=<n>  EXCERPTED=<0|1>  QUOTE_FOUND=<0|1|NA>
# Exit codes: 0 ok; 2 bad args; 3 fetch failed / empty.

URL="" QUOTE="" MAXWORDS=1500 STDIN=0 SELFCHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --quote) QUOTE="${2:-}"; shift 2 ;;
    --max-words) MAXWORDS="${2:-1500}"; shift 2 ;;
    --stdin) STDIN=1; shift ;;      # read raw HTML from stdin instead of curl (testing/piping)
    --self-check) SELFCHECK=1; shift ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) if [ -z "$URL" ]; then URL="$1"; shift; else echo "extra arg: $1" >&2; exit 2; fi ;;
  esac
done

if [ "$SELFCHECK" = 1 ]; then
  # A 3000-word body with the supporting quote near the END: a head-truncate
  # would drop it (the bug this helper fixes). Assert the windowed excerpt keeps
  # the quote and stays within the cap.
  Q="the boost knob was wired up for active mode"
  body=$(python3 -c 'print("filler word "*1490 + "SECTION HEADER the boost knob was wired up for active mode tail text " + "filler word "*20)')
  out=$(printf '<html><body><p>%s</p></body></html>' "$body" | "$0" --stdin --quote "$Q" --max-words 400 2>/tmp/.fst_err)
  err=$(cat /tmp/.fst_err); rm -f /tmp/.fst_err
  fail=0
  echo "$out" | tr -s '[:space:]' ' ' | grep -Fq "$Q" && echo "SELF-CHECK PASS [quote-survives-windowing]" || { echo "SELF-CHECK FAIL [quote-survives-windowing]"; fail=1; }
  wc=$(echo "$out" | wc -w | tr -d ' '); [ "$wc" -le 420 ] && echo "SELF-CHECK PASS [respects-cap] ($wc words)" || { echo "SELF-CHECK FAIL [respects-cap] ($wc words)"; fail=1; }
  echo "$err" | grep -q 'EXCERPTED=1' && echo "SELF-CHECK PASS [reports-excerpted]" || { echo "SELF-CHECK FAIL [reports-excerpted]: $err"; fail=1; }
  # short body with quote → full text, not excerpted
  short=$(printf '<p>a short page mentioning the boost knob was wired up for active mode here</p>')
  sout=$(printf '%s' "$short" | "$0" --stdin --quote "$Q" --max-words 400 2>/tmp/.fst_err2); serr=$(cat /tmp/.fst_err2); rm -f /tmp/.fst_err2
  echo "$serr" | grep -q 'EXCERPTED=0' && echo "SELF-CHECK PASS [short-body-full]" || { echo "SELF-CHECK FAIL [short-body-full]: $serr"; fail=1; }
  exit $fail
fi

[ -n "$URL" ] || [ "$STDIN" = 1 ] || { echo "usage: fetch-source-text.sh <url> [--quote ...] [--max-words N]" >&2; exit 2; }

if [ "$STDIN" = 1 ]; then
  RAW=$(cat)
else
  RAW=$(curl -sSL --max-time 45 -A 'Mozilla/5.0 (compatible; stacks-enrich/1)' "$URL" 2>/dev/null)
fi
[ -n "$RAW" ] || { echo "WORDS=0 EXCERPTED=0 QUOTE_FOUND=NA" >&2; echo "fetch failed or empty: ${URL:-<stdin>}" >&2; exit 3; }

printf '%s' "$RAW" | QUOTE="$QUOTE" MAXWORDS="$MAXWORDS" python3 -c '
import sys, os, re, html
raw = sys.stdin.read()
raw = re.sub(r"<script.*?</script>", " ", raw, flags=re.S|re.I)
raw = re.sub(r"<style.*?</style>", " ", raw, flags=re.S|re.I)
raw = re.sub(r"<(br|/p|/div|/li|/tr|/h[1-6])\s*/?>", "\n", raw, flags=re.I)
raw = re.sub(r"<[^>]+>", " ", raw)
raw = html.unescape(raw)
raw = re.sub(r"[ \t]+", " ", raw)
raw = re.sub(r"\n[ \t]+", "\n", raw)
raw = re.sub(r"\n{3,}", "\n\n", raw).strip()

quote = os.environ.get("QUOTE", "").strip()
maxw = int(os.environ.get("MAXWORDS", "1500"))
words = raw.split()
n = len(words)
excerpted = 0
qfound = "NA" if not quote else "0"

def flat(s): return re.sub(r"\s+", " ", s).strip()

if quote:
    qfound = "1" if flat(quote) in flat(raw) else "0"

out = raw
if n > maxw:
    excerpted = 1
    if quote and qfound == "1":
        # window centered on the quote, snapped to whitespace, headings intact
        fr = flat(raw); fq = flat(quote)
        pos = fr.find(fq)
        # map flattened pos back to an approximate word index
        frac = pos / max(len(fr), 1)
        center = int(frac * n)
        half = maxw // 2
        lo = max(0, center - half); hi = min(n, lo + maxw); lo = max(0, hi - maxw)
        out = " ".join(words[lo:hi])
        # widen once if the quote fell just outside the naive window
        if fq not in flat(out):
            out = raw  # fall back to full text rather than drop the passage
            excerpted = 0
    else:
        out = " ".join(words[:maxw])

sys.stderr.write("WORDS=%d EXCERPTED=%d QUOTE_FOUND=%s\n" % (n, excerpted, qfound))
sys.stdout.write(out + "\n")
'
