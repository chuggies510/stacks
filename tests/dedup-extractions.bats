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
  grep -q '^  - sources/incoming/cpsc-legacy.md (tier 1)$' "$EXTR/_dedup.md"
  ! grep -q 'electrical/sources/' "$EXTR/_dedup.md"
}

@test "leaves an already-bare source_path unchanged" {
  python3 "$SCRIPT" "$EXTR" "$EXTR/_dedup.md"
  grep -q '^  - sources/incoming/neta-field.md (tier 1)$' "$EXTR/_dedup.md"
}

@test "preserves per-source tier when one slug merges blocks of different tiers (stacks#89)" {
  # Same slug across two batches, Tier 1 source then Tier 4 source. The merged block
  # must carry each source's own tier inline, not collapse both to the first-seen tier.
  cat > "$EXTR/batch-2-concepts.md" <<'EOF'
## Concept: Legacy wiring hazards
slug: legacy-wiring-hazards
title: Legacy wiring hazards
source_paths:
  - sources/incoming/some-blog.md
target_article: ""
tier: 4

### Claims
- A blog notes knob-and-tube runs are common in pre-1950 homes.
EOF
  run python3 "$SCRIPT" "$EXTR" "$EXTR/_dedup.md"
  [ "$status" -eq 0 ]
  # Tier-1 sources from batch-1 keep tier 1; the Tier-4 blog from batch-2 keeps tier 4.
  grep -q '^  - sources/incoming/cpsc-legacy.md (tier 1)$' "$EXTR/_dedup.md"
  grep -q '^  - sources/incoming/some-blog.md (tier 4)$' "$EXTR/_dedup.md"
  # No collapsed block-level scalar tier line survives.
  ! grep -qE '^tier:' "$EXTR/_dedup.md"
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

@test "flags two new slugs with near-identical titles as a near-dup pair (stacks#78)" {
  cat > "$EXTR/batch-2-concepts.md" <<'EOF'
## Concept: Knob-and-tube wiring hazards

slug: knob-and-tube-hazards
title: Legacy wiring hazards in old homes
source_paths:
  - sources/incoming/cpsc-old-homes.md
target_article: ""
tier: 1

### Claims
- Knob-and-tube runs hot under insulation.
EOF
  run python3 "$SCRIPT" "$EXTR" "$EXTR/_dedup.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
  [[ "$output" == *"similar titles"* ]]
  grep -q '^NEAR_DUP_PAIRS=.*knob-and-tube-hazards~legacy-wiring-hazards\|^NEAR_DUP_PAIRS=.*legacy-wiring-hazards~knob-and-tube-hazards' "$EXTR/_dedup-meta.txt"
}

@test "does not flag two new slugs with unrelated titles" {
  cat > "$EXTR/batch-2-concepts.md" <<'EOF'
## Concept: Grounding electrode conductors

slug: grounding-electrode-conductors
title: Grounding electrode conductor sizing
source_paths:
  - sources/incoming/nec-250.md
target_article: ""
tier: 1

### Claims
- The GEC is sized from Table 250.66.
EOF
  run python3 "$SCRIPT" "$EXTR" "$EXTR/_dedup.md"
  [ "$status" -eq 0 ]
  grep -q '^NEAR_DUP_PAIRS=$' "$EXTR/_dedup-meta.txt"
}
