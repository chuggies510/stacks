#!/usr/bin/env bash
# synth-shadow.sh <concept-block-file> <cloud-article-file|NONE> <item-id>
#
# Local-first, cloud-authoritative pilot for the stacks synthesis stage:
# runs the local model on ONE concept block, tag-postfilters the output,
# captures cheap structural metrics for local vs cloud, and appends one JSON
# line to <RUN_DIR>/synthesis.jsonl. The article-verifier grades quality
# (catalog Step 8.6); this script judges nothing.
set -euo pipefail

# The reply is an article only when its first non-blank line, after an optional
# opening code fence, is `---`. Keep from there and drop one closing fence. Anything
# else is a refusal (the contract's shortfall line) or malformed, never a draft.
EXTRACT_AWK='{a[++n]=$0} END{
    i=1; while (i<=n && a[i] ~ /^[[:space:]]*$/) i++
    if (i<=n && a[i] ~ /^```/) { i++; while (i<=n && a[i] ~ /^[[:space:]]*$/) i++ }
    if (i>n || a[i] != "---") exit 1
    j=n; while (j>i && a[j] ~ /^[[:space:]]*$/) j--
    if (a[j] ~ /^```[[:space:]]*$/) j--
    for (k=i; k<=j; k++) print a[k]
  }'

# shellcheck source=../../../../scripts/article-field.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../../scripts/article-field.sh"

# The `sources:` list is fully determined by the inputs, so the harness writes it: the
# pre-update article's paths (on an update) followed by the block's `source_paths`
# with the tier suffix removed. The drafter only writes prose; a path it dropped or
# mistyped (the 4-bit drafter wrote `sources/inimal/` twice) never reaches the draft.
set_sources() { # <block> <pre-update article, or a missing path for a new slug> <draft>
  { [[ ! -f "$2" ]] || article_list sources "$2"
             awk '/^source_paths:/{f=1;next} f&&/^[[:space:]]*-[[:space:]]/{sub(/^[[:space:]]*-[[:space:]]*/,""); sub(/[[:space:]]*\(tier [0-9]+\)[[:space:]]*$/,""); print; next} f{exit}' "$1"
  } | awk 'NF && !seen[$0]++' | article_set_list sources "$3"
}

# A new or updated article starts unverified; the audit stamps the date. A drafter
# reading the pre-update article copies its date, so the harness sets the field. A
# draft with no last_verified line is left as is, for the reviewer's structure check.
blank_verified() { article_set_field last_verified '""' "$1" 2>/dev/null || true; }

