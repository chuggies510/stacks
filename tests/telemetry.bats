#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/telemetry.sh"
  export HOME="$TEST_TMP"           # redirect the log into the sandbox
  LOG="$TEST_TMP/.chuggiesmart/telemetry.jsonl"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "writes a base record with the skill name" {
  SKILL_NAME="stacks:lookup" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  run jq -r '.skill' "$LOG"
  [ "$output" = "stacks:lookup" ]
}

@test "merges TELEMETRY_EXTRA fields into the record" {
  SKILL_NAME="stacks:lookup" TELEMETRY_EXTRA='{"query":"vav sizing","articles":"VAV Systems"}' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  run jq -r '.query' "$LOG"
  [ "$output" = "vav sizing" ]
  run jq -r '.articles' "$LOG"
  [ "$output" = "VAV Systems" ]
}

@test "falls back to base record when TELEMETRY_EXTRA is malformed JSON" {
  SKILL_NAME="stacks:lookup" TELEMETRY_EXTRA='not json{' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  run jq -r '.skill' "$LOG"
  [ "$output" = "stacks:lookup" ]
  run jq -r '.query // "absent"' "$LOG"
  [ "$output" = "absent" ]
}

@test "ignores a non-object TELEMETRY_EXTRA (array)" {
  SKILL_NAME="stacks:lookup" TELEMETRY_EXTRA='[1,2,3]' run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  run jq -r '.skill' "$LOG"
  [ "$output" = "stacks:lookup" ]
}
