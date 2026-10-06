#!/usr/bin/env bats
# fetch-source-text.sh network paths. The stdin/windowing logic is covered by the
# script's own --self-check; these cases pin the fetch step (gzip #138, PDF #115,
# arXiv rewrite #116) with a stub curl and file:// PDFs, so no network is needed.

setup() {
  TEST_TMP=$(mktemp -d)
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/fetch-source-text.sh"
  mkdir "$TEST_TMP/bin"
  # Stub curl: records every arg, then serves $STUB_GZ the way an S3 object stored
  # with content-encoding gzip is served: always gzipped, decoded by curl only
  # when --compressed is passed.
  cat > "$TEST_TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_ARGS"
comp=0 out=
while [ $# -gt 0 ]; do
  case "$1" in --compressed) comp=1 ;; -o) out=$2; shift ;; esac
  shift
done
if [ $comp = 1 ]; then gzip -dc "$STUB_GZ"; else cat "$STUB_GZ"; fi > "${out:-/dev/stdout}"
STUB
  chmod +x "$TEST_TMP/bin/curl"
  export STUB_ARGS="$TEST_TMP/args" STUB_GZ="$TEST_TMP/body.gz"
  printf '<p>the surge tank pressure relief valve was resized during the retrofit</p>' | gzip > "$STUB_GZ"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# Run the script on $1 with the stub curl first on PATH; echo the URL curl got.
fetched_url() {
  PATH="$TEST_TMP/bin:$PATH" "$SCRIPT" "$1" >/dev/null 2>&1
  tail -1 "$STUB_ARGS"
}

mkpdf() {  # $1 out path, $2 page text ("" = a page with no text layer)
  python3 - "$1" "$2" <<'PY'
import sys
out, text = sys.argv[1], sys.argv[2]
stream = ("BT /F1 12 Tf 72 720 Td (%s) Tj ET" % text) if text else ""
objs = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R"
    " /Resources << /Font << /F1 5 0 R >> >> >>",
    "<< /Length %d >>\nstream\n%s\nendstream" % (len(stream), stream),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
]
pdf = "%PDF-1.4\n"
offs = []
for i, o in enumerate(objs, 1):
    offs.append(len(pdf))
    pdf += "%d 0 obj\n%s\nendobj\n" % (i, o)
x = len(pdf)
pdf += "xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
pdf += "".join("%010d 00000 n \n" % o for o in offs)
pdf += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, x)
open(out, "w", encoding="latin-1").write(pdf)
PY
}

need_pdfplumber() {
  command -v uv >/dev/null 2>&1 || skip "uv not installed"
  uv run --no-project --with pdfplumber python3 -c 'import pdfplumber' >/dev/null 2>&1 \
    || skip "pdfplumber unavailable"
}

@test "gzip-encoded page is decoded: curl gets --compressed, quote found (#138)" {
  run bash -c 'PATH="$1/bin:$PATH" "$2" https://example.com/p --quote "the surge tank pressure relief valve was resized" 2>&1' _ "$TEST_TMP" "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"QUOTE_FOUND=1"* ]]
  [[ "$output" == *"resized during the retrofit"* ]]
  grep -Fxq -- '--compressed' "$STUB_ARGS"
}

@test "arXiv /abs/ URLs are fetched as /pdf/, other URLs are untouched (#116)" {
  [ "$(fetched_url http://arxiv.org/abs/1706.03762v2)" = "https://arxiv.org/pdf/1706.03762v2" ]
  [ "$(fetched_url https://www.arxiv.org/abs/hep-th/9901001)" = "https://arxiv.org/pdf/hep-th/9901001" ]
  [ "$(fetched_url https://arxiv.org/pdf/1706.03762)" = "https://arxiv.org/pdf/1706.03762" ]
  [ "$(fetched_url https://arxiv.org/html/1706.03762)" = "https://arxiv.org/html/1706.03762" ]
  [ "$(fetched_url https://example.com/arxiv.org/abs/1)" = "https://example.com/arxiv.org/abs/1" ]
  [ "$(fetched_url https://web.archive.org/web/2020/https://arxiv.org/abs/1)" = "https://web.archive.org/web/2020/https://arxiv.org/abs/1" ]
}

@test "a PDF URL yields extracted text, not the PDF skeleton (#115)" {
  need_pdfplumber
  mkpdf "$TEST_TMP/doc.pdf" 'the boiler plant was recommissioned in March after the retrofit and if x < 5 and y > 3 then the valve closes'
  run bash -c '"$1" "file://$2" --quote "boiler plant was recommissioned in March after the retrofit" 2>&1' _ "$SCRIPT" "$TEST_TMP/doc.pdf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"QUOTE_FOUND=1"* ]]
  [[ "$output" != *"%PDF"* ]]
  [[ "$output" != *"endobj"* ]]
  # PDF text is not HTML: a bare < ... > must survive the tag strip
  [[ "$output" == *"x < 5 and y > 3"* ]]
}

@test "a PDF with no text layer exits 3, not the PDF skeleton (#115)" {
  need_pdfplumber
  mkpdf "$TEST_TMP/scan.pdf" ''
  run bash -c '"$1" "file://$2" 2>&1' _ "$SCRIPT" "$TEST_TMP/scan.pdf"
  [ "$status" -eq 3 ]
  [[ "$output" == *"fetch failed or empty"* ]]
  [[ "$output" != *"%PDF"* ]]
}
