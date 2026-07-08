#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/assert-structure.sh"
}

teardown() {
  rm -rf "$TEST_TMP"
}

run_script() {
  local file=$1 type=$2 label=${3:-testlabel}
  run bash -c '"$1" "$2" "$3" "$4" 2>&1' _ "$SCRIPT" "$file" "$type" "$label"
}

# ── concept-batch ──────────────────────────────────────────────────────────────

@test "concept-batch: valid file passes" {
  local f="$TEST_TMP/batch.md"
  printf '## Concept: heat-exchanger\nsome content\n' > "$f"
  run_script "$f" concept-batch
  [ "$status" -eq 0 ]
}

@test "concept-batch: missing header fails" {
  local f="$TEST_TMP/batch.md"
  printf 'no concept header here\n' > "$f"
  run_script "$f" concept-batch
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# ── concept-batch: receipted-empty sentinel for a pure-reference source (#93) ──

@test "concept-batch: no-concepts sentinel with a reason passes" {
  local f="$TEST_TMP/batch.md"
  printf '# no-concepts: pure CLI flag reference, no behavior knowledge\n' > "$f"
  run_script "$f" concept-batch
  [ "$status" -eq 0 ]
}

@test "concept-batch: reason-less no-concepts sentinel fails" {
  local f="$TEST_TMP/batch.md"
  printf '# no-concepts:\n' > "$f"
  run_script "$f" concept-batch
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "concept-batch: junk line above the sentinel fails (sentinel must be sole non-blank line)" {
  local f="$TEST_TMP/batch.md"
  printf 'stray prose the extractor left behind\n# no-concepts: pure CLI flag reference\n' > "$f"
  run_script "$f" concept-batch
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "concept-batch: sentinel with surrounding blank lines still passes" {
  local f="$TEST_TMP/batch.md"
  printf '\n# no-concepts: pure reference\n\n' > "$f"
  run_script "$f" concept-batch
  [ "$status" -eq 0 ]
}

@test "concept-batch: whitespace-only reason fails" {
  local f="$TEST_TMP/batch.md"
  printf '# no-concepts:    \n' > "$f"
  run_script "$f" concept-batch
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "concept-batch: empty file fails" {
  local f="$TEST_TMP/batch.md"
  : > "$f"
  run_script "$f" concept-batch
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "dedup-md: no-concepts sentinel does NOT pass (dedup never emits one)" {
  local f="$TEST_TMP/dedup.md"
  printf '# no-concepts: whatever\n' > "$f"
  run_script "$f" dedup-md
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# ── dedup-md ───────────────────────────────────────────────────────────────────

@test "dedup-md: valid file passes" {
  local f="$TEST_TMP/dedup.md"
  printf '## Concept: thermal-mass\ncontent\n' > "$f"
  run_script "$f" dedup-md
  [ "$status" -eq 0 ]
}

@test "dedup-md: missing header fails" {
  local f="$TEST_TMP/dedup.md"
  printf 'no header\n' > "$f"
  run_script "$f" dedup-md
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# ── dedup-meta ─────────────────────────────────────────────────────────────────

@test "dedup-meta: valid file passes" {
  local f="$TEST_TMP/dedup-meta.txt"
  printf 'ALL_SLUGS=heat-exchanger thermal-mass\n' > "$f"
  run_script "$f" dedup-meta
  [ "$status" -eq 0 ]
}

@test "dedup-meta: missing ALL_SLUGS key fails" {
  local f="$TEST_TMP/dedup-meta.txt"
  printf 'SOME_OTHER=value\n' > "$f"
  run_script "$f" dedup-meta
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "dedup-meta: empty ALL_SLUGS value fails" {
  local f="$TEST_TMP/dedup-meta.txt"
  printf 'ALL_SLUGS=\n' > "$f"
  run_script "$f" dedup-meta
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# ── article-md ─────────────────────────────────────────────────────────────────

@test "article-md: valid file passes" {
  local f="$TEST_TMP/article.md"
  printf 'title: Heat Exchanger Types\nlast_verified: ""\n' > "$f"
  run_script "$f" article-md
  [ "$status" -eq 0 ]
}

@test "article-md: missing title fails" {
  local f="$TEST_TMP/article.md"
  printf 'last_verified: ""\n' > "$f"
  run_script "$f" article-md
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "article-md: missing last_verified fails" {
  local f="$TEST_TMP/article.md"
  printf 'title: Heat Exchanger Types\n' > "$f"
  run_script "$f" article-md
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# ── audit-findings ─────────────────────────────────────────────────────────────
# The audit gate no longer keys on a today-dated last_verified (#87 T7); the
# per-batch validator file must carry a VALIDATED receipt row per assigned article.

@test "audit-findings: file with a VALIDATED receipt row passes" {
  local f="$TEST_TMP/_audit-0.md"
  printf 'VALIDATED\tvav-box\t1700000000\n' > "$f"
  run_script "$f" audit-findings
  [ "$status" -eq 0 ]
}

@test "audit-findings: receipts mixed with CORRECTION/SOFTSPOT rows pass" {
  local f="$TEST_TMP/_audit-0.md"
  printf 'VALIDATED\tvav-box\t1700000000\nCORRECTION\tvav-box\t"30%%"->"20%%"\nVALIDATED\tchiller\t1700000000\nSOFTSPOT\tchiller\tsome claim\tno source\n' > "$f"
  run_script "$f" audit-findings
  [ "$status" -eq 0 ]
}

@test "audit-findings: file with only CORRECTION rows (no receipt) fails" {
  local f="$TEST_TMP/_audit-0.md"
  printf 'CORRECTION\tvav-box\t"30%%"->"20%%"\n' > "$f"
  run_script "$f" audit-findings
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "audit-findings: empty file fails" {
  local f="$TEST_TMP/_audit-0.md"
  : > "$f"
  run_script "$f" audit-findings
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# ── enrichment-findings ────────────────────────────────────────────────────────

@test "enrichment-findings: valid file passes" {
  local f="$TEST_TMP/enrich.md"
  printf 'CANDIDATE\tgap-0\tprompt-engineering\t\thttps://x/y\t1\tTitle\tquote\n' >  "$f"
  printf 'NOSOURCE\tgap-1\tcontext-mgmt\t\t\t\t\tno source found\n'              >> "$f"
  run_script "$f" enrichment-findings
  [ "$status" -eq 0 ]
}

@test "enrichment-findings: malformed line fails" {
  local f="$TEST_TMP/enrich.md"
  printf 'CANDIDATE\tgap-0\tslug\t\turl\t1\tTitle\tquote\n' >  "$f"
  printf 'garbage line with no kind\n'                      >> "$f"
  run_script "$f" enrichment-findings
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "enrichment-findings: wrong field count fails" {
  local f="$TEST_TMP/enrich.md"
  # 6 fields (an un-stripped tab would shift columns like this)
  printf 'CANDIDATE\tgap-0\tslug\turl\t1\tquote\n' > "$f"
  run_script "$f" enrichment-findings
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "enrichment-findings: empty file fails" {
  local f="$TEST_TMP/enrich.md"
  : > "$f"
  run_script "$f" enrichment-findings
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# ── unknown type ───────────────────────────────────────────────────────────────

@test "unknown type fails" {
  local f="$TEST_TMP/file.md"
  printf 'content\n' > "$f"
  run_script "$f" bogus-type
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}
