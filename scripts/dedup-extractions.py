# dedup-extractions.py
# W1b dedup: merge concept extractions from batch files into a single deduplicated file.
# Usage: python3 dedup-extractions.py <extr_dir> <dedup_path>
# Side-output: writes _dedup-meta.txt to extr_dir; caller must source it for env var injection.

import os, re, sys, glob, math
from itertools import combinations
from collections import Counter

# --- near-dup similarity (stacks#106) ---------------------------------------
# Flag two NEW slugs that are the same concept under different titles, WITHOUT
# flagging distinct concepts that share a boilerplate title template. The pre-#106
# metric (raw SequenceMatcher on the whole title) did both wrong on a cold-start
# catalog: it flagged "HVAC/Plumbing/Electrical Walk-Through Scope (E2018)" as
# mutual dups (shared template) and missed "HVAC Walk-Through Scope" vs "HVAC
# Systems Observation" (a real dup with differing titles).
#
# Fix: strip *template* tokens — those appearing in >= _BOILERPLATE_DF of the
# candidate titles, which are generic scaffolding, not a dup signal — then score the
# remaining distinctive tokens with a plain set cosine. A genuine same-concept pair
# shares a distinctive token present in only those ~2 titles (kept); a template phrase
# spans many titles (dropped). Ceiling: a concept minted under 3+ different titles by
# 3+ blind extractors loses its shared token to the cutoff — rare; the operator's
# near-dup review and the index-scope reuse hint remain the backstops.
_TOKEN_RE = re.compile(r"[a-z0-9]+")
_STOP = {"the", "a", "an", "of", "and", "or", "for", "to", "in", "on", "with",
         "by", "is", "are", "as", "at"}
_BOILERPLATE_DF = 3      # a token in >= this many titles is template scaffolding, not a dup signal
NEAR_DUP_FLOOR = 0.40    # ponytail: set-cosine floor. Report-only, so bias loose (a spurious
                         # pair is a cheap operator skip; a miss is silent). Tune per corpus.
_IDENTICAL_TITLE_FLOOR = 0.85  # fallback when both titles are all-boilerplate (see below)

def _title_tokens(title):
    return [t for t in _TOKEN_RE.findall(title.casefold()) if len(t) > 1 and t not in _STOP]

def near_dup_pairs_from_titles(titles):
    """titles: {slug: title}. Return [(a, b, score)] with score >= NEAR_DUP_FLOOR,
    most-similar first. Score = cosine over each title's DISTINCTIVE token set
    (template tokens shared by >= _BOILERPLATE_DF titles removed first).

    Boundary (stacks#106 codex pass): when 3+ slugs share an *identical* title, every
    token hits df >= _BOILERPLATE_DF and both distinctive sets empty. Falling straight
    through would silently miss a real exact-title dup the old raw-ratio metric caught,
    so an all-boilerplate pair falls back to the FULL-token cosine and flags only if the
    titles are near-identical. A distinct system that merely shares a template keeps a
    non-empty distinctive set (its system name), so it never reaches the fallback.
    Small-n ceiling: with < 3 candidates no token can reach the cutoff, so a shared
    template is not stripped and may score above the floor — report-only, one pair,
    cheap to skip."""
    slugs = sorted(titles)
    df = Counter()
    for s in slugs:
        for t in set(_title_tokens(titles[s])):
            df[t] += 1
    full = {s: set(_title_tokens(titles[s])) for s in slugs}
    sets = {s: {t for t in full[s] if df[t] < _BOILERPLATE_DF} for s in slugs}
    pairs = []
    for a, b in combinations(slugs, 2):
        sa, sb = sets[a], sets[b]
        if sa and sb:
            score = len(sa & sb) / math.sqrt(len(sa) * len(sb))
        else:
            fa, fb = full[a], full[b]
            raw = len(fa & fb) / math.sqrt(len(fa) * len(fb)) if fa and fb else 0.0
            score = raw if raw >= _IDENTICAL_TITLE_FLOOR else 0.0
        if score >= NEAR_DUP_FLOOR:
            pairs.append((a, b, score))
    return sorted(pairs, key=lambda p: -p[2])

