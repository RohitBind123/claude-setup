---
name: content-quality-audit
description: Audit an existing app for misleading content - zeros that should be "unknown", internal snake_case fields bleeding to users, charts coercing null to 0, boolean grids rendering false as "absent". Use when a feature is technically working but users are getting wrong impressions from the data shown. Pairs with prioritized-resolver and data-quality rules.
origin: session-learnings
---

# Content Quality Audit

Features can pass tests and still mislead users. A $0 cost badge on a
paid-only tool, an "unknown" category rendered as empty, an internal
`company_stage=pre_seed` tag shown raw - these are content bugs, not
code bugs, and they don't show up in CI.

This skill is the playbook for a full-app content audit: what to look
for, how to categorize findings, and how to ship fixes in safe batches.

## When to Activate

- Pre-launch sweep before showing the app to real users
- After a data backfill or schema change when old rows may render oddly
- When users report "the numbers don't make sense" or "why does X say 0"
- Alongside a `prioritized-resolver` rollout (the resolver fixes data,
  this audit fixes rendering)
- Any time you add a field to a model and 6 months later you're not sure
  which screens show it

## The Four Failure Modes

Every content bug in this category falls into one of four buckets.

### 1. Missing rendered as zero

A numeric field that could be "we don't know" is coerced to 0 and shown
as a confident fact. Price, score, count, rating, duration.

**Symptoms:**
- `cost ?? 0`, `score || 0`, `{value || "0"}`
- "Free" badge on a tool that charges per seat but we never scraped the price
- Radar chart with spikes at the origin because null dimensions collapsed to 0
- Average rating "0.0/5" on a product with no reviews yet

**Fix category:** RELABEL. Render "-", "Contact sales", "Not rated yet",
or hide the element entirely. Never show 0 for a value you never measured.

### 2. Internal field bleeding to users

A database column or enum value designed for engineers ends up in the UI
verbatim. Snake_case, cryptic abbreviations, leaked foreign keys.

**Symptoms:**
- `company_stage: pre_seed` in a user-facing card
- `source: llm_estimate` as a raw tag (should be "Estimated")
- `tool_type: saas_platform` where a human would say "SaaS"
- `integration_complexity: 3` with no legend
- `difficulty: intermediate_plus` (the `_plus` is an internal hack)
- `budget_tier: under_100` rendered as-is

