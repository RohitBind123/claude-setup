---
name: prioritized-resolver
description: Build a prioritized fallback resolver for multi-source data with per-branch confidence, logging, and analytics. Use when data for a single field can come from multiple places (exact DB match, LLM estimate, fuzzy match, cheapest fallback, unknown) and silent fallthrough would mislead users. Prevents misleading zero values, silent data quality degradation, and confidence drift.
origin: session-learnings
---

# Prioritized Resolver Pattern

When a single piece of data (price, score, count, category) can come from
multiple sources of varying trust, the code MUST resolve the value through
an explicit priority chain. Silent fallthrough and `?? 0` coercion are
anti-patterns that mislead users and hide data quality problems.

This skill shows the full pattern: dataclass, resolver function, branch
logging, analytics integration, tests, and the frontend rendering rules
that pair with it.

## When to Activate

- Pricing data from a mix of DB records and LLM research
- Cost calculations where some sources have stale or partial data
- Confidence/quality scores that need per-source attribution
- Any "if A, else if B, else if C" chain that currently uses silent defaults
- Data shown to users where "missing" and "zero" are different facts

## The Pattern

### 1. Define the resolution result as a dataclass

```python
from dataclasses import dataclass

# Branch tags — string constants so they can be logged, persisted, and
# aggregated in analytics without typo risk.
SOURCE_EXACT = "exact_match"           # confidence 1.00
SOURCE_LLM_ESTIMATE = "llm_estimate"   # confidence 0.85
SOURCE_FUZZY = "fuzzy_match"           # confidence 0.70
SOURCE_CHEAPEST = "cheapest_fallback"  # confidence 0.40
SOURCE_FREE_ONLY = "free_only"         # confidence 1.00
SOURCE_UNKNOWN = "unknown"             # confidence 0.00

CONFIDENCE_BY_SOURCE: dict[str, float] = {
    SOURCE_EXACT: 1.00,
    SOURCE_LLM_ESTIMATE: 0.85,
    SOURCE_FUZZY: 0.70,
    SOURCE_CHEAPEST: 0.40,
    SOURCE_FREE_ONLY: 1.00,
    SOURCE_UNKNOWN: 0.00,
}

@dataclass(frozen=True)
class PriceResolution:
    monthly_cost: float
    cost_source: str
    resolved_tier_name: str
    confidence: float
```

### 2. Write the resolver with explicit branches

