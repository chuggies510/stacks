---
session: 25
---

# stacks Active Context

## Current state

| | |
|-|-|
| Version | 0.64.0 (shipped this session; 0.60.1 → 0.61.0 → 0.62.x → 0.63.0 → 0.64.0) |
| Tests | 6 harness gate/summary self-checks green; pipelines unchanged |
| Shipped | verify-and-fix recipe (ADR-002) — machinery for all 4 stages; synthesis+extraction advisory wired (#109) |
| In flight | validation + enrichment SKILL wiring (need local-run harnesses); enrichment full-loop proof; synthesis authoritative flip |

## Open thread

None, closed clean. The user's two asks ("re-run codex, move to SKILL wiring") are both delivered: 2 codex rounds on the machinery (all findings fixed + boundary-guarded by self-checks), and extraction wired into catalog as opt-in Step 5.5. The verify-and-fix rollout is an ongoing campaign, carried in Next priority — not an unresolved fork.

## Next priority

| # | Item | Note |
|---|------|------|
| #109 | validation SKILL wiring | needs a validation-on-real-articles local-run harness |
| #109 | enrichment SKILL wiring | lift liminal's `enrich_agentic.py` loop (search→fetch→judge) |
| #109 | synthesis authoritative flip | calibration green (4/4) — authorized, slice 1b |
| — | backlog | #102 #100 #95 #70 |

**Cross-repo follow-up:** enrichment local loop reference is `podly/extract_bench/enrich_agentic.py` (committed ce54eaa, peer **liminal** session); Brave key at `~/.config/brave-search.key`. library-stack#10 filed (circuit-breaker facts triplicated across 3 llm articles — library content, not the tool).

## Session log
- DECIDED: #109 direction is a cheap-tier **verify-and-fix recipe** (ADR-002) — cheap tier does ONE object judgment, a deterministic harness gate owns every meta-judgment, a cloud verifier grades/fixes the residue; determinism retired as a criterion (it was a testing scaffold). Both local qwen3-30b-a3b (~$0, off-quota) and subscription haiku clear the floors behind the harness — the differentiator is cost/ops, not capability.
- DECIDED: SKILL wiring needs a per-stage **local-run harness** (the analog of `shadow-synth-run.sh`), not just verifier prose. Extraction wired (catalog Step 5.5, 0.64.0, smoke-tested); validation + enrichment pending theirs.
- FACT: parallel sonnet build-agents follow a template's SURFACE but miss its deeper invariants (fail-closed, derive-from-authoritative-fields, enforce-structurally) — 2 codex rounds caught them; the fix is to encode each invariant as a boundary case in the script's `--self-check`.
- TRAP: an apostrophe in a bash COMMENT placed INSIDE a `jq '...'` single-quoted program closes the bash quote and breaks the script (hit again S25 — "agent's own" in a summary comment). Keep apostrophes out of jq-block comments; the passing `--self-check` is the tripwire.
- ARC: #109 verify-and-fix — recipe decided (ADR-002), all 4 stages' machinery built + self-checked, 3 proven live behind the harness (synthesis 4/4, validation item-6 e2e, extraction 35/38), synthesis+extraction advisory wired opt-in; validation/enrichment SKILL wiring + the authoritative flips remain.
- ADR-ABSORBED: verify-and-fix recipe effect written into `system-patterns.md` (ADR-002).

<!-- ═══ JOURNAL — derived view, carried forward by /stop, regenerable from archive/ ═══ -->

## Standing facts
- The Agent tool cannot dispatch local models (reaches only sonnet/haiku/opus/fable); the local-worker harness is **pal MCP `chat`** with a local model name — confirmed S25: pal is configured against `http://localhost:11434/v1` (Ollama) with 50 local models, so `read source → pal chat(model=<local>) → write gate file` works without the Agent tool. A bash+curl-to-`:11434` worker is the alternative harness (deterministic, no MCP/agent). (as-of: 2026-07-12) (rode: S22, S23, S24, S25)
- liminal is the peer Claude session (local-LLM / fine-tuning expert), co-located on this host (3900x) at `~/chungus/dev/liminal`; it serves + scores local models on the shared RTX 3090 (SHARED with liminal's curator cron at :13 every 6h — during its training windows it evicts resident models, so gate heavy local calls on `nvidia-smi --query-gpu=memory.free` and keep pilot models warm via keep-alive). Locate its pane by NAME (windows renumber between sessions): `tmux list-panes -a -F '#{window_name} #{pane_id}' | awk '$1=="liminal"{print $2}'` (S25: pane `%47`). **Walkie-talkie send/verify/metachar-escape/return-path mechanics are canonical in `reference.md#cross-session-coordination` (dev bindings, dev.md § Worktrees & concurrent sessions points at it) — follow that, do NOT restate it here.** (as-of: 2026-07-12) (rode: S22, S23, S24, S25)
- The `dev/experiments/model-tier/` dir (epic #109) is the first-class model-tier test area. **All four pipeline stages now have an offline gold-set benchmark** (extraction, synthesis, validation, enrichment); front-door `README.md` maps them. Local scoring by liminal + the live layers (enrich search-recall, validator shadow test) are the remaining epic work. (as-of: 2026-07-11) (rode: S22, S23, S24, S25)

## Recent arc
- S25 (07-12): #109 verify-and-fix — decided the recipe (ADR-002, determinism retired), ran the live synthesis calibration (qwen draft → sonnet `article-verifier` → summary: 4/4 floors clear + refusal honored), built validation's citation-presence gate (closes qwen's item-6 add-citation miss e2e), then wired the other 3 stages' machinery via 3 parallel `/using-agent-skills` agents (gates + verifiers + summaries), proving each on real data (validation item-6, extraction 35/38 over-mints caught, url-dedup on 43 real URLs). Two codex rounds hardened it (round 2 caught round-1 over-corrections). Wired extraction into catalog as opt-in Step 5.5 (0.64.0). Shipped 0.61.0→0.64.0.
- S24 (07-11): #109 cutover-prep — shipped validator gate-first prompt hardening (0.59.0), then a 7-issue pipeline/skill batch (0.60.0/0.60.1): fixed the catalog self-check `\t`/grep tab-escape (#104), rewrote near-dup detection (#106), enrich source-URL dedup (#98), a lookup web-search guardrail (#107), and background dispatch across the 3 pipeline skills (#108) — via 3 parallel agents + a codex courier that caught 3 real edge cases (fixed in 0.60.1). #102 and #100 deferred with tracked comments.
- S23 (07-11): model-tier program (#109) — ran a codex confirmation pass on the S22 benchmarks: verified 9/10 first-round fixes held, fixed 3 adjacent defects, and audited the extraction benchmark for the first time (4 critical, incl. a reuse-precision gaming hole), all verified against the corpus before fixing. liminal began landing gold-scored local-model numbers.
- S22 (07-11): model-tier program (#109) — built the synthesis, validation, and enrichment offline benchmarks (extraction was the template), completing the four-stage suite; ran a codex adversarial review that caught 10 real scoring defects (all fixed: input-relative scoring, non-gameable denominators). Grounded the metric design via a `/stacks:lookup` into the llm-eval stack.
- S21 (07-11): model-tier program (#95→#109) — built the extraction benchmark, found the over-mint was scope-starvation not weak tier, shipped the `index.md` scope-map fix to all 4 worker agents (0.57.0–0.58.0) with a 0.57.1 anti-lumping counterweight; earlier in the window, an enrich/audit hardening batch (0.52.0–0.56.3). Collaboration with liminal on local-model scoring.

## Theme index
- model-tier-eval: S21, S22, S23, S24, S25
- verify-and-fix: S25
- corpus-context-to-agents: S21
- pipeline-hardening (was: enrich-audit-hardening): S21, S24

<!-- journal:cold -->

## Arcs
(none yet)

## Milestones
(none yet)

## CONTEXT HANDOFF - 2026-07-12 (Session 25)

### Session summary
One long arc under epic #109 (cheapest-model-per-stage cutover), pivoting the epic from "benchmark + score" to a shipped architecture. Opening segment (pre-compaction, recovered from 2 compaction summaries): fixed a liminal precision nit on `DESIGN-local-tier.md`, measured **haiku behind the same harness** (clears synthesis + validation floors — capability parity with qwen; the differentiator is determinism + cost, not capability), confirmed the session uses the Claude **subscription** not the metered API, then — on the user's steer — **retired byte-determinism as a criterion** ("a good outcome doesn't have to be the same outcome") and rebased the aim to "good output that clears the floors." Main segment (commits 557a415→e56e96f): wrote **ADR-002** (verify-and-fix recipe, the durable decision) after the user flagged the dev/specs file as rot-prone; ran the **live synthesis calibration** through the shipped 0.62.x apparatus (qwen drafts serially on the GPU → sonnet `article-verifier` grades → `synth-verify-summary` aggregates: 4/4 article floors clear, 0 over-claims, refusal honored — authorizing the flip); built validation's **citation-presence gate** (STEP 1 as a deterministic regex, closing qwen's byte-deterministic item-6 add-citation miss that liminal had flagged); then, on the user's `/dispatching-parallel-agents` invocation, dispatched **3 parallel `/using-agent-skills` agents** to build the validation/extraction/enrichment machinery (each stage's deterministic gate + cloud verifier + summary), which I integrated and **falsification-proved serially** on the box (validation item-6 e2e byte-DET, extraction 35/38 over-mints caught on the item-3 cliff, url-dedup on 43 real filed URLs). Two codex adversarial rounds via background haiku couriers hardened the machinery — the first caught 7 defects (fail-open, trust-the-boolean, prompt-not-structural), the second caught 6 more that were my round-1 over-corrections (add-citation miscounted as poison, empty-set rejected, mixed-case slug rejected, changed-reuse-target missed) — all fixed and encoded as boundary self-checks. Finally wired **extraction into catalog as opt-in Step 5.5** (0.64.0, smoke-tested e2e). Coordinated the single serial GPU with liminal throughout (curator pause/unpause). liminal independently confirmed the citation gate closes its Hole-B flag and handed over the enrichment loop reference.

### Chat
S25-verify-and-fix-wiring

### Changes made
| Change | Status |
|--------|--------|
| ADR-002 + rot-resistance relocation (557a415) | committed |
| Live synthesis calibration — 4/4 floors (bcafcec) | committed |
| Validation citation-presence gate (7123189) | committed |
| 3-stage machinery via parallel agents, 0.63.0 (11fbf50) | committed |
| Codex round-1 hardening — 7 fixes (6f5c38e) | committed |
| Extraction advisory wired into catalog Step 5.5, 0.64.0 (e56e96f) | committed |
| Codex round-2 — 6 over-correction fixes (post-0.64.0) | committed |
| Durable: system-patterns ADR-002 absorption; this handoff | this handoff |

### Knowledge extracted
`docs/decisions/decision-log.md`: ADR-002 (verify-and-fix recipe). `system-patterns.md`: #109 line updated with the recipe, gate/verifier locations, shipped opt-in advisory steps. `dev/experiments/model-tier/DESIGN-local-tier.md`: per-stage table updated for all 4 stages + the S25 aim rebase. CHANGELOG: 0.61.0–0.64.0.

### Decisions recorded
ADR-002 (Session 25): worker stages use a cheap-tier verify-and-fix recipe; harness owns meta-judgments; determinism retired.

### Next session priority
#109 continues: (1) validation SKILL wiring — needs a validation-on-real-articles local-run harness; (2) enrichment SKILL wiring — lift liminal's `enrich_agentic.py` search→fetch→judge loop; (3) synthesis authoritative flip (calibration green, slice 1b). Backlog #102 #100 #95 #70.

### Open issues
5 open: #70 #95 #100 #102 #109. Plus library-stack#10 (circuit-breaker triplication, library content).
