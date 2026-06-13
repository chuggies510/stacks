#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  A="$TEST_TMP/stack/articles"
  mkdir -p "$A"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/rank-articles.sh"
  cat > "$A/vav.md" <<'EOF'
---
title: VAV Box Operation
tags: [airflow]
---
A variable air volume box modulates airflow to each zone with reheat at minimum flow.
EOF
  cat > "$A/econ.md" <<'EOF'
---
title: Airside Economizer Controls
tags: [controls]
---
Free cooling with outside air. VAV systems often pair with economizers.
EOF
}

teardown() { rm -rf "$TEST_TMP"; }

@test "ranks body matches, not just title — title-only would miss this" {
  # 'reheat' appears only in the vav body, not in any title. A title-only
  # search returns nothing; body search must surface vav.md.
  run bash "$SCRIPT" 3 "reheat minimum flow" "$A"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"vav.md"* ]]
}

@test "title hit outranks a lone body mention" {
  # 'economizer' is in econ's title (+5) and econ's body; vav only mentions it
  # in passing. econ must rank first.
  run bash "$SCRIPT" 3 "economizer" "$A"
  [[ "${lines[0]}" == *"econ.md"* ]]
}

@test "all-stopword query yields no ranking signal (empty)" {
  run bash "$SCRIPT" 3 "how do you" "$A"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no keyword match yields empty (caller treats as no-match)" {
  run bash "$SCRIPT" 3 "refrigerant superheat compressor" "$A"
  [ -z "$output" ]
}

@test "top_n caps the result count" {
  run bash "$SCRIPT" 1 "vav air cooling" "$A"
  [ "${#lines[@]}" -eq 1 ]
}

@test "searches multiple stack dirs together" {
  mkdir -p "$TEST_TMP/stack2/articles"
  cat > "$TEST_TMP/stack2/articles/pump.md" <<'EOF'
---
title: Chilled Water Pumping
---
Primary-secondary pumping decouples flow.
EOF
  run bash "$SCRIPT" 5 "pumping flow" "$A" "$TEST_TMP/stack2/articles"
  [[ "$output" == *"pump.md"* ]]
}

@test "invalid args exit 2" {
  run bash "$SCRIPT" 3
  [ "$status" -eq 2 ]
}
