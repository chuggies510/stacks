#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  STACK="$TEST_TMP/plumbing"
  BOOK="aspe-pedh"
  BOOK_DIR="$STACK/reference/$BOOK"
  mkdir -p "$BOOK_DIR"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/regenerate-reference-index.sh"
  cat > "$BOOK_DIR/vol2-ch06-domestic-water-heating.md" <<'EOF'
---
book: ASPE Plumbing Engineering Design Handbook
book_slug: aspe-pedh
volume: 2
chapter: 6
title: Domestic Water Heating
topics: water heater sizing, recirculation, legionella
printed_pages: "155-198"
gate: PASS
---
Body.
EOF
  cat > "$BOOK_DIR/vol2-ch04-piping.md" <<'EOF'
---
book: ASPE Plumbing Engineering Design Handbook
book_slug: aspe-pedh
volume: 2
chapter: 4
title: Piping Systems
topics: pipe sizing, materials
printed_pages: "90-120"
gate: PASS
---
Body.
EOF
}

teardown() { rm -rf "$TEST_TMP"; }

@test "chapter renders as a recognition line with topics + printed pages" {
  run bash "$SCRIPT" "$STACK" "$BOOK"
  [ "$status" -eq 0 ]
  grep -qF '[[vol2-ch06-domestic-water-heating|Vol 2 Ch 6: Domestic Water Heating]] — water heater sizing, recirculation, legionella (printed pp. 155-198)' "$BOOK_DIR/index.md"
}

@test "chapters sort by volume then chapter, not filename/lexical" {
  bash "$SCRIPT" "$STACK" "$BOOK"
  # ch04 must appear before ch06 in the emitted map
  ch04_line=$(grep -n 'ch04' "$BOOK_DIR/index.md" | cut -d: -f1)
  ch06_line=$(grep -n 'ch06' "$BOOK_DIR/index.md" | cut -d: -f1)
  [ "$ch04_line" -lt "$ch06_line" ]
}

@test "H1 uses the book: field, not the slug" {
  bash "$SCRIPT" "$STACK" "$BOOK"
  grep -qxF '# ASPE Plumbing Engineering Design Handbook — Reference Index' "$BOOK_DIR/index.md"
}

@test "index.md itself is excluded from the chapter list" {
  bash "$SCRIPT" "$STACK" "$BOOK"
  # a second run must not list the just-written index.md as a chapter
  bash "$SCRIPT" "$STACK" "$BOOK"
  ! grep -qF '[[index|' "$BOOK_DIR/index.md"
}

@test "topics absent → falls back to title as the routing line" {
  cat > "$BOOK_DIR/vol1-ch01-intro.md" <<'EOF'
---
book: ASPE Plumbing Engineering Design Handbook
volume: 1
chapter: 1
title: Introduction
gate: PASS
---
Body.
EOF
  bash "$SCRIPT" "$STACK" "$BOOK"
  grep -qF '[[vol1-ch01-intro|Vol 1 Ch 1: Introduction]] — Introduction' "$BOOK_DIR/index.md"
}

@test "empty book dir yields a valid index with a placeholder" {
  EMPTY_BOOK_DIR="$STACK/reference/empty-book"
  mkdir -p "$EMPTY_BOOK_DIR"
  run bash "$SCRIPT" "$STACK" "empty-book"
  [ "$status" -eq 0 ]
  grep -qF '## Chapters' "$EMPTY_BOOK_DIR/index.md"
  grep -qF 'No chapters ingested yet' "$EMPTY_BOOK_DIR/index.md"
}

@test "zero-padded chapter (08/09) does not crash the octal-sensitive sort key" {
  cat > "$BOOK_DIR/vol2-ch08-storm-drainage.md" <<'EOF'
---
book: ASPE Plumbing Engineering Design Handbook
volume: 2
chapter: 08
title: Storm Drainage
topics: roof drains, sizing
printed_pages: "230-260"
gate: PASS
---
Body.
EOF
  run bash "$SCRIPT" "$STACK" "$BOOK"
  [ "$status" -eq 0 ]
  grep -qF '[[vol2-ch08-storm-drainage|Vol 2 Ch 08: Storm Drainage]]' "$BOOK_DIR/index.md"
  # sorts after ch06 (8 > 6), not lexically mangled
  ch06_line=$(grep -n 'ch06' "$BOOK_DIR/index.md" | cut -d: -f1)
  ch08_line=$(grep -n 'ch08' "$BOOK_DIR/index.md" | cut -d: -f1)
  [ "$ch06_line" -lt "$ch08_line" ]
}

@test "missing book dir errors non-zero" {
  run bash "$SCRIPT" "$STACK" "nonexistent-book"
  [ "$status" -ne 0 ]
}
