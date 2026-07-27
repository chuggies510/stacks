#!/usr/bin/env bash
# shadow-extract-run.sh <stack>
#
# Pilot (#109), extraction stage: after catalog `gate-w1`, run the LOCAL
# extraction model on each W1 source and apply the deterministic slug-prematch
# gate, writing per-source candidate rows + a NEAR/NEW survivor manifest for the
# cloud extraction-verifier to grade. The cloud source-extractor output that
# actually feeds W1b/dedup is authoritative and untouched — this only observes,
# to grade whether the local tier is safe to make authoritative for extraction.
#
# Mirrors shadow-synth-run.sh: reads the TRANSIENT run files (dispatch-w1.tsv),
# which exist after prep and are cleared by `finish` — run BETWEEN gate-w1 and
# finish. Non-destructive: never touches sources, extractions, articles, or any
# pipeline state file. Opt-in; the skill gates this on STACKS_LOCAL_SHADOW=1.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_ROOT="$(cd "$HERE/../../../.." && pwd)"   # harness -> model-tier -> experiments -> dev -> repo root

# build_menu <shape> <exist-file> <articles-dir> <out-file>
#
# The article menu the MODEL is shown (#139), which is a DIFFERENT question from
# the pure slug list slug-prematch.sh needs. Defined here, above the run path, so
# --self-check exercises the same code the pipeline runs — a self-check with its
# own copy of this would be the #136 defect one layer down.
#
# Reads `title:` / `routing:` straight from each article's YAML frontmatter. An
# earlier version parsed those back out of the stack's index.md, which is the WRONG
# layer: index.md is itself generated from this frontmatter, and recovering the
# fields from the rendered markdown meant re-deriving them through a wiki-link
# grammar. That parser needed fence tracking, duplicate detection, a malformed-title
# heuristic, and a staleness override, and adversarial review still found holes in
# each (nested fences of differing length, a `]]` inside a title, routing lines that
# legitimately contain their own wiki-links). Reading the source of truth deletes all
# four problems rather than hardening them: one file is one slug so duplicates cannot
# exist, there is no markdown to mis-parse, and the index can never be stale relative
# to the articles because it is not consulted. Verified across all 12 stacks, 1,174
# articles: every one carries both fields on a single line.
build_menu() {
  local shape="$1" exist="$2" articles="$3" out="$4"
  local FIELD="$HERE/../../../../scripts/article-field.sh"
  # shellcheck source=/dev/null
  [[ -r "$FIELD" ]] && source "$FIELD"
  [[ -r "$exist" ]]  || { echo "ERROR: slug list $exist is missing or unreadable" >&2; return 1; }
  [[ -r "$FIELD" ]]  || { echo "ERROR: missing $FIELD" >&2; return 1; }

  # Same-file collisions caught by INODE, not spelling: "/tmp/x", "/tmp/./x" and a
  # symlink are three spellings of one file. Writing the menu (or its diagnostics)
  # over EXIST_FILE would feed slug-prematch.sh "- slug - Title" rows and break every
  # reuse decision downstream, silently.
  local o
  for o in "$out" "$out.diag"; do
    [[ -e "$o" && "$o" -ef "$exist" ]] && { echo "ERROR: build_menu would write $o over the slug list $exist (same file) — that list must stay bare for slug-prematch.sh" >&2; return 1; }
  done
  [[ -e "$out" && -e "$out.diag" && "$out" -ef "$out.diag" ]] && { echo "ERROR: menu and diagnostics resolve to the same file ($out)" >&2; return 1; }
  : > "$out.diag"; : > "$out"

  case "$shape" in
    bare)
      awk '{ sub(/\r$/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 != "") print "- " $0 }' "$exist" > "$out" \
        || { echo "ERROR: could not read the slug list $exist" >&2; return 1; }
      ;;
    title|scope)
      [[ -d "$articles" ]] || { echo "ERROR: MENU_SHAPE=$shape needs the articles dir, and $articles is not one" >&2; return 1; }
      local key slug f d
      key=$([[ "$shape" == "title" ]] && echo title || echo routing)
      # Fields come from scripts/article-field.sh — the SAME reader regenerate-moc.sh
      # uses to build index.md. An earlier version of this function had its own stricter
      # parser, which refused frontmatter the pipeline renders happily: two readers of
      # one format, i.e. the #136 drift this release exists to end, one layer down.
      # Extraction is shared; the POLICY on a refusal is each caller's own. The map
      # degrades to a bare wiki-link; a measurement run refuses to start.
      # `|| [[ -n "$slug" ]]` so a final line with no trailing newline is still processed:
      # without it that article silently vanishes from the menu and from the counts.
      while IFS= read -r slug || [[ -n "$slug" ]]; do
        slug="${slug%$'\r'}"; slug="${slug#"${slug%%[![:space:]]*}"}"; slug="${slug%"${slug##*[![:space:]]}"}"
        [[ -n "$slug" ]] || continue
        f="$articles/$slug.md"
        if [[ ! -r "$f" ]]; then
          printf 'NOFILE_OR_UNREADABLE\t%s\n' "$slug" >> "$out.diag"; d=""
        else
          d=$(article_field "$key" "$f" 2>/dev/null) || d=""
          # A block-scalar marker means the value is on the FOLLOWING lines, so the
          # marker itself is not a description — printing "- slug - >-" would tell the
          # model an article covers ">-". Policy, not parsing: refuse rather than show
          # text that is wrong as opposed to merely missing.
          [[ "$d" =~ ^[\|\>] ]] && { printf 'BLOCK_SCALAR_UNSUPPORTED\t%s\n' "$slug" >> "$out.diag"; d=""; }
        fi
        printf -- '- %s%s\n' "$slug" "${d:+ - $d}"
        [[ -n "$d" ]] || printf 'UNDESCRIBED\t%s\n' "$slug" >> "$out.diag"
      done < "$exist" | sort > "$out"
      ;;
    *) echo "ERROR: MENU_SHAPE=$shape is not one of bare|title|scope" >&2; return 1 ;;
  esac

  # EVERY article must carry a description, not merely SOME. An earlier version of this
  # guard asked `n_desc -eq 0` — "are there any descriptions" — which passes a menu where
  # 54 of 55 articles are described and one is bare. That one is then judged under the
  # starvation this whole change exists to remove, while the run is labelled `title`.
  # Asking about the record's SHAPE (does a description exist anywhere) when the question
  # is about its CONTENT (is each article described) is the same instrument error the
  # 0.77.0 self-check made. Count the gap, name the slugs, refuse.
  local n_slugs n_undesc
  n_slugs=$(grep -cve '^[[:space:]]*$' "$exist" || true)
  n_undesc=$(grep -c '^UNDESCRIBED' "$out.diag" 2>/dev/null || true)
  grep -v '^UNDESCRIBED' "$out.diag" >&2 || true     # name every article that could not be read

  if [[ "$shape" != "bare" && "$n_undesc" -gt 0 ]]; then
    echo "ERROR: MENU_SHAPE=$shape left $n_undesc of $n_slugs articles with no description:" >&2
    grep '^UNDESCRIBED' "$out.diag" | cut -f2 | sed 's/^/  /' >&2
    echo "Those articles would be judged under the bare-name starvation this shape exists to remove, inside a run labelled $shape. Fix the frontmatter named above, or set MENU_ALLOW_UNDESCRIBED=1 to proceed knowing the menu is mixed." >&2
    [[ "${MENU_ALLOW_UNDESCRIBED:-0}" == "1" ]] || return 1
    echo "WARN: proceeding with a MIXED menu (MENU_ALLOW_UNDESCRIBED=1) — $n_undesc articles are bare under a $shape label." >&2
  fi
  echo "MENU: shape=$shape slugs=$n_slugs undescribed=$n_undesc" >&2
}