if [[ "${1:-}" == "--self-check" ]]; then
  fails=0
  chk() { local want="$1" got; got=$(printf '%b' "$2" | awk "$EXTRACT_AWK" | tr '\n' '|') || got="NONE"
    [[ "$got" == "$want" ]] || { echo "FAIL: [$2] gave [$got] want [$want]"; fails=$((fails+1)); }; }
  chk '---|t: x|---|Body.|' '---\nt: x\n---\nBody.\n'
  chk '---|t: x|---|Body.|' '\n```markdown\n---\nt: x\n---\nBody.\n```\n\n'
  chk 'NONE' 'Here is the article:\n---\nt: x\n---\n'
  chk 'NONE' 'Concept foo: insufficient claims - article not written.\n\n---\n'
  t=$(mktemp -d)
  printf -- '---\nsources:\n  - sources/a/old.md\n  - sources/b/kept.md\ntitle: P\n---\nBody.\n' > "$t/prior.md"
  printf 'slug: x\nsource_paths:\n  - sources/incoming/new.md (tier 3)\n  - sources/b/kept.md (tier 1)\ntarget_article: x\n\n### Claims\n- c\n' > "$t/block.md"
  printf -- '---\nsources:\n  - sources/inimal/new.md\ntitle: D\n---\nBody with sources:\n- bullet\n' > "$t/draft.md"
  set_sources "$t/block.md" "$t/prior.md" "$t/draft.md"
  got=$(article_list sources "$t/draft.md" | tr '\n' '|')
  [[ "$got" == 'sources/a/old.md|sources/b/kept.md|sources/incoming/new.md|' ]] || { echo "FAIL: sources gave [$got]"; fails=$((fails+1)); }
  grep -qx -- '- bullet' "$t/draft.md" || { echo "FAIL: body bullet lost"; fails=$((fails+1)); }
  printf -- '---\ntitle: D\n---\nBody.\n' > "$t/nosrc.md"
  set_sources "$t/block.md" NONE "$t/nosrc.md"
  got=$(article_list sources "$t/nosrc.md" | tr '\n' '|')
  [[ "$got" == 'sources/incoming/new.md|sources/b/kept.md|' ]] || { echo "FAIL: missing sources line not added, got [$got]"; fails=$((fails+1)); }
  printf -- '---\nlast_verified: "2026-07-10"\ntitle: D\n---\nBody.\n' > "$t/dated.md"
  blank_verified "$t/dated.md"
  got=$(article_field last_verified "$t/dated.md"); rm -rf "$t"
  [[ "$got" == '""' ]] || { echo "FAIL: last_verified left as [$got]"; fails=$((fails+1)); }
  [[ $fails -eq 0 ]] && echo "SELF-CHECK PASS (8 cases)" || exit 1
  exit 0
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Every run writes into its own folder (drafts, log), exported by shadow-synth-run.sh,
# so no two runs or variants ever share a draft file.
RUN_DIR="${RUN_DIR:?RUN_DIR must be this run folder, exported by shadow-synth-run.sh}"
INFER="$HERE/local-infer.sh"
POSTFILTER="$HERE/tag-postfilter.sh"
NORMALIZER="$HERE/citation-normalizer.sh"
MODEL="$(bash "$HERE/local-infer.sh" --model)"
RUN_ID="${RUN_ID:-manual}"
# Both exported by shadow-synth-run.sh: the target stack's allowed_tags, and its
# absolute directory (STACK.md and index.md are read from there).
VOCAB="${TAG_VOCAB:?TAG_VOCAB must hold the allowed_tags of the stack}"
STACK_DIR="${STACK_DIR:?STACK_DIR must be the absolute path of the target stack}"

concept_file="${1:?Usage: synth-shadow.sh <concept-block-file> <cloud-article-file|NONE> <item-id>}"
cloud_file="${2:?}"
item_id="${3:?}"
[[ -f "$concept_file" ]] || { echo "ERROR: concept block not found: $concept_file" >&2; exit 1; }
# Pre-update snapshot catalog.sh dedup took before W2 overwrote the article; absent for a new slug.
prior_file="$(dirname "$concept_file")/_prior-$item_id.md"

# Remove any prior local draft for this slug up front: a failed inference below
# exits before the fresh cp, so without this an earlier run's stale draft would
# survive and get graded against THIS run's block (codex, #109). No draft is the
# correct state on inference failure — the advisory verify then skips the slug.
rm -f "$RUN_DIR/bodies/${item_id}__local.md"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

in_vocab() { local t="$1" v; for v in $VOCAB; do [[ "$t" == "$v" ]] && return 0; done; return 1; }

# metrics_for <file> -> "words citations tags_total tags_in_vocab has_title has_last_verified has_sources has_routing"
metrics_for() {
  local f="$1" fm body words cites tags_total=0 tags_ok=0 in_list=0 t
  fm=$(awk '/^---$/{c++; if(c==2) exit; next} c==1' "$f")
  body=$(awk 'BEGIN{c=0} /^---$/{c++; next} c>=2' "$f")
  words=$(wc -w <<< "$body" | tr -d ' ')
  cites=$(sed -E 's/\[\[[^]]*\]\]//g' <<< "$body" | grep -oE '\[[a-zA-Z0-9][a-zA-Z0-9._-]*\]' | wc -l | tr -d ' ')
  while IFS= read -r line; do
    if [[ "$line" =~ ^tags:[[:space:]]*\[(.*)\]$ ]]; then
      IFS=',' read -ra arr <<< "${BASH_REMATCH[1]}"
      for t in "${arr[@]}"; do t="$(echo "$t" | xargs)"; [[ -z "$t" ]] && continue
        tags_total=$((tags_total+1)); in_vocab "$t" && tags_ok=$((tags_ok+1)); done
    elif [[ "$line" == "tags:" ]]; then in_list=1
    elif [[ $in_list -eq 1 && "$line" =~ ^[[:space:]]*-[[:space:]]*(.+)$ ]]; then
      t="$(echo "${BASH_REMATCH[1]}" | xargs)"; tags_total=$((tags_total+1)); in_vocab "$t" && tags_ok=$((tags_ok+1))
    else in_list=0
    fi
  done <<< "$fm"
  local ht=false hlv=false hs=false hr=false
  grep -qE '^title:' <<< "$fm" && ht=true
  grep -qE '^last_verified:' <<< "$fm" && hlv=true
  grep -qE '^sources:' <<< "$fm" && hs=true
  grep -qE '^routing:' <<< "$fm" && hr=true
  echo "$words $cites $tags_total $tags_ok $ht $hlv $hs $hr"
}

