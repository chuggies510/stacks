#!/usr/bin/env python3
"""pair-claims.py <article.md> <stack-root>

Deterministic claim->cited-source-excerpt pairing for the validation shadow
(#109 retrieval follow-on). The article-dump approach let the local model pick
its own excerpt per claim and it re-used one boilerplate passage across many
claims (a retrieval failure). Here the HARNESS owns retrieval: it splits the
article into claims, resolves each claim's inline [slug] citation (or, for an
uncited claim, its best-matching frontmatter-listed source), and pulls the
single best token-overlap passage from that source. The model then judges ONE
claim + ONE excerpt — the offline-benchmark shape that scored 1.00.

Retrieval is plain token-overlap (no embeddings): lazy, dependency-free, and
deterministic, which is what a regression harness needs.

Output: one TAB-separated line per claim, fields scrubbed of tabs/newlines:
  <idx>\t<cited 0|1>\t<claim text>\t<src_slug or NONE>\t<excerpt or NONE>

--self-check runs an on-disk fixture and asserts extraction + retrieval.
"""
import os, re, sys, glob, tempfile

STOP = set("""the a an and or but of to in on at for with without from by as is are was were be been
being this that these those it its it's their there here then than so such not no nor can could
will would may might must should have has had do does did who whom which what when where why how
into over under above below out off up down more most less least very much many few both each any
all some one two three you your we our they them he she his her about only also just even still
because if while during after before between within across per via using used use uses""".split())

CITE_RE = re.compile(r'\[([A-Za-z0-9][\w.\-]+)\](?!\()')   # [slug] not a markdown link
SENT_RE = re.compile(r'(?<=[.!?])\s+')
MIN_WORDS = 6
EXCERPT_CAP = 700
# A real claim opens on a capital/digit/quote and does not end on a dangling
# function word — the two high-precision signals that separate a whole sentence
# from mid-sentence fragment/heading leakage the splitter would otherwise feed the
# model as a "claim" (liminal S63: ~11% of false positives were such junk). Kept
# conservative so it never drops a real claim; no-antecedent-pronoun and verbless
# heading cases need coref/POS and are out of scope.
DANGLING = set("to and or of the a an with for in on at by from as that which into "
               "than but nor so if while over under between within".split())
TOP_K = 3        # feed the model the K best-overlap source sentences, not just the
                 # single best — token-overlap is noisier than the offline
                 # hand-pairing, so the claim's decisive sentence may be 2nd/3rd.


def tokens(text):
    return {t for t in re.findall(r'[a-z0-9]{3,}', text.lower()) if t not in STOP}


def split_sentences(text):
    return [s.strip() for s in SENT_RE.split(text.strip()) if s.strip()]


def scrub(s):
    return re.sub(r'\s+', ' ', s.replace('\t', ' ').replace('\n', ' ')).strip()


def parse_frontmatter_sources(lines):
    """Return {slug: relpath} for the frontmatter `sources:` list (slug = basename -.md)."""
    out, in_fm, in_src = {}, False, False
    for i, ln in enumerate(lines):
        if ln.rstrip() == '---':
            if not in_fm and i == 0:
                in_fm = True; continue
            if in_fm:
                break
        if not in_fm:
            continue
        if re.match(r'^\s*sources:\s*$', ln):
            in_src = True; continue
        if in_src:
            m = re.match(r'^\s*-\s*(\S+)', ln)
            if m:
                rel = m.group(1)
                out[os.path.splitext(os.path.basename(rel))[0]] = rel
            elif re.match(r'^\S', ln):   # next top-level key ends the list
                in_src = False
    return out


def body_lines(lines):
    """Strip frontmatter, skip headings / tables / fenced code."""
    fm_seen, in_fm, fenced, out = 0, False, False, []
    for i, ln in enumerate(lines):
        if ln.rstrip() == '---':
            if i == 0:
                in_fm = True; continue
            if in_fm:
                in_fm = False; continue
        if in_fm:
            continue
        if ln.lstrip().startswith('```'):
            fenced = not fenced; continue
        if fenced:
            continue
        s = ln.strip()
        if not s or s.startswith('#') or s.startswith('|'):
            continue
        out.append(s)
    return out