if [[ "${1:-}" == "--self-check" ]]; then
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  fails=0 passes=0
  ok()  { printf 'ok   %s\n' "$1"; passes=$((passes+1)); }
  bad() { printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }
  # assert <label> <condition-cmd...>  — one counter increment per assertion. An earlier
  # version ran `cmp ... || bad "x"` then `ok "x"` unconditionally, so a failure counted
  # as BOTH a pass and a fail and the "N passed" line lied while the exit code was right.
  assert()   { local m="$1"; shift; if "$@"; then ok "$m"; else bad "$m"; fi; }
  refutes()  { local m="$1"; shift; if "$@" 2>/dev/null; then bad "$m"; else ok "$m"; fi; }
  art="$t/articles"; mkdir -p "$art"
  mkarticle() { # <slug> <title-line> <routing-line>
    { printf -- '---\n'; [ -n "$2" ] && printf '%s\n' "$2"; printf 'sources:\n  - sources/x/y.md\n'
      [ -n "$3" ] && printf '%s\n' "$3"; printf -- 'tags: [llm]\n---\n\nbody\n'; } > "$art/$1.md"
  }
  has() { grep -qxF -- "$2" "$1"; }

  mkarticle context-engineering-production \
    'title: Context Engineering in Production' \
    'routing: just-in-time loading, tool masking, compaction strategies'
  mkarticle rag 'title: Retrieval Augmented Generation' 'routing: chunking, embedding, reranking'
  mkarticle not-an-article 'title: Ghost' 'routing: should never appear'   # on disk, not in the list
  printf 'context-engineering-production\nrag\n' > "$t/exist"

  # ---- shapes -------------------------------------------------------------------
  build_menu bare "$t/exist" "$art" "$t/bare" 2>/dev/null
  assert "bare: one row per article"      test "$(grep -c '' "$t/bare")" -eq 2
  refutes "bare: no descriptions"         grep -q ' - ' "$t/bare"
  assert "bare: rows carry the - prefix"  has "$t/bare" '- rag'

  build_menu title "$t/exist" "$art" "$t/title" 2>/dev/null
  assert  "title: uses title:, not routing:"  has "$t/title" '- rag - Retrieval Augmented Generation'
  refutes "title: routing line excluded"      grep -q 'chunking' "$t/title"

  build_menu scope "$t/exist" "$art" "$t/scope" 2>/dev/null
  assert "scope: uses routing:, not title:"   has "$t/scope" '- rag - chunking, embedding, reranking'
  # The S59 receipt: ALL THREE phrases are what the models minted as NEW slugs because
  # they could not see them. Checking one would pass on a truncated routing line.
  allphrases() { local f="$1" ph; for ph in 'just-in-time loading' 'tool masking' 'compaction strategies'; do
                   grep -qF "$ph" "$f" || return 1; done; }
  assert "scope: carries every S59 receipt phrase" allphrases "$t/scope"

  # Exact set equality, not "the one ghost I remember is absent".
  setmatches() { cut -d' ' -f2 "$1" | sort | cmp -s - <(sort "$t/exist"); }
  for sh in bare title scope; do assert "$sh: menu slug set is exactly EXIST_FILE" setmatches "$t/$sh"; done

  # ---- the round-1 high-severity case: partial menus ------------------------------
  # The old guard asked "are there ANY descriptions", so one bare article among described
  # ones ran labelled `title`, starving exactly the article the shape exists to feed.
  mkarticle nodesc 'title: Has A Title' ''
  mkarticle nodescbeta 'title: Also Has A Title' ''
  printf 'context-engineering-production\nrag\nnodesc\nnodescbeta\n' > "$t/partial"
  refutes "partial menu (2 of 4 bare) refused"   build_menu scope "$t/partial" "$art" "$t/x1"
  build_menu scope "$t/partial" "$art" "$t/x1" 2>"$t/err" || true
  # BOTH must be named: a guard hardcoded to one undescribed article would pass on one.
  assert "partial refusal names EVERY undescribed article" \
    bash -c 'grep -qw nodesc "$1" && grep -qw nodescbeta "$1"' _ "$t/err"
  with_override() { MENU_ALLOW_UNDESCRIBED=1 build_menu scope "$t/partial" "$art" "$t/x2" 2>/dev/null; }
  assert "MENU_ALLOW_UNDESCRIBED=1 permits a knowingly-mixed menu" with_override
  assert "overridden: the bare article still appears, never dropped" has "$t/x2" '- nodesc'

  # ---- reading the frontmatter ------------------------------------------------------
  # Fields come from scripts/article-field.sh, the SAME reader that builds index.md.
  # The bar here is not "is this valid YAML" — the format is line-oriented and 27 of the
  # library's 1,174 articles are not valid YAML — it is "can the menu ever show the model
  # text that is WRONG rather than absent". Absent refuses; wrong would be believed.
  mkbad() { printf '%s' "$2" > "$art/$1.md"; printf '%s\n' "$1" > "$t/e-$1"; }

  # The wrong-text path: an article with no title in its frontmatter, and a line in its
  # BODY that looks like one. An unbounded reader shows the body line as the title.
  mkbad bodykey "$(printf -- '---\nrouting: real routing\n---\n\ntitle: Body Impostor\n')"
  refutes "article with no frontmatter title refused" build_menu title "$t/e-bodykey" "$art" "$t/o15"
  build_menu title "$t/e-bodykey" "$art" "$t/o15" 2>/dev/null || true
  refutes "body title: never read as the frontmatter key" grep -q 'Body Impostor' "$t/o15"

  # A BOM pushes the real frontmatter into body position, so the same trap applies.
  mkbad bomfile "$(printf '\xef\xbb\xbf---\ntitle: Real Title\nrouting: r\n---\n\ntitle: Body Impostor\n')"
  refutes "BOM before the delimiter refused" build_menu title "$t/e-bomfile" "$art" "$t/o1"
  build_menu title "$t/e-bomfile" "$art" "$t/o1" 2>/dev/null || true
  refutes "BOM case never shows the body line as a title" grep -q 'Body Impostor' "$t/o1"

  # ROUND-5 HIGH FINDING. No closing delimiter means there is no way to tell frontmatter
  # from body, so a `title:` further down is body prose. The previous fixtures all HAD a
  # closing delimiter, so 54 assertions stayed green while the reader returned "Body
  # Impostor" with exit 0 — the wrong-not-absent outcome this change claims to remove.
  mkbad unclosed "$(printf -- '---\nrouting: real routing\nbody prose\ntitle: Body Impostor\n')"
  refutes "unclosed frontmatter refused" build_menu title "$t/e-unclosed" "$art" "$t/o2"
  build_menu title "$t/e-unclosed" "$art" "$t/o2" 2>/dev/null || true
  refutes "unclosed frontmatter never yields the body line" grep -q 'Body Impostor' "$t/o2"

  # An article that exists but cannot be read must refuse, not silently go bare. Skipped
  # as root, where mode 000 is still readable.
  if [[ "$(id -u)" -ne 0 ]]; then
    mkarticle unreadable 'title: Secret' 'routing: secret'
    chmod 000 "$art/unreadable.md"; printf 'unreadable\n' > "$t/e-unreadable"
    refutes "unreadable article refused" build_menu title "$t/e-unreadable" "$art" "$t/o25"
    chmod 644 "$art/unreadable.md"
  else ok "unreadable-article check skipped (running as root)"; fi

  # A final slug with no trailing newline must still be processed, not dropped.
  printf -- '- rag' > /dev/null; printf 'rag' > "$t/e-nonl"      # no trailing \n
  build_menu title "$t/e-nonl" "$art" "$t/o26" 2>/dev/null
  assert "final line without a trailing newline is still read" has "$t/o26" '- rag - Retrieval Augmented Generation'

  mkbad noprefix "$(printf -- 'preamble line\n---\ntitle: T\nrouting: r\n---\n')"
  refutes "frontmatter not on line 1 refused" build_menu title "$t/e-noprefix" "$art" "$t/o6"

  mkbad nofm "$(printf 'just a body, no frontmatter at all\n')"
  refutes "file with no frontmatter refused" build_menu title "$t/e-nofm" "$art" "$t/o7"

  # `title:` with no space slices mid-word ("title:NoSpace" -> "oSpace"), which reads
  # like a real value. Refuse rather than emit garbage that looks like a description.
  mkbad nospace "$(printf -- '---\ntitle:NotAMapping\nrouting: r\n---\n')"
  refutes "key with no space after the colon refused" build_menu title "$t/e-nospace" "$art" "$t/o5"
  build_menu title "$t/e-nospace" "$art" "$t/o5" 2>/dev/null || true
  refutes "no-space key never emits a sliced fragment" grep -q 'otAMapping' "$t/o5"

  # A block-scalar marker means the value is on the NEXT lines; showing "-" or ">-" as
  # an article's scope is wrong text, so the menu refuses even though index.md renders it.
  mkbad blockscalar "$(printf -- '---\ntitle: >-\n  folded title\nrouting: r\n---\n')"
  refutes "block scalar refused (not shown as \">-\")" build_menu title "$t/e-blockscalar" "$art" "$t/o3"
  build_menu title "$t/e-blockscalar" "$art" "$t/o3" 2>/dev/null || true
  refutes "block scalar marker never reaches the menu" grep -q '>-' "$t/o3"

  # First occurrence wins, matching index.md. A duplicate whose FIRST value is empty must
  # not fall through to the override: an empty value is a refusal, not "not seen yet".
  mkbad dupempty "$(printf -- '---\ntitle:\ntitle: An Override\nrouting: r\n---\n')"
  refutes "duplicate key with an EMPTY first value refused" build_menu title "$t/e-dupempty" "$art" "$t/o12"
  build_menu title "$t/e-dupempty" "$art" "$t/o12" 2>/dev/null || true
  refutes "empty-first duplicate never yields the override value" grep -q 'An Override' "$t/o12"
  mkbad duptitle "$(printf -- '---\ntitle: The First Title\nrouting: r\ntitle: An Override\n---\n')"
  build_menu title "$t/e-duptitle" "$art" "$t/o10" 2>/dev/null
  assert "duplicate title: is first-wins, as index.md is" has "$t/o10" '- duptitle - The First Title'

  # Unreadable and missing articles are refusals, and are named.
  : > "$art/emptyfile.md"; printf 'emptyfile\n' > "$t/e-empty"
  refutes "empty article file refused" build_menu title "$t/e-empty" "$art" "$t/o8"
  printf 'ghost-slug\n' > "$t/e-ghost"
  refutes "missing article file refused" build_menu title "$t/e-ghost" "$art" "$t/o9"
  build_menu title "$t/e-ghost" "$art" "$t/o9" 2>/dev/null || true
  assert "missing article is named by slug in the diagnostics" grep -q "NOFILE_OR_UNREADABLE.ghost-slug" "$t/o9.diag"

  # ---- anchoring: a key name inside another field's VALUE is not the key -------------
  mkbad valuekey  "$(printf -- '---\nnote: see title: below\ntitle: The Real Title\nrouting: r\n---\n')"
  build_menu title "$t/e-valuekey" "$art" "$t/o13" 2>/dev/null
  assert "anchored: a value containing title: is not the key" has "$t/o13" '- valuekey - The Real Title'
  mkbad valuekey2 "$(printf -- '---\ntitle: T\nnote: see routing: below\nrouting: The Real Routing\n---\n')"
  build_menu scope "$t/e-valuekey2" "$art" "$t/o14" 2>/dev/null
  assert "anchored: a value containing routing: is not the key" has "$t/o14" '- valuekey2 - The Real Routing'

  # This reader is deliberately NOT a YAML parser: it must agree with index.md, and the
  # corpus is not valid YAML. A quoted value keeps its quotes in both places. Cosmetic,
  # consistent, and asserted so a future "improvement" to unquote here shows up as the
  # divergence from index.md that it would be.
  mkarticle quoted 'title: "Quoted: A Title"' 'routing: q'
  printf 'quoted\n' > "$t/e-quoted"
  build_menu title "$t/e-quoted" "$art" "$t/o16" 2>/dev/null
  assert "quoted value passes through verbatim, as index.md renders it" has "$t/o16" '- quoted - "Quoted: A Title"'

  # ---- values -----------------------------------------------------------------------
  mkarticle wsonly 'title:    ' 'routing: real scope'
  printf 'wsonly\n' > "$t/e-ws"
  refutes "whitespace-only title counts as undescribed" build_menu title "$t/e-ws" "$art" "$t/o17"

  printf -- '---\r\ntitle: CRLF Title\r\nrouting: crlf scope\r\n---\r\n' > "$art/crlf.md"
  printf 'crlf\r\n' > "$t/e-crlf"
  build_menu title "$t/e-crlf" "$art" "$t/o18" 2>/dev/null
  assert "CRLF stripped from slug list and article" has "$t/o18" '- crlf - CRLF Title'
  build_menu bare "$t/e-crlf" "$art" "$t/o19" 2>/dev/null
  assert "bare: CRLF stripped from the slug list" has "$t/o19" '- crlf'

  printf 'rag\n\n   \n' > "$t/e-blank"
  build_menu bare "$t/e-blank" "$art" "$t/o20" 2>/dev/null
  assert "bare: blank slug-list lines make no phantom rows" test "$(grep -c '' "$t/o20")" -eq 1
  # In title/scope a blank line would become "$articles/.md" — an unreadable path, so it
  # refuses the whole run for a file nobody asked for.
  build_menu title "$t/e-blank" "$art" "$t/o20b" 2>/dev/null
  assert "title: blank slug-list lines make no phantom rows" test "$(grep -c '' "$t/o20b")" -eq 1
  refutes "title: a blank line is not reported as a missing article" grep -q 'NOFILE' "$t/o20b.diag"

  # article-field.sh is a shared script with its own contract: print the value and exit 0,
  # or print nothing and exit 1. regenerate-moc.sh depends on the exit code to decide
  # between a described and a bare wiki-link, so assert it directly rather than only
  # through the menu.
  FIELD_SH="$HERE/../../../../scripts/article-field.sh"
  assert  "article-field: reads a present field"  bash -c 'test "$(bash "$1" title "$2")" = "Retrieval Augmented Generation"' _ "$FIELD_SH" "$art/rag.md"
  refutes "article-field: exits nonzero on an absent field" bash "$FIELD_SH" nosuchfield "$art/rag.md"
  refutes "article-field: exits nonzero on an EMPTY value"  bash "$FIELD_SH" title "$art/wsonly.md"
  assert  "article-field: prints nothing on refusal" bash -c 'test -z "$(bash "$1" nosuchfield "$2" 2>/dev/null || true)"' _ "$FIELD_SH" "$art/rag.md"

  # ---- wiring guards ------------------------------------------------------------------
  # A prior call on this same output path leaves a populated .diag; the next call must
  # not read it as its own result. bare never writes diagnostics, so it is the exposing
  # shape: without the reset it would inherit the title run's UNDESCRIBED rows.
  build_menu title "$t/e-ws" "$art" "$t/o21" 2>/dev/null || true
  assert  "prior call left diagnostics to inherit" grep -q . "$t/o21.diag"
  build_menu bare "$t/exist" "$art" "$t/o21" 2>/dev/null
  refutes "diagnostics reset per call (no stale rows read)" grep -q . "$t/o21.diag"

  cp "$t/exist" "$t/exist.before"
  for spell in plain dotslash symlink; do
    case $spell in
      plain)    target="$t/exist" ;;
      dotslash) target="$t/./exist" ;;
      symlink)  ln -sf "$t/exist" "$t/exist.link"; target="$t/exist.link" ;;
    esac
    refutes "same-file write refused via the $spell path" build_menu scope "$t/exist" "$art" "$target"
  done
  # .diag is a second output path and needs the same guard as the menu itself.
  ln -sf "$t/exist" "$t/menuout.diag"
  refutes "refused when .diag resolves onto the slug list" build_menu scope "$t/exist" "$art" "$t/menuout"
  rm -f "$t/menuout.diag"
  assert "EXIST_FILE byte-identical after every attempt" cmp -s "$t/exist.before" "$t/exist"

  # Empty slug list, so this fails for the DIRECTORY reason and not for a missing article.
  : > "$t/e-none"
  refutes "missing articles dir refused" build_menu title "$t/e-none" "$t/no-such-dir" "$t/o22"
  refutes "unreadable slug list refused (title)" build_menu title "$t/no-such-list" "$art" "$t/o23"
  refutes "unreadable slug list refused (bare)"  build_menu bare  "$t/no-such-list" "$art" "$t/o23b"
  refutes "unknown shape refused"        build_menu bogus "$t/exist" "$art" "$t/o24"

  # ---- the OTHER consumer of the shared reader ---------------------------------------
  # Nothing here exercised regenerate-moc.sh, so deleting its helper calls left every
  # assertion green while index.md silently lost every title. It is shipped pipeline
  # code and the reader is now shared with it, so it gets covered here.
  MOC="$HERE/../../../../scripts/regenerate-moc.sh"
  if [[ -r "$MOC" ]]; then
    mocstack="$t/mocstack"; mkdir -p "$mocstack/articles"
    cp "$art/rag.md" "$mocstack/articles/rag.md"
    printf -- '---\ntitle: No Routing Here\ntags: [llm]\n---\n\nbody\n' > "$mocstack/articles/bare-link.md"
    bash "$MOC" "$mocstack" >/dev/null 2>&1
    assert "regenerate-moc renders the title and routing it read" \
      grep -q 'rag|Retrieval Augmented Generation.*chunking' "$mocstack/index.md"
    assert "regenerate-moc degrades to a bare wiki-link when routing is absent" \
      grep -q '^- \[\[bare-link|No Routing Here\]\]$' "$mocstack/index.md"
    # Invoked through a symlink, dirname-of-$0 resolves the LINK's directory and the
    # helper is not found; with the failure masked that rewrote index.md with empty titles.
    # Assert the symlinked run SUCCEEDS and still renders titles. Comparing the index
    # before/after is not enough: a run that ABORTS also leaves it unchanged, so that
    # assertion passed with the symlink resolution deliberately broken.
    ln -sf "$MOC" "$t/moc-link.sh"
    rm -f "$mocstack/index.md"
    assert "regenerate-moc succeeds when invoked through a symlink" bash "$t/moc-link.sh" "$mocstack"
    assert "symlinked run still renders the title it read" \
      grep -q 'rag|Retrieval Augmented Generation' "$mocstack/index.md"

    # A deployed copy without its helper beside it must abort loudly, not quietly write
    # an index with every title blank.
    cp "$MOC" "$t/lonely-moc.sh"
    refutes "regenerate-moc aborts when the shared reader is missing" bash "$t/lonely-moc.sh" "$mocstack"
  else bad "regenerate-moc.sh not found at $MOC"; fi

  echo
  echo "shadow-extract menu self-check: $passes passed, $fails failed"
  [[ "$fails" -eq 0 ]]
  exit
