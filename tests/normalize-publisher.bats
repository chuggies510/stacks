#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  SRC="$TEST_TMP/sources"
  mkdir -p "$SRC"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/normalize-publisher.sh"
}

teardown() { rm -rf "$TEST_TMP"; }

@test "lowercases, strips trailing punctuation, collapses separators" {
  run bash "$SCRIPT" "IBTInc." "$SRC"
  [ "$status" -eq 0 ]
  [ "$output" = "ibtinc" ]
}

@test "collapses dots to hyphens (up.codes -> up-codes)" {
  run bash "$SCRIPT" "up.codes" "$SRC"
  [ "$output" = "up-codes" ]
}

@test "reuses an existing dir matching the normalized slug" {
  mkdir -p "$SRC/up-codes"
  run bash "$SCRIPT" "Up.Codes" "$SRC"
  [ "$output" = "up-codes" ]
}

@test "reuses an existing dir via the tld-stripped variant (cpsc.gov -> cpsc)" {
  mkdir -p "$SRC/cpsc"
  run bash "$SCRIPT" "cpsc.gov" "$SRC"
  [ "$output" = "cpsc" ]
}

@test "no existing dir: keeps full normalized slug, does not over-strip" {
  run bash "$SCRIPT" "cpsc.gov" "$SRC"
  [ "$output" = "cpsc-gov" ]
}

@test "empty publisher -> unknown" {
  run bash "$SCRIPT" "" "$SRC"
  [ "$output" = "unknown" ]
}
