# Data Quality

> Hard-won rules from production bug-hunts. Every one of these was a real
> bug that shipped to users in a real session and had to be rolled back or
> hot-patched. Apply them FROM THE START; don't wait for a data audit.

## 1. Missing data is NOT zero (CRITICAL)

Never coerce NULL/undefined prices, scores, counts, or metrics to zero for
display. Zero is a concrete value the user can reason about; missing data
is a distinct state that must look different in the UI.

```
WRONG:  price_monthly ?? 0 → "$0/mo"      // user thinks the plan is free
CORRECT: price_monthly == null  → "Contact sales" | "Pricing unavailable"
         price_monthly === 0    → "$0/mo" (only if is_free is true)
         price_monthly > 0      → "$X/mo"
```

The same principle applies to:
- Chart axes (null dimension → drop the dimension, don't render 0)
- Cost totals (sum skips null instead of treating as 0)
- Confidence scores (0.0 only if you truly have zero confidence)
- View counts, save counts, etc. (null → "—", 0 → "0")

At the database level, NULL and 0 are different facts; preserve that
distinction all the way to the render layer. If a column can be NULL
legitimately, write a CHECK constraint that enforces when it's allowed
(e.g., `price_monthly IS NOT NULL OR is_free = TRUE OR is_enterprise = TRUE`).

## 2. Prioritized resolver for multi-source data

When a piece of data can come from multiple sources (DB, LLM estimate,
fallback, default), write an explicit priority chain with per-source
confidence and logging. Never silently fall through to the worst source.

```
# Pseudocode for a price resolver
def resolve_price(step, tiers, requested_tier):
    # 1. Exact match (highest confidence)
    if exact_tier_match(tiers, requested_tier):
        return Resolution(value, source="exact_match", confidence=1.0)

    # 2. Persisted LLM estimate (medium-high confidence)
    if step.estimated_monthly_cost is not None:
        return Resolution(..., source="llm_estimate", confidence=0.85)

    # 3. Fuzzy match on normalized names (medium confidence)
    if fuzzy_match(tiers, requested_tier):
        return Resolution(..., source="fuzzy_match", confidence=0.7)

    # 4. Cheapest fallback (low confidence, log warning)
    if cheapest_paid := pick_cheapest(tiers):
        logger.warning("cheapest fallback for tool=%s", ...)
        return Resolution(..., source="cheapest_fallback", confidence=0.4)

    # 5. Unknown (zero confidence, log warning, return None or 0)
    logger.warning("no pricing resolved for tool=%s", ...)
    return Resolution(value=0.0, source="unknown", confidence=0.0)
```

**Rules for writing a resolver:**
- Every branch must be explicit — no silent fallthrough
- Return a structured result that includes `source` and `confidence`
- Log at INFO for "normal" fallbacks (LLM estimate, fuzzy)
- Log at WARNING for "suspicious" fallbacks (cheapest, unknown)
- Emit analytics counters per branch so data quality is measurable over time
- The aggregate confidence for a workflow/page/result is a cost-weighted
  mean of per-item confidence, not a flat average

See skill `prioritized-resolver` for a complete example with tests.

## 3. Snapshot vs live read

Denormalized columns (e.g., `total_cost_paid`, `total_tool_count`) are a
SNAPSHOT of what the user saw when the row was created. Live values are
computed on read. They are different fields with different semantics —
do not conflate them.

```
# Schema level
class Workflow(Base):
    # Snapshot — captures what the user saw on creation. Do NOT mutate
    # on pricing refreshes; users revisiting their workflow expect the
    # same number they decided on.
    total_cost_paid: Mapped[float | None]
    cost_snapshot_at: Mapped[datetime | None]  # when the snapshot was taken

# API level
def serialize_workflow(wf):
    return {
        "total_cost_paid": wf.total_cost_paid,           # snapshot
        "cost_snapshot_at": wf.cost_snapshot_at,
        "current_monthly_cost": compute_live(wf),        # live
        "current_cost_confidence": ...,
    }

# Frontend
if snapshot !== current:
    show "As of {snapshot_date}: $X" and "Current: $Y"
```

When to use each:
- **Snapshot** → user's saved workflows, "what did my stack cost?", audit trail
- **Live** → "what would it cost right now", pricing pages, comparisons

Rule: if pricing changes on the DB, old snapshots stay. Only write them
on initial creation or explicit user-initiated refresh.

## 4. Internal fields must not bleed to users

A database column is not a user-facing label. Before rendering any field,
ask: would a user know what this value means?

**Banned from user-facing rendering (without transformation):**
- Enum values like `"manual"`, `"f8_recommendation"`, `"ai_generated"`, `"hybrid"`
- Snake_case keys (`api_calls_per_month`, `has_free_tier`, `is_enterprise`)
- Version numbers with no history (`V1`, `v2`)
- Internal IDs, slugs, UUIDs as primary content
- Quality scores, confidence scores as raw decimals (0.4, 0.85)
- Tool types like `saas_tool`, `ai_tool` shown without transformation
- Debug metadata (generation tokens, model name, latency_ms)

**How to handle:**
1. Write a `humanize*` helper for every enum:
   ```
   humanizeSource("manual") → "Team curated"
   humanizeSource("ai_generated") → "AI-generated"
   humanizeDifficulty("intermediate") → "Intermediate"
   humanizeComplexity("low") → "Simple"  // not "Low"
   ```
2. For snake_case tier limit keys, use a lookup map:
   ```
   LIMIT_LABELS = { "api_calls_per_month": "API calls/mo", ... }
   ```
3. For confidence scores, derive a label:
   ```
   score >= 0.9 → "Verified pricing"
   score >= 0.7 → "Partial estimate"
   score <  0.7 → "Approximate"
   ```
4. For missing data where a row exists but the value is unknown, show:
   - "Contact sales" for pricing
   - Em-dash `—` or "Not available" for numeric data
   - Empty state card (not 0-value bars) for charts

## 5. Charts and visualizations: filter null, don't coerce

Charts with numeric axes are particularly vulnerable to NULL-coerced-to-0.
A radar chart with a 0-value spoke implies "this tool scores 0/10" when
the truth may be "we have no data".

**Rules:**
- Filter out null values at the data prep step, not at render
- If filtering drops too much data to be useful (< 3 points for a radar,
  < 2 for a line chart), render a textual empty state instead
- Don't use `|| 0`, `?? 0`, or `Number(x)` shortcuts on chart data
- Add a tooltip or legend explaining when data is incomplete

```
WRONG:  entry[slug] = dim.scores[slug] ?? 0  // flat 0 on radar spoke
CORRECT: chartData = dimensions.filter(d =>
          toolSlugs.every(s => d.scores[s] != null)
        );
        if (chartData.length < 3) return <EmptyChart />;
```

## 6. Boolean feature grids: asymmetric rendering

When showing "does tool X support feature Y?" as a ✓/✗ grid:

- **Confirmed supported** → bright green ✓ (high visual weight)
- **Not in data** → neutral gray dash `–` (low visual weight)
- **Never use red ✗** — it implies "definitely does not support" when the
  data usually means "not in our feature list"

Add a footnote: _"Dashes mean the feature isn't listed in our data — the
tool may still support it."_

This asymmetry makes data quality visible without lying to the user.

## 7. Analytics in the read path is an anti-pattern

Do NOT fire analytics counters per-item inside a function that gets
called on every read. You'll multiply the event volume by page views
and swamp the analytics pipeline with redundant data.

```
WRONG:  async def calculate_workflow_costs(db, wf_id):
    for step in steps:
        analytics.track("cost_resolved", {...})  # fires N times per page view

CORRECT: async def recalculate_and_cache(db, wf_id):  # write path only
    costs = await calculate_workflow_costs(db, wf_id)
    for step in costs["steps"]:
        analytics.track("cost_resolved", {...})  # fires once per recalc
```

Counters belong on the write/resolve path, not the read path.

## 8. Pre-migration data quality audit

Before adding a CHECK constraint, NOT NULL constraint, or unique index to
an existing table, count how many current rows would violate the new
invariant. If any row violates it, you have three options:

1. **Fix the violating rows in the migration** (e.g., auto-demote
   duplicate `is_current=TRUE` rows to `FALSE` before creating the
   unique index)
2. **Defer the constraint** to a follow-up migration and document why in
   the module docstring
3. **Backfill with a safe default** for the violating rows

Never add a constraint without checking. The migration will fail mid-deploy
and leave the database in a half-migrated state.

```
# Pseudocode for the audit step
async def check_check_constraint_feasibility(db, table, predicate):
    count = await db.execute(
        f"SELECT count(*) FROM {table} WHERE NOT ({predicate})"
    )
    return count.scalar()

# Before adding: CHECK (price_monthly IS NOT NULL OR is_free = TRUE)
violations = await check_check_constraint_feasibility(
    db, "tool_pricing",
    "price_monthly IS NOT NULL OR is_free = TRUE OR is_enterprise = TRUE"
)
if violations > 0:
    # Fix the rows OR defer the constraint
```

## 9. Observability for data quality

Every resolver, fallback chain, or place where data can be partial should
emit per-branch counters so drift is visible in dashboards.

**At minimum:**
- Counter per resolver branch (exact_match, llm_estimate, fuzzy_match,
  cheapest_fallback, unknown)
- Alert if `cheapest_fallback` or `unknown` rate exceeds 10% over an hour
- A weekly report script that aggregates the counts and prints a
  distribution (see `cost_resolver_report.py` pattern)
- Logger.warning (not debug) for fallback paths so ops can grep for them

Without this, data quality degrades silently as the pipeline ages.

## Data Quality Checklist

Before marking any page/feature as "done":

- [ ] No `?? 0` or `|| 0` coercion on prices, scores, or counts
- [ ] Resolver with explicit branches and per-branch logging
- [ ] Snapshot columns are immutable post-creation
- [ ] Every enum has a `humanize*` helper
- [ ] Charts filter null values instead of coercing
- [ ] Boolean grids use asymmetric ✓ / `–` rendering
- [ ] Analytics counters on write path only
- [ ] Migration with new constraints has a data audit comment
- [ ] Alert threshold set for fallback rate
- [ ] Weekly health report script exists for critical resolvers
