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

@test "title containing [[ ]] markup produces no nested brackets in index" {
  cat > "$STACK/articles/wikilink-title.md" <<'EOF'
---
title: Bash [[test]] conditional syntax
tags:
  - airflow
---
Body.
EOF
  bash "$SCRIPT" "$STACK"
  # display label must not contain [[ or ]]
  ! grep -qF '[[wikilink-title|Bash [[test]]' "$STACK/index.md"
  grep -qF '[[wikilink-title|Bash test conditional syntax]]' "$STACK/index.md"
}

@test "inline flow-list tags group by first tag, not uncategorized (#18)" {
  # STACK.md's template demonstrates the inline form; normalize-tags.sh accepts it.
  # regenerate-moc must too, or an inline-tagged article silently lands in
  # 'uncategorized' despite carrying a valid tag.
  cat > "$STACK/articles/econ.md" <<'EOF'
---
title: Economizer
tags: [controls, airflow]
---
Body.
EOF
  bash "$SCRIPT" "$STACK"
  grep -qF '### controls' "$STACK/index.md"
  ! grep -qF '### uncategorized' "$STACK/index.md"
  grep -qF '[[econ|Economizer]]' "$STACK/index.md"
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
