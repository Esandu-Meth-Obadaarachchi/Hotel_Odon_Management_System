// ══════════════════════════════════════════════════════════════════════════════
// AI INSIGHT REPORTS — agent
//
// The dashboard posts a "data pack" (already-computed monthly metrics, statistical
// baselines and clustered expense items). This module runs a two-phase Claude call
// over it and returns a structured report.
//
//   Phase 1  investigation — Haiku with four tools, all served synchronously from
//            the posted pack held in memory. No DB reads, no network inside the loop.
//   Phase 2  composition   — one call with a JSON schema, so the dashboard can render
//            with plain components instead of parsing markdown.
//
// A hand-written tool loop is used rather than the SDK's beta toolRunner: the tool set
// is fixed and tiny, and this keeps the module off the beta API surface entirely.
// ══════════════════════════════════════════════════════════════════════════════

const crypto = require('crypto');
const { Anthropic } = require('@anthropic-ai/sdk');

const MODEL = 'claude-haiku-4-5';
const PRICE_IN_PER_MTOK = 1.0;   // USD
const PRICE_OUT_PER_MTOK = 5.0;  // USD
const MAX_TOOL_ITERATIONS = 12;

const MONTHS_FULL = ['January','February','March','April','May','June',
                     'July','August','September','October','November','December'];