def well_formed_claim(s):
    """True iff s looks like a whole factual sentence, not a fragment/heading the
    splitter leaked. Two conservative signals (S63): opens on a capital/digit/quote
    (a mid-sentence fragment opens on '(', ';', or a lowercase word), and does not
    end on a dangling function word (a truncated clause ends in 'to'/'and'/...)."""
    core = re.sub(r'\s*\[[^\]]+\]\s*$', '', s).rstrip()        # drop a trailing [cite]
    if not core:
        return False
    if not re.match(r'["\'A-Z0-9]', core):                    # fragment opener
        return False
    last = re.sub(r'[^\w]+$', '', core.split()[-1]).lower()   # last word, depunct
    return last not in DANGLING


def line_to_claims(line):
    """A body line -> its factual sentences. Strips list markers and bold/italic."""
    line = re.sub(r'^\s*(?:[-*+]|\d+\.)\s+', '', line)          # list marker
    line = re.sub(r'\*\*([^*]+)\*\*', r'\1', line)              # bold
    line = re.sub(r'(?<!\*)\*([^*]+)\*(?!\*)', r'\1', line)     # italic
    for sent in split_sentences(line):
        sent = sent.strip()
        # skip list-intro fragments ("... operates at two levels:") — not factual
        # claims, and no source passage grounds a lead-in.
        if sent.endswith(':'):
            continue
        if len(sent.split()) >= MIN_WORDS and well_formed_claim(sent):
            yield sent


def source_units(text):
    """Split a source into retrieval units: each markdown BULLET is its own unit,
    each prose line is split into sentences. Headers/fenced-code/table rows are
    dropped. Keeping bullets separate is load-bearing — a bulleted list has no
    terminal periods, so joining lines first merges the whole list into one giant
    'sentence' whose relevant tail gets truncated away by the excerpt cap."""
    fenced, units = False, []
    for ln in text.splitlines():
        s = ln.strip()
        if s.startswith('```'):
            fenced = not fenced; continue
        if fenced or s.startswith('#') or s.startswith('|') or not s:
            continue
        s = re.sub(r'\*\*([^*]+)\*\*', r'\1', s)
        s = re.sub(r'^\s*(?:[-*+]|\d+\.)\s+', '', s)   # strip list marker
        units.extend(split_sentences(s) or [s])
    return [u for u in units if u.strip()]


def retrieve(claim, source_text):
    """The TOP_K token-overlap units of source_text vs claim, in source order,
    joined and length-capped. Top-K (not top-1) hedges retrieval noise so the
    claim's decisive unit is very likely present."""
    ct = tokens(claim)
    if not ct:
        return ''
    sents = source_units(source_text)
    scored = [(len(ct & tokens(s)), i, s) for i, s in enumerate(sents)]
    scored = [x for x in scored if x[0] > 0]
    if not scored:
        return ''
    top = sorted(scored, key=lambda x: (-x[0], x[1]))[:TOP_K]
    top.sort(key=lambda x: x[1])                       # back to source order
    return ' … '.join(s for _, _, s in top)[:EXCERPT_CAP]


