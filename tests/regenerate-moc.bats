#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  STACK="$TEST_TMP/hvac"
  mkdir -p "$STACK/articles"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/regenerate-moc.sh"
  cat > "$STACK/articles/vav.md" <<'EOF'
---
title: VAV Box
routing: Minimum airflow for VAV boxes — how low can the minimum go
tags:
  - airflow
---
Body.
EOF
  cat > "$STACK/articles/legacy.md" <<'EOF'
---
title: Legacy Article
tags:
  - airflow
---
Body, no routing field (synthesized before #59).
EOF
}

teardown() { rm -rf "$TEST_TMP"; }

@test "article with routing renders as a recognition line" {
  run bash "$SCRIPT" "$STACK"
  [ "$status" -eq 0 ]
  grep -qF '[[vav|VAV Box]] — Minimum airflow for VAV boxes — how low can the minimum go' "$STACK/index.md"
}

@test "article without routing renders as a bare link (backward compat)" {
  bash "$SCRIPT" "$STACK"
  grep -qxF -- '- [[legacy|Legacy Article]]' "$STACK/index.md"
}

@test "preserves the Reading Paths section verbatim" {
  cat > "$STACK/index.md" <<'EOF'
# hvac: Map of Contents

## Articles

### old

## Reading Paths

- Start with [[vav]] then read the rest.
EOF
  bash "$SCRIPT" "$STACK"
  grep -qF 'Start with [[vav]] then read the rest.' "$STACK/index.md"
}
