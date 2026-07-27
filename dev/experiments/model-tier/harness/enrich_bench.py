#!/usr/bin/env python3
"""Offline enrichment benchmark runner — the stage with the least evidence behind it.

stacks' enrichment-benchmark.md is self-contained (prompt + 6 items + gold inline) but
had no runner, which is why the whole role rests on one model and six hand-run items.
This drives it: slices the prompt and items out of the benchmark, strips the gold line
before anything reaches the model, calls the SAME local-infer.sh every other stage's
measurement used, and scores the four floors.

Slicing is by fence and by item marker, never by line number: stacks-6 lost a run today
to a hardcoded `sed -n '17,41p'` that silently truncated the moment the file changed
length, and this file is one someone will edit.

    MODEL=qwen3.6-27b PASSES=3 python3 stacks/enrich_bench.py [out.json]
"""
import json, os, re, subprocess, sys, tempfile

BENCH = "/home/chris/chungus/dev/stacks/dev/experiments/model-tier/enrichment-benchmark.md"
INFER = "/home/chris/chungus/dev/stacks/dev/experiments/model-tier/harness/local-infer.sh"
MODEL = os.environ.get("MODEL", "qwen3.6-27b")
PASSES = int(os.environ.get("PASSES", 3))

GOLD = {1: ("CANDIDATE", 2), 2: ("NOSOURCE", None), 3: ("NOSOURCE", None),
        4: ("CANDIDATE", 3), 5: ("WEAK", 4), 6: ("DUP", None)}
TRAPS, GROUNDING, TIERED = {2, 3}, {1, 4, 6}, {1, 4, 5}


AGENT = "/home/chris/chungus/dev/stacks/agents/enrichment.md"
SLICE = "/home/chris/chungus/dev/stacks/dev/experiments/model-tier/harness/agent-prompt.sh"

# This harness owns the I/O contract, the agent def owns the judgment (#136). The
# agent's own output section describes a tab-separated findings FILE written with the
# Write tool, which is wrong here — offline, the model returns one line on stdout and
# does no searching or fetching of its own.
CONTRACT = """
OUTPUT CONTRACT (overrides the input and output shapes described above):

This is an offline bench. You do NOT search, fetch, or write a file. The gap, the
candidate source's identity, and the relevant passage from it are all given to you
inline below. Treat that supplied passage as if you had fetched and read the page
yourself — the "never fabricate, only cite a page you actually read" rule above is
satisfied by the passage you are given, and it still forbids you from asserting
anything the supplied passage does not say. Your one remaining judgment is the one
the rule is really about: does that passage state this specific claim, and what tier
is the publisher.

OUTPUT one line, exactly:  <VERDICT> | tier:<N|->
  VERDICT  one of CANDIDATE, WEAK, DUP, NOSOURCE
  tier     the digit 1-4 when you assign one, or a bare - when you do not
Nothing else.
"""


def load():
    txt = open(BENCH).read()
    # The prompt is sliced from the SHIPPING agent, not from a hand-copy in the
    # benchmark. The copy this replaced was 14 non-blank lines standing in for a
    # 70-line agent and carried ZERO of its six procedure steps, so the six identical
    # perfect scores behind #137 were scored against a restatement of the stage rather
    # than the stage (#136). The benchmark keeps only the items and the gold.
    prompt = subprocess.run(["bash", SLICE, AGENT], capture_output=True, text=True,
                            check=True).stdout.strip() + "\n" + CONTRACT
    assert "OUTPUT one line" in prompt, "prompt slice missed the output contract"
    assert "NOSOURCE" in prompt, "prompt slice missed the verdict vocabulary"

    items = {}
    for m in re.finditer(r"^\*\*Item (\d+)[^\n]*\*\*\n(.*?)(?=^\*\*Item |\n## )",
                         txt, re.S | re.M):
        n, body = int(m.group(1)), m.group(2)
        # the gold line is the answer key; it must never reach the model
        body = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("- **Gold:"))
        assert "Gold:" not in body, f"item {n} still carries its gold"
        items[n] = body.strip()
    assert set(items) == set(GOLD), f"parsed items {sorted(items)}"
    return prompt, items


def ask(prompt, item):
    with tempfile.TemporaryDirectory() as d:
        pf, of = f"{d}/p.txt", f"{d}/o.txt"
        open(pf, "w").write(f"{prompt}\n\n---\n\n{item}\n")
        env = {**os.environ, "TEMP": "0", "NUM_CTX": "8192"}
        r = subprocess.run(["bash", INFER, MODEL, pf, of], capture_output=True, env=env)
        if r.returncode != 0:
            return f"ERROR {r.stderr.decode()[:120]}"
        return open(of).read().strip()


def parse(raw):
    """First line matching the output contract wins; verdict + tier."""
    for line in raw.splitlines():
        line = line.strip().strip("`").strip()
        m = re.match(r"^(CANDIDATE|WEAK|DUP|NOSOURCE)\b(.*)$", line, re.I)
        if m:
            v = m.group(1).upper()
            t = re.search(r"tier:\s*(\d)", m.group(2), re.I)
            return v, (int(t.group(1)) if t else None)
    return "UNPARSED", None


def main():
    prompt, items = load()
    runs = []
    for p in range(PASSES):
        got = {n: parse(ask(prompt, items[n])) for n in sorted(items)}
        runs.append(got)
        print(f"pass {p+1}: " + "  ".join(f"{n}={v}{'/'+str(t) if t else ''}"
                                          for n, (v, t) in got.items()), file=sys.stderr)

    r0 = runs[0]
    false_cand = sum(r0[n][0] in ("CANDIDATE", "WEAK") for n in TRAPS) / len(TRAPS)
    grounding = sum(r0[n][0] in ("CANDIDATE", "DUP") for n in GROUNDING) / len(GROUNDING)
    tier_ok = sum(r0[n] == GOLD[n] for n in TIERED)
    dup_ok = r0[6][0] == "DUP"
    det = all(r == r0 for r in runs)

    out = {"model": MODEL, "passes": PASSES,
           "false_candidate_rate": false_cand, "false_candidate_floor": 0.0,
           "grounding_recall": grounding, "grounding_floor": 0.90,
           "tier_accuracy": f"{tier_ok}/3", "tier_floor": "3/3",
           "dup_detected": dup_ok, "deterministic": det,
           "clears_floors": false_cand == 0 and grounding >= 0.90 and tier_ok == 3 and dup_ok,
           "per_item": {str(n): {"got": f"{v}{'/tier'+str(t) if t else ''}",
                                 "gold": f"{GOLD[n][0]}{'/tier'+str(GOLD[n][1]) if GOLD[n][1] else ''}",
                                 "ok": (v, t) == GOLD[n]} for n, (v, t) in r0.items()}}
    print(json.dumps(out, indent=2))
    if len(sys.argv) > 1:
        json.dump(out, open(sys.argv[1], "w"), indent=2)


if __name__ == "__main__":
    main()