let client = null;
function getClient() {
  if (!process.env.ANTHROPIC_API_KEY) {
    throw new Error('ANTHROPIC_API_KEY is not set on the server.');
  }
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

// ─── SYSTEM PROMPT ────────────────────────────────────────────────────────────
// Static across every call so it can carry a cache breakpoint. Note Haiku 4.5's
// minimum cacheable prefix is 4096 tokens — if this sits under that the marker is a
// silent no-op, which is why generate() logs cache_read_input_tokens.
const SYSTEM_PROMPT = `You are the financial analyst for The Odon, an 11-room boutique hotel in Anuradhapura, Sri Lanka. All money is Sri Lankan Rupees (LKR). You analyse one month at a time and write for the owner, who knows the business well and does not need basic concepts explained.

## The business

11 sellable rooms (12 configured, room 4 is permanently blocked). Volume is measured in ROOM-NIGHTS, not bookings: a 3-room booking for 2 nights is 6 room-nights. Maximum capacity is roughly 330 room-nights per month.

Room rates by type and package (LKR per room per night):
| Type | Room only | Bed & breakfast | Half board | Full board |
|---|---|---|---|---|
| Double | 11,000 | 14,000 | 19,000 | 24,000 |
| Triple | 12,000 | 16,500 | 24,000 | 31,500 |
| Family | 13,000 | 19,000 | 29,000 | 39,000 |
| Family Plus | 15,000 | 22,500 | 35,000 | 47,500 |

Variable cost per room-night: Double 9,919 · Triple 10,693 · Family 11,617 · Family Plus 12,391.

Fixed costs are about 37,365/month (yearly fixed spread over 12: government levies 68,000, fire extinguishers 15,000, fire department 5,000, facilitation 10,000, tax 60,000, pool supplies 161,500, EPF/ETF 128,880 per year).

Base payroll is 128,880/month across five staff: Rasika (manager) 28,800, Sujeewa (chef) 28,800, Ishara (room boy) 23,760, Thilak (room boy) 23,760, Anura (helper) 23,760. Any salary spend above roughly 128,880 in a month is overtime or commission, not headcount.

## How the numbers are built

Food cost is not the raw Food category alone. It is:
  foodCost = Food expenses + chef salary + all overtime + 70% of Transportation
The other 30% of Transportation is treated as non-food. Cost per meal divides that food cost by total meals fed, where meals fed = guest meals (derived from package and pax) + 400 staff meals in any operating month.

Meal prices charged per person: 2025 breakfast 1,250 / lunch 1,750 / dinner 1,750. 2026 breakfast 1,500 / lunch 2,500 / dinner 2,500.

Guest counts are assumed per room type: Double 2, Triple 3, Family 4, Family Plus 5.

Expense categories are exactly: Food, Utilities, Maintenance, Supplies, Transportation, Marketing, Equipment, Other. Anything uncategorised falls into Other.

## What you are given

A data pack with a metric block for every month of the year, statistical baselines (mean and standard deviation per metric, computed over completed months only), and any months already flagged as statistical outliers at 1.5 standard deviations. "completeThrough" tells you the last complete month — never treat an incomplete month as a low-revenue month.

## How to work

Investigate before you conclude. You have tools; use them.

A raw total means nothing on its own. The unit that matters is cost PER ROOM-NIGHT, because volume drives most spend. When a month looks expensive, the first question is always whether it was busier — call find_comparable_months to get months at similar occupancy, then compare. If two months did similar room-nights but very different spend, that gap is real and worth explaining: call get_expense_items on the suspect categories for both months and find the line item that actually diverged.

Do not stop at "Food was high". Say which item, how much of the gap it accounts for, and how many purchases it took.

Never state a number without the comparison that gives it meaning. "Food was 412,000" is useless. "Food was 412,000, which is 1,840 per room-night against a 1,290 average, and 92% of the gap is one 68,000 fish purchase" is the job.

Be direct. If a month was simply fine, say so and keep it short — do not manufacture concern. If something is genuinely wrong, be blunt about it. Distinguish clearly between what the data shows and what you are inferring. Where a cause is a guess, label it a guess.`;

// ─── TOOLS ────────────────────────────────────────────────────────────────────
// Descriptions state WHEN to call, not just what they do — Haiku under-calls tools
// given passive descriptions.
const TOOLS = [
  {
    name: 'find_comparable_months',
    description: 'Find other months in the year with a similar number of room-nights. CALL THIS FIRST whenever a month looks unusually expensive or unusually cheap — it is the only way to tell a real cost problem from simply being busier. Returns each comparable month with its full metric block so you can compare spend at matched occupancy.',
    input_schema: {
      type: 'object',
      properties: {
        roomNights: { type: 'number', description: 'The room-night count to match against, normally the subject month\'s.' },
        tolerance:  { type: 'number', description: 'Maximum room-night difference to count as comparable. Start around 10% of roomNights; widen if nothing comes back.' },
      },
      required: ['roomNights', 'tolerance'],
    },
  },
  {
    name: 'get_expense_items',
    description: 'Break a spend category down into individual line items for one month or the whole year. CALL THIS whenever a category looks high, or whenever you are comparing the same category across two months and need to know which specific item caused the difference. Returns items with total, number of purchases, and the month-by-month split.',
    input_schema: {
      type: 'object',
      properties: {
        category:   { type: 'string', enum: ['Food','Utilities','Maintenance','Supplies','Transportation','Marketing','Equipment','Other'] },
        monthIndex: { type: 'number', description: '0 = January through 11 = December. Use -1 for the whole year.' },
      },
      required: ['category', 'monthIndex'],
    },
  },
  {
    name: 'get_month_detail',
    description: 'Get the complete metric block for any month: room-nights, revenue, expenses by category, salaries, profit, margin, per-room-night ratios, and the full meal economics. CALL THIS when you want to compare the subject month against a specific other month.',
    input_schema: {
      type: 'object',
      properties: { monthIndex: { type: 'number', description: '0 = January through 11 = December.' } },
      required: ['monthIndex'],
    },
  },
  {
    name: 'get_booking_mix',
    description: 'Get the package and room-type mix for a month: how many bookings were bed & breakfast, half board and full board, and how the room-nights split across Double, Triple, Family and Family Plus. CALL THIS when revenue per room-night or food cost moves and you need to know whether the mix of what was sold changed.',
    input_schema: {
      type: 'object',
      properties: { monthIndex: { type: 'number', description: '0 = January through 11 = December.' } },
      required: ['monthIndex'],
    },
  },
];

// Tool implementations — pure lookups over the in-memory pack.
function runTool(name, input, pack) {
  const months = pack.months || [];
  const mi = Number(input?.monthIndex);

  switch (name) {
    case 'find_comparable_months': {
      const target = Number(input.roomNights);
      const tol = Math.abs(Number(input.tolerance)) || 0;
      const hits = months
        .filter(m => m.roomNights > 0 && Math.abs(m.roomNights - target) <= tol)
        .filter(m => m.monthIndex <= pack.completeThrough)
        .map(m => ({ ...m, roomNightDifference: m.roomNights - target }))
        .sort((a, b) => Math.abs(a.roomNightDifference) - Math.abs(b.roomNightDifference));
      return hits.length
        ? { matched: hits.length, months: hits }
        : { matched: 0, note: `No complete month within ${tol} room-nights of ${target}. Widen the tolerance.` };
    }

    case 'get_expense_items': {
      const cat = input.category;
      const items = pack.expenseItems?.[cat];
      if (!items || !items.length) return { category: cat, items: [], note: 'No spend recorded in this category for the year.' };
      if (mi === -1) {
        return { category: cat, scope: 'full year', items: items.map(i => ({ item: i.item, total: i.total, purchases: i.purchases })) };
      }
      const forMonth = items
        .map(i => ({ item: i.item, total: i.monthly?.[mi] || 0, purchases: i.monthlyCount?.[mi] || 0 }))
        .filter(i => i.total > 0)
        .sort((a, b) => b.total - a.total);
      return {
        category: cat,
        scope: MONTHS_FULL[mi] || `month ${mi}`,
        monthTotal: forMonth.reduce((s, i) => s + i.total, 0),
        items: forMonth,
      };
    }

    case 'get_month_detail': {
      const m = months[mi];
      if (!m) return { error: `No month at index ${mi}.` };
      return {
        ...m,
        isComplete: mi <= pack.completeThrough,
        flagsThisMonth: (pack.flags || []).filter(f => f.monthIndex === mi),
      };
    }

    case 'get_booking_mix': {
      const m = months[mi];
      if (!m) return { error: `No month at index ${mi}.` };
      return {
        month: m.month,
        roomNights: m.roomNights,
        roomTypeNights: m.roomTypeNights,
        packageMix: m.meals?.packageMix,
        guestMeals: m.meals?.guestMeals,
        revenuePerRoomNight: m.revenuePerRoomNight,
      };
    }

    default:
      return { error: `Unknown tool: ${name}` };
  }
}

// ─── OUTPUT SCHEMA ────────────────────────────────────────────────────────────
// Structured outputs cannot use minLength/maximum, and every object needs
// additionalProperties:false plus a complete required list.
const obj = (properties) => ({
  type: 'object',
  properties,
  required: Object.keys(properties),
  additionalProperties: false,
});

const REPORT_SCHEMA = obj({
  headline: { type: 'string', description: 'One sentence summarising the month.' },
  verdict: { type: 'string', enum: ['good', 'mixed', 'concern'] },
  findings: {
    type: 'array',
    description: 'The things that actually matter this month. Between one and five.',
    items: obj({
      severity: { type: 'string', enum: ['high', 'medium', 'info'] },
      title: { type: 'string' },
      detail: { type: 'string' },
      evidence: { type: 'string', description: 'The concrete numbers behind the claim.' },
      metric: { type: 'string', description: 'Metric key this relates to, e.g. expCats.Food, revenue, costPerMeal.' },
    }),
  },
  anomalies: {
    type: 'array',
    description: 'Outliers explained against a matched-occupancy comparison. Empty if nothing stands out.',
    items: obj({
      metric: { type: 'string' },
      observed: { type: 'string' },
      expected: { type: 'string' },
      comparison: { type: 'string', description: 'The specific comparable month and how it differed.' },
      likely_cause: { type: 'string' },
      confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    }),
  },
  trends: {
    type: 'array',
    items: obj({
      metric: { type: 'string' },
      direction: { type: 'string', enum: ['up', 'down', 'flat'] },
      detail: { type: 'string' },
    }),
  },
  actions: {
    type: 'array',
    description: 'Concrete next steps, most important first. Empty if none are warranted.',
    items: obj({
      priority: { type: 'integer', enum: [1, 2, 3] },
      action: { type: 'string' },
      why: { type: 'string' },
    }),
  },
});

const YEAR_SCHEMA = obj({
  headline: { type: 'string' },
  verdict: { type: 'string', enum: ['good', 'mixed', 'concern'] },
  year_narrative: { type: 'string', description: 'A few paragraphs on how the year actually went.' },
  findings: REPORT_SCHEMA.properties.findings,
  anomalies: REPORT_SCHEMA.properties.anomalies,
  trends: REPORT_SCHEMA.properties.trends,
  actions: REPORT_SCHEMA.properties.actions,
});

// ─── HASHING ──────────────────────────────────────────────────────────────────
// Stable stringify: sorted keys, so key order never changes the hash.
function stable(v) {
  if (Array.isArray(v)) return `[${v.map(stable).join(',')}]`;
  if (v && typeof v === 'object') {
    return `{${Object.keys(v).sort().map(k => `${JSON.stringify(k)}:${stable(v[k])}`).join(',')}}`;
  }
  return JSON.stringify(v === undefined ? null : v);
}
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex').slice(0, 32);

// A month's report is invalidated by changes to that month's own figures, not by
// unrelated edits elsewhere in the year. Peer months only supply context.
function hashMonth(pack, month) {
  const m = pack.months?.[month];
  return sha(stable({
    month: m,
    flags: (pack.flags || []).filter(f => f.monthIndex === month),
    items: Object.fromEntries(Object.entries(pack.expenseItems || {}).map(([cat, items]) => [
      cat, items.map(i => [i.item, i.monthly?.[month] || 0, i.monthlyCount?.[month] || 0]).filter(x => x[1] > 0),
    ])),
  }));
}

// The roll-up goes stale exactly when any month underneath it does.
function hashYear(pack, monthHashes) {
  return sha(stable({ totals: pack.yearTotals, completeThrough: pack.completeThrough, monthHashes }));
}

// ─── CLAUDE CALLS ─────────────────────────────────────────────────────────────
const usageOf = (r) => ({
  input_tokens: r.usage?.input_tokens || 0,
  output_tokens: r.usage?.output_tokens || 0,
  cache_read_input_tokens: r.usage?.cache_read_input_tokens || 0,
  cache_creation_input_tokens: r.usage?.cache_creation_input_tokens || 0,
});
const addUsage = (a, b) => ({
  input_tokens: a.input_tokens + b.input_tokens,
  output_tokens: a.output_tokens + b.output_tokens,
  cache_read_input_tokens: a.cache_read_input_tokens + b.cache_read_input_tokens,
  cache_creation_input_tokens: a.cache_creation_input_tokens + b.cache_creation_input_tokens,
});
const costOf = (u) => Math.round(
  ((u.input_tokens + u.cache_creation_input_tokens + u.cache_read_input_tokens) / 1e6 * PRICE_IN_PER_MTOK
    + u.output_tokens / 1e6 * PRICE_OUT_PER_MTOK) * 10000
) / 10000;

const systemBlocks = () => ([
  { type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } },
]);