def _self_check():
    # The #106 cold-start case: 4 building systems sharing a title template + one real
    # dup (hvac split across two extractors under different titles). The template pairs
    # must NOT flag; the real HVAC pair MUST.
    titles = {
        "hvac": "HVAC Walk-Through Scope (E2018)",
        "plumbing": "Plumbing Walk-Through Scope (E2018)",
        "electrical": "Electrical Walk-Through Scope (E2018)",
        "roofing": "Roofing Walk-Through Scope (E2018)",
        "hvac-systems-pca-observation": "HVAC Systems Observation",
        "chiller-efficiency": "Chiller Efficiency Metrics",
    }
    flagged = {frozenset((a, b)) for a, b, _ in near_dup_pairs_from_titles(titles)}
    def has(x, y):
        return frozenset((x, y)) in flagged
    assert has("hvac", "hvac-systems-pca-observation"), f"real HVAC dup not flagged; flagged={flagged}"
    for a, b in combinations(["hvac", "plumbing", "electrical", "roofing"], 2):
        assert not has(a, b), f"boilerplate-template pair {a}~{b} wrongly flagged; flagged={flagged}"
    assert not has("chiller-efficiency", "hvac"), "unrelated pair flagged"
    # 3-way EXACT-title dup: every token looks like boilerplate (df==n), but they are
    # the same concept and must all flag via the full-token fallback (regression guard).
    same = near_dup_pairs_from_titles(
        {"a1": "HVAC Systems Observation", "a2": "HVAC Systems Observation",
         "a3": "HVAC Systems Observation"})
    sflag = {frozenset((x, y)) for x, y, _ in same}
    assert sflag == {frozenset(("a1", "a2")), frozenset(("a1", "a3")), frozenset(("a2", "a3"))}, \
        f"3-way exact-title dup not all flagged: {sflag}"
    print("dedup-extractions near-dup self-check: PASS", file=sys.stderr)

if sys.argv[1:] == ["--self-check"]:
    _self_check()
    sys.exit(0)

extr_dir, dedup_path = sys.argv[1], sys.argv[2]
batch_files = sorted(glob.glob(os.path.join(extr_dir, "batch-*-concepts.md")))

slug_sources = {}              # slug -> list of source paths in first-seen order
slug_target_article = {}       # slug -> existing target slug ("" if none)
slug_title = {}                # slug -> human title
slug_source_tier = {}          # slug -> {source_path -> tier}, first-seen per source (stacks#89)
slug_claims = {}               # slug -> list of claim lines (concatenated across batches)
input_blocks_total = 0
title_mismatch_slugs = set()   # slugs where a later block's title disagreed with the first-seen title

def _norm_title(s):
    return re.sub(r"\s+", " ", s.strip()).casefold()

block_re = re.compile(r"^## Concept: ", re.MULTILINE)

def parse_block(block_text):
    lines = block_text.splitlines()
    fields = {"slug": "", "title": "", "target_article": "",
              "tier": "", "source_paths": [], "claims_lines": []}
    in_sources = False
    in_claims = False
    for line in lines:
        if line.startswith("### Claims"):
            in_claims = True; in_sources = False; continue
        if in_claims:
            fields["claims_lines"].append(line); continue
        if line.startswith("source_paths:"):
            in_sources = True; continue
        if in_sources:
            m = re.match(r"^\s+-\s+(.+)$", line)
            if m:
                # Normalize to bare `sources/...`: strip any leading `<stack>/`
                # or absolute prefix the extractor echoed from the dispatched
                # path, so article frontmatter never carries the redundant
                # `<stack>/sources/` form (stacks#65).
                sp = re.sub(r"^.*?(?=sources/)", "", m.group(1).strip())
                fields["source_paths"].append(sp); continue
            in_sources = False
        m = re.match(r"^(slug|title|target_article|tier):\s*(.*)$", line)
        if m:
            v = m.group(2).strip().strip('"')
            fields[m.group(1)] = v
    return fields

for bf in batch_files:
    with open(bf) as f: text = f.read()
    parts = block_re.split(text)
    # parts[0] is anything before the first "## Concept: ", discard
    for body in parts[1:]:
        block = "## Concept: " + body
        fields = parse_block(block)
        slug = fields["slug"]
        if not slug: continue
        input_blocks_total += 1
        # Same slug, different concept: extractors run in parallel per-source and can
        # collide on a slug for genuinely different titles. Warn instead of silently
        # merging under the first-seen title. Detecting the inverse (same concept,
        # different slug) needs a similarity pass and is deferred, out of scope here.
        if slug in slug_title and _norm_title(fields["title"]) != _norm_title(slug_title[slug]):
            print(
                f"WARNING: slug '{slug}' has conflicting titles: "
                f"first-seen '{slug_title[slug]}' vs '{fields['title']}' in {bf} "
                "(different concepts sharing a slug are being merged under the first-seen title)",
                file=sys.stderr,
            )
            title_mismatch_slugs.add(slug)
        if slug not in slug_sources:
            slug_sources[slug] = []
            slug_target_article[slug] = fields["target_article"]
            slug_title[slug] = fields["title"]
            slug_source_tier[slug] = {}
            slug_claims[slug] = []
        # Tier attaches per source_path, not per concept (contract §3, stacks#89): a
        # block's tier applies to every source it lists; record it first-seen per source
        # so a slug merging a Tier-1 standard and a Tier-4 blog keeps both distinctions
        # instead of collapsing to the first-seen block's scalar tier.
        for sp in fields["source_paths"]:
            slug_source_tier[slug].setdefault(sp, fields["tier"])
        slug_sources[slug] = list(dict.fromkeys(slug_sources[slug] + fields["source_paths"]))
        if fields["target_article"] and not slug_target_article[slug]:
            slug_target_article[slug] = fields["target_article"]
        slug_claims[slug].extend(fields["claims_lines"])

