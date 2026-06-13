# reconcile-findings.py
# Purpose: pre-A3 reconcile pass. Closes prior open findings whose articles were deleted, or whose claim now carries a [VERIFIED] or [DRIFT] inline mark.
# Usage:   python3 reconcile-findings.py <stack> <audit_date> <stack_head>
# Output:  rewrites <stack>/dev/audit/findings.md in place. Logs ambiguous-match warnings to stderr.

import difflib, os, re, sys
from collections import Counter

stack = sys.argv[1]
audit_date = sys.argv[2]
stack_head = sys.argv[3]
findings_path = f"{stack}/dev/audit/findings.md"
articles_dir = f"{stack}/articles"

if not os.path.isfile(findings_path):
    sys.exit(0)

raw = open(findings_path).read()

# Split on `- id:` boundaries. Section headers (`## ...`) between items get
# attached to the trailing edge of the preceding item block. Acceptable because
# A3 merge rewrites findings.md from scratch immediately after reconcile, so
# the post-reconcile file is transient state.
parts = re.split(r'(?m)^(?=- id:)', raw)
preamble = parts[0]
item_blocks = parts[1:]

MARK_PATTERN = re.compile(r'\[VERIFIED\]|\[DRIFT\]|\[UNSOURCED\]|\[STALE\]')


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


def _fuzzy_rewrite_check(body, norm_claim):
    """Return a close-note string if a sentence in body is a fuzzy match for
    norm_claim AND carries a [VERIFIED] or [DRIFT] mark immediately after it.
    Return None if no match is found or the claim is too short to score reliably."""
    if len(norm_claim.split()) < 4:
        return None
    claim_tokens = set(norm_claim.lower().split())
    sentences = re.split(r'(?<=\.)\s+|\n', body)
    for sent in sentences:
        sent = sent.strip()
        if not sent:
            continue
        norm_sent = normalize_ws(sent)
        sent_tokens = set(norm_sent.lower().split())
        if not sent_tokens:
            continue
        jaccard = len(claim_tokens & sent_tokens) / len(claim_tokens | sent_tokens)
        if jaccard < 0.3:
            continue
        ratio = difflib.SequenceMatcher(None, norm_claim, norm_sent).ratio()
        if ratio < 0.55:
            continue
        sent_pos = body.find(sent)
        if sent_pos == -1:
            continue
        window_start = sent_pos + len(sent)
        window_end = min(len(body), window_start + 60)
        m = MARK_PATTERN.search(body, window_start, window_end)
        if m and m.group() in ("[VERIFIED]", "[DRIFT]"):
            return (
                f"rewrite-then-verify: claim rewritten but {m.group()} "
                f"found in adjacent sentence (ratio={ratio:.2f})"
            )
    return None


def reconcile(blk):
    """Return (new_blk, action). action is one of:
       'unchanged', 'closed-article-missing', 'closed-verified',
       'closed-drift', 'closed-rewrite-verified', 'ambiguous'."""
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
        return _close(blk, "article deleted between audit cycles"), "closed-article-missing"

    body = open(article_path).read()
    norm_body = normalize_ws(body)
    norm_claim = normalize_ws(claim)
    if not norm_claim:
        return blk, "unchanged"

    occurrences = [m.start() for m in re.finditer(re.escape(norm_claim), norm_body)]

    if len(occurrences) == 0:
        fuzzy_note = _fuzzy_rewrite_check(body, norm_claim)
        if fuzzy_note:
            return _close(blk, fuzzy_note), "closed-rewrite-verified"
        return blk, "unchanged"

    if len(occurrences) > 1:
        sys.stderr.write(
            f"reconcile-findings: ambiguous match for id={fields.get('id', '?')} "
            f"({len(occurrences)} occurrences)\n"
        )
        return blk, "ambiguous"

    # Forward-only window is required: validator marks land end-of-sentence
    # ("claim text. [VERIFIED]"). Bidirectional windows pick up marks that
    # belong to neighboring sentences.
    pos = occurrences[0]
    window_start = pos + len(norm_claim)
    window_end = min(len(norm_body), window_start + 30)
    m = MARK_PATTERN.search(norm_body, window_start, window_end)
    first_mark = m.group() if m else None

    if first_mark == "[VERIFIED]":
        return _close(blk, f"validator marked VERIFIED on {audit_date} pass"), "closed-verified"
    if first_mark == "[DRIFT]":
        return _close(blk, "claim now [DRIFT]; new finding emitted under fresh id by A3"), "closed-drift"

    return blk, "unchanged"


def _close(blk, note):
    """Return blk with status flipped to closed and terminal_transitioned_on +
       note inserted/updated. Status field is guaranteed present on open items
       by reconcile()'s gate; only ttoon and note may need to be appended."""
    out_lines = []
    saw_ttoon = False
    saw_note = False
    for line in blk.splitlines():
        if re.match(r'^\s+status:\s', line):
            indent = re.match(r'^(\s+)', line).group(1)
            out_lines.append(f"{indent}status: closed")
        elif re.match(r'^\s+terminal_transitioned_on:\s', line):
            indent = re.match(r'^(\s+)', line).group(1)
            out_lines.append(f"{indent}terminal_transitioned_on: {audit_date}")
            saw_ttoon = True
        elif re.match(r'^\s+note:\s', line):
            indent = re.match(r'^(\s+)', line).group(1)
            existing = strip_quotes(re.sub(r'^\s+note:\s*', '', line).strip())
            existing_escaped = existing.replace('\\', '\\\\').replace('"', '\\"')
            merged = f"{existing_escaped}; reconcile: {note}" if existing_escaped else f"reconcile: {note}"
            out_lines.append(f'{indent}note: "{merged}"')
            saw_note = True
        else:
            out_lines.append(line)

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
counts = Counter()
for blk in item_blocks:
    new_blk, action = reconcile(blk)
    counts[action] += 1
    reconciled_blocks.append(new_blk)

new_content = preamble + "".join(reconciled_blocks)
open(findings_path, "w").write(new_content)

print(
    f"reconciled: article_missing={counts['closed-article-missing']} "
    f"verified={counts['closed-verified']} "
    f"drift={counts['closed-drift']} "
    f"rewrite_verified={counts['closed-rewrite-verified']} "
    f"ambiguous={counts['ambiguous']} "
    f"unchanged={counts['unchanged']}"
)