json_for() { # <words> <cites> <tt> <to> <ht> <hlv> <hs> <hr> <rel-path>
  jq -n --argjson words "$1" --argjson citations "$2" --argjson tags_total "$3" --argjson tags_in_vocab "$4" \
    --argjson has_title "$5" --argjson has_last_verified "$6" --argjson has_sources "$7" --argjson has_routing "$8" \
    --arg body_path "$9" \
    '{words:$words, citations:$citations, tags_total:$tags_total, tags_in_vocab:$tags_in_vocab,
      has_title:$has_title, has_last_verified:$has_last_verified, has_sources:$has_sources, has_routing:$has_routing,
      body_path:$body_path}'
}

# Assemble prompt: the SHIPPING agent's model-facing region (#136), then the files the
# cloud synthesizer reads in production, inlined because a raw prompt cannot open them:
# the stack's own STACK.md (source hierarchy, article template, tag vocabulary), its
# index.md scope map (sibling boundaries), and the pre-update article on an update.
# The harness owns only the stdout output contract, because the agent's own I/O
# instruction (dispatch paths, the Write tool) is wrong for a raw prompt.
bash "$HERE/agent-prompt.sh" "$HERE/../../../../agents/article-synthesizer.md" > "$work/prompt.txt"
{
  printf '\nSTACK.md (the stack you write for: source hierarchy, article template, tag vocabulary):\n\n'
  cat "$STACK_DIR/STACK.md"
  if [[ -f "$STACK_DIR/index.md" ]]; then
    printf '\nindex.md ## Articles scope map (sibling articles and what each covers):\n\n'
    awk '/^## Articles/{f=1;next} /^## /{f=0} f' "$STACK_DIR/index.md"
  fi
} >> "$work/prompt.txt"
cat >> "$work/prompt.txt" <<'CONTRACT'

