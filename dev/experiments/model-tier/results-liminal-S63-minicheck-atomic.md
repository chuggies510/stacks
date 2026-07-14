# Validation: the empty cell — MiniCheck × atomic decomposition (liminal S63, stacks #109)

The strongest untried combination, and the one that tests "are we asking the specialist the
right question?" We had run atomic-decompose on the *general* model, and MiniCheck on *whole*
claims. This fills the empty 2×2 cell: **decompose each claim into atoms, run each atom through
MiniCheck.** A lone atomic overclaim ("this confirms the field-ordering trap") strips the
2500-word surface cover that let the specialist gist-gloss the whole claim.

## The 2×2, now complete

| | monolithic claim | atomic claims |
|---|---|---|
| **general MoE** | R 0.38 / P 0.22 | R 0.70 / P ~0.35 |
| **MiniCheck** | R 0.69 / P 0.17 | **R 0.788 / P 0.145** |

## Result

- **Recall 0.788** (52/66) — the **best single-approach recall** of the entire search, up from
  0.69 monolithic. The theory held: decomposition removes the surface cover, and the specialist
  finally confronts the atomic overclaim it was gist-glossing.
- **Precision 0.145** (fp 307/519 CLEAN) — the **worst** of any lever. Out-of-context atoms read
  "unsupported" more readily: a true sub-assertion, lifted out of the claim that framed it,
  loses the context that made it fair, so MiniCheck rejects it.

**Gate R≥0.90 ∧ P≥0.50: misses both.** Recall got closer than anything tried; precision cratered.

## What this proves

The recall/precision **tradeoff is now mechanical, not incidental:** decomposition BUYS recall
and PAYS it back double in precision. Across all six levers the two axes trade against each
other and no operating point hits both gates:

| Lever | Recall | Precision |
|---|---|---|
| general, monolithic | 0.38 | 0.22 |
| general, thinking | 0.591 | **0.51** (P-ceiling) |
| general, atomic | 0.697 | ~0.35 |
| MiniCheck, monolithic | 0.687 | 0.168 |
| **MiniCheck, atomic** | **0.788** (R-ceiling) | 0.145 |
| ensemble (atomic ∪ minicheck-mono) | 0.773 | ~0.32 |

The close **hardens**: substrate (dense-32B), structure (atomic), specialization (MiniCheck),
and the strongest combo (specialist × atomic) all converge below the gate from every direction.
Validation stays cloud-owned, the shadow stays advisory-only, and because the best recall (0.788)
still misses ~21% of real overstatements, the cloud pass must be a full independent pass, not a
spot-check of local flags.

## The one untried direction with a real mechanism

Every single model and every single-model+structure combo fails **precision**. The one lever
that attacks precision directly is the **diverse fleet** — our own measurement showed an
ensemble of complementary checkers beats any single one (0.773 recall from non-overlapping blind
spots). The S63 substrate survey found concrete cheap fleet members from *different training
lineages*: MiniCheck-Flan-T5-Large (770M, same lineage 9× smaller), nli-deberta-v3-large (435M,
general NLI), Vectara HHEM-2.1-Open (110M). Composition: OR the flags to raise recall, then
require **2-of-3 agreement to auto-block** vs single-dissent → advisory — which trades the recall
gain back for precision on the hard-fail path, the exact axis every single model fails. Not run;
it is the recommended next probe if #109 revisits local validation. Details:
`results-liminal-S63-future-substrate-candidates.md`.
