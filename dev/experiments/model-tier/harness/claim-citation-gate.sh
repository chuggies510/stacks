#!/usr/bin/env bash
# claim-citation-gate.sh  (validation stage, verify-and-fix recipe — #109)
#
# STEP 1 of the validator rubric as a DETERMINISTIC harness gate, not a model
# judgment. Given one article claim line, answer: does it carry its OWN inline
# [source-slug] citation? Prints exactly `CITED` or `UNCITED`.
#
# Why this is a gate and not a prompt: liminal's S61 measurement showed qwen
# misses the item-6 "uncited-but-grounded" case byte-deterministically under the
# gate-first prompt — it returns CLEAN on a claim that has no citation. Citation
# PRESENCE is a pure regex (no content judgment), so per the DESIGN principle
# (harness owns every meta-decision; the model owns only the object judgment) it
# leaves the prompt entirely. The validator/verifier is then asked only the
# irreducibly-content question — CLEAN vs contradiction vs overstatement on a
# CITED claim; which listed source grounds an UNCITED one, or SOFTSPOT — and can
# NEVER wrongly return CLEAN on an uncited claim, because it never sees STEP 1.
#
# Reuses the repo's canonical inline-citation regex (synth-shadow.sh:47): strip
# [[wikilinks]] first (they are cross-links, not source citations), then match a
# [slug] token. Also strips legacy audit marks ([VERIFIED]/[DRIFT]/[UNSOURCED]/
# [STALE]) so an un-scrubbed older article body does not read a mark as a citation.
#
#   echo "claim text [zenml-...]" | bash claim-citation-gate.sh   -> CITED
#   bash claim-citation-gate.sh "claim text, no citation"          -> UNCITED
#   bash claim-citation-gate.sh --self-check
set -euo pipefail

cited() {
  # $1 = claim text. Returns 0 (CITED) if an inline [source-slug] survives after
  # removing things that LOOK like a bracket token but are not source citations:
  #   [[wikilinks]]        — cross-links, not sources
  #   [text](url)          — markdown links (the [text] is not a source slug)
  #   [VERIFIED]/[DRIFT]/… — legacy audit marks
  # A real citation is [source-slug]. Slugs derive from source basenames, which
  # are NOT forced lowercase (e.g. [OpenAI-GPT4]), so match ANY case but require at
  # least one LETTER — this excludes pure-numeric footnote labels like [1]/[42]
  # while still accepting mixed-case slugs (codex #109). A bracketed proper-noun
  # label such as [Figure-1] is indistinguishable from a slug by regex and reads
  # CITED (a rare, accepted false-positive — the alternative broke real citations).
  local t="$1"
  t=$(sed -E 's/\[\[[^]]*\]\]//g; s/\[[^]]*\]\([^)]*\)//g; s/\[(VERIFIED|DRIFT|UNSOURCED|STALE)\]//g' <<< "$t")
  grep -qE '\[[a-zA-Z0-9._-]*[a-zA-Z][a-zA-Z0-9._-]*\]' <<< "$t"
}

gate() { if cited "$1"; then echo CITED; else echo UNCITED; fi; }

self_check() {
  local fail=0
  chk() { # <expected> <claim>
    local got; got=$(gate "$2")
    if [[ "$got" != "$1" ]]; then echo "FAIL: expected $1 got $got for: $2"; fail=1; fi
  }
  # The 7 gold items: 1-5 carry an inline citation, 6-7 do not.
  chk CITED   "GPT-4 judges reach over 80% agreement with humans. [arxiv-2306.05685-llm-as-judge-mt-bench]"
  chk CITED   "GPT-4 consistently outperforms human raters. [arxiv-2306.05685-llm-as-judge-mt-bench]"
  chk CITED   "Released MT-bench questions, ~300 expert votes, 30,000 conversations. [arxiv-2306.05685-llm-as-judge-mt-bench]"
  chk CITED   "Three judge biases: position, verbosity, self-enhancement. [arxiv-2306.05685-llm-as-judge-mt-bench]"
  chk CITED   "Shadow mode deploys any new agent live with zero risk. [zenml-2025-12-llmops-1200-deployments]"
  chk UNCITED "Cox Automotive runs continuous red teaming throughout its development lifecycle, not as a one-time pre-launch assessment."
  chk UNCITED "In practice, most teams find a two-week shadow-mode window sufficient before enabling live execution."
  # Edge cases that prove the strip-first logic:
  chk UNCITED "See [[shadow-mode]] for the deployment gate."                              # a cross-link is not a citation
  chk UNCITED "The judge favored longer answers here [DRIFT]"                             # a legacy audit mark is not a citation
  chk CITED   "See [[shadow-mode]]; agreement was over 80% [arxiv-2306.05685-llm-as-judge-mt-bench]."  # wikilink + real citation
  chk CITED   "Cost was roughly \$80 on a single H100. [zenml-2025-12-llmops-1200-deployments]"        # numbers/punctuation around the slug
  chk UNCITED "Accuracy improved; see [paper](https://example.com/paper)."                            # markdown link, NOT a source citation
  chk CITED   "See [analysis](https://x.com) and the data [zenml-2025-12-llmops-1200-deployments]."   # markdown link stripped, real citation remains
  chk CITED   "GPT-4 beat the baseline. [OpenAI-GPT4]"                                                # MIXED-CASE source slug must still read CITED (codex #109)
  chk UNCITED "The result held across trials [1]."                                                    # pure-numeric footnote label, not a slug
  chk UNCITED "See results [42] and [7] below."                                                       # numeric labels only
  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS"; else echo "SELF-CHECK FAIL"; return 1; fi
}

case "${1:-}" in
  --self-check) self_check ;;
  "") gate "$(cat)" ;;               # claim on stdin
  *)  gate "$1" ;;                    # claim as arg
esac
