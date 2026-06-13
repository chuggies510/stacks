#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  IN="$TEST_TMP/in"; RAW="$TEST_TMP/raw"
  mkdir -p "$IN"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/convert-sources.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

run_convert() {
  run bash -c '"$1" "$2" "$3" 2>&1' _ "$SCRIPT" "$IN" "$RAW"
}

@test "text files pass through untouched, not archived" {
  printf '# notes\n' > "$IN/notes.md"
  printf 'plain\n'   > "$IN/readme.txt"
  run_convert
  [ "$status" -eq 0 ]
  [ -f "$IN/notes.md" ]
  [ -f "$IN/readme.txt" ]
  [[ "$output" == *"PASSTHROUGH: notes.md"* ]]
}

@test "images are skipped and archived, never left in incoming" {
  printf 'fake' > "$IN/diagram.png"
  run_convert
  [ ! -f "$IN/diagram.png" ]
  [ -f "$RAW/diagram.png" ]
  [[ "$output" == *"SKIPPED:     diagram.png"* ]]
  [[ "$output" == *"image"* ]]
}

@test "unknown binary types are skipped and archived" {
  printf 'random' > "$IN/blob.xyz"
  run_convert
  [ ! -f "$IN/blob.xyz" ]
  [ -f "$RAW/blob.xyz" ]
  [[ "$output" == *"unknown/binary"* ]]
}

@test ".gitkeep is ignored" {
  touch "$IN/.gitkeep"
  run_convert
  [ -f "$IN/.gitkeep" ]
  [[ "$output" == *"0 passthrough, 0 converted, 0 skipped"* ]]
}

@test "PDF with a text layer converts to a sidecar; original archived" {
  command -v uv >/dev/null 2>&1 || skip "uv not installed"
  uv run --no-project --with reportlab python3 - "$IN/doc.pdf" <<'PY' 2>/dev/null || skip "reportlab unavailable"
import sys
from reportlab.pdfgen import canvas
c = canvas.Canvas(sys.argv[1]); c.drawString(72, 720, "Economizer required above 54000 Btu/h."); c.save()
PY
  run_convert
  [ -f "$IN/doc.txt" ]
  [ -f "$RAW/doc.pdf" ]
  [ ! -f "$IN/doc.pdf" ]
  grep -q "Economizer" "$IN/doc.txt"
  [[ "$output" == *"CONVERTED:   doc.pdf"* ]]
}

@test "xlsx converts to a csv-text sidecar via libreoffice; original archived" {
  command -v libreoffice >/dev/null 2>&1 || skip "libreoffice not installed"
  printf 'tag,unit_cost,years\nAHU-1,12000,20\n' > "$TEST_TMP/sched.csv"
  libreoffice --headless -env:UserInstallation="file:///tmp/lo_bats_$$" \
    --convert-to xlsx --outdir "$IN" "$TEST_TMP/sched.csv" >/dev/null 2>&1 || skip "xlsx build failed"
  run_convert
  [ -f "$IN/sched.txt" ]
  [ -f "$RAW/sched.xlsx" ]
  [ ! -f "$IN/sched.xlsx" ]
  grep -q "AHU-1" "$IN/sched.txt"
}

@test "invalid args exit 2" {
  run bash "$SCRIPT" only-one-arg
  [ "$status" -eq 2 ]
}
