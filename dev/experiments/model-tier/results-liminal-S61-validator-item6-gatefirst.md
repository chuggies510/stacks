# Validation item-6 (add-citation) under gate-first — qwen does NOT catch it (liminal S61)

Corrects an **unmeasured cell**. `results-stacks-S25-haiku.md`'s comparison table marks qwen3-30b
as "catches" validation item-6 under the gate-first prompt, attributed to "liminal S59/S61". That
was never measured on qwen — S59 only established qwen returns CLEAN on item-6 under the **flat**
prompt; gate-first was the proposed-but-untested lever (validation-benchmark.md line 139: "re-score
item 6 under the revised prompt"). This is that measurement.

## Result: the gate-first PROMPT lever does not transfer to qwen

qwen3-30b-a3b-instruct, gate-first prompt (verbatim), temp 0, 3 passes:

| Item | Gold | qwen pass1 / 2 / 3 | Verdict |
|------|------|--------------------|---------|
| 6 (uncited-but-grounded) | CORRECTION/add-citation | **CLEAN / CLEAN / CLEAN** | **MISS, byte-DET** |
| 7 (uncited, unsupported) | SOFTSPOT | **add-citation / SOFTSPOT / SOFTSPOT** | **MISS, NONDET** |

Two failures, both meaningful:

1. **Item 6 — the gate is ignored.** The gate-first prompt states explicitly *"an uncited claim is
   NEVER CLEAN, even when it is true."* The item-6 claim carries no inline `[slug]` citation. qwen
   returned CLEAN anyway, byte-deterministically. The prompt-level self-gate does not bind qwen — it
   reads uncited-but-true as "supported → CLEAN" exactly as it did under the flat prompt. The lever
   that works on haiku (and sonnet) does **not** close the miss on qwen.

2. **Item 7 — gate-first introduces a false-correction.** One pass in three, qwen invented a citation
   (`CORRECTION/add-citation | zenml-...`) for a claim (two-week shadow window) that no listed source
   states — a false correction, the dangerous class. The other two passes correctly SOFTSPOT. So
   gate-first not only fails to fix item-6, it destabilizes item-7 on qwen — the regression the
   benchmark flagged ("closes the miss without regressing item 7").

## Why: it's a prompt lever, and prompt levers don't fix weak-tier meta-judgments

"Is an uncited-but-true claim CLEAN, add-citation, or softspot?" is a meta-judgment. Gate-first tries
to fix it *inside the model* by restructuring the prompt (STEP 1 = self-gate on citation presence).
That is the same move as the synth-refusal preamble and the validator prompt-split — and it fails the
same way on the weak tier: the model doesn't honor the self-gate. Haiku is strong enough to honor it;
qwen is not. So **"gate-first is model-agnostic" is only half true — the PROMPT lever is
model-dependent** (haiku/sonnet yes, qwen no).

## The model-agnostic fix is the harness version, per the four-stage rule

Don't ask the model whether the claim is cited — that's a deterministic string check:

- **Harness gate:** does the claim contain an inline `[slug]` token? (regex, 100% reliable).
- If **uncited**, never route it to a CLEAN/not-CLEAN model call at all. Hand the model only the
  grounding sub-question — "does any listed source state this claim?" — which is exactly the
  enrichment grounding judgment qwen scored **3/3, byte-DET** on (enrichment item-4 is the same Cox
  red-teaming claim). A yes → add-citation with that slug; a no → SOFTSPOT.
- If **inline-cited**, the model does the CLEAN/contradiction/overstatement judgment it already
  handles (poison recall 1.00).

This is the same conclusion as DUP (containment in code) and refusal (count gate in code): the
citation-presence gate belongs in the harness, and then qwen's part is the object-level grounding it's
good at. Done that way the stage is model-agnostic; done as a prompt self-gate it is not.

## Net for the model-choice picture

Behind an identical prompt, qwen is **not** a drop-in for haiku on validation. On the add-citation
class, haiku honors the gate-first prompt and qwen does not (byte-DET CLEAN), and gate-first adds an
item-7 false-correction wobble on qwen. qwen stays viable on validation only if the citation-presence
gate is pulled into the harness (deterministic) rather than left as a prompt instruction. The
"determinism + \$0, same capability" summary holds for the poison-recall class; it does **not** hold
for add-citation under the current prompt lever.
