---
session: 26
---

# stacks Active Context

## Current state

| | |
|-|-|
| Version | 0.66.1 (shipped this session: 0.65.0 → 0.66.0 → 0.66.1; later commits are dev/experiment docs, no bump) |
| Tests | pair-claims + harness self-checks green |
| Shipped | validation retrieval build — `pair-claims.py` per-claim cited-source pairing wired into audit Step 4.5 (0.66.x, #109) |
| Validation flip | CLOSED (final) — solo-local faithfulness refuted, 6 levers / full 2×2, data-wall; stays cloud-owned |
| In flight | none — validation close final (liminal's last cell landed) |
| Cost | $86.02 · 19h11m34s |

## Open thread

None, closed clean. Liminal's last empty 2×2 cell (MiniCheck specialist on ATOMIC claims) landed: recall 0.788 (best of any lever) but precision 0.145 (worst), still misses both gates. All four quadrants of the {specialist,general}×{whole,atomic} 2×2 are below the gate, so the close HARDENED to final — validation stays cloud-owned. The one untried forward direction (if anyone reopens) is a diverse small-model fleet voted on precision — carried in Next priority, not an open fork.

## Next priority

| # | Item | Note |
|---|------|------|
| — | apply ~71 confirmed llm defects | agent-memory-systems first (11, fabrications) |
| #113 | retire Step 4.5 shadow wiring | validation now cloud-owned |
| #109 | synthesis at-scale measurement | same faithfulness skill, likely same wall |
| — | diverse-fleet precision play | if validation reopens; the one untried lever |
| — | backlog | #111 #102 #100 #95 #70 |

**Cross-repo follow-up:** enrichment local loop reference `podly/extract_bench/enrich_agentic.py` (peer liminal); Brave key at `~/.config/brave-search.key` (pre-existing). library-stack: the ~71 confirmed overstatements live in `library-stack/llm/articles/` (a separate repo), not here. Diverse-fleet lead detailed in `dev/experiments/model-tier/results-liminal-S63-minicheck-atomic.md`.

## Session log
- DECIDED: validation stays CLOUD-OWNED (final) — solo-local faithfulness refuted across 6 levers filling all four quadrants of the {specialist,general}×{whole,atomic} 2×2 (no-think MoE qwen3-30b-a3b, thinking, dense qwen3-32b, atomic-claim decomposition, Bespoke-MiniCheck-7B specialist, specialist×atomic); none clears recall ≥0.90 ∧ precision ≥0.50. The two axes trade against each other — recall ceiling 0.788 (specialist×atomic), precision ceiling 0.51 (thinking-general), every quadrant below the gate → the ceiling is in the DATA (a ~15-claim gist-preserving-overstatement core), not the model or the harness.
- DECIDED: the shadow cannot shrink the cloud pass — best local recall (ensemble 0.773) misses ~23%, so the cloud verifier runs a full independent pass, not a spot-check of local flags; the "local flags, cloud confirms" cost-saving hybrid does not exist for validation.
- FACT: qwen over-flags hard — of 596 claims it called overstatement, only 57 were real (~10% precision); label-based poison-recall (90%) is a mirage, real fix-recall 56% (25 ghost-corrections: a CORRECTION label with a byte-identical / still-broken replacement that ships the poison). → #111.
- FACT: the `llm` stack has ~71 verifier-confirmed genuine overstatements, worst `agent-memory-systems` (11, incl. fabricated memory-architecture mechanisms the source never states) — real audit payload, unfixed.
- FACT: the retrieval fix (harness pairs each claim to its OWN cited-source excerpt, bullets as units) is the sound part — drove 90% detection; the failure is precision/fix-quality, not retrieval. Confirmed the earlier "false-corrects heavily" read was a harness confound (source starvation + bullet-merge truncation), now fixed.
- TRAP: a verify/grade sub-agent over a large batch (253 claims → one JSON) blows the 64K output-token cap and dies mid-write with no file; split at an article boundary + keep per-item notes terse (added to project CLAUDE.md gotchas).
- ARC: #109 verify-and-fix — validation sub-thread CLOSED (cloud-owned, 5-lever data-wall); enrichment/synthesis/extraction still in play; synthesis is the same faithfulness skill and inherits the prior.
- ADR-ABSORBED: validation-local-closed effect written into `system-patterns.md` #109 line.

<!-- ═══ JOURNAL — derived view, carried forward by /stop, regenerable from archive/ ═══ -->

## Standing facts
- The Agent tool cannot dispatch local models (reaches only sonnet/haiku/opus/fable); the local-worker harness is **pal MCP `chat`** with a local model name — confirmed S25: pal is configured against `http://localhost:11434/v1` (Ollama) with 50 local models, so `read source → pal chat(model=<local>) → write gate file` works without the Agent tool. A bash+curl-to-`:11434` worker is the alternative harness (deterministic, no MCP/agent). (as-of: 2026-07-12) (rode: S22, S23, S24, S25, S26)
- liminal is the peer Claude session (local-LLM / fine-tuning expert), co-located on this host (3900x) at `~/chungus/dev/liminal`; it serves + scores local models on the shared RTX 3090 (SHARED with liminal's curator cron at :13 every 6h — during its training windows it evicts resident models, so gate heavy local calls on `nvidia-smi --query-gpu=memory.free` and keep pilot models warm via keep-alive). Locate its pane by NAME (windows renumber between sessions): `tmux list-panes -a -F '#{window_name} #{pane_id}' | awk '$1=="liminal"{print $2}'` (S25: pane `%47`). **Walkie-talkie send/verify/metachar-escape/return-path mechanics are canonical in `reference.md#cross-session-coordination` (dev bindings, dev.md § Worktrees & concurrent sessions points at it) — follow that, do NOT restate it here.** (as-of: 2026-07-12) (rode: S22, S23, S24, S25, S26)
- The `dev/experiments/model-tier/` dir (epic #109) is the first-class model-tier test area. **All four pipeline stages now have an offline gold-set benchmark** (extraction, synthesis, validation, enrichment); front-door `README.md` maps them. Local scoring by liminal + the live layers (enrich search-recall, validator shadow test) are the remaining epic work. (as-of: 2026-07-11) (rode: S22, S23, S24, S25, S26)

## Recent arc
- S26 (07-13): #109 — exercised the new verify-and-fix tools on the real `llm` stack, then closed the validation-local question. Built + ran the retrieval fix (`pair-claims.py` pairs each claim to its cited-source excerpt; a bullet-as-unit fix surfaced supporting bullets that a merge+truncate bug had hidden, 0.66.0/0.66.1). Ran the local shadow across all 45 `llm` articles (1717 claims), dispatched 6 cloud `validation-verifier` agents grading every claim against the real source: found ~71 genuine overstatements (worst agent-memory-systems, 11 fabrications) and exposed that label-based poison-recall (90%) is a mirage — real fix-recall 56%, false-correction 49% (#111). Then a 6-lever precision search WITH liminal filling all four quadrants of the {specialist,general}×{whole,atomic} 2×2 (no-think MoE, thinking, dense-32B, atomic-decompose, MiniCheck-7B specialist, specialist×atomic): none cleared the gate; recall and precision trade (ceilings 0.788 / 0.51) → data-wall, validation cloud-owned (final). Filed #111, #113. Forward lead noted: a diverse small-model fleet voted on precision (the one untried lever).
- S25 (07-12): #109 verify-and-fix — decided the recipe (ADR-002, determinism retired), ran the live synthesis calibration (qwen draft → sonnet `article-verifier` → summary: 4/4 floors clear + refusal honored), built validation's citation-presence gate (closes qwen's item-6 add-citation miss e2e), then wired the other 3 stages' machinery via 3 parallel `/using-agent-skills` agents (gates + verifiers + summaries), proving each on real data (validation item-6, extraction 35/38 over-mints caught, url-dedup on 43 real URLs). Two codex rounds hardened it (round 2 caught round-1 over-corrections). Wired extraction into catalog as opt-in Step 5.5 (0.64.0). Shipped 0.61.0→0.64.0.
- S24 (07-11): #109 cutover-prep — shipped validator gate-first prompt hardening (0.59.0), then a 7-issue pipeline/skill batch (0.60.0/0.60.1): fixed the catalog self-check `\t`/grep tab-escape (#104), rewrote near-dup detection (#106), enrich source-URL dedup (#98), a lookup web-search guardrail (#107), and background dispatch across the 3 pipeline skills (#108) — via 3 parallel agents + a codex courier that caught 3 real edge cases (fixed in 0.60.1). #102 and #100 deferred with tracked comments.
- S23 (07-11): model-tier program (#109) — ran a codex confirmation pass on the S22 benchmarks: verified 9/10 first-round fixes held, fixed 3 adjacent defects, and audited the extraction benchmark for the first time (4 critical, incl. a reuse-precision gaming hole), all verified against the corpus before fixing. liminal began landing gold-scored local-model numbers.
- S22 (07-11): model-tier program (#109) — built the synthesis, validation, and enrichment offline benchmarks (extraction was the template), completing the four-stage suite; ran a codex adversarial review that caught 10 real scoring defects (all fixed: input-relative scoring, non-gameable denominators). Grounded the metric design via a `/stacks:lookup` into the llm-eval stack.
- S21 (07-11): model-tier program (#95→#109) — built the extraction benchmark, found the over-mint was scope-starvation not weak tier, shipped the `index.md` scope-map fix to all 4 worker agents (0.57.0–0.58.0) with a 0.57.1 anti-lumping counterweight; earlier in the window, an enrich/audit hardening batch (0.52.0–0.56.3). Collaboration with liminal on local-model scoring.

## Theme index
- model-tier-eval: S21, S22, S23, S24, S25, S26
- verify-and-fix: S25, S26
- corpus-context-to-agents: S21
- pipeline-hardening (was: enrich-audit-hardening): S21, S24

<!-- journal:cold -->

## Arcs
(none yet)

## Milestones
(none yet)

## CONTEXT HANDOFF - 2026-07-13 (Session 26)

### Session summary
One long arc under epic #109: take the verify-and-fix machinery from "built + advisory-wired" (S25 end) to "exercised on the real `llm` stack and the validation-local question closed." Opening segment (continued from a compaction, recovering the 0.65.0 codex review): finished hardening the local-shadow parity wiring for validation + enrichment (0.65.0, bash+curl to Ollama, opt-in `STACKS_LOCAL_SHADOW=1`). On the user's steer ("use the new tools on our current stacks"), built the deferred **retrieval fix** — `pair-claims.py` splits each article into claims and pulls each claim's OWN cited-source excerpt (token-overlap, top-K, bullets as first-class units) so the model judges one claim + one excerpt (0.66.0); a real-article smoke exposed a bullet-merge+truncation bug that hid supporting bullets (systematic false-overstatement), fixed as bullet-as-unit (0.66.1, with a corrected gold-check number). Main segment: ran the **full `llm`-stack audit** the user chose — local shadow over all 45 articles (1717 claims), then 6 cloud `validation-verifier` agents grading every claim against the real source (one batch, b3, blew the 64K output cap grading 253 claims → split b3a/b3b; a stray `0.json` and 6 b1 scratch files cleaned before aggregating). Result: label-based poison-recall 90% is a **mirage** — real fix-recall 56%, 25 ghost-corrections (CORRECTION label + no-op replacement), false-correction 49% (#111); and ~71 verifier-confirmed genuine overstatements surfaced (worst agent-memory-systems, 11 fabrications). Then a **5-lever precision search** with liminal, who owned the 3090 runs while I owned the prompt/excerpt spec: a two-stage-gate + calibration + full-section spec removed the S27 confounds (precision 0.10→0.22, fix-quality 0.51→0.84) but the gate still missed both bars; dense qwen3-32b was no better (capacity walled); thinking-mode lifted both axes but plateaued (recall 0.59); atomic-claim decomposition (the harness-owns-structure lever) hit recall 0.70; and a purpose-built MiniCheck-7B specialist tied the same ~0.69 wall at the worst precision (0.17). The **convergence** of specialist and harness on one recall ceiling closed it: the wall is in the data (a ~15-claim gist-preserving-overstatement core), not the substrate. Recorded the close (README key findings, #109 comment, `system-patterns.md` absorption), landed a `pair-claims` claim-quality gate (drops fragment/heading leakage liminal flagged), and filed #111 (unsafe label-recall metric) + #113 (retire the now-answered Step 4.5 shadow from the shipped audit flow). Corrected myself twice mid-flow: walked back an over-strong "local faithfulness is dead" (it was one config, not the capability — which drove the whole lever search), and dropped a false "stale source path" finding a verifier reported (checked all 92 refs, 0 stale). Liminal's last 2×2 cell landed during this handoff (specialist×atomic: recall 0.788 — best of any lever — but precision 0.145 — worst), still below the gate, so the close is FINAL: all four quadrants below the gate, recall/precision trade against each other, validation cloud-owned. The one untried forward direction is a diverse small-model fleet voted on precision.

### Chat
S26-local-validation-close

### Changes made
| Change | Status |
|--------|--------|
| Local-shadow parity (validation+enrichment), codex-hardened, 0.65.0 (9fc64ae) | committed |
| Retrieval build — pair-claims per-claim cited excerpt, 0.66.0 (7f56fe8) | committed |
| Bullet-as-unit retrieval fix + corrected gold number, 0.66.1 (42d30c9) | committed |
| At-scale finding — label recall is a mirage (5c919dc) | committed |
| Precision re-run spec — remove two confounds (51052cc) | committed |
| S63 precision re-run result + pair-claims claim-quality gate (5cfb435) | committed |
| Dense-32b lever — capacity walled (332b130) | committed |
| Specialist + convergence — validation-local closed on 5 levers (61b3a9d) | committed |
| Record validation close — cloud-owned, data-wall (5735bc1) | committed |
| Durable: system-patterns #109 absorption; CLAUDE.md 64K-cap gotcha; this handoff | this handoff |
| liminal future-substrate-candidates note (untracked) | staged this handoff |

### Knowledge extracted
`system-patterns.md`: #109 line absorbs the validation-local close (cloud-owned, 5-lever data-wall, generalizes to synthesis). Project `CLAUDE.md`: 64K-output-cap sub-agent gotcha. `dev/experiments/model-tier/README.md`: validation row + two key-finding sections rewritten to the close. `results-liminal-S63-*.md`: 4 per-lever result files (precision, dense32b, minicheck, future-substrate).

### Decisions recorded
No new ADR (this refines ADR-002's validation stage, absorbed into system-patterns rather than a new decision). Governing call: validation authoritative flip CLOSED, cloud-owned.

### Next session priority
(1) Apply the ~71 confirmed `llm`-stack overstatements, agent-memory-systems first (in `library-stack`, a separate repo); (2) #113 retire the Step 4.5 shadow wiring; (3) #109 synthesis at-scale measurement (same skill, likely same wall); (4) if validation is ever reopened, the diverse-fleet precision play is the one untried lever. Backlog #111 #102 #100 #95 #70.

### Open issues
7 open: #70 #95 #100 #102 #109 #111 #113. Plus library-stack#10 (circuit-breaker triplication, library content).
