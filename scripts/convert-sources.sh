#!/usr/bin/env bash
set -uo pipefail

# Convert non-text source files in a directory to readable text sidecars so the
# source-extractor agent never reads a binary blind. PDF and Office docs become
# text; images, scanned PDFs (no text layer), and unknown binaries are skipped
# and reported, never garbled or silently truncated. Originals are archived (not
# deleted) so provenance survives.
#
# This is the single conversion stage shared by catalog-sources (--from staging
# and direct drops into sources/incoming/) — type-awareness lives here, once.
#
# Usage:
#   convert-sources.sh <incoming_dir> <archive_dir>
#
# Arguments:
#   incoming_dir   Directory whose top-level files are converted in place; text
#                  sidecars are written here. Only depth-1 files are touched.
#   archive_dir    Directory where each converted/skipped original is moved.
#                  Created on demand. Pass-through text files are left alone.
#
# Output (stdout): one line per file then a summary —
#   PASSTHROUGH: <file>
#   CONVERTED:   <file>  ->  <sidecar>
#   SKIPPED:     <file>  (<reason>)
#
# Exit codes:
#   0   Always, unless arguments are invalid. A skipped file is a reported
#       outcome, not a failure — the operator decides what to do about it.
#   2   Invalid arguments.
#
# Tools (each used only for the formats that need it; absence → skip-and-report,
# never a crash): uv (fetches pdfplumber ephemerally) for PDF, pandoc for .docx,
# libreoffice headless for legacy/spreadsheet/slide formats.
#
# ponytail: serial, one file at a time. A 400-page PDF can take ~30-60s under
# pdfplumber; parallelize only if a real batch makes this the bottleneck.

