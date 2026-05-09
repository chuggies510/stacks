# reconcile-findings.py
# Purpose: pre-A3 reconcile pass. Closes prior open findings whose articles
#          were deleted, whose claim text was rewritten out, or whose claim
#          now carries a [VERIFIED] / [DRIFT] inline mark.
# Usage:   python3 reconcile-findings.py <stack> <audit_date> <stack_head>
# Output:  rewrites <stack>/dev/audit/findings.md in place. Stable when nothing
#          to reconcile. Logs ambiguous-match warnings to stderr.

import os, re, sys

stack = sys.argv[1]
audit_date = sys.argv[2]
stack_head = sys.argv[3]
findings_path = f"{stack}/dev/audit/findings.md"
articles_dir = f"{stack}/articles"

if not os.path.isfile(findings_path):
    sys.exit(0)

raw = open(findings_path).read()

# Split into preamble (frontmatter + section headers up to first item) and items.
# Items begin at column 0 with `- id:`. Preserve everything between items including
# section headers, since we rewrite the file in place by re-emitting the
# preamble + maybe-modified items.
parts = re.split(r'(?m)^(?=- id:)', raw)
preamble = parts[0]
item_blocks = parts[1:]


def normalize_ws(s):
    return re.sub(r'\s+', ' ', s).strip()


def parse_item(blk):
    fields = {}
    for line in blk.splitlines():
        m = re.match(r'^\s*-?\s*(\w+):\s*(.*)$', line)
        if m:
            fields[m.group(1)] = m.group(2).strip()
    return fields


def strip_quotes(v):
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
        return v[1:-1]
    return v


def reconcile(blk):
    """Return (new_blk, action_taken). action_taken is one of:
       'unchanged', 'closed-article-missing', 'closed-verified',
       'closed-drift', 'closed-claim-removed', 'ambiguous'."""
    fields = parse_item(blk)
    if fields.get("status") != "open":
        return blk, "unchanged"
    if fields.get("action") == "research_question":
        return blk, "unchanged"
    article_slug = fields.get("article", "")
    claim = strip_quotes(fields.get("claim", ""))
    if not article_slug or not claim:
        return blk, "unchanged"

    article_path = f"{articles_dir}/{article_slug}.md"
    if not os.path.isfile(article_path):
        return _close(blk, fields, "article deleted between audit cycles"), "closed-article-missing"

    body = open(article_path).read()
    norm_body = normalize_ws(body)
    norm_claim = normalize_ws(claim)
    if not norm_claim:
        return blk, "unchanged"

    occurrences = []
    start = 0
    while True:
        idx = norm_body.find(norm_claim, start)
        if idx == -1:
            break
        occurrences.append(idx)
        start = idx + 1

    if len(occurrences) == 0:
        # Claim text not found verbatim. This usually means findings-analyst
        # paraphrased when extracting (dropped parentheticals, expanded
        # acronyms, etc.) — not that the claim was rewritten out. Don't close
        # on this signal; carry forward and let rotate-findings.sh age out
        # truly-stale items eventually.
        return blk, "unchanged"

    if len(occurrences) > 1:
        sys.stderr.write(
            f"reconcile-findings: ambiguous match for id={fields.get('id', '?')} "
            f"({len(occurrences)} occurrences)\n"
        )
        return blk, "ambiguous"

    # Single match. Inspect 30 chars FORWARD from end of claim for the first
    # inline mark. Forward-only is required: validator marks land
    # end-of-sentence (e.g., "claim text. [VERIFIED]") so the mark immediately
    # after the matched claim is the one that applies. A bidirectional window
    # picks up marks belonging to neighboring sentences (the mark from the
    # preceding paragraph closes against this paragraph's claim).
    pos = occurrences[0]
    window_start = pos + len(norm_claim)
    window_end = min(len(norm_body), window_start + 30)
    window = norm_body[window_start:window_end]

    # Find which mark appears first in the forward window.
    first_idx = -1
    first_mark = None
    for mark in ("[VERIFIED]", "[DRIFT]", "[UNSOURCED]", "[STALE]"):
        idx = window.find(mark)
        if idx != -1 and (first_idx == -1 or idx < first_idx):
            first_idx = idx
            first_mark = mark

    if first_mark == "[VERIFIED]":
        note = f"validator marked VERIFIED on {audit_date} pass"
        return _close(blk, fields, note), "closed-verified"
    if first_mark == "[DRIFT]":
        note = f"claim now [DRIFT]; new finding emitted under fresh id by A3"
        return _close(blk, fields, note), "closed-drift"

    # Still UNSOURCED / STALE / no mark — carry forward.
    return blk, "unchanged"


def _close(blk, fields, note):
    """Return blk with status flipped to closed and terminal_transitioned_on +
       note inserted/updated. Preserves all other lines verbatim."""
    out_lines = []
    saw_status = False
    saw_ttoon = False
    saw_note = False
    for line in blk.splitlines():
        if re.match(r'^\s+status:\s', line):
            indent = re.match(r'^(\s+)', line).group(1)
            out_lines.append(f"{indent}status: closed")
            saw_status = True
        elif re.match(r'^\s+terminal_transitioned_on:\s', line):
            indent = re.match(r'^(\s+)', line).group(1)
            out_lines.append(f"{indent}terminal_transitioned_on: {audit_date}")
            saw_ttoon = True
        elif re.match(r'^\s+note:\s', line):
            indent = re.match(r'^(\s+)', line).group(1)
            existing = strip_quotes(re.sub(r'^\s+note:\s*', '', line).strip())
            merged = f"{existing}; reconcile: {note}" if existing else f"reconcile: {note}"
            out_lines.append(f'{indent}note: "{merged}"')
            saw_note = True
        else:
            out_lines.append(line)

    if not saw_status:
        out_lines.append("  status: closed")
    if not saw_ttoon:
        out_lines.append(f"  terminal_transitioned_on: {audit_date}")
    if not saw_note:
        out_lines.append(f'  note: "reconcile: {note}"')

    result = "\n".join(out_lines)
    if not blk.endswith("\n") and result.endswith("\n"):
        result = result.rstrip("\n")
    elif blk.endswith("\n") and not result.endswith("\n"):
        result += "\n"
    return result


reconciled_blocks = []
counts = {
    "unchanged": 0,
    "closed-article-missing": 0,
    "closed-verified": 0,
    "closed-drift": 0,
    "ambiguous": 0,
}
for blk in item_blocks:
    new_blk, action = reconcile(blk)
    counts[action] += 1
    reconciled_blocks.append(new_blk)

new_content = preamble + "".join(reconciled_blocks)
open(findings_path, "w").write(new_content)

closed_total = (
    counts["closed-article-missing"]
    + counts["closed-verified"]
    + counts["closed-drift"]
)
print(
    f"reconciled: closed_total={closed_total} "
    f"article_missing={counts['closed-article-missing']} "
    f"verified={counts['closed-verified']} "
    f"drift={counts['closed-drift']} "
    f"ambiguous={counts['ambiguous']} "
    f"unchanged={counts['unchanged']}"
)
