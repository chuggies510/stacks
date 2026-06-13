# Fetching web sources into a stack

When you need to pull a web page into `{stack}/sources/incoming/` before cataloging, pick the fetch method per URL instead of looping WebFetch over everything. These are the recurring failure modes (observed across real augment passes) and the workaround for each. Pick the method, write the result to `incoming/{slug}.md`, then run `/stacks:catalog-sources` — the convert stage and extractor take it from there.

Downloaded PDFs/Office files do NOT need special handling here: drop them in `incoming/` and `convert-sources.sh` (catalog Step 3.5) converts them.

## Routing table

| Situation | Method |
|-----------|--------|
| HTTPS canonical, no known block | `WebFetch` |
| Cloudflare-fronted host returning 403 (Wayback `web.archive.org/web/*`, ACM Queue) | `curl --user-agent 'Mozilla/5.0 ...' <url> \| pandoc -f html -t markdown` |
| HTTP-only mirror (WebFetch refuses the HTTPS upgrade, no cert) | same curl + pandoc |
| Long technical spec (RFCs, >~50k tokens) — output filter truncates mid-response | curl + pandoc, skip the LLM round-trip entirely |
| 404 on a guessed canonical URL (docs moved, no 301) | `WebSearch` the title, take the first authoritative result, retry once |
| Origin returns 4xx/5xx | Wayback fallback: `curl` on `web.archive.org/web/*/{url}` + pandoc |

## Truncation detection

The Anthropic output filter can truncate long technical content with no error code. Symptom: the response body ends mid-sentence with no closing fence. When you see that, switch to curl + pandoc (skips the model) or fetch in URL-anchored sections.

## Write contract (if you dispatch an agent to clean up HTML)

An agent told to "fetch and synthesize" sometimes returns a summary describing what it would write but never calls `Write`. Make the success condition "file written" and verify it (the same write-or-fail gate `catalog-sources` uses via `gate-batch.sh`), not "summary returned."

## Frontmatter to populate

Give each fetched source `source_url`, `fetched_at`, `publisher`, `tier` so catalog-sources W3 files it by publisher without guessing.

---

Harvested from issue #51 (closed): the failure modes are real, but a dedicated `fetch-sources` skill with a queue file and wave dispatch was over-built — its auto-feed seam (audit `fetch_source` findings) was removed in 0.21.0, and Claude routes per-URL inline anyway. This table is the durable part.