fi

STACK="${1:?Usage: shadow-extract-run.sh <stack> | --self-check}"
MODEL="${MODEL:-qwen3-30b-a3b-instruct}"
INFER="$HERE/local-infer.sh"
PREMATCH="$HERE/slug-prematch.sh"
OUT="$STACKS_ROOT/dev/experiments/model-tier/live-diffs/extractions"

LIB="$(bash "$STACKS_ROOT/scripts/resolve-library.sh")" || { echo "ERROR: could not resolve library" >&2; exit 1; }
cd "$LIB" || { echo "ERROR: cannot cd into library: $LIB" >&2; exit 1; }
DEV="$STACK/dev/extractions"
DISPATCH="$DEV/dispatch-w1.tsv"
[[ -f "$DISPATCH" ]] || { echo "ERROR: no $DISPATCH — run catalog through prep first (finish clears it)" >&2; exit 1; }

# Reset the output dir each run so the verifier + summary reflect only THIS batch,
# not a prior run's leftover survivor rows (the codex #109 reset-dir lesson).
rm -rf "$OUT"; mkdir -p "$OUT"
SURVIVORS="$OUT/survivors.tsv"   # slug<TAB>local_decision<TAB>prematch  — NEAR/NEW only, the verifier's input
: > "$SURVIVORS"

