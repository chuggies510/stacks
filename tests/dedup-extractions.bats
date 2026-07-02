#!/usr/bin/env bats

# Covers the stacks#65 fix: source_paths are normalized to bare `sources/...`
# at W1b, regardless of the prefix the extractor echoed.

setup() {
  TEST_TMP=$(mktemp -d)
  EXTR="$TEST_TMP/extractions"
  mkdir -p "$EXTR"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/dedup-extractions.py"
  cat > "$EXTR/batch-1-concepts.md" <<'EOF'
## Concept: Legacy wiring hazards

slug: legacy-wiring-hazards
title: Legacy wiring hazards
source_paths:
  - electrical/sources/incoming/cpsc-legacy.md
  - sources/incoming/neta-field.md
target_article: ""
tier: 1

### Claims
- Knob-and-tube wiring lacks a ground.
EOF
}

teardown() { rm -rf "$TEST_TMP"; }

@test "strips a leading <stack>/ prefix from source_paths" {
  run python3 "$SCRIPT" "$EXTR" "$EXTR/_dedup.md"
  [ "$status" -eq 0 ]
  grep -q '^  - sources/incoming/cpsc-legacy.md$' "$EXTR/_dedup.md"
  ! grep -q 'electrical/sources/' "$EXTR/_dedup.md"
}

@test "leaves an already-bare source_path unchanged" {
  python3 "$SCRIPT" "$EXTR" "$EXTR/_dedup.md"
  grep -q '^  - sources/incoming/neta-field.md$' "$EXTR/_dedup.md"
}

@test "warns and records a slug shared by two different-titled concepts" {
  cat > "$EXTR/batch-2-concepts.md" <<'EOF'
## Concept: Arc-fault breakers

slug: legacy-wiring-hazards
title: Arc-fault breakers
source_paths:
  - sources/incoming/nec-arc-fault.md
target_article: ""
tier: 4

### Claims
- AFCIs detect arcing conditions on branch circuits.
EOF
  run python3 "$SCRIPT" "$EXTR" "$EXTR/_dedup.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
  [[ "$output" == *"legacy-wiring-hazards"* ]]
  [[ "$output" == *"Legacy wiring hazards"* ]]
  [[ "$output" == *"Arc-fault breakers"* ]]
  grep -q '^TITLE_MISMATCH_SLUGS=.*legacy-wiring-hazards' "$EXTR/_dedup-meta.txt"
}