**Fix category:** RENAME (via a humanize helper) or HIDE (if the field
isn't useful to users at all).

### 3. Boolean asymmetry

A feature grid uses a checkmark for `true` but leaves the cell blank for
`false` - visually indistinguishable from "unknown". Users read blank as
"not supported" when it may mean "we don't know yet".

**Symptoms:**
- Compare feature grid where missing data looks identical to "no"
- "Integrates with: Slack, Zapier" with no way to know if the absence of
  "Notion" means "no" or "untested"

**Fix category:** GUARD. Three-state rendering: check mark for true,
x mark for explicit false, em-dash for null/unknown. Legend in the header.

### 4. Jargon or internal taxonomy

Field values that are technically meaningful but use vocabulary only the
team understands. Often inherited from a third-party API or scraper.

**Symptoms:**
- `pricing_model: usage_based` (better: "Pay as you go")
- `hosting: self_hosted` (better: "Self-hosted" with capital S and hyphen)
- `lifecycle_stage: ga` (better: "Generally Available")

**Fix category:** RENAME via humanize helper.

## The Audit Process

### Step 1: Grep for the four failure modes

Run these searches and bucket the findings. Save the list - you'll
categorize them in step 2.

```bash
# Missing -> zero coercions in rendering code
rg '\?\? *0|\|\| *0|\|\| *"0"|\?\? *"0"' --type tsx --type ts frontend/src

# Snake_case strings in JSX (likely internal field bleed)
rg '\{[a-z]+_[a-z_]+\}' --type tsx frontend/src

# Raw enum renders - look for identifiers that match DB enum values
rg 'company_stage|budget_tier|difficulty|tool_type|integration_complexity|pricing_model' \
   --type tsx frontend/src/components frontend/src/app

# Charts with numeric dimensions (candidates for null-coercion bugs)
rg 'dataKey=|PolarRadiusAxis|YAxis' --type tsx frontend/src/components

# Price rendering - look for formatters that don't handle null
rg 'formatCurrency|formatPrice|\$\{.*price|toFixed\(2\)' --type tsx frontend/src
```

### Step 2: Categorize each finding

Every finding gets one of four labels. Write the list in a scratch doc
with the category in front so you can batch the fixes.

| Category | Meaning | Fix shape |
|----------|---------|-----------|
| HIDE | The field shouldn't be shown to users at all | Delete the render |
| RELABEL | Replace misleading value with honest copy | "Contact sales", em-dash, "Not rated" |
| GUARD | Render three states (true / false / unknown) | Checkmark / X / em-dash |
| RENAME | Humanize via a helper function | "pre_seed" -> "Pre-seed" |

Example scratch output from a real audit:

```
RELABEL  pricing-table.tsx:142   $0 on paid-only tool -> "Contact sales"
RELABEL  radar-chart.tsx:88      null dims coerced to 0 -> filter + empty state
GUARD    feature-grid.tsx:201    blank cells for false -> add X icon
RENAME   tool-card.tsx:55        company_stage: pre_seed -> humanize
RENAME   workflow-card.tsx:33    difficulty: intermediate_plus -> humanize
HIDE     tool-detail.tsx:412     internal tool_type field shown - not useful
RELABEL  stack-summary.tsx:78    "0 integrations" on untested tool -> "Untested"
RENAME   stack-detail.tsx:156    budget_tier: under_100 -> "Under $100/mo"
```

### Step 3: Build a humanize helper module once

Don't fix RENAME findings in place - each one needs a string map and
they'll drift. Create one helper file and reference it everywhere.

```typescript
// frontend/src/lib/humanize.ts

const COMPANY_STAGE: Record<string, string> = {
  pre_seed: "Pre-seed",
  seed: "Seed",
  series_a: "Series A",
  series_b: "Series B",
  series_c_plus: "Series C+",
  public: "Public",
  bootstrapped: "Bootstrapped",
};

const BUDGET_TIER: Record<string, string> = {
  under_100: "Under $100/mo",
  "100_500": "$100 - $500/mo",
  "500_2000": "$500 - $2,000/mo",
  over_2000: "Over $2,000/mo",
  enterprise: "Enterprise",
};

const DIFFICULTY: Record<string, string> = {
  beginner: "Beginner",
  intermediate: "Intermediate",
  intermediate_plus: "Intermediate+",
  advanced: "Advanced",
  expert: "Expert",
};

const COST_SOURCE: Record<string, string> = {
  exact_match: "Verified",
  llm_estimate: "Estimated",
  fuzzy_match: "Matched",
  cheapest_fallback: "Approximate",
  free_only: "Free tier",
  unknown: "Unknown",
};

export const humanizeCompanyStage = (v: string | null | undefined) =>
  v ? COMPANY_STAGE[v] ?? v : null;

export const humanizeBudgetTier = (v: string | null | undefined) =>
  v ? BUDGET_TIER[v] ?? v : null;

export const humanizeDifficulty = (v: string | null | undefined) =>
  v ? DIFFICULTY[v] ?? v : null;

export const humanizeCostSource = (v: string | null | undefined) =>
  v ? COST_SOURCE[v] ?? v : null;
```

Key points:
- Every function returns `null` for null/undefined input (so JSX can
  short-circuit with `{humanized && <span>...</span>}`)
- Every function falls back to the raw value if the key is missing, so
  a new enum value doesn't render as blank - it renders as the raw key,
  which is visible in QA and prompts you to add it to the map
- Keep the maps in one file - drift between `TierLabel.tsx` and
  `StackCard.tsx` is how you end up with "Series A" in one place and
  "series_a" in another

### Step 4: Rendering rules for RELABEL fixes

Adopt a small set of copy conventions and apply them consistently:

| Situation | Show |
|-----------|------|
| Price unknown on a paid tool | "Contact sales" |
| Price unknown on a free-or-paid tool | em-dash with tooltip "Not publicly listed" |
| Score/rating with no data | em-dash (not 0.0) |
| Count with no data | em-dash (not 0) |
| Chart dimension null | Filter the dimension out; show empty state if all null |
| Boolean false vs unknown | X icon for false, em-dash for unknown |
| Date unknown | em-dash (not "Jan 1, 1970") |

Example:

```tsx
// BAD
<span>${tool.monthly_cost ?? 0}/mo</span>

// GOOD
{tool.cost_source === "unknown" || tool.monthly_cost == null ? (
  <span className="text-muted-foreground">
    {tool.has_paid_tier ? "Contact sales" : "—"}
  </span>
) : (
  <span>${tool.monthly_cost}/mo</span>
)}
```

### Step 5: Chart null handling

Charts are the highest-damage surface for content bugs because a zero
spike on a radar chart or a 0-height bar reads as "this tool scores
zero", not "we have no data". Always:

1. Filter null dimensions out of the dataset before passing to the chart
2. If fewer than N dimensions remain, show an empty state instead of a
   degenerate chart ("Not enough data to compare")
3. Never default missing to 0 inside the chart's data-transform function

```tsx
const dimensions = RAW_DIMENSIONS
  .map((d) => ({ ...d, value: tool[d.key] }))
  .filter((d) => d.value != null);

if (dimensions.length < 3) {
  return <EmptyChartState message="Not enough data to compare" />;
}

return <RadarChart data={dimensions} />;
```

## Batch-and-Commit Strategy

A content audit typically finds 20-80 issues across a codebase. Don't
ship them as one giant PR - batch by category so reviewers can verify
each pattern independently and rollbacks are surgical.

Suggested batches:
1. **Humanize helper module** (one commit, just adds the file)
2. **RENAME fixes** (one commit per surface: tools, workflows, stacks)
3. **RELABEL: pricing** (pricing tables, cost badges, stack summaries)
4. **RELABEL: charts** (filter nulls, empty states)
5. **GUARD: feature grids** (three-state rendering)
6. **HIDE: internal fields** (delete renders)
7. **Legend and tooltips** (once everything else is consistent)

Each commit should have a one-line commit message naming the category
and the surface: `content: rename company_stage on tool cards via
humanize helper`.

## Multi-Agent Audit Methodology

For a large codebase, parallelize the audit across three agents:

- `architect` - reads the domain model and flags which fields are
  internal-only and should never reach users
- `database-reviewer` - scans SQL and ORM models for columns with
  nullable numerics that feed user-facing views
- `ui-ux-architect` - walks the frontend component tree and flags
  rendering sites that use the four failure modes

Give each agent the same categorization schema (HIDE / RELABEL / GUARD
/ RENAME) and merge their findings into one scratch doc. This catches
issues that a single-pass review would miss because the bug is
distributed across layers.

## Observability Follow-up

After the audit is fixed, add telemetry so regressions are caught:

```python
# Track what source label users actually see
analytics.track("content_rendered", {
    "surface": "pricing_table",
    "cost_source": resolved_source,
    "relabeled": resolved_source in ("unknown", "llm_estimate"),
})
```

Then add a weekly check:
- How many page views show `"Contact sales"` instead of a real price?
- How many chart renders hit the empty state?
- How many humanize lookups fall through to the raw-value branch?

A rising raw-value fallthrough rate means a new enum value was added
upstream and the humanize map needs updating.

## Key Rules

1. **Zero is a claim, not a default.** If you don't know the value,
   say so - never show 0.
2. **One humanize helper per enum, one file total.** Don't inline maps.
3. **Three-state booleans in grids**: true / false / unknown are all
   distinct.
4. **Charts filter nulls, never coerce.** Empty state beats fake data.
5. **Snake_case in the UI is always a bug.** If you see one, grep for
   more.
6. **Ship in category batches**, not one monster PR.
7. **Humanize helpers fall through to raw**, so new enum values are
   loud in QA.
8. **Telemetry on rendered labels** catches regressions before users do.

## Related Rules and Skills

- `rules/common/data-quality.md` - the upstream rules that prevent
  bad data from reaching the render layer
- `skills/prioritized-resolver` - how to produce the source/confidence
  tags that this skill's RELABEL rules consume
- `rules/common/migration-safety.md` - when you backfill a new column,
  rerun this audit on any surface that reads it
