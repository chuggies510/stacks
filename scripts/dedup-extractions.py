# dedup-extractions.py
# W1b dedup: merge concept extractions from batch files into a single deduplicated file.
# Usage: python3 dedup-extractions.py <extr_dir> <dedup_path>
# Side-output: writes _dedup-meta.txt to extr_dir; caller must source it for env var injection.

import os, re, sys, glob

extr_dir, dedup_path = sys.argv[1], sys.argv[2]
batch_files = sorted(glob.glob(os.path.join(extr_dir, "batch-*-concepts.md")))

slug_sources = {}              # slug -> list of source paths in first-seen order
slug_target_article = {}       # slug -> existing target slug ("" if none)
slug_title = {}                # slug -> human title
slug_tier = {}                 # slug -> tier
slug_claims = {}               # slug -> list of claim lines (concatenated across batches)
input_blocks_total = 0

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
            if m: fields["source_paths"].append(m.group(1).strip()); continue
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

# Emit slug list, new/updated classification, and counts to _dedup-meta.txt for caller to source.
updated_slugs = [s for s in slug_sources if slug_target_article[s]]
with open(os.path.join(extr_dir, "_dedup-meta.txt"), "w") as f:
    f.write(f"INPUT_BLOCKS={input_blocks_total}\n")
    f.write(f"N_UNIQUE_CONCEPTS={len(slug_sources)}\n")
    f.write(f"N_NEW={len(slug_sources) - len(updated_slugs)}\n")
    f.write(f"N_UPDATED={len(updated_slugs)}\n")
    f.write("ALL_SLUGS=" + " ".join(sorted(slug_sources)) + "\n")
    f.write("UPDATED_SLUGS=" + " ".join(sorted(updated_slugs)) + "\n")

# Write one _dedup-{slug}.md per unique slug so article-synthesizer agents each
# read a self-contained single-concept file rather than parsing _dedup.md.
for slug in sorted(slug_sources):
    per_slug_path = os.path.join(extr_dir, f"_dedup-{slug}.md")
    with open(per_slug_path, "w") as f:
        write_block(f, slug)
