// T6 measurement harness (epic #87): fan out enrich gaps via the Workflow substrate
// instead of main-session Agent calls. The one substrate difference that matters:
// each findings row is schema-validated at the tool layer (StructuredOutput), so a
// malformed row cannot reach the file — the deterministic caller writes the TSV.
// Throwaway spike script; args carry the pre-sharded batches (workflow scripts have
// no fs access, so gaps are passed in, not read from dispatch.tsv).
export const meta = {
  name: 't6-enrich-workflow',
  description: 'T6: fan out electrical enrich gaps via Workflow with schema-validated findings rows',
  phases: [{ title: 'Enrich', detail: 'one stacks:enrichment agent per batch, schema-validated' }],
}

const FINDINGS_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['rows'],
  properties: { rows: { type: 'array', items: {
    type: 'object', additionalProperties: false,
    required: ['kind', 'gap_id', 'slug', 'source_ref', 'url', 'tier', 'title', 'quote'],
    properties: {
      kind: { type: 'string', enum: ['CANDIDATE', 'WEAK', 'DUP', 'NOSOURCE'] },
      gap_id: { type: 'string' }, slug: { type: 'string' },
      source_ref: { type: 'string' }, url: { type: 'string' },
      tier: { type: 'string' }, title: { type: 'string' }, quote: { type: 'string' },
    } } } },
}

const STACK = '/Users/chris/chungus/dev/library-stack/electrical'
const A = typeof args === 'string' ? JSON.parse(args) : args   // args may arrive JSON-encoded
phase('Enrich')
const results = await parallel(A.batches.map(b => () =>
  agent(
    `You are enriching audit soft spots for the electrical stack. Follow the stacks:enrichment contract exactly: for each gap, turn the claim into a targeted query, WebSearch, WebFetch the 1-3 best hits, and verify the source STATES THE SPECIFIC CLAIM (topic-adjacent is NOSOURCE). Rate tier against STACK.md (1 gold/official ... 4 forum). Default to NOSOURCE/WEAK when unsure; never fabricate a url/title/quote.\n\n` +
    `Read for tier vocabulary, scope, and dedup:\n- ${STACK}/STACK.md\n- ${STACK}/dev/enrich/_filed-sources.tsv (slug<TAB>url of already-filed sources; a candidate whose url is already filed is a DUP)\n\n` +
    `Your assigned gaps:\n` +
    b.gaps.map(g => `- ${g.gap_id} [${g.slug}] CLAIM: ${g.claim}  (why a gap: ${g.reason})`).join('\n') +
    `\n\nDo NOT write any file. Return exactly one row object per assigned gap_id via structured output: kind CANDIDATE|WEAK|DUP|NOSOURCE; gap_id echoed verbatim; slug; source_ref (filed slug for DUP, else ""); url/tier/title populated for CANDIDATE/WEAK/DUP and "" for NOSOURCE; quote = the supporting passage as plain text with no surrounding quotation marks (or the short reason for NOSOURCE). One row per gap, no omissions, no duplicates, no invented ids.`,
    { label: `enrich:batch-${b.tag}`, phase: 'Enrich', schema: FINDINGS_SCHEMA, agentType: 'stacks:enrichment' },
  ).then(r => ({ tag: b.tag, rows: r ? r.rows : [] }))
))
return results
