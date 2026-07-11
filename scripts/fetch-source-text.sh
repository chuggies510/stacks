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
  # a STITCHED + reworded quote: page renders an em-dash and has intervening
  # text the agent dropped; the quote joins two spans with a comma. Longest-run
  # + punctuation-flatten must still verify it.
  page3='<p>discriminated unions are the killer feature for this style &mdash; they are as close as the language gets. lots of other words here. zod is great, use it at every boundary.</p>'
  q3="the killer feature for this style, they are as close as the language gets. zod is great"
  s3=$(printf '%s' "$page3" | "$0" --stdin --quote "$q3" --max-words 400 2>/tmp/.fst_err3); s3e=$(cat /tmp/.fst_err3); rm -f /tmp/.fst_err3
  echo "$s3e" | grep -q 'QUOTE_FOUND=1' && echo "SELF-CHECK PASS [stitched-reworded-quote]" || { echo "SELF-CHECK FAIL [stitched-reworded-quote]: $s3e"; fail=1; }
  # a genuinely absent quote must NOT verify (guard against over-loose matching)
  q4="this sentence appears nowhere on the fetched page whatsoever indeed"
  s4e=$(printf '%s' "$page3" | "$0" --stdin --quote "$q4" --max-words 400 2>&1 >/dev/null)
  echo "$s4e" | grep -q 'QUOTE_FOUND=0' && echo "SELF-CHECK PASS [absent-quote-rejected]" || { echo "SELF-CHECK FAIL [absent-quote-rejected]: $s4e"; fail=1; }
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

def flat(s):
    # normalize smart punctuation to ASCII so a quote recorded with straight
    # quotes/hyphens still matches a page that renders curly quotes / en/em
    # dashes / nbsp — otherwise real web prose false-negatives the re-verify.
    for a, b in (("‘","'"),("’","'"),("“",'"'),("”",'"'),
                 ("–","-"),("—","-"),("‒","-"),("‑","-"),
                 ("…","..."),(" "," ")):
        s = s.replace(a, b)
    s = re.sub(r"[^0-9A-Za-z ]", " ", s)   # drop punctuation to spaces (match-only)
    return re.sub(r"\s+", " ", s).strip()

def longest_run(qwords, pagef):
    # longest run of consecutive qwords appearing contiguously in pagef;
    # returns (run_len_words, char_pos_of_that_run). Tolerates the agent
    # stitching two passages or swapping a dash for a comma.
    best_len, best_pos = 0, -1
    L = len(qwords); i = 0
    while i < L:
        sub, pos, j = "", -1, i
        while j < L:
            trial = (sub + " " + qwords[j]).strip()
            p = pagef.find(trial)
            if p == -1: break
            sub, pos, j = trial, p, j + 1
        if (j - i) > best_len: best_len, best_pos = j - i, pos
        i += 1
    return best_len, best_pos

pagef = flat(raw)
run_len, run_pos = 0, -1
if quote:
    qwords = flat(quote).split()
    run_len, run_pos = longest_run(qwords, pagef)
    # verified if a solid contiguous run of the quote is on the page (8 words,
    # or the whole quote when shorter). An absent/hallucinated quote shares no
    # long run; a stitched or lightly-reworded real quote does.
    thresh = min(8, len(qwords)) if qwords else 1
    qfound = "1" if run_len >= thresh else "0"

out = raw
if n > maxw:
    excerpted = 1
    if quote and qfound == "1" and run_pos >= 0:
        frac = run_pos / max(len(pagef), 1)
        center = int(frac * n)
        half = maxw // 2
        lo = max(0, center - half); hi = min(n, lo + maxw); lo = max(0, hi - maxw)
        out = " ".join(words[lo:hi])
        rl2, _ = longest_run(qwords, flat(out))
        if rl2 < (min(8, len(qwords)) if qwords else 1):
            out = raw   # window missed the passage; keep full text
            excerpted = 0
    else:
        out = " ".join(words[:maxw])

sys.stderr.write("WORDS=%d EXCERPTED=%d QUOTE_FOUND=%s\n" % (n, excerpted, qfound))
sys.stdout.write(out + "\n")
'
