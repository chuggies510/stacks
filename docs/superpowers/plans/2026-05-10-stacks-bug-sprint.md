# Stacks Bug Sprint — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close four active bugs (#46, #48/#49, #44, #47) that all produce silent data corruption in the catalog/audit pipeline, applying the meta-pattern insight that the mechanical fix always beats the agent-instruction fix.

**Architecture:** Each task is a self-contained code change to either a SKILL.md or a script in `scripts/`. No new files created — all changes extend or trim existing surfaces. Tasks are ordered by dependency: T1 and T2 are independent and can be done in either order; T3 and T4 are also independent. One consolidated version bump and CHANGELOG update happens at the end (Final Task).

**Tech Stack:** Bash (SKILL.md), Python 3 (scripts), `difflib` stdlib (T4 fuzzy match)

---

## Roadmap (not this session)

**Phase 2 — next session:**
- File new issue: structural validation gate (Pattern 2 from problem-solving pass — extend `assert-written.sh` or add `assert-structure.sh` with per-filetype content checks to catch the entire silent-validity class before it hits downstream consumers)
- #5 cross-stack ask (1 session, ready — design the retrieval path as a clean swap-out stub for when #10 lands)

**Phase 3 — design-gated:**
- #14 scheduled loop — needs cost guardrail design decision first
- #40 process-inbox quality gate — needs LLM-per-file cost budget decision first
- #10 qmd search — needs deployment model decision (zero-config vs local infra)

**Phase 4 — blocked:**
- #18 guide synthesis — after #5 (cross-stack retrieval)
- #7 page types — after #18 (synthesis page type emerges from guide work)

---

## Pre-flight: Reconcile version files

`plugin.json` is at `0.17.1` and `marketplace.json` is at `0.16.1` — already drifted before this sprint starts. Reconcile before the first task so all bumps share a common base.

- [ ] In `.claude-plugin/marketplace.json`, set `"version": "0.17.1"` to match `plugin.json`.
- [ ] Confirm: `grep '"version"' .claude-plugin/plugin.json .claude-plugin/marketplace.json` → both show `0.17.1`.
- [ ] Commit: `git add .claude-plugin/marketplace.json && git commit -m "chore: sync marketplace.json version to plugin.json (0.17.1)"`

---

## Task 1: Pre-clean dev/extractions/ before W1 dispatch

**Goal:** Two `rm -f` lines before Step 6 dispatch eliminate stale batch files from prior catalog runs, closing #46.

**Files:**
- Modify: `skills/catalog-sources/SKILL.md` — add rm -f lines after `mkdir -p "$STACK/dev/extractions"` in the normal dispatch path (~line 230)

**Acceptance Criteria:**
- [ ] `batch-*-concepts.md` and `_dedup*.md` are absent in `dev/extractions/` at the start of every W1 run
- [ ] Zero-sources early-exit path is unaffected (it returns before the pre-clean)

**Verify:** `grep -A2 'mkdir -p "\$STACK/dev/extractions"' skills/catalog-sources/SKILL.md` → output shows the two rm -f lines immediately following the mkdir, confirming correct placement

**Steps:**

- [ ] **Step 1: Insert pre-clean**

In `skills/catalog-sources/SKILL.md`, find the block (~line 229):
```
N_BATCHES_W1=$N_SOURCES
mkdir -p "$STACK/dev/extractions"
DISPATCH_EPOCH_W1=$(date +%s)
```
After `mkdir -p "$STACK/dev/extractions"`, add:
```bash
rm -f "$STACK/dev/extractions"/batch-*-concepts.md
rm -f "$STACK/dev/extractions"/_dedup*.md
```

- [ ] **Step 2: Commit**

```bash
git add skills/catalog-sources/SKILL.md
git commit -m "fix(catalog-sources): pre-clean dev/extractions/ before W1 dispatch (#46)"
```

---

## Task 2: Move per-slug split into dedup-extractions.py

**Goal:** Eliminate the awk per-slug split from `skills/catalog-sources/SKILL.md` by having `dedup-extractions.py` write the per-slug files directly, closing #48 and #49.

**Files:**
- Modify: `scripts/dedup-extractions.py` — add per-slug file writes after the `_dedup-meta.txt` write
- Modify: `skills/catalog-sources/SKILL.md` — remove the awk for-loop (lines 292-309), update prose comment

