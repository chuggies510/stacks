#!/usr/bin/env bash
# slug-prematch.sh  (extraction stage, verify-and-fix recipe — #109)
#
# The DETERMINISTIC half of the reuse-vs-mint meta-judgment. Extraction's failure
# is slug over-proliferation: a weak tier mints a NEW slug for a concept an
# existing article already covers (a fragment). Full reuse-vs-mint is partly a
# CONTENT judgment (does the concept fall in an existing article's described
# scope?) that only the model/cloud can make — but the mechanical part leaves the
# model per the DESIGN principle (harness owns every meta-decision it can).
#
# Given a candidate slug and the existing slug set, emit exactly one of:
#   REUSE:<slug>  exact match after normalization (case/separator) — force reuse,
#                 never mint a duplicate. Slug immutability is a hard constraint.
#   NEAR:<slug>   token-set containment (candidate tokens ⊆ existing, or vice
#                 versa) — a LIKELY fragment. Route to cloud verify WITH this hint;
#                 do not auto-reuse (it may be a legitimately distinct sibling).
#   NEW           no overlap — a genuine mint candidate. Still cloud-verified
#                 against the scope map for SEMANTIC fragments this gate can't see
#                 (e.g. agent-rl-fine-tuning vs agent-harness-engineering — no
#                 shared tokens, so only the cloud verifier catches it).
#
# So the recipe is: model proposes → this gate forces exact collisions to reuse
# and flags containment fragments → cloud verifies every NEAR/NEW against the
# scope map. Over-mint can no longer ship a duplicate or an obvious fragment as a
# new article.
#
#   bash slug-prematch.sh <candidate> <existing-slugs-file|articles-dir>
#   bash slug-prematch.sh --self-check
# existing set: a file with one slug per line, OR a dir of {slug}.md (slugs = basenames).
set -euo pipefail

normalize() { # slug -> canonical kebab
  printf '%s' "$1" | tr '[:upper:] _' '[:lower:]--' \
    | sed -E 's/[^a-z0-9-]//g; s/-+/-/g; s/^-+//; s/-+$//'
}

# token-set containment: is set A ⊆ set B? (A,B are hyphen-split token lists)
subset() { # <a-tokens-newline> <b-tokens-newline>  -> 0 if A⊆B
  local a="$1" b="$2" t
  while IFS= read -r t; do [[ -z "$t" ]] && continue
    grep -qxF "$t" <<<"$b" || return 1
  done <<<"$a"
  return 0
}

prematch() { # <candidate> <existing-list-newline>
  local c; c=$(normalize "$1"); local existing="$2" e ctok etok
  # 1. exact/normalized collision
  while IFS= read -r e; do [[ -z "$e" ]] && continue
    [[ "$c" == "$(normalize "$e")" ]] && { echo "REUSE:$e"; return; }
  done <<<"$existing"
  # 2. token-containment (fragment signal)
  ctok=$(tr '-' '\n' <<<"$c" | grep -v '^$' | sort -u)
  while IFS= read -r e; do [[ -z "$e" ]] && continue
    etok=$(normalize "$e" | tr '-' '\n' | grep -v '^$' | sort -u)
    # require >1 shared structure: single-token candidates ({agent}) would subset
    # too many existing slugs, so only flag when the smaller set has ≥2 tokens.
    local small; small=$(( $(wc -l <<<"$ctok") < $(wc -l <<<"$etok") ? $(wc -l <<<"$ctok") : $(wc -l <<<"$etok") ))
    [[ $small -ge 2 ]] || continue
    if subset "$ctok" "$etok" || subset "$etok" "$ctok"; then echo "NEAR:$e"; return; fi
  done <<<"$existing"
  echo "NEW"
}

load_existing() { # <file-or-dir> -> newline slug list
  if [[ -d "$1" ]]; then ls "$1"/*.md 2>/dev/null | xargs -r -n1 basename | sed 's/\.md$//'
  elif [[ -f "$1" ]]; then grep -vE '^\s*$' "$1"
  else echo "ERROR: existing set not found: $1" >&2; return 1; fi
}

self_check() {
  local ex; ex=$(printf '%s\n' agent-harness-engineering agent-memory-systems context-engineering \
    llm-as-judge token-budget-management multi-agent-orchestration production-eval-systems \
    retrieval-augmented-generation)
  local fail=0
  chk() { local got; got=$(prematch "$1" "$ex"); [[ "$got" == "$2" ]] || { echo "FAIL: '$1' -> got '$got' want '$2'"; fail=1; }; }
  chk "llm-as-judge"              "REUSE:llm-as-judge"            # exact
  chk "LLM-As-Judge"             "REUSE:llm-as-judge"            # case-normalized
  chk "llm_as_judge"             "REUSE:llm-as-judge"            # separator-normalized
  chk "token-budget"             "NEAR:token-budget-management"  # candidate tokens ⊂ existing (fragment)
  chk "multi-agent-orchestration-patterns" "NEAR:multi-agent-orchestration" # existing tokens ⊂ candidate
  chk "agent-rl-fine-tuning"     "NEW"                           # SEMANTIC fragment, no shared tokens -> cloud verify's job
  chk "prompt-caching"           "NEW"                           # genuinely new, no overlap
  chk "agent-tools"              "NEW"                           # single shared token 'agent' must NOT trigger NEAR
  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS"; else echo "SELF-CHECK FAIL"; return 1; fi
}

case "${1:-}" in
  --self-check) self_check ;;
  "") echo "Usage: slug-prematch.sh <candidate> <existing-slugs-file|articles-dir> | --self-check" >&2; exit 2 ;;
  *) [[ -n "${2:-}" ]] || { echo "Usage: slug-prematch.sh <candidate> <existing-slugs-file|articles-dir>" >&2; exit 2; }
     prematch "$1" "$(load_existing "$2")" ;;
esac