# EXISTING_SLUGS regenerated LIVE from the stack's articles (never a frozen
# snapshot — the corpus drifts as the stack grows). This stays a PURE slug list:
# slug-prematch.sh consumes it as one-slug-per-line and must not see menu text.
EXIST_FILE="$OUT/existing-slugs.txt"
ls "$STACK"/articles/*.md 2>/dev/null | xargs -r -n1 basename | sed 's/\.md$//' | sort -u > "$EXIST_FILE"
[[ -s "$EXIST_FILE" ]] || echo "WARN: $STACK has no articles yet — every concept will be a genuine mint (first-catalog case)" >&2

# MENU: what the MODEL is shown, which is a different question from what prematch
# needs (#139). Three shapes, because the choice is three-way and the middle rung
# is the one with measured numbers behind it:
#
#   bare   slug only. The pre-0.78.0 behaviour, and the configuration this repo's
#          own key finding blames for fragmenting one article into sub-topic mints.
#          Kept ONLY as the measurement baseline; do not run it for real work.
#   title  "slug - Title". The cheap middle rung. 126 of the peer's ~139 arms used
#          this shape, so it is what their published extraction numbers describe.
#   scope  "slug - routing line". The full scope map. Peer-measured at
#          +0.065 F1 over `title` — but ZERO of that gain landed on primary gold,
#          and it cost 4.3x wall clock. Worth measuring here, not worth assuming.
#
# Default is `title`: it beats bare, and `scope` has not yet earned its 4.3x on
# this harness's own gold. Flip with MENU_SHAPE=scope once that is measured.
MENU_SHAPE="${MENU_SHAPE:-title}"
MENU_FILE="$OUT/menu.txt"

# Descriptions come from each article's own frontmatter, not from index.md — the index
# is generated FROM that frontmatter, so reading it back would re-derive the fields
# through a markdown grammar and inherit the index's staleness. See build_menu.
build_menu "$MENU_SHAPE" "$EXIST_FILE" "$STACK/articles" "$MENU_FILE"

# The prompt must describe the menu the model ACTUALLY gets. A fixed sentence here
# would go false the moment MENU_SHAPE changes, which is the drift class #136 was
# about, one layer down.
case "$MENU_SHAPE" in
  bare)  MENU_NOTE="EXISTING ARTICLES below is a BARE SLUG LIST, not the scope map the reuse-vs-mint
rule above describes. You get slugs only, with no scope line for any of them, so judge
reuse from what each slug's wording implies." ;;
  title) MENU_NOTE="EXISTING ARTICLES below gives each article as 'slug - Title'. That is the title only,
NOT the full described scope the reuse-vs-mint rule above refers to: a title names an
article's subject but does not enumerate what it covers. Judge reuse from the title,
and prefer reuse when a concept plausibly falls under one." ;;
  scope) MENU_NOTE="EXISTING ARTICLES below gives each article as 'slug - described scope', the routing
line from the stack index. That IS the described scope the reuse-vs-mint rule above
refers to. Apply the rule directly: reuse when the concept falls inside a listed scope." ;;
esac

# Tier rubric fed to the local model (the STACK.md hierarchy is the real trust
# order; this generic 1-4 rubric is enough for the advisory grade).
read -r -d '' RUBRIC <<'EOF' || true
Tier 1 Official — vendor docs, model cards, API reference, official cookbooks
Tier 2 Standard — peer-reviewed papers, vendor research blogs, established surveys
Tier 3 Practitioner — practitioner blogs, conference talks, production case studies
Tier 4 General — forum posts, X/HN/Reddit threads
EOF

extract_prompt() { # <source-file> -> stdout: the local extraction prompt
  cat <<EOF
$(bash "$HERE/agent-prompt.sh" "$HERE/../../../../agents/source-extractor.md")

OUTPUT CONTRACT (overrides any output shape described above): emit ONLY the one-line
rows specified at the end of this prompt. No concept blocks, no headings, no prose.
$MENU_NOTE
(No backticks in this heredoc: it is unquoted, so a backtick pair would be executed
as a command and silently vanish from the prompt, exit 0.)

TIER RUBRIC:
$RUBRIC

EXISTING ARTICLES:
$(cat "$MENU_FILE")

SOURCE TEXT:
$(cat "$1")

OUTPUT: one line per concept, exactly <slug> | reuse:<existing-slug|NEW> | tier:<N>. Nothing else.
EOF
}

n=0 skipped=0 failed=0 total_candidates=0 total_survivors=0
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

while IFS=$'\t' read -r batch_tag src; do
  [[ -n "${src:-}" ]] || continue
  if [[ ! -f "$src" ]]; then echo "SKIP $batch_tag: no source ($src)" >&2; skipped=$((skipped+1)); continue; fi
  extract_prompt "$src" > "$work/prompt.txt"
  if ! NUM_CTX="${NUM_CTX:-16384}" bash "$INFER" "$MODEL" "$work/prompt.txt" "$work/out.txt" 2>"$work/err"; then
    echo "EXTRACT-FAIL $batch_tag ($(tail -1 "$work/err" 2>/dev/null))" >&2; failed=$((failed+1)); continue
  fi
  # parse "<slug> | reuse:... | tier:N" rows, prematch each emitted slug
  candfile="$OUT/${batch_tag}.tsv"; : > "$candfile"
  while IFS='|' read -r slug decision tier; do
    slug="$(echo "$slug" | tr -d '[:space:]')"; [[ -n "$slug" ]] || continue
    decision="$(echo "$decision" | tr -d '[:space:]')"
    pm="$(bash "$PREMATCH" "$slug" "$EXIST_FILE")"
    printf '%s\t%s\t%s\n' "$slug" "${decision:-NEW}" "$pm" >> "$candfile"
    total_candidates=$((total_candidates+1))
    # REUSE (exact/normalized collision) is harness-resolved and never sent to the
    # verifier; NEAR/NEW survive to the cloud grade.
    case "$pm" in REUSE:*) ;; *) printf '%s\t%s\t%s\n' "$slug" "${decision:-NEW}" "$pm" >> "$SURVIVORS"; total_survivors=$((total_survivors+1)) ;; esac
  done < <(grep -E '\|' "$work/out.txt")
  n=$((n+1))
done < "$DISPATCH"

echo "SHADOW_EXTRACT_SUMMARY: stack=$STACK sources=$n skipped=$skipped failed=$failed candidates=$total_candidates survivors(NEAR/NEW->verify)=$total_survivors -> $SURVIVORS" >&2