**Acceptance Criteria:**
- [ ] After `dedup-extractions.py` runs, `dev/extractions/_dedup-{slug}.md` files exist for every unique slug and are non-empty
- [ ] Each `_dedup-{slug}.md` contains exactly one `## Concept:` block matching that slug
- [ ] The awk for-loop no longer appears in `skills/catalog-sources/SKILL.md`
- [ ] `compute-extraction-hash.sh` still reads per-slug files correctly (the file format is unchanged)

**Verify:**
```bash
mkdir -p /tmp/test-extr
printf '## Concept: Test Concept\n\nslug: test-concept\ntitle: Test Concept\nsource_paths:\n  - /tmp/src.md\ntarget_article: \ntier: 1\n\n### Claims\n- A test claim.\n' > /tmp/test-extr/batch-1-concepts.md
python3 scripts/dedup-extractions.py /tmp/test-extr /tmp/test-dedup.md
grep -c "^## Concept:" /tmp/test-extr/_dedup-*.md
```
Expected: `/tmp/test-extr/_dedup-test-concept.md:1` (each per-slug file has exactly one `## Concept:` line)

**Steps:**

- [ ] **Step 1: Add per-slug writes to dedup-extractions.py**

At the end of `scripts/dedup-extractions.py`, after the `_dedup-meta.txt` write block, add:

```python
# Write per-slug _dedup-{slug}.md files. One concept block each.
# These replace the awk per-slug split that was previously in the skill body.
# The awk form was vulnerable to harness $N substitution (CLAUDE.md gotcha).
for slug in sorted(slug_seen):
    per_slug_path = os.path.join(extr_dir, f"_dedup-{slug}.md")
    with open(per_slug_path, "w") as f:
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
```

- [ ] **Step 2: Remove the awk for-loop from SKILL.md**

In `skills/catalog-sources/SKILL.md`, find and remove this entire block (lines ~289-309):

```
# Per-slug split: for each unique slug, write dev/extractions/_dedup-{slug}.md
# containing only that slug's merged block. The aggregated _dedup.md is the
# audit trail; the per-slug files are what W2 article-synthesizer agents read.
for slug in "${CONCEPT_SLUGS[@]}"; do
  per_slug_path="$STACK/dev/extractions/_dedup-${slug}.md"
  awk -v want="$slug" '
    /^## Concept: / {
      if (in_block && block) { print block }
      block = $0 "\n"
      next
    }
    /^slug:[[:space:]]/ {
      cur=$2
      in_block=(cur==want)
      block = block $0 "\n"
      next
    }
    in_block { block = block $0 "\n" }
    END { if (in_block && block) print block }
  ' "$DEDUP" > "$per_slug_path"
done
```

Replace with a single comment line:
```
# Per-slug _dedup-{slug}.md files are written by dedup-extractions.py above.
```

- [ ] **Step 3: Update the prose explanation (~line 324)**

Find: "The Python pass merges `source_paths[]` deterministically (set-of-seen with first-seen-order preservation) and writes a single canonical `_dedup.md` plus per-slug files. The awk per-slug split mirrors the orchestrator's previous behavior."

Replace with: "The Python pass merges `source_paths[]` deterministically (set-of-seen with first-seen-order preservation) and writes a single canonical `_dedup.md` plus per-slug `_dedup-{slug}.md` files in one pass. No awk in the skill body — the harness `$N` substitution gotcha (CLAUDE.md) makes any awk `$0` literal in a skill body dangerous."

- [ ] **Step 4: Commit**

```bash
git add scripts/dedup-extractions.py skills/catalog-sources/SKILL.md
git commit -m "refactor(catalog-sources): move per-slug split into dedup-extractions.py, closes #48 #49"
```

---

## Task 3: Mechanical wikilink preservation after A1 validator wave

**Goal:** Re-run `wikilink-pass.sh` after each A1 validator pass in audit-stack so wikilinks stripped by the validator are immediately restored before A2 sees the articles, closing #44.

**Files:**
- Modify: `skills/audit-stack/SKILL.md` — add wikilink-pass.sh call after the A1 gate+summary+cleanup block (~line 187), before A2 starts (~line 189)

