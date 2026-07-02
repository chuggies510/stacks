# dedup-extractions.py
# W1b dedup: merge concept extractions from batch files into a single deduplicated file.
# Usage: python3 dedup-extractions.py <extr_dir> <dedup_path>
# Side-output: writes _dedup-meta.txt to extr_dir; caller must source it for env var injection.

import os, re, sys, glob
from difflib import SequenceMatcher
from itertools import combinations

extr_dir, dedup_path = sys.argv[1], sys.argv[2]
batch_files = sorted(glob.glob(os.path.join(extr_dir, "batch-*-concepts.md")))

slug_sources = {}              # slug -> list of source paths in first-seen order
slug_target_article = {}       # slug -> existing target slug ("" if none)
slug_title = {}                # slug -> human title
slug_tier = {}                 # slug -> tier
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
        # merging under the first-seen title/tier. Detecting the inverse (same concept,
        # different slug) needs a similarity pass and is deferred, out of scope here.
        if slug in slug_title and _norm_title(fields["title"]) != _norm_title(slug_title[slug]):
            print(
                f"WARNING: slug '{slug}' has conflicting titles: "
                f"first-seen '{slug_title[slug]}' vs '{fields['title']}' in {bf} "
                "(different concepts sharing a slug are being merged under the first-seen title/tier)",
                file=sys.stderr,
            )
            title_mismatch_slugs.add(slug)
        if slug not in slug_sources:
            slug_sources[slug] = []
            slug_target_article[slug] = fields["target_article"]
            slug_title[slug] = fields["title"]
            slug_tier[slug] = fields["tier"]
            slug_claims[slug] = []
        slug_sources[slug] = list(dict.fromkeys(slug_sources[slug] + fields["source_paths"]))
        if fields["target_article"] and not slug_target_article[slug]:
            slug_target_article[slug] = fields["target_article"]
        slug_claims[slug].extend(fields["claims_lines"])

def write_block(fh, slug):
    fh.write(f"## Concept: {slug_title[slug]}\n\n")
    fh.write(f"slug: {slug}\n")
    fh.write(f"title: {slug_title[slug]}\n")
    fh.write("source_paths:\n")
    for sp in slug_sources[slug]:
        fh.write(f"  - {sp}\n")
    fh.write(f'target_article: {slug_target_article[slug] or ""}\n')
    fh.write(f"tier: {slug_tier[slug]}\n\n")
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
# Title is the cheap high-signal field present in every block (routing lives in the
# article, not the extraction). Flag pairs above a similarity floor for the operator
# to merge before synthesis; report-only, never auto-merges (a wrong merge is worse
# than two stubs). Only NEW slugs — an updated slug already has its article. (stacks#78)
NEAR_DUP_FLOOR = 0.72
new_slugs = sorted(s for s in slug_sources if not slug_target_article[s])
near_dup_pairs = []
for a, b in combinations(new_slugs, 2):
    ratio = SequenceMatcher(None, _norm_title(slug_title[a]), _norm_title(slug_title[b])).ratio()
    if ratio >= NEAR_DUP_FLOOR:
        near_dup_pairs.append((a, b, ratio))
        print(
            f"WARNING: new slugs '{a}' and '{b}' have {ratio:.0%}-similar titles "
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
