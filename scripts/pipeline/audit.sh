#!/usr/bin/env bash
set -euo pipefail

# Audit-stack pipeline orchestration — the deterministic control flow that used
# to live in audit-stack SKILL.md Bash blocks, now one checked-in script with
# phase subcommands. The model dispatch (validator agents) stays in the skill as
# prose; everything mechanical (arg parse, article enum, sharding, gating, report
# aggregation, cleanup) is here. Mirrors scripts/pipeline/enrich.sh (#87).
#
# Usage:
#   bash audit.sh prep   <stack>   # Step 1+3-setup: enum, shard, run-state
#                                  # [--full] re-audit all; [--only a,b] scope to named slugs
#   bash audit.sh gate   <stack>   # Step 3-gate: gate-batch + check-coverage
#   bash audit.sh finish <stack>   # Step 4: report.md + soft-spots.tsv + counts
#   bash audit.sh --self-check
#
# Phase contract (subcommands because a bash script can't spawn subagents, so the
# pipeline is always prep -> validator dispatch -> gate -> finish, split at the
# dispatch boundary):
#
#   prep    Resolve the library, enum articles/*.md, shard into CAP=5 batches, and
#           write dev/audit/dispatch.tsv + run.env (with RUN_ID). Clears stale
#           per-batch findings. Prints the paths + dispatch instructions the skill
#           prose reads. Exits non-zero if the stack has no articles.
#   gate    Re-read run-state from disk, gate every expected _audit-<tag>.md
#           (gate-batch.sh: write-or-fail + audit-findings shape = a VALIDATED
#           receipt row exists) then check-coverage.sh --verdict VALIDATED --field 2
#           (reconciles dispatched slugs vs the slug column of the VALIDATED
#           receipt rows). A dropped/dup/unknown/missing receipt fails by name.
#           This replaces the old per-article `last_verified == today` date-gate,
#           which proved a date but never per-article coverage (#71 headline).
#   finish  Aggregate CORRECTION/SOFTSPOT rows across the dispatched batch files
#           (enumerated from dispatch.tsv, not globbed — a file the gate somehow
#           let through still can't silently shrink the report), write report.md +
#           soft-spots.tsv, print AUDIT_SUMMARY counts for the skill's log+commit,
#           then remove the transient run files. VALIDATED receipt rows are ignored
#           by the report (it filters CORRECTION/SOFTSPOT only).
#
# State crosses phases ONLY through these files, never shell env (the #72 fix —
# a var set in one SKILL.md Bash block is empty in the next):
#
#   dev/audit/run.env       KEY=VAL. RUN_ID (dispatch epoch + gate-batch freshness
#                           floor), STACK, N_ARTICLES, CAP, DISPATCH path.
#   dev/audit/dispatch.tsv  The coverage manifest, one row per article:
#                           batch_tag<TAB>slug<TAB>article_path
#                           col 1 groups articles into one validator's assignment;
#                           col 2 (slug) is what check-coverage reconciles; col 3
#                           is the absolute path handed to the agent.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$SCRIPT_DIR/.."   # scripts/ — where the shared helpers live

CAP=5   # articles per validator agent. Kept modest on purpose: each agent re-reads every
        # cited source too, so a big slice risks prompt-overflow + cross-article
        # contamination. Raise only if dispatch fan-out becomes the bottleneck.

die() { echo "ERROR: $*" >&2; exit 1; }

# Echo the resolved library's absolute path, or fail non-zero. Every phase cds
# itself (self-contained — never assumes an earlier phase's cd survived). Callers
# MUST capture-then-cd, never `cd "$(enter_library)"` (on a resolve failure that
# is `cd ""`, which succeeds as a no-op and runs in the wrong dir — the #74 footgun).
enter_library() {
  bash "$HELPERS/resolve-library.sh"
}

# Extract the stack name from a phase's args, ignoring any flags (--full etc.).
# gate/finish take only the stack; without this, `audit-stack {stack} --full`
# invoked as `--full {stack}` would make them treat "--full" as the stack name.
stack_arg() {
  local s="" a
  for a in "$@"; do case "$a" in --*) ;; *) [[ -z "$s" ]] && s="$a" ;; esac; done
  echo "$s"
}