if [[ $# -ne 2 ]]; then
  echo "usage: convert-sources.sh <incoming_dir> <archive_dir>" >&2
  exit 2
fi

INCOMING=$1
ARCHIVE=$2
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$INCOMING" ]]; then
  echo "ERROR: incoming dir does not exist: $INCOMING" >&2
  exit 2
fi

n_pass=0 n_conv=0 n_skip=0
skipped_names=()   # #16: name each archived failure in the summary so it stays visible

archive_original() {
  mkdir -p "$ARCHIVE"
  local dest
  dest=$(bash "$SCRIPT_DIR/collision-dest.sh" "$ARCHIVE" "$(basename "$1")")
  mv "$1" "$dest"
}

# Write text to a non-colliding <stem>.txt sidecar in INCOMING. Echoes the path.
sidecar_path() {
  local stem; stem=$(basename "$1"); stem=${stem%.*}
  bash "$SCRIPT_DIR/collision-dest.sh" "$INCOMING" "$stem.txt"
}

extract_pdf() {  # $1 file -> stdout text (empty if no text layer / failure)
  command -v uv >/dev/null 2>&1 || return 1
  uv run --no-project --with pdfplumber python3 - "$1" 2>/dev/null <<'PY'
import sys, re, pdfplumber
out = []
try:
    with pdfplumber.open(sys.argv[1]) as pdf:
        for page in pdf.pages:
            # layout=True keeps multi-column standards in reading order; the cost
            # is whitespace padding, squeezed below so it doesn't bloat tokens.
            t = page.extract_text(layout=True)
            if t:
                out.append(t)
except Exception:
    sys.exit(1)
text = "\n\n".join(out)
text = re.sub(r"[ \t]+\n", "\n", text)   # drop trailing whitespace
text = re.sub(r"\n{3,}", "\n\n", text)   # collapse blank-line runs
sys.stdout.write(text)
PY
}

extract_xlsx_sheets() {  # $1 xlsx, $2 outdir -> writes one <sheet>.csv per non-empty
                         # sheet; returns 1 if none produced (caller falls back).
  # #17: `libreoffice --convert-to csv` exports only the active sheet, silently
  # dropping the rest of a multi-sheet workbook. openpyxl (via uv, ephemeral) reads
  # every sheet. Handles .xlsx/.xlsm only — .xls/.ods still go through libreoffice.
  command -v uv >/dev/null 2>&1 || return 1
  uv run --no-project --with openpyxl python3 - "$1" "$2" 2>/dev/null <<'PY'
import sys, csv, os, re
from openpyxl import load_workbook
src, outdir = sys.argv[1], sys.argv[2]
try:
    wb = load_workbook(src, read_only=True, data_only=True)
except Exception:
    sys.exit(1)
n = 0
for ws in wb.worksheets:
    rows = [["" if c is None else c for c in row] for row in ws.iter_rows(values_only=True)]
    while rows and all(str(c) == "" for c in rows[-1]):
        rows.pop()
    if not rows:
        continue                       # skip an empty sheet — no CSV for nothing
    safe = re.sub(r"[^A-Za-z0-9._-]+", "-", ws.title).strip("-") or f"sheet{n+1}"
    with open(os.path.join(outdir, f"{safe}.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        for r in rows:
            w.writerow(r)
    n += 1
sys.exit(0 if n else 1)
PY
}

lo_convert() {  # $1 file, $2 target ext (txt|csv) -> echoes produced file or fails
  command -v libreoffice >/dev/null 2>&1 || return 1
  local out; out=$(mktemp -d)
  # Bare target ext lets LibreOffice pick the right export filter per source type
  # (Calc→csv, Writer/Impress→txt). Explicit filter strings are fragile across
  # source types; an unconvertible type just yields nothing → caught below.
  libreoffice --headless -env:UserInstallation="file:///tmp/lo_stacks_$$" \
    --convert-to "$2" --outdir "$out" "$1" >/dev/null 2>&1 || { rm -rf "$out"; return 1; }
  local produced; produced=$(find "$out" -maxdepth 1 -type f | head -1)
  [[ -s "$produced" ]] || { rm -rf "$out"; return 1; }
  echo "$produced"
}

report_converted() { n_conv=$((n_conv+1)); echo "CONVERTED:   $(basename "$1")  ->  $(basename "$2")"; }
report_skipped()   { n_skip=$((n_skip+1)); skipped_names+=("$(basename "$1")"); echo "SKIPPED:     $(basename "$1")  ($2)"; }
report_pass()      { n_pass=$((n_pass+1)); echo "PASSTHROUGH: $(basename "$1")"; }

while IFS= read -r -d '' f; do
  ext=${f##*.}; ext=${ext,,}
  case "$ext" in
    md|markdown|txt|text|html|htm|csv|tsv|json|xml|rst|org|tex|yaml|yml)
      report_pass "$f" ;;

    pdf)
      text=$(extract_pdf "$f")
      if [[ -n "${text//[[:space:]]/}" ]]; then
        side=$(sidecar_path "$f"); printf '%s' "$text" > "$side"
        archive_original "$f"; report_converted "$f" "$side"
      else
        archive_original "$f"
        if command -v uv >/dev/null 2>&1; then
          report_skipped "$f" "no text layer — likely scanned, needs OCR"
        else
          report_skipped "$f" "uv not installed — cannot extract PDF"
        fi
      fi ;;

    docx)
      if command -v pandoc >/dev/null 2>&1 \
         && text=$(pandoc -t markdown "$f" 2>/dev/null) && [[ -n "${text//[[:space:]]/}" ]]; then
        side=$(sidecar_path "$f"); printf '%s' "$text" > "$side"
        archive_original "$f"; report_converted "$f" "$side"
      elif produced=$(lo_convert "$f" txt); then
        side=$(sidecar_path "$f"); mv "$produced" "$side"
        archive_original "$f"; report_converted "$f" "$side"
      else
        archive_original "$f"; report_skipped "$f" "no pandoc/libreoffice — cannot convert .docx"
      fi ;;

    xlsx|xlsm)
      # #17: one CSV sidecar per non-empty sheet (openpyxl); libreoffice single-
      # sheet export is the fallback when uv/openpyxl is unavailable.
      sheetdir=$(mktemp -d)
      if extract_xlsx_sheets "$f" "$sheetdir"; then
        stem=$(basename "$f"); stem=${stem%.*}
        while IFS= read -r produced; do
          sheet=$(basename "$produced" .csv)
          side=$(bash "$SCRIPT_DIR/collision-dest.sh" "$INCOMING" "$stem-$sheet.csv")
          mv "$produced" "$side"; report_converted "$f" "$side"
        done < <(find "$sheetdir" -maxdepth 1 -type f -name '*.csv' | sort)
        rm -rf "$sheetdir"; archive_original "$f"
      elif produced=$(lo_convert "$f" csv); then
        rm -rf "$sheetdir"
        side=$(sidecar_path "$f"); mv "$produced" "$side"
        archive_original "$f"; report_converted "$f" "$side"
      else
        rm -rf "$sheetdir"
        archive_original "$f"; report_skipped "$f" "no openpyxl/libreoffice — cannot convert spreadsheet"
      fi ;;

    xls|ods)
      if produced=$(lo_convert "$f" csv); then
        side=$(sidecar_path "$f"); mv "$produced" "$side"
        archive_original "$f"; report_converted "$f" "$side"
      else
        archive_original "$f"; report_skipped "$f" "no libreoffice — cannot convert spreadsheet"
      fi ;;

    doc|odt|rtf|ppt|pptx)
      if produced=$(lo_convert "$f" txt); then
        side=$(sidecar_path "$f"); mv "$produced" "$side"
        archive_original "$f"; report_converted "$f" "$side"
      else
        archive_original "$f"; report_skipped "$f" "no libreoffice — cannot convert $ext"
      fi ;;

    jpg|jpeg|png|gif|tiff|tif|bmp|webp|svg|heic|heif)
      archive_original "$f"; report_skipped "$f" "image — extraction disabled (no OCR)" ;;

    *)
      archive_original "$f"; report_skipped "$f" "unknown/binary type .$ext — skipped" ;;
  esac
done < <(find "$INCOMING" -maxdepth 1 -type f ! -name ".gitkeep" -print0 2>/dev/null)

echo "convert-sources: $n_pass passthrough, $n_conv converted, $n_skip skipped (archived to $ARCHIVE)"
# #16: the per-file SKIPPED lines scroll away; a failed input archived to the
# gitignored archive dir is then easy to forget. Name each one in a summary line
# so the operator sees exactly what needs attention (OCR, a missing tool, a
# binary that should be dropped).
if [[ $n_skip -gt 0 ]]; then
  echo "convert-sources: archived unconverted, need attention: ${skipped_names[*]}"
fi
exit 0