```python
import re
import logging

logger = logging.getLogger(__name__)

def _normalize_tier(name: str | None) -> str:
    """Lowercase + strip non-alphanumerics for fuzzy matching."""
    if not name:
        return ""
    return re.sub(r"[^a-z0-9]", "", name.lower())


def resolve_step_price(
    step: Step,
    tiers: list[Tier],
    requested_tier: str | None,
) -> PriceResolution:
    """Resolve a single step's monthly cost using the prioritized chain.

    Order:
        1. Exact tier_name match (ToolPricing)
        2. LLM-persisted estimate on the step
        3. Fuzzy normalized tier_name match (last-resort DB match)
        4. Cheapest non-free, non-enterprise tier
        5. Free-only (tool has only a free tier)
        6. Unknown (no pricing at all)
    """
    req_norm = _normalize_tier(requested_tier)

    # 1. Exact match (case-insensitive)
    if requested_tier:
        for t in tiers:
            if t.tier_name and t.tier_name.lower() == requested_tier.lower():
                if t.is_free:
                    return PriceResolution(
                        monthly_cost=0.0,
                        cost_source=SOURCE_EXACT,
                        resolved_tier_name=t.tier_name,
                        confidence=CONFIDENCE_BY_SOURCE[SOURCE_EXACT],
                    )
                if t.price_monthly is not None:
                    return PriceResolution(
                        monthly_cost=float(t.price_monthly),
                        cost_source=SOURCE_EXACT,
                        resolved_tier_name=t.tier_name,
                        confidence=CONFIDENCE_BY_SOURCE[SOURCE_EXACT],
                    )
                # NULL price on a matched paid row → fall through to next
                logger.info(
                    "exact match has NULL price, falling through tool=%s tier=%s",
                    step.tool_id, t.tier_name,
                )
                break

    # 2. LLM-persisted estimate on the row itself
    if step.estimated_monthly_cost is not None:
        try:
            est = float(step.estimated_monthly_cost)
        except (TypeError, ValueError):
            est = 0.0
        if est >= 0:
            logger.info(
                "llm estimate tool=%s requested=%s est=%.2f",
                step.tool_id, requested_tier, est,
            )
            return PriceResolution(
                monthly_cost=est,
                cost_source=SOURCE_LLM_ESTIMATE,
                resolved_tier_name=requested_tier or "estimated",
                confidence=CONFIDENCE_BY_SOURCE[SOURCE_LLM_ESTIMATE],
            )

    # 3. Fuzzy match — strict token equality, NOT substring
    if req_norm:
        for t in tiers:
            if _normalize_tier(t.tier_name) == req_norm and t.price_monthly is not None:
                logger.info(
                    "fuzzy match tool=%s requested=%s matched=%s",
                    step.tool_id, requested_tier, t.tier_name,
                )
                return PriceResolution(
                    monthly_cost=float(t.price_monthly),
                    cost_source=SOURCE_FUZZY,
                    resolved_tier_name=t.tier_name,
                    confidence=CONFIDENCE_BY_SOURCE[SOURCE_FUZZY],
                )

    # 4. Cheapest non-free, non-enterprise paid tier
    paid_tiers = [
        t for t in tiers
        if not t.is_free and not t.is_enterprise and t.price_monthly is not None
    ]
    if paid_tiers:
        cheapest = min(paid_tiers, key=lambda t: float(t.price_monthly))
        logger.warning(  # WARNING — this is suspicious, not normal
            "cheapest fallback tool=%s requested=%s chosen=%s price=%.2f",
            step.tool_id, requested_tier, cheapest.tier_name,
            float(cheapest.price_monthly),
        )
        return PriceResolution(
            monthly_cost=float(cheapest.price_monthly),
            cost_source=SOURCE_CHEAPEST,
            resolved_tier_name=cheapest.tier_name,
            confidence=CONFIDENCE_BY_SOURCE[SOURCE_CHEAPEST],
        )

    # 5. Free-only: tool genuinely has no paid tier
    free_tier = next((t for t in tiers if t.is_free), None)
    if free_tier:
        return PriceResolution(
            monthly_cost=0.0,
            cost_source=SOURCE_FREE_ONLY,
            resolved_tier_name=free_tier.tier_name or "Free",
            confidence=CONFIDENCE_BY_SOURCE[SOURCE_FREE_ONLY],
        )

    # 6. Unknown — nothing to resolve
    logger.warning(
        "no price resolved tool=%s requested=%s tier_count=%d",
        step.tool_id, requested_tier, len(tiers),
    )
    return PriceResolution(
        monthly_cost=0.0,
        cost_source=SOURCE_UNKNOWN,
        resolved_tier_name=requested_tier or "unknown",
        confidence=CONFIDENCE_BY_SOURCE[SOURCE_UNKNOWN],
    )
```

### 3. Aggregate confidence as cost-weighted mean, not arithmetic

```python
# For a workflow with N steps, compute the aggregate confidence as a
# COST-WEIGHTED mean. A cheap step with low confidence should not drag
# down a $500 step with exact match.

weighted_conf_num = 0.0  # sum of (cost * confidence)
weighted_conf_den = 0.0  # sum of cost
unweighted_conf_sum = 0.0  # fallback for all-free stacks

for res in resolutions:
    weighted_conf_num += res.monthly_cost * res.confidence
    weighted_conf_den += res.monthly_cost
    unweighted_conf_sum += res.confidence

confidence_score = (
    weighted_conf_num / weighted_conf_den
    if weighted_conf_den > 0
    else (unweighted_conf_sum / len(resolutions) if resolutions else 0.0)
)

# Derive label for UI
confidence_label = (
    "high" if confidence_score >= 0.9
    else "medium" if confidence_score >= 0.7
    else "low"
)
```

### 4. Emit analytics per branch — on write path only

```python
# BAD: analytics in the read path fires N events per page view
# async def calculate_costs(wf_id):
#     for step in steps:
#         analytics.track("cost_resolved", {...})  # ← bad

# GOOD: analytics on the recalc/write path fires once per recalc
async def recalculate_and_cache(db, wf_id, redis):
    costs = await calculate_costs(db, wf_id)
    # ... persist snapshot columns ...
    for step_breakdown in costs["steps"]:
        try:
            analytics.track("system", "cost_resolved", {
                "source": step_breakdown["cost_source"],
                "tool_id": step_breakdown["tool_id"],
                "workflow_id": str(wf_id),
                "confidence": step_breakdown["confidence"],
            })
        except Exception:
            logger.debug("analytics track failed", exc_info=True)
```

### 5. Test every branch

