# merge-findings.py
# Purpose: A3 merge -- merge partial findings files into findings.md
# Usage:   python3 merge-findings.py <stack> <audit_date> <stack_head> <new_pass_counter>
# Output:  writes <stack>/dev/audit/findings.md

import os, re, glob, sys

stack = sys.argv[1]
audit_date = sys.argv[2]
stack_head = sys.argv[3]
new_pass = int(sys.argv[4])
findings_path = f"{stack}/dev/audit/findings.md"

partials = sorted(glob.glob(f"{stack}/dev/audit/_a3-partial-*.md"))
items = []
for p in partials:
    content = open(p).read()
    # Split at each "- id:" block boundary
    for blk in re.split(r'\n(?=- id:)', content):
        blk = blk.strip()
        if not blk.startswith("- id:"):
            continue
        item = {"raw": blk}
        for line in blk.splitlines():
            m = re.match(r'^\s*-?\s*(\w+):\s*(.*)$', line)
            if m:
                k, v = m.group(1), m.group(2).strip()
                item[k] = v
        if "id" in item:
            items.append(item)

TERMINAL = {"applied", "closed", "deferred", "stale", "failed"}
by_id = {}
for it in items:
    iid = it["id"]
    cur = by_id.get(iid)
    is_term = it.get("status", "open") in TERMINAL
    if cur is None:
        by_id[iid] = it
    else:
        cur_term = cur.get("status", "open") in TERMINAL
        if is_term and not cur_term:
            by_id[iid] = it
        elif is_term == cur_term:
            by_id[iid] = it  # latest wins on tie

# Status-first bucketing: status:deferred items route to Deferred regardless
# of action. Everything else routes by action. This matches the findings-analyst
# schema, where "Deferred" means "operator moved to status: deferred", not
# "action == noop".
groups = {"fetch_source": [], "resynthesize": [], "research_question": [], "deferred": []}
for it in by_id.values():
    if it.get("status") == "deferred":
        groups["deferred"].append(it)
        continue
    a = it.get("action", "")
    if a in groups:
        groups[a].append(it)

lines = ["---",
         f"audit_date: {audit_date}",
         f"stack_head: {stack_head}",
         f"pass_counter: {new_pass}",
         "schema_version: 4",
         "---",
         ""]
for section, key in [("New Acquisitions", "fetch_source"),
                     ("Articles to Re-Synthesize", "resynthesize"),
                     ("Research Questions", "research_question"),
                     ("Deferred", "deferred")]:
    lines.append(f"## {section}")
    lines.append("")
    for it in groups[key]:
        lines.append(it["raw"])
        lines.append("")

open(findings_path, "w").write("\n".join(lines))
print(f"merged: total_items={len(by_id)} fetch_source={len(groups['fetch_source'])} "
      f"resynthesize={len(groups['resynthesize'])} research_question={len(groups['research_question'])}")