// Phase 1 — investigation loop.
async function investigate(pack, kickoff) {
  const anthropic = getClient();
  const messages = [{ role: 'user', content: kickoff }];
  let usage = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 };
  let toolCalls = 0;

  for (let i = 0; i < MAX_TOOL_ITERATIONS; i++) {
    const res = await anthropic.messages.create({
      model: MODEL,
      max_tokens: 8000,
      thinking: { type: 'enabled', budget_tokens: 3000 },
      system: systemBlocks(),
      tools: TOOLS,
      messages,
    });
    usage = addUsage(usage, usageOf(res));

    // Append the whole content array — thinking blocks must survive the round trip.
    messages.push({ role: 'assistant', content: res.content });

    if (res.stop_reason !== 'tool_use') {
      const text = res.content.filter(b => b.type === 'text').map(b => b.text).join('\n').trim();
      return { analysis: text, usage, toolCalls, stopReason: res.stop_reason };
    }

    const results = res.content
      .filter(b => b.type === 'tool_use')
      .map(b => {
        toolCalls++;
        let out;
        try {
          out = runTool(b.name, b.input, pack);
        } catch (err) {
          return { type: 'tool_result', tool_use_id: b.id, content: `Tool failed: ${err.message}`, is_error: true };
        }
        return { type: 'tool_result', tool_use_id: b.id, content: JSON.stringify(out) };
      });

    messages.push({ role: 'user', content: results });
  }

  // Ran out of iterations — ask for a conclusion with the tools withdrawn.
  const final = await anthropic.messages.create({
    model: MODEL,
    max_tokens: 4000,
    system: systemBlocks(),
    messages: [...messages, { role: 'user', content: 'Stop investigating and write up what you have found so far.' }],
  });
  usage = addUsage(usage, usageOf(final));
  return {
    analysis: final.content.filter(b => b.type === 'text').map(b => b.text).join('\n').trim(),
    usage, toolCalls, stopReason: 'max_iterations',
  };
}