# --- prep -------------------------------------------------------------------
phase_prep() {
  local STACK="" FULL=0 ONLY="" arg expect_only=0
  for arg in "$@"; do
    if [[ "$expect_only" -eq 1 ]]; then ONLY="$arg"; expect_only=0; continue; fi
    case "$arg" in
      --full)   FULL=1 ;;
      --only)   expect_only=1 ;;
      --only=*) ONLY="${arg#--only=}"; [[ -n "$ONLY" ]] || die "--only needs a comma-separated slug list (e.g. --only ts-a,ts-b)." ;;
      -*)       die "unknown flag: $arg (usage: audit.sh prep <stack> [--full] [--only <slug,slug,...>])" ;;
      *)        [[ -z "$STACK" ]] && STACK="$arg" || die "unexpected extra argument: $arg" ;;
    esac
  done
  [[ "$expect_only" -eq 0 ]] || die "--only needs a comma-separated slug list (e.g. --only ts-a,ts-b)."
  [[ -n "$STACK" ]] || die "Specify a stack name. Usage: audit.sh prep <stack> [--full] [--only <slug,slug,...>]"

  local LIB; LIB=$(enter_library) || die "could not resolve the library (no config, and cwd is not a library)."
  cd "$LIB" || die "could not cd into library: $LIB"
  [[ -f "$STACK/STACK.md" ]] || die "Stack '$STACK' not found (no STACK.md)."

  local DEV="$STACK/dev/audit"
  local ADEV="$LIB/$DEV"
  mkdir -p "$DEV"

  # Enumerate all articles (sorted, stable order → deterministic batch assignment).
  local ARTICLES=() a
  while IFS= read -r a; do ARTICLES+=("$a"); done \
    < <(find "$STACK/articles" -maxdepth 1 -name '*.md' 2>/dev/null | sort)
  local N_TOTAL=${#ARTICLES[@]}
  [[ "$N_TOTAL" -ge 1 ]] || die "No articles found in $STACK/articles/. Run /stacks:catalog-sources $STACK first."

  # Scoped audit (--only): restrict the article set to the named slugs, bypassing
  # the incremental skip (an explicitly named article is always re-audited). The
  # manifest below then covers ONLY these, so gate/finish reconcile the scoped
  # subset — a validator dispatched on just the named articles passes the gate
  # instead of false-failing against a whole-stack manifest (#100).
  if [[ -n "$ONLY" ]]; then
    local -a want; IFS=',' read -ra want <<< "$ONLY"
    local -a sel=(); local w aa
    for w in "${want[@]}"; do
      [[ -n "$w" ]] || continue
      [[ -f "$STACK/articles/$w.md" ]] || die "--only: no such article '$w' in $STACK/articles/ (expected $w.md)."
    done
    for aa in "${ARTICLES[@]}"; do
      for w in "${want[@]}"; do [[ "$(basename "$aa" .md)" == "$w" ]] && { sel+=("$aa"); break; }; done
    done
    [[ ${#sel[@]} -ge 1 ]] || die "--only: no valid slugs given."
    ARTICLES=("${sel[@]}"); N_TOTAL=${#ARTICLES[@]}
  fi

  # Incremental skip. An article whose current content hash matches its row in
  # verified.tsv (written by the last finish) is byte-for-byte unchanged since it
  # was validated, so re-checking it would reproduce the same result at full token
  # cost — skip it. `--full` ignores verified.tsv and re-audits everything (use it
  # after the validator's own logic improves, when every article must be re-checked).
  # A first run (no verified.tsv) audits all; the corpus self-migrates on that pass.
  # Content hash = `git hash-object` (git's own blob SHA — no sha256sum portability
  # trap; works outside a repo). A hash miss always falls through to auditing, so
  # the failure direction is "audit an unchanged article" (waste), never "skip a
  # changed one" (serve stale content).
  local VERIFIED="$DEV/verified.tsv"
  local ARTICLES_TA=() slug hash N_SKIP=0
  for a in "${ARTICLES[@]}"; do
    if [[ "$FULL" -eq 0 && -z "$ONLY" && -f "$VERIFIED" ]]; then
      slug=$(basename "$a" .md)
      # `|| true`: a hash failure must fall through to auditing (safe direction),
      # not abort prep under set -e. Empty hash never matches, so it re-audits.
      hash=$(git hash-object "$a" 2>/dev/null || true)
      if [[ -n "$hash" ]] && grep -qxF "$slug"$'\t'"$hash" "$VERIFIED"; then
        N_SKIP=$((N_SKIP + 1)); continue
      fi
    fi
    ARTICLES_TA+=("$a")
  done
  local N=${#ARTICLES_TA[@]}

  # Inert-optimization warning: a stack with a prior audit history but no
  # verified.tsv (e.g. last audited by a pre-incremental audit.sh) skips nothing
  # and silently pays a full-stack sweep. Surface the defeated optimization;
  # finish writes the baseline, so the NEXT run skips the unchanged articles.
  if [[ "$FULL" -eq 0 && -z "$ONLY" && ! -f "$VERIFIED" ]]; then
    echo "WARNING: no baseline at $DEV/verified.tsv — incremental skip inert; auditing all $N_TOTAL article(s). finish writes the baseline so the next run skips unchanged ones. Scope to specific articles with: --only <slug,slug,...>" >&2
  fi

  # Dispatch manifest over the to-audit set only: batch_tag<TAB>slug<TAB>path, CAP per batch.
  local DISPATCH="$DEV/dispatch.tsv"
  : > "$DISPATCH"
  local i
  for i in "${!ARTICLES_TA[@]}"; do
    slug=$(basename "${ARTICLES_TA[$i]}" .md)
    printf '%d\t%s\t%s\n' "$((i / CAP))" "$slug" "$LIB/${ARTICLES_TA[$i]}" >> "$DISPATCH"
  done

  # Clear stale per-batch findings (freshness gate depends on every kept file
  # being written strictly after RUN_ID below).
  rm -f "$DEV"/_audit-*.md

  local RUN_ID; RUN_ID=$(date +%s)
  local N_BATCH; N_BATCH=$(cut -f1 "$DISPATCH" | sort -u | wc -l | tr -d ' ')
  {
    echo "RUN_ID=$RUN_ID"
    echo "STACK=$STACK"
    echo "N_ARTICLES=$N"
    echo "N_TOTAL=$N_TOTAL"
    echo "N_SKIPPED=$N_SKIP"
    echo "CAP=$CAP"
    echo "DISPATCH=$ADEV/dispatch.tsv"
  } > "$DEV/run.env"

  # Nothing changed → no dispatch, no gate. finish still runs (refresh the report,
  # carry skipped soft spots forward, re-hash verified.tsv).
  if [[ "$N" -eq 0 ]]; then
    echo "NOTHING_TO_AUDIT: all $N_TOTAL article(s) unchanged since last audit (dev/audit/verified.tsv). Skip the validator dispatch and gate; run 'audit.sh finish $STACK' to refresh the report."
    return 0
  fi

  echo "Articles: $N_TOTAL total; $N_SKIP unchanged (skipped); $N to audit.  Dispatch: $N_BATCH batch(es), CAP=$CAP, RUN_ID=$RUN_ID"
  echo "Manifest:   $ADEV/dispatch.tsv   (batch_tag<TAB>slug<TAB>article_path)"
  echo "Sources:    $LIB/$STACK/sources/   (validators read cited sources; exclude incoming/ + trash/)"
  echo "Stack root: $LIB/$STACK"
  echo "Dispatch one stacks:validator agent per distinct batch_tag; pass BATCH_TAG + RUN_ID=$RUN_ID; write findings to $LIB/$DEV/_audit-<batch_tag>.md"
}

# --- gate -------------------------------------------------------------------
phase_gate() {
  local STACK; STACK=$(stack_arg "$@"); [[ -n "$STACK" ]] || die "Usage: audit.sh gate <stack>"
  local LIB; LIB=$(enter_library) || die "could not resolve the library."
  cd "$LIB" || die "could not cd into library: $LIB"
  local DEV="$STACK/dev/audit"
  [[ -f "$DEV/run.env" ]]      || die "no run.env at $DEV — run 'audit.sh prep' first."
  [[ -f "$DEV/dispatch.tsv" ]] || die "no dispatch.tsv at $DEV — run 'audit.sh prep' first."

  local RUN_ID; RUN_ID=$(grep -m1 '^RUN_ID=' "$DEV/run.env" | cut -d= -f2)
  [[ "$RUN_ID" =~ ^[0-9]+$ ]] || die "RUN_ID missing/garbled in $DEV/run.env"

  # Run-state consistency: the dispatch row count MUST equal prep's recorded
  # N_ARTICLES. An empty dispatch is legitimate ONLY when prep skipped everything
  # (N_ARTICLES=0); any other empty/short dispatch is a truncated/corrupted run
  # (e.g. a crash between prep and gate) that must NOT pass the gate and let finish
  # stamp never-validated articles as verified. Die instead.
  local N_ARTICLES DISP_ROWS
  N_ARTICLES=$(grep -m1 '^N_ARTICLES=' "$DEV/run.env" | cut -d= -f2)
  DISP_ROWS=$(grep -c '' "$DEV/dispatch.tsv" 2>/dev/null || true)
  [[ "$DISP_ROWS" == "$N_ARTICLES" ]] || die "run-state corrupted: dispatch.tsv has $DISP_ROWS row(s) but run.env N_ARTICLES=$N_ARTICLES — re-run 'audit.sh prep $STACK'."
  if [[ "$N_ARTICLES" -eq 0 ]]; then
    echo "gate: nothing dispatched (all articles unchanged) — nothing to reconcile."
    return 0
  fi

  # Expected per-batch files, one per distinct batch_tag in the manifest. PAIRS
  # carries the same tag->file association for check-coverage's --batched mode.
  local BATCHFILES=() PAIRS=() t
  while IFS= read -r t; do
    BATCHFILES+=("$DEV/_audit-$t.md")
    PAIRS+=("$t=$DEV/_audit-$t.md")
  done < <(cut -f1 "$DEV/dispatch.tsv" | sort -u)

  # 1) write-or-fail + a VALIDATED receipt row exists.
  bash "$HELPERS/gate-batch.sh" "$RUN_ID" validator audit-findings "${BATCHFILES[@]}"

  # 2) every VALIDATED receipt must carry THIS run's RUN_ID in col 3. gate-batch's
  # mtime proves the FILE is fresh; this proves each ROW is — catching an agent
  # that echoed a wrong/empty RUN_ID or copied a receipt forward. Without it the
  # RUN_ID column would be pure decoration (finish deletes the file, so it is
  # never persisted). Runs after gate-batch, so every path here exists.
  local BADRUN
  BADRUN=$(awk -F'\t' -v r="$RUN_ID" '$1=="VALIDATED" && $3!=r {print $2}' "${BATCHFILES[@]}")
  if [[ -n "$BADRUN" ]]; then
    echo "AUDIT_GATE_FAILURE: VALIDATED receipt(s) not carrying RUN_ID=$RUN_ID (slug(s)): $(printf '%s' "$BADRUN" | paste -sd' ' -)" >&2
    exit 1
  fi

  # 3) per-article coverage: every dispatched slug (manifest col 2) has exactly one
  # VALIDATED receipt IN ITS OWN BATCH FILE (col 2 of the VALIDATED-only rows;
  # --verdict skips CORRECTION/SOFTSPOT which reuse the slug column). --batched
  # reconciles each batch_tag against only its _audit-<tag>.md, so a slug dropped by
  # its own batch but cross-emitted by another now fails (batchB omission + batchA
  # unknown) instead of leaking past the global union (#92).
  bash "$HELPERS/check-coverage.sh" --verdict VALIDATED --field 2 --batched "$DEV/dispatch.tsv" "${PAIRS[@]}"
}

# --- finish -----------------------------------------------------------------
phase_finish() {
  local STACK; STACK=$(stack_arg "$@"); [[ -n "$STACK" ]] || die "Usage: audit.sh finish <stack>"
  local LIB; LIB=$(enter_library) || die "could not resolve the library."
  cd "$LIB" || die "could not cd into library: $LIB"
  local DEV="$STACK/dev/audit"
  [[ -f "$DEV/run.env" ]]      || die "no run.env at $DEV — run 'audit.sh prep' first."
  [[ -f "$DEV/dispatch.tsv" ]] || die "no dispatch.tsv at $DEV — run 'audit.sh prep' first."

  local N_ARTICLES; N_ARTICLES=$(grep -m1 '^N_ARTICLES=' "$DEV/run.env" | cut -d= -f2)
  local N_SKIPPED; N_SKIPPED=$(grep -m1 '^N_SKIPPED=' "$DEV/run.env" | cut -d= -f2); N_SKIPPED=${N_SKIPPED:-0}

  # Same run-state consistency guard as gate (finish can be run standalone): the
  # dispatch row count must equal prep's N_ARTICLES, so a truncated dispatch can't
  # make finish re-stamp verified.tsv for articles that were never validated.
  local DISP_ROWS; DISP_ROWS=$(grep -c '' "$DEV/dispatch.tsv" 2>/dev/null || true)
  [[ "$DISP_ROWS" == "$N_ARTICLES" ]] || die "run-state corrupted: dispatch.tsv has $DISP_ROWS row(s) but run.env N_ARTICLES=$N_ARTICLES — re-run 'audit.sh prep $STACK'."

  # Aggregate from the dispatched batch files (enumerated, not globbed — a stray
  # extra _audit-*.md can't leak in, and a dispatched-but-vanished file FAILS here
  # instead of `cat 2>/dev/null` silently shrinking the report; the old skill's
  # glob+swallow is the bug this kills). The gate normally guarantees presence, but
  # finish must not trust that — it can be run standalone.
  local BATCHFILES=() t MISSING=()
  while IFS= read -r t; do
    if [[ -f "$DEV/_audit-$t.md" ]]; then BATCHFILES+=("$DEV/_audit-$t.md")
    else MISSING+=("_audit-$t.md"); fi
  done < <(cut -f1 "$DEV/dispatch.tsv" | sort -u)
  [[ ${#MISSING[@]} -eq 0 ]] || die "finish: dispatched batch file(s) missing (run gate first): ${MISSING[*]}"

  local REPORT="$DEV/report.md"
  local TODAY; TODAY=$(date +%Y-%m-%d)
  local AUDIT_LINES=""
  [[ ${#BATCHFILES[@]} -gt 0 ]] && AUDIT_LINES=$(cat "${BATCHFILES[@]}")
  local N_CORR N_SOFT_NEW
  N_CORR=$(printf '%s\n' "$AUDIT_LINES" | grep -c '^CORRECTION'$'\t' || true)
  N_SOFT_NEW=$(printf '%s\n' "$AUDIT_LINES" | grep -c '^SOFTSPOT'$'\t' || true)

  # Merge soft spots. An incremental run only re-checks changed articles, so the
  # durable /stacks:enrich-stack input (soft-spots.tsv) must CARRY FORWARD the soft
  # spots of the skipped (unchanged) articles — replacing only the re-audited ones'
  # rows — or a one-article re-audit would silently shrink the enrich queue to that
  # one article. Carry a prior row when its slug was not re-audited this run AND its
  # article still exists (a deleted article's soft spots are dropped).
  local AUDITED; AUDITED=$(cut -f2 "$DEV/dispatch.tsv" 2>/dev/null | sort -u)
  local SS="$DEV/soft-spots.tsv" SS_NEW; SS_NEW=$(mktemp)
  # this run's fresh soft spots (empty on a nothing-to-audit run)
  printf '%s\n' "$AUDIT_LINES" | awk -F'\t' '$1=="SOFTSPOT"{print $2"\t"$3"\t"$4}' > "$SS_NEW"
  if [[ -f "$SS" ]]; then
    while IFS=$'\t' read -r s c r; do
      [[ -n "$s" ]] || continue
      grep -qxF "$s" <<<"$AUDITED" && continue          # re-audited → fresh row already in SS_NEW
      [[ -f "$STACK/articles/$s.md" ]] || continue       # article gone → drop its stale soft spots
      printf '%s\t%s\t%s\n' "$s" "$c" "$r"
    done < "$SS" >> "$SS_NEW"
  fi
  sort -u "$SS_NEW" -o "$SS"; rm -f "$SS_NEW"
  local N_SOFT_TOTAL; N_SOFT_TOTAL=$(grep -c $'\t' "$SS" 2>/dev/null || true); N_SOFT_TOTAL=${N_SOFT_TOTAL:-0}

  local SKIPNOTE=""; [[ "$N_SKIPPED" -gt 0 ]] && SKIPNOTE=" ($N_SKIPPED unchanged, skipped)"

  {
    echo "# $STACK — audit report ($TODAY)"
    echo
    echo "Per-run activity report; soft-spots.tsv is the cumulative enrich queue (skipped articles' soft spots carry forward)."
    echo
    echo "Articles validated: $N_ARTICLES$SKIPNOTE.  Corrections applied: $N_CORR.  Soft spots: $N_SOFT_NEW new, $N_SOFT_TOTAL tracked."
    echo
    echo "## Corrections applied"
    echo "_Claims the validator rewrote in place to match their cited source._"
    echo
    if [[ "$N_CORR" -gt 0 ]]; then
      printf '%s\n' "$AUDIT_LINES" | awk -F'\t' '$1=="CORRECTION"{printf "- `%s` — %s\n", $2, $3}'
    else echo "_None. No cited claim contradicted its source._"; fi
    echo
    echo "## Soft spots found this run"
    echo "_Claims not tied to a cited source. Left in place — add a source or confirm. The cumulative queue (incl. skipped articles) is soft-spots.tsv._"
    echo
    if [[ "$N_SOFT_NEW" -gt 0 ]]; then
      printf '%s\n' "$AUDIT_LINES" | awk -F'\t' '$1=="SOFTSPOT"{printf "- `%s` — \"%s\" — %s\n", $2, $3, $4}'
    else echo "_None this run. Every re-audited claim ties to a cited source._"; fi
  } > "$REPORT"

  # soft-spots.tsv (the /stacks:enrich-stack input) was already written by the merge
  # block above — it carries skipped articles' soft spots forward, which a per-run
  # overwrite would lose.

  # Refresh verified.tsv: the baseline the next prep skips against. Re-audited
  # articles (this run's dispatch slugs, in AUDITED) get their post-validation hash.
  # Articles NOT audited this run keep their PRIOR baseline row if they had one, and
  # get NO row if they didn't — a scoped --only run must never stamp an article it
  # never checked as verified (that would make the next full run skip a
  # never-audited article). For a full/incremental run every non-audited article is
  # a skipped one that already had a matching row, so carry-forward reproduces the
  # old hash-everything behavior. Deleted articles fall out (not re-enumerated).
  # Runs after the validator's edits (finish is post-gate).
  local VOUT="$DEV/verified.tsv" af h slug2 prior
  local VPRIOR; VPRIOR=$(mktemp); [[ -f "$VOUT" ]] && cp "$VOUT" "$VPRIOR"
  : > "$VOUT"
  while IFS= read -r af; do
    slug2=$(basename "$af" .md)
    if grep -qxF "$slug2" <<<"$AUDITED"; then
      h=$(git hash-object "$af" 2>/dev/null || true)
      # Skip a row we couldn't hash rather than write `slug<TAB>` (empty hash) as bad
      # metadata — a missing row just re-audits that article next run (safe direction).
      [[ -n "$h" ]] && printf '%s\t%s\n' "$slug2" "$h" >> "$VOUT"
    else
      prior=$(awk -F'\t' -v s="$slug2" '$1==s{print; exit}' "$VPRIOR")
      [[ -n "$prior" ]] && printf '%s\n' "$prior" >> "$VOUT"
    fi
  done < <(find "$STACK/articles" -maxdepth 1 -name '*.md' 2>/dev/null | sort)
  rm -f "$VPRIOR"

  # Cleanup: transient per-batch inputs + run-state. report.md, soft-spots.tsv, and
  # verified.tsv are the durable artifacts the skill commits.
  rm -f "$DEV"/_audit-*.md "$DEV/dispatch.tsv" "$DEV/run.env"

  echo "AUDIT_SUMMARY: articles=$N_ARTICLES skipped=$N_SKIPPED corrections=$N_CORR softspots=$N_SOFT_TOTAL"
  echo "Wrote $REPORT, $DEV/soft-spots.tsv ($N_SOFT_TOTAL tracked), $VOUT ($N_SKIPPED skipped next run if unchanged)"
}

# --- self-check -------------------------------------------------------------
# Red-when-broken: seed a throwaway library with 6 articles (→ 2 batches at CAP=5),
# run prep, assert the manifest shape, fabricate clean validator output → gate PASS,
# then (a) drop one VALIDATED receipt row → gate FAILS naming that slug, (b) delete
# a whole batch file → gate FAILS by path, then finish → report counts correct.
self_check() {
  local d; d=$(mktemp -d)
  trap 'rm -rf "$d"' RETURN
  local pass=0 fail=0
  ok()  { echo "SELF-CHECK PASS [$1]"; pass=$((pass+1)); }
  bad() { echo "SELF-CHECK FAIL [$1]: $2" >&2; fail=$((fail+1)); }

  touch "$d/catalog.md"
  mkdir -p "$d/mep/articles" "$d/mep/sources" "$d/mep/dev/audit"
  echo "# MEP" > "$d/mep/STACK.md"
  local s
  for s in vav chiller pump cooling-tower ahu boiler; do
    printf '# %s\n\nBody.\n' "$s" > "$d/mep/articles/$s.md"
  done

  export STACKS_CONFIG="$d/config.json"
  printf '{"library":"%s"}\n' "$d" > "$d/config.json"

  # prep
  bash "$0" prep mep >/dev/null 2>&1 || bad "prep-runs" "prep exited nonzero"
  # no verified.tsv yet (finish never ran) → prep must WARN the skip is inert (#100),
  # not silently proceed as though everything is a fresh cold-start.
  local prepout; prepout=$(bash "$0" prep mep 2>&1)
  if grep -q 'WARNING' <<<"$prepout" && grep -q 'verified.tsv' <<<"$prepout"; then
    ok "prep-warns-no-baseline"
  else
    bad "prep-warns-no-baseline" "expected WARNING naming verified.tsv, out=$prepout"
  fi
  local DISP="$d/mep/dev/audit/dispatch.tsv" ENV="$d/mep/dev/audit/run.env"
  [[ -f "$DISP" && -f "$ENV" ]] && ok "prep-writes-run-state" || bad "prep-writes-run-state" "missing dispatch.tsv/run.env"
  # 6 rows, batch 0 = first 5 slugs, batch 1 = the 6th.
  if [[ "$(wc -l < "$DISP" | tr -d ' ')" == "6" ]] \
     && grep -q $'^0\tchiller\t' "$DISP" && grep -q $'^1\tvav\t' "$DISP"; then
    ok "prep-shards-cap5"
  else
    bad "prep-shards-cap5" "expected 6 rows 5+1, got: $(cat "$DISP")"
  fi
  local RUN_ID; RUN_ID=$(grep -m1 '^RUN_ID=' "$ENV" | cut -d= -f2)
  [[ "$RUN_ID" =~ ^[0-9]+$ ]] && ok "run-env-has-runid" || bad "run-env-has-runid" "no RUN_ID"

  # slugs per batch (sorted order: ahu boiler chiller cooling-tower pump | vav)
  local F0="$d/mep/dev/audit/_audit-0.md" F1="$d/mep/dev/audit/_audit-1.md"
  mk_clean() {
    {
      printf 'VALIDATED\tahu\t%s\n' "$RUN_ID"
      printf 'VALIDATED\tboiler\t%s\n' "$RUN_ID"
      printf 'VALIDATED\tchiller\t%s\n' "$RUN_ID"
      printf 'VALIDATED\tcooling-tower\t%s\n' "$RUN_ID"
      printf 'VALIDATED\tpump\t%s\n' "$RUN_ID"
      printf 'CORRECTION\tchiller\t"44 F" -> "42 F" per [ashrae]\n'
      printf 'SOFTSPOT\tpump\tPumps rarely exceed 80%% efficiency.\tno scoped source\n'
    } > "$F0"
    printf 'VALIDATED\tvav\t%s\n' "$RUN_ID" > "$F1"
  }
  mk_clean
  if bash "$0" gate mep >/dev/null 2>&1; then ok "gate-clean-passes"; else bad "gate-clean-passes" "clean gate failed"; fi

  # flag-first arg ordering: the skill hands gate/finish the same $ARGUMENTS as prep,
  # so `audit-stack {stack} --full` reaches gate as `--full {stack}` — it must still
  # resolve the stack past the leading flag, not treat "--full" as the stack name.
  mk_clean
  if bash "$0" gate --full mep >/dev/null 2>&1; then ok "gate-resolves-stack-past-flag"; else bad "gate-resolves-stack-past-flag" "gate --full mep failed to resolve stack"; fi

  # (a) drop the vav receipt row → present-but-incomplete: gate-batch passes (file
  #     present, has a VALIDATED row for... nothing now), check-coverage FAILS naming vav.
  local out rc
  mk_clean; : > "$F1"   # F1 must stay non-empty + have a VALIDATED row or gate-batch trips first;
  printf 'VALIDATED\tnot-vav\t%s\n' "$RUN_ID" > "$F1"   # a receipt for an UNKNOWN slug: vav omitted + not-vav unknown
  out=$(bash "$0" gate mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qw 'vav' <<<"$out"; then
    ok "gate-fails-naming-dropped-receipt"
  else
    bad "gate-fails-naming-dropped-receipt" "expected nonzero + 'vav', rc=$rc out=$out"
  fi

  # (a2) a receipt carrying a STALE/absent RUN_ID in col 3 → gate FAILS naming the
  #      slug, even though the file is fresh and coverage-complete.
  mk_clean
  printf 'VALIDATED\tvav\t999\n' > "$F1"   # wrong RUN_ID (999 != this run's)
  out=$(bash "$0" gate mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qw 'vav' <<<"$out" && grep -q 'RUN_ID' <<<"$out"; then
    ok "gate-fails-on-stale-runid"
  else
    bad "gate-fails-on-stale-runid" "expected nonzero + 'vav' + RUN_ID, rc=$rc out=$out"
  fi

  # (b) whole batch file deleted → gate-batch trips first, failing by path.
  mk_clean; rm -f "$F1"
  out=$(bash "$0" gate mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q '_audit-1.md' <<<"$out"; then
    ok "gate-fails-on-deleted-file"
  else
    bad "gate-fails-on-deleted-file" "expected nonzero + path, rc=$rc out=$out"
  fi

  # finish must FAIL on a dispatched batch file that vanished (the silent-shrink
  # the old glob+`cat 2>/dev/null` bug allowed), not quietly emit a short report.
  mk_clean; rm -f "$F1"
  out=$(bash "$0" finish mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q '_audit-1.md' <<<"$out"; then
    ok "finish-fails-on-missing-batch"
  else
    bad "finish-fails-on-missing-batch" "expected nonzero + path, rc=$rc out=$out"
  fi

  # finish: report + soft-spots with correct counts (1 correction, 1 soft spot).
  mk_clean
  out=$(bash "$0" finish mep 2>&1) || bad "finish-runs" "finish exited nonzero"
  local REPORT="$d/mep/dev/audit/report.md" SS="$d/mep/dev/audit/soft-spots.tsv"
  if grep -q 'articles=6 skipped=0 corrections=1 softspots=1' <<<"$out" \
     && [[ -f "$REPORT" && -f "$SS" ]] \
     && grep -q $'^pump\tPumps rarely exceed' "$SS"; then
    ok "finish-writes-report-and-softspots"
  else
    bad "finish-writes-report-and-softspots" "out=$out ss=$(cat "$SS" 2>/dev/null)"
  fi
  # finish cleaned up the transient run-state.
  [[ ! -f "$DISP" && ! -f "$ENV" ]] && ok "finish-cleans-run-state" || bad "finish-cleans-run-state" "run-state survived"

  # --- incremental skip (verified.tsv now exists from the finish above) ---
  local VER="$d/mep/dev/audit/verified.tsv"
  [[ -f "$VER" && "$(wc -l < "$VER" | tr -d ' ')" == "6" ]] && ok "finish-writes-verified" || bad "finish-writes-verified" "verified.tsv missing/wrong-size: $(cat "$VER" 2>/dev/null)"

  # (i) nothing changed → prep skips all 6, dispatch empty, NOTHING_TO_AUDIT.
  out=$(bash "$0" prep mep 2>&1)
  if grep -q 'NOTHING_TO_AUDIT' <<<"$out" && [[ ! -s "$DISP" ]]; then
    ok "prep-skips-all-unchanged"
  else
    bad "prep-skips-all-unchanged" "expected NOTHING_TO_AUDIT + empty dispatch, out=$out disp=$(cat "$DISP" 2>/dev/null)"
  fi

  # (i2) gate no-ops cleanly on the empty dispatch (nothing to reconcile).
  if bash "$0" gate mep >/dev/null 2>&1; then ok "gate-noop-on-empty"; else bad "gate-noop-on-empty" "gate failed on empty dispatch"; fi

  # (i3) finish on the empty run CARRIES the prior soft spot (pump) forward — the
  #      skip must not shrink the enrich queue to only re-audited articles.
  out=$(bash "$0" finish mep 2>&1) || bad "finish-empty-runs" "finish exited nonzero: $out"
  if grep -q $'^pump\tPumps rarely exceed' "$SS"; then
    ok "finish-carries-skipped-softspots"
  else
    bad "finish-carries-skipped-softspots" "pump soft spot lost, ss=$(cat "$SS" 2>/dev/null)"
  fi

  # (ii) change ONE article → its hash moves → prep dispatches only it.
  printf '# vav\n\nEdited body — a real change.\n' > "$d/mep/articles/vav.md"
  out=$(bash "$0" prep mep 2>&1)
  if [[ "$(wc -l < "$DISP" | tr -d ' ')" == "1" ]] && grep -q $'\tvav\t' "$DISP"; then
    ok "prep-dispatches-only-changed"
  else
    bad "prep-dispatches-only-changed" "expected 1 row (vav), got: $(cat "$DISP")"
  fi

  # (iii) --full re-audits everything despite verified.tsv.
  bash "$0" prep mep --full >/dev/null 2>&1
  if [[ "$(wc -l < "$DISP" | tr -d ' ')" == "6" ]]; then
    ok "prep-full-ignores-verified"
  else
    bad "prep-full-ignores-verified" "expected 6 rows, got: $(cat "$DISP")"
  fi

  # (iv) truncated dispatch (N_ARTICLES>0 in run.env but zero rows) is a CORRUPTED
  #      run, not a legit skip-all — gate must DIE, never pass the empty no-op (which
  #      would let finish stamp never-validated articles as verified). Guards codex #1.
  : > "$DISP"
  out=$(bash "$0" gate mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q 'corrupted' <<<"$out"; then
    ok "gate-dies-on-truncated-dispatch"
  else
    bad "gate-dies-on-truncated-dispatch" "expected nonzero + 'corrupted', rc=$rc out=$out"
  fi

  # (v) --only scopes prep to exactly the named slugs, bypassing the skip even when
  #     unchanged. The manifest is just those slugs, so gate reconciles the scoped
  #     subset (not the whole stack) — a validator dispatched on only the named
  #     articles passes, instead of false-failing against a 6-article manifest (#100).
  bash "$0" prep mep --only chiller,ahu >/dev/null 2>&1
  if [[ "$(wc -l < "$DISP" | tr -d ' ')" == "2" ]] \
     && grep -q $'\tchiller\t' "$DISP" && grep -q $'\tahu\t' "$DISP"; then
    ok "prep-only-scopes-named"
  else
    bad "prep-only-scopes-named" "expected 2 rows chiller+ahu, got: $(cat "$DISP")"
  fi
  # gate the scoped run: receipts for exactly the 2 named slugs pass the 2-row
  # manifest (both slugs fall in batch 0 → _audit-0.md).
  RUN_ID=$(grep -m1 '^RUN_ID=' "$ENV" | cut -d= -f2)
  { printf 'VALIDATED\tahu\t%s\n' "$RUN_ID"; printf 'VALIDATED\tchiller\t%s\n' "$RUN_ID"; } > "$F0"
  if bash "$0" gate mep >/dev/null 2>&1; then ok "gate-passes-scoped-manifest"; else bad "gate-passes-scoped-manifest" "scoped gate false-failed"; fi
  # finish stamps only the 2 audited slugs fresh but carries the other 4 verified.tsv
  # rows forward — a scoped run must not shrink the baseline to just the named slugs.
  out=$(bash "$0" finish mep 2>&1) || bad "finish-only-runs" "finish nonzero: $out"
  if grep -q 'articles=2' <<<"$out" && [[ "$(wc -l < "$VER" | tr -d ' ')" == "6" ]]; then
    ok "finish-only-carries-verified"
  else
    bad "finish-only-carries-verified" "expected articles=2 + 6 verified rows, out=$out ver=$(cat "$VER" 2>/dev/null)"
  fi
  # an unknown --only slug fails fast, naming it (never silently audits nothing).
  out=$(bash "$0" prep mep --only nonesuch 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q 'nonesuch' <<<"$out"; then
    ok "prep-only-rejects-unknown"
  else
    bad "prep-only-rejects-unknown" "expected nonzero + 'nonesuch', rc=$rc out=$out"
  fi

  echo "---"; echo "self-check: $pass passed, $fail failed"
  [[ "$fail" -eq 0 ]]
}

# --- dispatch ---------------------------------------------------------------
cmd="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$cmd" in
  prep)         phase_prep "$@" ;;
  gate)         phase_gate "$@" ;;
  finish)       phase_finish "$@" ;;
  --self-check) self_check ;;
  *) echo "usage: audit.sh {prep|gate|finish} <stack>  |  audit.sh --self-check" >&2; exit 1 ;;
esac
