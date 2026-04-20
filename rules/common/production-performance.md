# Production Performance (Backend)

> Hard-won patterns from real production audits. Apply these FROM THE START
> when building any backend — not as a post-launch fix.

## 1. Parallelize Independent Queries

NEVER await independent DB queries sequentially. Use `asyncio.gather` (Python)
or `Promise.all` (Node.js) with **separate DB sessions/connections** per query.

```python
# WRONG: 400ms total (100ms + 100ms + 100ms + 100ms)
feed = await get_feed(db, user_id)
trending = await get_trending(db)
usage = await get_usage(db, user_id)
alerts = await get_alerts(db)

# CORRECT: 100ms total (all run concurrently)
async def _trending():
    async with session_factory() as s:
        return await get_trending(s)

feed, trending, usage, alerts = await asyncio.gather(
    get_feed(db, user_id),   # uses request session (may write)
    _trending(),              # read-only, own session
    _usage(),                 # read-only, own session
    _alerts(),                # read-only, own session
)
```

**Rules:**
- Read-only queries get their own session (safe for concurrent use)
- Write queries stay on the request session (needs commit)
- Admin dashboards with N count queries are the #1 offender — always parallelize

## 2. Eliminate N+1 Queries

NEVER fetch related data inside a loop. Batch-fetch everything.

```python
# WRONG: N+1 (one query per tool)
for slug in tool_slugs:
    pricing = await db.execute(select(Pricing).where(tool_id=tool.id))

# CORRECT: batch (one query for all tools)
all_pricing = await db.execute(
    select(Pricing).where(Pricing.tool_id.in_(tool_ids))
)
pricing_by_tool = {}
for p in all_pricing:
    pricing_by_tool.setdefault(p.tool_id, []).append(p)
```

## 3. Defer Heavy Columns

Columns not needed in list queries should use `deferred()` loading.
Embedding vectors (768-dim), large JSONB, long text content.

```python
from sqlalchemy.orm import deferred

class Tool(Base):
    # Loaded on every query (lightweight)
    name = mapped_column(String)
    slug = mapped_column(String)

    # Only loaded when explicitly accessed (heavy)
    embedding = deferred(mapped_column(Vector(768), nullable=True))
    full_description = deferred(mapped_column(Text))
```

## 4. Cache Stable Data in Redis

Data that changes rarely (taxonomy, categories, featured content) must be
cached in Redis with appropriate TTLs.

| Data Type | TTL | Example |
|-----------|-----|---------|
| Taxonomy/categories | 24 hours | Industries, categories, filter options |
| Trending/popular | 1 hour | Trending tools, popular comparisons |
| Per-user dashboard | 60 seconds | Assembled dashboard response |
| Search suggestions | 1 hour | "Did you mean" corrections |

**Pattern:**
```python
cache_key = f"cache:{entity}:{params_hash}"
cached = await redis.get(cache_key)
if cached:
    return json.loads(cached)

result = await expensive_query(db)
await redis.set(cache_key, json.dumps(result, default=str), ex=TTL)
return result
```

## 5. Add HTTP Cache-Control Headers

Every endpoint should declare cacheability:

| Endpoint Type | Header |
|---------------|--------|
| Public static (taxonomy) | `public, max-age=3600, stale-while-revalidate=86400` |
| Semi-static (trending) | `private, max-age=300, stale-while-revalidate=600` |
| User-specific (dashboard) | `private, no-cache` (use Redis instead) |
| Real-time (feed) | `no-store` |

## 6. SQL WHERE, Not Python Filter

NEVER load all rows and filter in Python. Use SQL operators.

```python
# WRONG: full table scan + Python filter
all_items = await db.execute(select(Comparison))
matching = [c for c in all_items if slug in c.tool_slugs]

# CORRECT: SQL JSONB contains operator
matching = await db.execute(
    select(Comparison).where(Comparison.tool_slugs.op("?")(slug))
)
```

For bulk updates:
```python
# WRONG: load all, loop, set, flush
for c in all_comparisons:
    if slug in c.slugs:
        c.stale = True

# CORRECT: single SQL UPDATE
await db.execute(
    update(Comparison).where(Comparison.tool_slugs.op("?")(slug)).values(stale=True)
)
```

## 7. Fire-and-Forget for Non-Critical External Calls

External API calls (Clerk, Stripe, analytics) that don't affect the response
should be fire-and-forget:

```python
# WRONG: blocks response by 200-500ms
await update_clerk_metadata(user_id, {"onboarded": True})
return ApiResponse.ok(data=result)

# CORRECT: response returns immediately
async def _sync():
    try:
        await update_clerk_metadata(user_id, {"onboarded": True})
    except Exception:
        logger.warning("Clerk sync failed", exc_info=True)

asyncio.create_task(_sync())
return ApiResponse.ok(data=result)
```

## 8. Database Indexes

Every model MUST have indexes for:
- Primary filter columns (status, type, is_active)
- Composite indexes for common query patterns (status + sort column)
- Foreign keys used in JOINs
- Trigram indexes for ILIKE/fuzzy search (`gin_trgm_ops`)
- JSONB containment for array-contains queries

```python
__table_args__ = (
    Index("idx_tools_status_trending", "status", "trending_score"),
    Index("idx_tools_name_trgm", "name",
          postgresql_using="gin", postgresql_ops={"name": "gin_trgm_ops"}),
)
```

## 9. Connection Pool Sizing

For 10K concurrent users: `pool_size=20, max_overflow=10` minimum.
Formula: `pool_size = num_workers * 2`, `max_overflow = pool_size / 2`.

```python
engine = create_async_engine(
    url,
    pool_size=20,       # Sustained connections
    max_overflow=10,    # Burst capacity
    pool_timeout=30,    # Max wait for connection
    pool_recycle=300,   # Recycle stale connections
    pool_pre_ping=True, # Verify connection before use
)
```

## 10. Rate Limiting Efficiency

Minimize Redis round-trips per request:
- Use INCR + conditional EXPIRE (2 ops on first request, 1 on subsequent)
- Skip the TTL call — compute reset time from window duration
- Never do 3+ Redis ops per rate-limit check

## Production Readiness Checklist

Before marking any endpoint as "done":

- [ ] No sequential independent queries (use gather/Promise.all)
- [ ] No N+1 patterns (batch-fetch related data)
- [ ] Heavy columns deferred (embeddings, large text)
- [ ] Stable data cached in Redis with TTL
- [ ] Cache-Control header set appropriately
- [ ] SQL-level filtering (no Python loops over full tables)
- [ ] Non-critical external calls are fire-and-forget
- [ ] Indexes exist for all filter/sort columns
- [ ] Connection pool sized for expected concurrency
