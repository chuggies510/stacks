# dedup-extractions.py
# W1b dedup: merge concept extractions from batch files into a single deduplicated file.
# Usage: python3 dedup-extractions.py <extr_dir> <dedup_path>
# Side-output: writes _dedup-meta.txt to extr_dir; caller must source it for env var injection.

import os, re, sys, glob

extr_dir, dedup_path = sys.argv[1], sys.argv[2]
batch_files = sorted(glob.glob(os.path.join(extr_dir, "batch-*-concepts.md")))

slug_seen = set()              # slugs encountered (dedup key)
slug_sources = {}              # slug -> list of source paths in first-seen order
slug_seen_sources = {}         # slug -> set
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
        if slug not in slug_seen:
            slug_seen.add(slug)
            slug_sources[slug] = []
            slug_seen_sources[slug] = set()
            slug_target_article[slug] = fields["target_article"]
            slug_title[slug] = fields["title"]
            slug_tier[slug] = fields["tier"]
            slug_claims[slug] = []
        for sp in fields["source_paths"]:
            if sp not in slug_seen_sources[slug]:
                slug_sources[slug].append(sp)
                slug_seen_sources[slug].add(sp)
        if fields["target_article"] and not slug_target_article[slug]:
            slug_target_article[slug] = fields["target_article"]
        slug_claims[slug].extend(fields["claims_lines"])

# Write merged _dedup.md (one block per unique slug, source_paths merged).
with open(dedup_path, "w") as f:
    for slug in sorted(slug_seen):
        f.write(f"## Concept: {slug_title[slug]}\n\n")
        f.write(f"slug: {slug}\n")
        f.write(f"title: {slug_title[slug]}\n")
        f.write("source_paths:\n")
        for sp in slug_sources[slug]:
            f.write(f"  - {sp}\n")
        f.write(f'target_article: {slug_target_article[slug] or ""}\n')
        f.write(f"tier: {slug_tier[slug]}\n\n")
        f.write("### Claims\n")
        for cl in slug_claims[slug]:
            f.write(cl + "\n")
        f.write("\n")

# Emit slug list, new/updated classification, and counts to _dedup-meta.txt for caller to source.
updated_slugs = [s for s in slug_seen if slug_target_article[s]]
with open(os.path.join(extr_dir, "_dedup-meta.txt"), "w") as f:
    f.write(f"INPUT_BLOCKS={input_blocks_total}\n")
    f.write(f"N_UNIQUE_CONCEPTS={len(slug_seen)}\n")
    f.write(f"N_NEW={len(slug_seen) - len(updated_slugs)}\n")
    f.write(f"N_UPDATED={len(updated_slugs)}\n")
    f.write("ALL_SLUGS=" + " ".join(sorted(slug_seen)) + "\n")
    f.write("UPDATED_SLUGS=" + " ".join(sorted(updated_slugs)) + "\n")
