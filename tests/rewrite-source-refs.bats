#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  A="$TEST_TMP/stack/articles"
  mkdir -p "$A"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/rewrite-source-refs.sh"
  # Two ref forms in one article: frontmatter (stack-relative) and body
  # (library-relative, with a {stack}/ prefix). Both must be rewritten.
  cat > "$A/vav.md" <<'EOF'
---
sources:
  - sources/incoming/pnnl-vav-guide.md
title: VAV Box
---
Minimum airflow per hvac/sources/incoming/pnnl-vav-guide.md guidance.
EOF
}

teardown() { rm -rf "$TEST_TMP"; }

@test "rewrites incoming ref to publisher dir in both frontmatter and body" {
  run bash "$SCRIPT" "$A" "pnnl-vav-guide.md" "pnnl"
  [ "$status" -eq 0 ]
  ! grep -q 'sources/incoming/' "$A/vav.md"
  grep -q 'sources/pnnl/pnnl-vav-guide.md' "$A/vav.md"        # frontmatter form
  grep -q 'hvac/sources/pnnl/pnnl-vav-guide.md' "$A/vav.md"   # body prefix preserved
}

@test "leaves a different source's incoming ref untouched" {
  echo '  - sources/incoming/other.md' >> "$A/vav.md"
  run bash "$SCRIPT" "$A" "pnnl-vav-guide.md" "pnnl"
  grep -q 'sources/incoming/other.md' "$A/vav.md"
}

@test "no-op when no article references the file" {
  cp "$A/vav.md" /tmp/before-$$.md
  run bash "$SCRIPT" "$A" "unrelated.md" "acme"
  [ "$status" -eq 0 ]
}

@test "empty articles dir does not error" {
  rm -f "$A"/*.md
  run bash "$SCRIPT" "$A" "x.md" "pub"
  [ "$status" -eq 0 ]
}

@test "missing articles dir exits 0 (nothing to rewrite)" {
  run bash "$SCRIPT" "$TEST_TMP/nope" "x.md" "pub"
  [ "$status" -eq 0 ]
}

@test "invalid args exit 2" {
  run bash "$SCRIPT" "$A" "only-two"
  [ "$status" -eq 2 ]
}