**Acceptance Criteria:**
- [ ] After A1 completes, the wikilink-pass.sh call appears in the skill body
- [ ] The call is invoked even when `glossary.md` doesn't exist yet — wikilink-pass.sh is a no-op without a glossary
- [ ] Wikilink count in articles does not decrease across audit passes (verifiable by `grep -roh '\[\[.*\]\]' articles/ | wc -l` before and after)

**Verify:** `grep -n "wikilink-pass" skills/audit-stack/SKILL.md` → two call sites (after A1 cleanup and after A2)

**Steps:**

- [ ] **Step 1: Insert wikilink-pass.sh call**

Read `skills/audit-stack/SKILL.md` around lines 185-192. Find the cleanup line:
```
Cleanup batch and per-batch sources files (`rm "$STACK"/dev/audit/_a1-batch-*.txt "$STACK"/dev/audit/_a1-sources-*.txt`) after summary writes.
```
Immediately after this line (before the `## Step 5: A2` header), add:

```bash
# Restore wikilinks stripped by the validator. The validator doesn't know about
# [[wikilinks]] and may collapse them to plain text. Re-running the pass here
# is a no-op if glossary.md doesn't exist yet (first pass with no prior A2).
"$SCRIPTS_DIR/wikilink-pass.sh" "$STACK/articles/" "$STACK/glossary.md"
```

- [ ] **Step 2: Commit**

```bash
git add skills/audit-stack/SKILL.md
git commit -m "fix(audit-stack): re-run wikilink-pass.sh after A1 to restore stripped wikilinks (#44)"
```

---

## Task 4: Fuzzy claim match in reconcile-findings.py

**Goal:** When a prior open finding's claim text no longer appears verbatim (because the synthesizer rewrote it), a fuzzy sentence-level match with a `[VERIFIED]`-mark gate closes the finding with an audit trail instead of silently dropping it, closing #47.

**Files:**
- Modify: `scripts/reconcile-findings.py` — add `import difflib`; add `_fuzzy_rewrite_check()` before `reconcile()`; update the `occurrences == 0` branch; add `"closed-rewrite-verified"` to counts dict; update `print()` output; update module docstring; update `reconcile()` docstring

**Acceptance Criteria:**
- [ ] A finding whose claim was rewritten-then-VERIFIED closes with `status: closed` and `note` containing `rewrite-then-verify`
- [ ] A finding rewritten but not followed by `[VERIFIED]` or `[DRIFT]` within 60 chars is not closed (mark required as false-positive guard)
- [ ] The existing verbatim path is unchanged (all prior reconciliation behaviour preserved)
- [ ] `difflib` is the only new import (stdlib, no external deps)

**Verify:** `grep -c "_fuzzy_rewrite_check" scripts/reconcile-findings.py` → at least 2 (definition + call site)

**Steps:**

- [ ] **Step 1: Add difflib import**

At the top of `scripts/reconcile-findings.py`, change:
```python
import os, re, sys
```
to:
```python
import difflib, os, re, sys
```

- [ ] **Step 2: Add `_fuzzy_rewrite_check()` and update the `occurrences == 0` branch**

Add `_fuzzy_rewrite_check()` immediately before the `reconcile()` function. The function takes raw `body` (not normalized) so it can split on newline boundaries that `normalize_ws` would erase, then normalizes each sentence individually:

```python
def _fuzzy_rewrite_check(body, norm_claim, audit_date):
    """Return a close-note string if a sentence in body is a close-enough
    rewrite of norm_claim AND [VERIFIED] or [DRIFT] follows it within 60 chars.
    Return None otherwise.

    Splits raw body (preserving newlines) so bullet-point sentences are found.
    Normalizes each candidate sentence individually before scoring.
    Threshold 0.55 catches claim expansions; [VERIFIED]/[DRIFT] mark requirement
    is the primary guard against false positives.
    """
    threshold = 0.55
    sentences = re.split(r'(?<=\.)\s+|\n', body)
    claim_tokens = set(norm_claim.lower().split())
    if len(claim_tokens) < 4:
        return None
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
        if ratio < threshold:
            continue
        sent_pos = body.find(sent)
        if sent_pos == -1:
            continue
        window_start = sent_pos + len(sent)
        window_end = min(len(body), window_start + 60)
        m = MARK_PATTERN.search(body, window_start, window_end)
        if m and m.group() in ("[VERIFIED]", "[DRIFT]"):
            return f"rewrite-then-verify: claim rewritten but {m.group()} found in adjacent sentence (ratio={ratio:.2f})"
    return None
```

