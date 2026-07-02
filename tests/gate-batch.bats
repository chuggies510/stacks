#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/gate-batch.sh"
  # Past epoch: any file written now will have mtime > this.
  EPOCH=1
  # Future epoch: no file written before the heat death of the universe passes.
  FUTURE_EPOCH=9999999999
}

teardown() {
  rm -rf "$TEST_TMP"
}

make_concept_batch() {
  local f=$1
  printf '## Concept: heat-exchanger\nsome content\n' > "$f"
  touch "$f"
}

@test "passes when all paths are fresh and well-structured" {
  local f1="$TEST_TMP/batch-1-concepts.md"
  local f2="$TEST_TMP/batch-2-concepts.md"
  make_concept_batch "$f1"
  make_concept_batch "$f2"
  run bash "$SCRIPT" "$EPOCH" "concept-identifier" concept-batch "$f1" "$f2"
  [ "$status" -eq 0 ]
}

@test "fails and lists all missing paths (aggregates failures)" {
  local f1="$TEST_TMP/batch-1-concepts.md"
  local f2="$TEST_TMP/batch-2-concepts.md"
  make_concept_batch "$f1"
  # f2 intentionally absent
  run bash "$SCRIPT" "$EPOCH" "concept-identifier" concept-batch "$f1" "$f2"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AGENT_WRITE_FAILURE"* ]]
  [[ "$output" == *"batch-2-concepts.md"* ]]
}

@test "fails when file is present but stale (mtime <= epoch)" {
  local f="$TEST_TMP/batch-1-concepts.md"
  make_concept_batch "$f"
  # FUTURE_EPOCH is after the file's mtime, so the write check trips.
  run bash "$SCRIPT" "$FUTURE_EPOCH" "concept-identifier" concept-batch "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AGENT_WRITE_FAILURE"* ]]
}

@test "rejects an empty dispatch_epoch instead of silently passing stale files" {
  # Regression: an epoch lost across a skill bash-block boundary arrives as "".
  # `(( mtime < "" ))` is a swallowed arithmetic error that ungated every file.
  local f="$TEST_TMP/batch-1-concepts.md"
  make_concept_batch "$f"
  touch -d 2020-01-01 "$f"   # stale: must NOT pass
  run bash "$SCRIPT" "" "concept-identifier" concept-batch "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dispatch_epoch must be a positive integer"* ]]
}

@test "rejects a non-numeric dispatch_epoch" {
  local f="$TEST_TMP/batch-1-concepts.md"
  make_concept_batch "$f"
  run bash "$SCRIPT" "not-a-number" "concept-identifier" concept-batch "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dispatch_epoch must be a positive integer"* ]]
}

@test "skips structure check when structure_kind is -" {
  local f="$TEST_TMP/batch-1.md"
  # Content has no concept header — would fail structure check.
  printf 'no concept header\n' > "$f"
  run bash "$SCRIPT" "$EPOCH" "some-agent" - "$f"
  [ "$status" -eq 0 ]
}