// Phase 2 — shape the findings into the render schema.
async function compose(analysis, schema, instruction) {
  const anthropic = getClient();
  const res = await anthropic.messages.create({
    model: MODEL,
    max_tokens: 6000,
    system: systemBlocks(),
    output_config: { format: { type: 'json_schema', schema } },
    messages: [{ role: 'user', content: `${instruction}\n\nYour analysis:\n\n${analysis}` }],
  });

  if (res.stop_reason === 'refusal') throw new Error('Claude declined to produce this report.');
  if (res.stop_reason === 'max_tokens') throw new Error('Report was truncated — retry.');

  const text = res.content.filter(b => b.type === 'text').map(b => b.text).join('');
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error('Model returned unparseable JSON.');
  }
  return { report: parsed, usage: usageOf(res) };
}

// ─── PUBLIC API ───────────────────────────────────────────────────────────────
async function generateMonthReport(pack, month) {
  const m = pack.months?.[month];
  if (!m) throw new Error(`No data for month index ${month}.`);

  const peers = (pack.months || [])
    .filter(x => x.monthIndex <= pack.completeThrough)
    .map(x => ({
      month: x.month, roomNights: x.roomNights, revenue: x.revenue, expenses: x.expenses,
      profit: x.profit, margin: x.margin, food: x.expenseByCategory?.Food,
      expensePerRoomNight: x.expensePerRoomNight,
    }));

  const kickoff = [
    `Analyse ${MONTHS_FULL[month]} ${pack.year} for The Odon.`,
    '',
    '## The month under review',
    JSON.stringify(m, null, 1),
    '',
    '## Statistical outliers already flagged for this month (1.5σ detector)',
    JSON.stringify((pack.flags || []).filter(f => f.monthIndex === month), null, 1),
    '',
    '## Baselines across completed months (mean and standard deviation)',
    JSON.stringify(pack.baselines, null, 1),
    '',
    `## Every completed month this year, for comparison (complete through index ${pack.completeThrough})`,
    JSON.stringify(peers, null, 1),
    '',
    pack.prior ? `## Same months last year (${pack.prior.year})\n${JSON.stringify(pack.prior.months, null, 1)}` : '',
    '',
    'Investigate using the tools, then write your findings. Do not skip the occupancy-matched comparison.',
  ].join('\n');

  const phase1 = await investigate(pack, kickoff);
  const phase2 = await compose(
    phase1.analysis,
    REPORT_SCHEMA,
    `Turn your analysis of ${MONTHS_FULL[month]} ${pack.year} into the structured report. Keep every concrete number you found — evidence fields should carry the actual figures, not paraphrases.`
  );

  const usage = addUsage(phase1.usage, phase2.usage);
  return {
    report: phase2.report,
    inputHash: hashMonth(pack, month),
    model: MODEL,
    usage: { ...usage, cost_usd: costOf(usage), tool_calls: phase1.toolCalls, stop_reason: phase1.stopReason },
  };
}