Then update the `reconcile()` function docstring to add the new action to its enumeration:

```python
    """Return (new_blk, action). action is one of:
       'unchanged', 'closed-article-missing', 'closed-verified',
       'closed-drift', 'closed-rewrite-verified', 'ambiguous'."""
```

Then in `reconcile()`, replace the `occurrences == 0` block:
```python
    if len(occurrences) == 0:
        # Claim text not found verbatim. Almost always means findings-analyst
        # paraphrased when extracting (dropped parentheticals, expanded
        # acronyms). Don't close on this signal; let rotate-findings.sh age
        # out truly-stale items eventually.
        return blk, "unchanged"
```
with:
```python
    if len(occurrences) == 0:
        # Verbatim match failed. Try fuzzy: split article into sentences, score
        # each against the claim. If a sentence matches well AND [VERIFIED] or
        # [DRIFT] follows it, close as rewrite-then-verify.
        fuzzy_result = _fuzzy_rewrite_check(body, norm_claim, audit_date)
        if fuzzy_result:
            return _close(blk, fuzzy_result), "closed-rewrite-verified"
        return blk, "unchanged"
```

- [ ] **Step 3: Add new count key and update print**

In the `counts` dict initialization, add the new key:
```python
counts = {
    "unchanged": 0,
    "closed-article-missing": 0,
    "closed-verified": 0,
    "closed-drift": 0,
    "closed-rewrite-verified": 0,
    "ambiguous": 0,
}
```

Update the `print()` at the bottom:
```python
print(
    f"reconciled: article_missing={counts['closed-article-missing']} "
    f"verified={counts['closed-verified']} "
    f"drift={counts['closed-drift']} "
    f"rewrite_verified={counts['closed-rewrite-verified']} "
    f"ambiguous={counts['ambiguous']} "
    f"unchanged={counts['unchanged']}"
)
```

- [ ] **Step 4: Update module docstring**

Find: `# Purpose: pre-A3 reconcile pass. Closes prior open findings whose articles were deleted, or whose claim now carries a [VERIFIED] or [DRIFT] inline mark.`

Replace with: `# Purpose: pre-A3 reconcile pass. Closes prior open findings whose articles were deleted, whose claim carries a [VERIFIED] or [DRIFT] mark, or whose claim was rewritten by the synthesizer and the rewritten form carries a [VERIFIED] or [DRIFT] mark (rewrite-then-verify path).`

- [ ] **Step 5: Commit**

```bash
git add scripts/reconcile-findings.py
git commit -m "fix(audit-stack): reconcile rewrite-then-verify findings instead of dropping them (#47)"
```

---

## Final Task: Bump version and update CHANGELOG

One version bump after all four task commits. T1 and T3 are pure bug fixes (patch scope); T2 and T4 add new behavior (minor scope). Net bump from reconciled base `0.17.1`: one minor increment.

**Target version: `0.18.0`**

- [ ] In both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, set `"version": "0.18.0"`.
- [ ] In `CHANGELOG.md`, add a new version section at the top:

```markdown
## 0.18.0 — 2026-05-10

### Fixes
- catalog-sources: pre-clean `dev/extractions/` before W1 dispatch; stale batch and dedup files from prior runs no longer contaminate W1b dedup (#46)
- audit-stack: re-run `wikilink-pass.sh` after A1 validator wave to restore [[wikilinks]] stripped by validators during pass-2+ re-validation (#44)
- audit-stack: `reconcile-findings.py` now closes rewrite-then-verify findings instead of silently dropping them; uses sentence-level fuzzy match (SequenceMatcher + Jaccard pre-filter) gated on a downstream [VERIFIED]/[DRIFT] mark (#47)

### Refactors
- catalog-sources: moved per-slug dedup file writes into `scripts/dedup-extractions.py`; removed awk per-slug split from skill body. Eliminates harness `$N` substitution surface. Closes #48, #49.
```

- [ ] Commit:

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -m "chore: bump to 0.18.0, roll up bug sprint CHANGELOG"
```