def read(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


def resolve_source(slug, fm_map, stack_root):
    rel = fm_map.get(slug)
    if rel and os.path.isfile(os.path.join(stack_root, rel)):
        return os.path.join(stack_root, rel)
    hits = glob.glob(os.path.join(stack_root, 'sources', '**', slug + '.md'), recursive=True)
    return hits[0] if hits else None


def pair(article_path, stack_root):
    lines = read(article_path).splitlines()
    fm_map = parse_frontmatter_sources(lines)
    src_cache = {}
    def src_text(slug):
        if slug not in src_cache:
            p = resolve_source(slug, fm_map, stack_root)
            src_cache[slug] = read(p) if p else ''
        return src_cache[slug]

    rows, idx = [], 0
    for line in body_lines(lines):
        for claim in line_to_claims(line):
            idx += 1
            slugs = [s for s in CITE_RE.findall(claim) if s in fm_map or re.search(r'[\d-]', s)]
            if slugs:
                slug = slugs[0]
                excerpt = retrieve(claim, src_text(slug))
                rows.append((idx, 1, claim, slug, excerpt or 'NONE'))
            else:
                # uncited: pick the frontmatter source with the best overlap so the
                # model can decide add-citation (a listed source grounds it) vs softspot.
                best = (-1, 'NONE', 'NONE')
                for slug in fm_map:
                    ex = retrieve(claim, src_text(slug))
                    sc = len(tokens(claim) & tokens(ex)) if ex else -1
                    if sc > best[0]:
                        best = (sc, slug, ex or 'NONE')
                rows.append((idx, 0, claim, best[1], best[2]))
    return rows


def emit(rows):
    for idx, cited, claim, slug, excerpt in rows:
        print(f"{idx}\t{cited}\t{scrub(claim)}\t{slug}\t{scrub(excerpt)}")


def self_check():
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, 'sources', 'pub'))
    with open(os.path.join(d, 'sources', 'pub', 'src-a.md'), 'w') as f:
        f.write("The widget spins at 3000 rpm under nominal load conditions. "
                "An unrelated filler sentence about warehouse paint colors.\n")
    with open(os.path.join(d, 'sources', 'pub', 'src-b.md'), 'w') as f:
        f.write("Backpressure damper interlocks trip on a fan fault to protect the ductwork.\n")
    art = os.path.join(d, 'art.md')
    with open(art, 'w') as f:
        f.write("---\nsources:\n  - sources/pub/src-a.md\n  - sources/pub/src-b.md\n---\n"
                "## Head\n"
                "The widget spins at 3000 rpm under sustained load [src-a].\n"
                "- **Something**: this connective sentence has plenty of words but carries no citation.\n"
                "(self-enhancement bias) a mid sentence fragment leaking into the body and\n"
                "```\ncode block line that must be skipped entirely here\n```\n"
                "| table | row | that | is | skipped |\n")
    rows = pair(art, d)
    fail = 0
    def chk(cond, msg):
        nonlocal fail
        if not cond:
            print("FAIL:", msg); fail = 1
    chk(len(rows) == 2, f"expected 2 claims, got {len(rows)}: {[r[2] for r in rows]}")
    c1 = rows[0]
    chk(c1[1] == 1 and c1[3] == 'src-a', f"claim1 should be cited to src-a, got cited={c1[1]} slug={c1[3]}")
    chk('3000 rpm' in c1[4], f"claim1 excerpt should retrieve the rpm sentence, got: {c1[4]!r}")
    chk('paint colors' not in c1[4], "claim1 excerpt wrongly grabbed the filler sentence")
    c2 = rows[1]
    chk(c2[1] == 0, f"claim2 should be uncited, got cited={c2[1]}")
    chk(not any('self-enhancement' in r[2] for r in rows),
        "the fragment line should be dropped by well_formed_claim, not yielded as a claim")
    chk(well_formed_claim("The widget spins at 3000 rpm under sustained load."),
        "a whole sentence should pass well_formed_claim")
    chk(not well_formed_claim("(self-enhancement bias) routing generation and evaluation to"),
        "leading-paren + dangling-'to' fragment should fail well_formed_claim")
    chk(not well_formed_claim("and this dangling clause ends on a function word and"),
        "lowercase-opener + dangling fragment should fail well_formed_claim")
    if fail == 0:
        print("SELF-CHECK PASS")
    sys.exit(fail)


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == '--self-check':
        self_check()
    # --retrieve <source.md ...>: read one claim from stdin, print the best
    # token-overlap excerpt across the given source files (used by --gold-check).
    if len(sys.argv) >= 3 and sys.argv[1] == '--retrieve':
        claim = sys.stdin.read()
        best = (-1, '')
        for src in sys.argv[2:]:
            ex = retrieve(claim, read(src)) if os.path.isfile(src) else ''
            sc = len(tokens(claim) & tokens(ex)) if ex else -1
            if sc > best[0]:
                best = (sc, ex)
        print(scrub(best[1]) if best[1] else 'NONE')
        sys.exit(0)
    if len(sys.argv) != 3:
        sys.exit("usage: pair-claims.py <article.md> <stack-root> | --retrieve <src...> | --self-check")
    emit(pair(sys.argv[1], sys.argv[2]))