// The roll-up reads the stored monthly reports, never the raw data. That is what keeps
// a newly closed month from costing a full-year regeneration.
async function generateYearReport(pack, monthlyReports) {
  const summaries = monthlyReports
    .sort((a, b) => a.month - b.month)
    .map(r => ({
      month: MONTHS_FULL[r.month],
      headline: r.report?.headline,
      verdict: r.report?.verdict,
      findings: (r.report?.findings || []).map(f => ({ title: f.title, severity: f.severity, evidence: f.evidence })),
      anomalies: (r.report?.anomalies || []).map(a => ({ metric: a.metric, observed: a.observed, likely_cause: a.likely_cause })),
    }));

  const compact = (pack.months || []).map(m => ({
    month: m.month, roomNights: m.roomNights, revenue: m.revenue, expenses: m.expenses,
    profit: m.profit, margin: m.margin, expensePerRoomNight: m.expensePerRoomNight,
  }));

  const anthropic = getClient();
  const prompt = [
    `Write the year review for The Odon, ${pack.year}.`,
    '',
    '## Year totals',
    JSON.stringify(pack.yearTotals, null, 1),
    '',
    `## Month by month (complete through index ${pack.completeThrough})`,
    JSON.stringify(compact, null, 1),
    '',
    summaries.length
      ? `## What the monthly reports already established\n${JSON.stringify(summaries, null, 1)}`
      : '## No monthly reports have been generated yet — work from the figures alone and say so.',
    '',
    pack.prior ? `## Last year (${pack.prior.year})\n${JSON.stringify(pack.prior.months, null, 1)}` : '',
    '',
    'Find the patterns that only show up across the whole year: seasonality, cost drift, months that repeat the same problem. Do not simply restate the monthly reports.',
  ].join('\n');

  const res = await anthropic.messages.create({
    model: MODEL,
    max_tokens: 8000,
    thinking: { type: 'enabled', budget_tokens: 3000 },
    system: systemBlocks(),
    messages: [{ role: 'user', content: prompt }],
  });
  const analysis = res.content.filter(b => b.type === 'text').map(b => b.text).join('\n').trim();

  const phase2 = await compose(analysis, YEAR_SCHEMA, `Turn your ${pack.year} year review into the structured report.`);

  const usage = addUsage(usageOf(res), phase2.usage);
  return {
    report: phase2.report,
    model: MODEL,
    usage: { ...usage, cost_usd: costOf(usage), tool_calls: 0, stop_reason: res.stop_reason },
  };
}

module.exports = {
  generateMonthReport,
  generateYearReport,
  hashMonth,
  hashYear,
  MODEL,
  // exported for the local test harness
  _internal: { runTool, SYSTEM_PROMPT, REPORT_SCHEMA, TOOLS },
};
