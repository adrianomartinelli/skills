export const meta = {
  name: 'policy-review',
  description: 'Review a diff against every Policy rule in AGENTS.md and CODING_STANDARDS.md: one agent per Policy subsection, a verdict per rule, a skeptic per violated rule',
  phases: [
    { title: 'Review', detail: 'one agent per Policy subsection, a verdict for each rule' },
    { title: 'Verify', detail: 'one skeptic per violated rule, defaults to refuted' },
  ],
}

// The /policy skill passes the diff command, the groups that its groups.py parses out of AGENTS.md
// and CODING_STANDARDS.md, and the path of its examples.md. This script cannot read files, so that
// parser is the coverage check.
const { diffCmd, groups, examples } = args ?? {}
if (typeof diffCmd !== 'string' || !diffCmd) throw new Error('policy-review needs args.diffCmd. Run /policy instead.')
if (!Array.isArray(groups) || !groups.length || groups.some(g => !g.rules?.length || !g.file)) {
  throw new Error('policy-review needs args.groups from the policy skill\'s groups.py. Run /policy instead.')
}
if (typeof examples !== 'string' || !examples) throw new Error('policy-review needs args.examples. Run /policy instead.')

const VIOLATION = {
  type: 'object',
  required: ['file', 'line', 'summary', 'fix', 'kind'],
  properties: {
    file: { type: 'string' },
    line: { type: 'integer' },
    summary: { type: 'string', description: 'one line: what the code does that the rule forbids' },
    fix: { type: 'string', description: 'the remedy that the rule states, applied to this code' },
    kind: {
      enum: ['mechanical', 'judgment'],
      description: 'mechanical: one obvious fix, local to the diff. judgment: the user must decide.',
    },
  },
}

// Every rule of the group is a required key, so a reviewer cannot skip a rule.
const reviewSchema = rules => ({
  type: 'object',
  required: ['verdicts'],
  properties: {
    verdicts: {
      type: 'object',
      additionalProperties: false,
      required: rules,
      properties: Object.fromEntries(rules.map(id => [id, {
        type: 'object',
        required: ['status', 'evidence', 'violations'],
        properties: {
          status: { enum: ['complies', 'violated', 'not_applicable'] },
          evidence: { type: 'string', description: 'one line: what in the diff you checked against this rule' },
          violations: { type: 'array', items: VIOLATION, description: 'empty unless status is violated' },
        },
      }])),
    },
  },
})

const SKEPTIC = {
  type: 'object',
  required: ['upheld', 'reason'],
  properties: {
    upheld: { type: 'array', items: { type: 'integer' }, description: 'indices of the violations that stand' },
    reason: { type: 'string' },
  },
}

const reports = await pipeline(
  groups,
  g => agent(
    `You review one group of the Policy rules in ${g.file}: "${g.title}" (${g.rules.join(', ')}). The ` +
    `diff under review is what \`${diffCmd}\` prints. Check the diff against each rule's text and ` +
    `Reason, one rule at a time. Include what the diff should contain but does not, for example ` +
    `a test or a paths class. ${examples} lists example signs, one per line, ` +
    `each prefixed by its rule ID. Read the lines for your rules, but do not limit the review to ` +
    `them: they are not complete. Give every rule a verdict. "violated": the diff introduces a ` +
    `violation. List each location, and base \`fix\` on the remedy that the rule states. ` +
    `"not_applicable": the diff touches nothing that the rule governs. Otherwise "complies".`,
    { label: `review:${g.title}`, phase: 'Review', schema: reviewSchema(g.rules) }),
  (review, g) => parallel(g.rules.map(id => async () => {
    const base = { rule_id: id, group: g.title }
    if (!review) return { ...base, status: 'unreviewed', evidence: 'the review agent did not return' }
    const v = review.verdicts[id]
    if (v.status !== 'violated') return { ...base, status: v.status, evidence: v.evidence }
    if (!v.violations.length) {
      return { ...base, status: 'unverified', evidence: `marked violated with no location: ${v.evidence}` }
    }
    const listed = v.violations.map((x, i) => `${i}. ${x.file}:${x.line}: ${x.summary}`).join('\n')
    const s = await agent(
      `A reviewer claims that the diff from \`${diffCmd}\` violates ${g.file} ${id}. Claimed ` +
      `violations:\n${listed}\nTry to refute each one. Is the rule misread? Is the code outside ` +
      `the diff? Does the rule's own text allow this case? Return the indices of the violations ` +
      `that stand in \`upheld\`. Leave out every violation that you are not sure of.`,
      { label: `verify:${id}`, phase: 'Verify', schema: SKEPTIC })
    if (!s) return { ...base, status: 'unverified', evidence: v.evidence, violations: v.violations }
    const upheld = v.violations.filter((_, i) => s.upheld.includes(i))
    return {
      ...base,
      status: upheld.length ? 'violated' : 'refuted',
      evidence: v.evidence,
      violations: upheld,
      refuted: v.violations.filter((_, i) => !s.upheld.includes(i)),
      skeptic: s.reason,
    }
  })),
)

const rules = reports.flatMap((r, i) => r ?? groups[i].rules.map(id =>
  ({ rule_id: id, group: groups[i].title, status: 'unreviewed', evidence: 'the group did not complete' })))
const count = status => rules.filter(r => r.status === status).length
log(`${rules.length} rules: ${count('violated')} violated, ${count('complies')} comply, ` +
  `${count('not_applicable')} not applicable, ${count('refuted')} refuted, ` +
  `${count('unverified') + count('unreviewed')} unverified or unreviewed`)
return { rules }