def write_block(fh, slug):
    fh.write(f"## Concept: {slug_title[slug]}\n\n")
    fh.write(f"slug: {slug}\n")
    fh.write(f"title: {slug_title[slug]}\n")
    fh.write("source_paths:\n")
    # Tier is carried inline per source `- {path} (tier {N})`, not as one collapsed
    # block-level `tier:` scalar (stacks#89). article-synthesizer reads the tier for
    # STACK.md-hierarchy weighting and writes the bare path (suffix stripped) into the
    # article's `sources:` frontmatter.
    for sp in slug_sources[slug]:
        tier = slug_source_tier[slug].get(sp, "")
        fh.write(f"  - {sp} (tier {tier})\n" if tier else f"  - {sp}\n")
    fh.write(f'target_article: {slug_target_article[slug] or ""}\n\n')
    fh.write("### Claims\n")
    for cl in slug_claims[slug]:
        fh.write(cl + "\n")
    fh.write("\n")

# Write merged _dedup.md (one block per unique slug, source_paths merged).
with open(dedup_path, "w") as f:
    for slug in sorted(slug_sources):
        write_block(f, slug)

# W1b near-dup pass: catch the inverse of the shared-slug collision — two NEW slugs
# that are really the same concept under different names. Exact-slug match can't see
# these (they never collide), so two thin stubs would ship forever. Extractors run
# blind to each other, so this can only be caught here, after all blocks are merged.
# Similarity is distinctive-token set cosine (see near_dup_pairs_from_titles at the
# top): it strips the shared boilerplate title template that made the old raw-string
# ratio flag distinct systems and miss real dups (stacks#106). Report-only, never
# auto-merges (a wrong merge is worse than two stubs). Only NEW slugs — an updated
# slug already has its article. (stacks#78, #106)
new_slugs = sorted(s for s in slug_sources if not slug_target_article[s])
near_dup_pairs = near_dup_pairs_from_titles({s: slug_title[s] for s in new_slugs})
for a, b, score in near_dup_pairs:
    print(
        f"WARNING: new slugs '{a}' and '{b}' have {score:.0%} distinctive-title overlap "
        f"('{slug_title[a]}' vs '{slug_title[b]}') — likely the same concept split "
        "across parallel extractors; review and merge before synthesis.",
        file=sys.stderr,
    )

# Emit slug list, new/updated classification, and counts to _dedup-meta.txt for caller to source.
updated_slugs = [s for s in slug_sources if slug_target_article[s]]
with open(os.path.join(extr_dir, "_dedup-meta.txt"), "w") as f:
    f.write(f"INPUT_BLOCKS={input_blocks_total}\n")
    f.write(f"N_UNIQUE_CONCEPTS={len(slug_sources)}\n")
    f.write(f"N_NEW={len(slug_sources) - len(updated_slugs)}\n")
    f.write(f"N_UPDATED={len(updated_slugs)}\n")
    f.write("ALL_SLUGS=" + " ".join(sorted(slug_sources)) + "\n")
    f.write("UPDATED_SLUGS=" + " ".join(sorted(updated_slugs)) + "\n")
    f.write("TITLE_MISMATCH_SLUGS=" + " ".join(sorted(title_mismatch_slugs)) + "\n")
    f.write("NEAR_DUP_PAIRS=" + " ".join(f"{a}~{b}" for a, b, _ in near_dup_pairs) + "\n")

# Write one _dedup-{slug}.md per unique slug so article-synthesizer agents each
# read a self-contained single-concept file rather than parsing _dedup.md.
for slug in sorted(slug_sources):
    per_slug_path = os.path.join(extr_dir, f"_dedup-{slug}.md")
    with open(per_slug_path, "w") as f:
        write_block(f, slug)