```python
@pytest.mark.asyncio
class TestResolverBranches:
    async def test_exact_match_with_confidence_1(self, db):
        # Exact tier_name match returns confidence 1.0, source exact_match

    async def test_exact_match_case_insensitive(self, db):
        # "business" requested matches "Business" tier

    async def test_llm_estimate_used_when_no_db_match(self, db):
        # DB has "Team"/"Business", step.estimated_monthly_cost = 55, requested "pro"
        # → returns 55 with source llm_estimate, confidence 0.85

    async def test_fuzzy_match_token_equality(self, db):
        # "Pro Team" normalizes to "proteam"; requested "pro-team" also matches

    async def test_fuzzy_does_not_match_substring(self, db):
        # "pro" should NOT match "proxy" — substring matching is wrong

    async def test_cheapest_fallback_excludes_enterprise(self, db):
        # Enterprise tier with low price should not win the cheapest branch

    async def test_free_only_when_no_paid_tiers(self, db):
        # Tool with only free tier → returns 0, source free_only, confidence 1.0

    async def test_unknown_when_no_pricing_rows(self, db):
        # No pricing at all → returns 0, source unknown, confidence 0.0

    async def test_null_price_on_matched_tier_falls_through(self, db):
        # Tier matches exactly but price_monthly is NULL → fall through to next


class TestConfidenceScoring:
    async def test_all_exact_gives_high(self, db):
        # All exact matches → score 1.0, label "high"

    async def test_mixed_sources_cost_weighted(self, db):
        # $100 exact (1.0) + $50 cheapest (0.4)
        # weighted mean = (100*1.0 + 50*0.4) / 150 = 0.8 → label "medium"
```

## Weekly Health Report Pattern

Any resolver in production deserves a weekly health report script that
prints the distribution of branches and flags threshold violations:

```python
# backend/scripts/cost_resolver_report.py

async def run(days: int = 7):
    # Query recent resolutions, aggregate by cost_source
    source_counter = Counter()
    for step_row in recent_steps:
        source_counter[step_row.cost_source] += 1

    total = sum(source_counter.values())
    exact_rate = source_counter["exact_match"] / total
    cheapest_rate = source_counter["cheapest_fallback"] / total

    # Print distribution + verdict
    print(f"exact_match rate:       {exact_rate:6.1%}  (target >= 70%)")
    print(f"cheapest_fallback rate: {cheapest_rate:6.1%}  (target < 10%)")

    verdict = []
    if exact_rate < 0.5:
        verdict.append("ALERT")
    if cheapest_rate > 0.2:
        verdict.append("ALERT-cheapest")
    print(f"Verdict: {' '.join(verdict) or 'GOOD'}")
    return 1 if "ALERT" in verdict else 0
```

Run this weekly, or on demand after pricing refreshes, to catch drift.

## Frontend Rendering Rules

The resolver only matters if the frontend renders confidence honestly.

### Per-item confidence badge

Use a colored status dot on the left of the cost/score badge, not a
hover-only tooltip. Scannable without hover.

```tsx
const dotColorClass =
  source === "exact_match" || source === "free_only"
    ? "bg-emerald-500"          // verified
    : source === "llm_estimate"
      ? "bg-amber-500"          // estimated
      : source === "fuzzy_match" || source === "cheapest_fallback"
        ? "bg-gray-400"         // approximate
        : null;

<span
  className="inline-flex items-center gap-1.5 rounded-full ..."
  title={confidenceTooltip}
>
  {dotColorClass && (
    <span className={`h-1.5 w-1.5 rounded-full ${dotColorClass}`} />
  )}
  {formatCurrency(cost)}/mo
</span>
```

### Aggregate confidence label on the container card

```tsx
{confidenceLabel === "high" && (
  <span className="badge bg-emerald-100 text-emerald-700">
    Verified pricing
  </span>
)}
{confidenceLabel === "medium" && (
  <span className="badge bg-amber-100 text-amber-700">
    Partial estimate
  </span>
)}
{confidenceLabel === "low" && (
  <span className="badge bg-red-100 text-red-700">
    Approximate
  </span>
)}
```

## Key Rules

1. **No silent fallthrough**: every branch is explicit, returns a
   structured result with source + confidence
2. **Log WARN for suspicious fallbacks** (cheapest, unknown),
   INFO for normal fallbacks (llm, fuzzy)
3. **Analytics on write path only**, never per-read
4. **Cost-weighted mean** for aggregate confidence, not arithmetic
5. **Test every branch** — one test per source tag
6. **Render confidence visibly** — colored dots, not hover tooltips
7. **Weekly health report** to catch resolver drift over time
8. **Derived labels** for UI (high/medium/low) so thresholds can
   change without touching rendering code

## Related Rules

- `rules/common/data-quality.md` — missing vs zero, denormalized snapshot
- `rules/common/async-state-safety.md` — analytics path rules
- `skills/content-quality-audit` — how to audit existing resolvers
