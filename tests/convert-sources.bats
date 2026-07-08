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

# Build a multi-sheet .xlsx fixture with openpyxl. Each arg is "SheetName:r,r;r,r".
build_xlsx() {
  local dest=$1; shift
  uv run --no-project --with openpyxl python3 - "$dest" "$@" 2>/dev/null <<'PY'
import sys
from openpyxl import Workbook
wb = Workbook(); wb.remove(wb.active)
for spec in sys.argv[2:]:
    name, rows = spec.split(":", 1)
    ws = wb.create_sheet(title=name)
    for row in rows.split(";"):
        ws.append(row.split(","))
wb.save(sys.argv[1])
PY
}

@test "single-sheet xlsx converts to one csv sidecar; original archived" {
  command -v uv >/dev/null 2>&1 || skip "uv not installed"
  build_xlsx "$IN/sched.xlsx" "Costs:tag,unit_cost,years;AHU-1,12000,20" || skip "openpyxl unavailable"
  run_convert
  [ "$status" -eq 0 ]
  [ -f "$IN/sched-Costs.csv" ]
  [ -f "$RAW/sched.xlsx" ]
  [ ! -f "$IN/sched.xlsx" ]
  grep -q "AHU-1" "$IN/sched-Costs.csv"
}

@test "multi-sheet xlsx yields one csv sidecar per sheet (#17)" {
  command -v uv >/dev/null 2>&1 || skip "uv not installed"
  build_xlsx "$IN/book.xlsx" "Equipment:tag,cost;AHU-1,12000" "Schedule:room,cfm;101,400" || skip "openpyxl unavailable"
  run_convert
  [ "$status" -eq 0 ]
  [ -f "$IN/book-Equipment.csv" ]
  [ -f "$IN/book-Schedule.csv" ]
  grep -q "AHU-1" "$IN/book-Equipment.csv"
  grep -q "400"   "$IN/book-Schedule.csv"
  [ -f "$RAW/book.xlsx" ]
  [ ! -f "$IN/book.xlsx" ]
}

@test "each skipped failure is named in the summary line (#16)" {
  printf 'fake'   > "$IN/scan.png"
  printf 'random' > "$IN/blob.xyz"
  run_convert
  [[ "$output" == *"archived unconverted, need attention:"* ]]
  [[ "$output" == *"scan.png"* ]]
  [[ "$output" == *"blob.xyz"* ]]
}

@test "no summary failure line when nothing was skipped (#16)" {
  printf '# ok\n' > "$IN/notes.md"
  run_convert
  [[ "$output" != *"need attention"* ]]
}

@test "invalid args exit 2" {
  run bash "$SCRIPT" only-one-arg
  [ "$status" -eq 2 ]
}