OUTPUT CONTRACT: return everything on stdout. Write no files.

  WHEN YOU WRITE the article, return YAML frontmatter then the body:
  ---
  last_verified: ""
  sources:            # bare paths, one per source, NO tier suffix
    - sources/{publisher}/{file}.md
  title: {human-readable title}
  routing: {one plain-text line, an asker's words, what it covers + questions answered}
  tags: [{from the allowed list below}]
  ---
  {body - `## ` sections from the stack's article template, inline [source-slug] citation on every claim}

  WHEN THE CLAIMS ARE TOO THIN to support an article (the judgment described above),
  return only the one-line shortfall report:
  Concept {slug}: insufficient claims - article not written.
CONTRACT
{
  echo; echo "Allowed tags: $VOCAB"
  # Last before the block, so every slug shares the longest possible prompt opening.
  if [[ -f "$prior_file" ]]; then
    printf '\nEXISTING ARTICLE (this is an update: follow the Update behavior above):\n\n'
    cat "$prior_file"
  fi
  echo; echo "CONCEPT BLOCK:"; cat "$concept_file"
} >> "$work/prompt.txt"

# Deterministic refusal gate (liminal S61): the weak tier's refuse-or-write call
# is prompt-CHAOTIC — a cosmetic framing change flips it, same fragility class as
# the validator's one-token flag flip — so decide it in code, not the model.
# Count the block's claim bullets; at/above the floor, append an explicit WRITE
# directive that overrides the rubric's thin-concept refusal. Below the floor the
# rubric's genuine refusal stands (the thin-concept case).
CLAIM_FLOOR="${CLAIM_FLOOR:-2}"
n_claims=$(bash "$HERE/claim-count.sh" "$concept_file")
if [[ "$n_claims" -ge "$CLAIM_FLOOR" ]]; then
  printf '\nThis concept block has %d claims, at or above the substantive-article floor: write the full article for it, not the shortfall report.\n' "$n_claims" >> "$work/prompt.txt"
fi

localraw="$work/local_raw.md"
t0=$SECONDS
if ! bash "$INFER" "$work/prompt.txt" "$localraw" 2>"$work/local.err"; then
  echo "FAIL item=$item_id: local inference errored (see $work/local.err, printed below)" >&2
  cat "$work/local.err" >&2
  jq -nc --arg item "$item_id" --arg model "$MODEL" --arg run "$RUN_ID" \
    '{item:$item, model:$model, run_id:$run, status:"local-inference-failed"}' >> "$RUN_DIR/synthesis.jsonl"
  exit 1
fi
secs=$((SECONDS - t0))
article="$work/article.md"
if ! awk "$EXTRACT_AWK" "$localraw" > "$article"; then
  if grep -qE '^Concept [^:]+: insufficient claims' "$localraw"; then status=refused; else status=malformed; fi
  jq -nc --arg item "$item_id" --arg model "$MODEL" --arg run "$RUN_ID" --arg st "$status" \
    '{item:$item, model:$model, run_id:$run, status:$st}' >> "$RUN_DIR/synthesis.jsonl"
  echo "$status item=$item_id: no article in the local reply" >&2
  [[ "$status" == refused ]] && exit 0
  exit 1
fi
mv "$article" "$localraw"

echo "--- tags before filter (item=$item_id) ---" >&2
grep -A6 '^tags:' "$localraw" >&2 || echo "(no tags: line found)" >&2

local_body="$RUN_DIR/bodies/${item_id}__local.md"
cp "$localraw" "$local_body"
bash "$POSTFILTER" "$local_body"     # drop out-of-vocab tags
bash "$NORMALIZER" "$local_body"     # [source: X] -> [X]
set_sources "$concept_file" "$prior_file" "$local_body"
blank_verified "$local_body"

echo "--- tags after filter (item=$item_id) ---" >&2
grep -A6 '^tags:' "$local_body" >&2 || echo "(no tags: line found)" >&2

read -r w_l c_l tt_l to_l ht_l hlv_l hs_l hr_l <<< "$(metrics_for "$local_body")"
local_json=$(json_for "$w_l" "$c_l" "$tt_l" "$to_l" "$ht_l" "$hlv_l" "$hs_l" "$hr_l" "bodies/${item_id}__local.md")

cloud_json="null"
if [[ "$cloud_file" != "NONE" && -f "$cloud_file" ]]; then
  cloud_body="$RUN_DIR/bodies/${item_id}__cloud.md"
  cp "$cloud_file" "$cloud_body"
  read -r w_c c_c tt_c to_c ht_c hlv_c hs_c hr_c <<< "$(metrics_for "$cloud_body")"
  cloud_json=$(json_for "$w_c" "$c_c" "$tt_c" "$to_c" "$ht_c" "$hlv_c" "$hs_c" "$hr_c" "bodies/${item_id}__cloud.md")
else
  echo "NOTE item=$item_id: no cloud article at '$cloud_file' — logging local metrics only, cloud:null" >&2
fi

jq -nc --arg item "$item_id" --arg model "$MODEL" --arg run "$RUN_ID" --argjson secs "$secs" \
  --argjson local "$local_json" --argjson cloud "$cloud_json" \
  '{item:$item, model:$model, run_id:$run, secs:$secs, status:"ok", local:$local, cloud:$cloud}' \
  >> "$RUN_DIR/synthesis.jsonl"

echo "OK item=$item_id: logged to $RUN_DIR/synthesis.jsonl (${secs}s)" >&2
