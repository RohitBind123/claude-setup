# Production Performance (Backend)

> Language-neutral backend patterns. Apply FROM THE START — not as a
> post-launch fix. For stack-specific extensions see:
> - Python / FastAPI / SQLAlchemy → [python/production-performance.md](../python/production-performance.md)
> - Node / TypeScript frontend → [typescript/production-performance.md](../typescript/production-performance.md)

## 1. Parallelize Independent Queries

NEVER await independent DB queries sequentially. Fan them out concurrently.

```python
# Python
feed, trending, usage, alerts = await asyncio.gather(
    get_feed(db, user_id),    # write-capable: uses request session
    _trending(),              # read-only: own session
    _usage(),                 # read-only: own session
    _alerts(),                # read-only: own session
)
```

```typescript
// Node / TypeScript
const [feed, trending, usage, alerts] = await Promise.all([
  getFeed(db, userId),
  getTrending(db),
  getUsage(db, userId),
  getAlerts(db),
]);
```

**Rules that apply in every language:**
- Read-only queries get their own connection/session (safe for concurrency)
- Write queries stay on the request-scoped session (needs commit)
- Admin dashboards with N count queries are the #1 offender — always parallelize

> SQLAlchemy-specific session rules (AsyncSession is not concurrent-safe)
> live in `python/production-performance.md`.

## 2. Eliminate N+1 Queries

NEVER fetch related data inside a loop. Batch-fetch, then group in memory.

```python
# WRONG — one round-trip per id
for tool_id in tool_ids:
    pricing = await db.execute(select(Pricing).where(Pricing.tool_id == tool_id))

# CORRECT — one round-trip for all ids
rows = await db.execute(select(Pricing).where(Pricing.tool_id.in_(tool_ids)))
pricing_by_tool = defaultdict(list)
for p in rows.scalars():
    pricing_by_tool[p.tool_id].append(p)
```

```typescript
// CORRECT — Prisma / Drizzle / TypeORM all support `IN`
const rows = await db.pricing.findMany({ where: { toolId: { in: toolIds } } });
const pricingByTool = groupBy(rows, (r) => r.toolId);
```

Detect N+1 early: log query counts per request and alert when a single
request issues more than ~20 DB round-trips.

## 3. Select Only What You Need

List endpoints should NOT load heavy columns (embeddings, full content,
large JSONB). Name the columns you need explicitly.

| Stack | Mechanism |
|---|---|
| SQLAlchemy | `deferred()` on the column, or `select(Tool.id, Tool.name)` |
| Django ORM | `Model.objects.defer("heavy_col")` or `.only("id", "name")` |
| Prisma | `select: { id: true, name: true }` |
| TypeORM | `createQueryBuilder().select(["t.id", "t.name"])` |
| Raw SQL | list columns explicitly; never `SELECT *` on wide tables |

Candidates to defer: embedding vectors (768/1536-dim), full-text bodies,
large JSONB metadata, audit logs.

## 4. Cache Stable Data

Data that changes rarely must go through a cache (Redis, Memcached,
CDN). Pick the TTL from the data's real update cadence, not a guess.

| Data Type | TTL | Example |
|---|---|---|
| Taxonomy / categories | 24 hours | Industries, filter options |
| Trending / popular | 1 hour | Trending items, hot comparisons |
| Per-user dashboard | 60 seconds | Assembled dashboard response |
| Search suggestions | 1 hour | "Did you mean" corrections |
| Query embeddings | 30 days | Deterministic per-query vectors |

**Cache-aside pattern (applies to any language):**

```
key      = build_cache_key(entity, params)
cached   = cache.get(key)
if cached: return deserialize(cached)

result   = expensive_query(db)
cache.set(key, serialize(result), ttl)
return result
```

## 5. HTTP Cache-Control Headers

Every endpoint should declare cacheability. The client and any
intermediate CDN / proxy will respect it.

| Endpoint Type | Header |
|---|---|
| Public static (taxonomy) | `public, max-age=3600, stale-while-revalidate=86400` |
| Semi-static (trending) | `private, max-age=300, stale-while-revalidate=600` |
| User-specific (dashboard) | `private, no-cache` (use server-side cache instead) |
| Real-time (feed) | `no-store` |

## 6. Push Filtering to the Database

NEVER load the full table and filter in application code. Push the
predicate into SQL so the engine can use indexes.

```python
# WRONG — full scan + in-memory filter
all_items = await db.execute(select(Comparison))
matching = [c for c in all_items if slug in c.tool_slugs]

# CORRECT — DB-side filter (JSONB ? operator)
matching = await db.execute(
    select(Comparison).where(Comparison.tool_slugs.op("?")(slug))
)
```

For bulk updates: one `UPDATE ... WHERE ...` statement, never load-loop-save.

> PostgreSQL JSONB / trigram / array operators catalogued in
> `python/production-performance.md`.

## 7. Fire-and-Forget for Non-Critical External Calls

External API calls (analytics, third-party metadata, audit webhooks)
that don't affect the response should not block it.

```python
# Python
async def _sync():
    try:
        await update_external(user_id, payload)
    except Exception:
        logger.warning("external sync failed", exc_info=True)

asyncio.create_task(_sync())
return ApiResponse.ok(data=result)
```

```typescript
// Node — don't await, but do catch so it doesn't become UnhandledPromiseRejection
void updateExternal(userId, payload).catch((err) =>
  logger.warn({ err }, "external sync failed")
);
return Response.json(result);
```

Rule: anything the user doesn't see in the response, and that can fail
without breaking the request, should be fire-and-forget.

## 8. Set Timeouts Everywhere

A call without a timeout is a bug waiting for a slow day. Every
boundary between your service and something else needs a deadline.

| Where | What to set | Typical value |
|---|---|---|
| HTTP client | connect + read timeout | 2s connect, 10s read |
| DB query | statement timeout | 5s OLTP, 30s reports |
| DB transaction | idle-in-transaction timeout | 30s |
| Lock acquisition | `lock_timeout` (Postgres) | 3s |
| External webhook | overall timeout | 5s (fire-and-forget) |
| gRPC / long-poll | deadline on the call | per endpoint |

In PostgreSQL, set a default statement timeout at the session level so
runaway queries can't pin a connection:

```sql
ALTER ROLE app_user SET statement_timeout = '5s';
ALTER ROLE app_user SET lock_timeout = '3s';
ALTER ROLE app_user SET idle_in_transaction_session_timeout = '30s';
```

## 9. Paginate Large Collections

No endpoint should return an unbounded list. Pick one of:

- **Offset pagination** — simple, fine for ≤10k rows. Slow past that.
- **Keyset / cursor pagination** — `WHERE id > last_id ORDER BY id LIMIT N`.
  Fast at any depth. Use for feeds, logs, search results.
- **Batched exports** — for full dumps, stream in chunks or hand the
  client a signed URL to S3, never buffer in memory.

Hard rules:
- Every list endpoint has a `limit` parameter with a **capped maximum**
  (typically 100).
- Default limit is small (20–50), not "all".
- Internal batch jobs use batch sizes of 100–500, never "load all".

## 10. Idempotent Writes (for retries)

Any write endpoint callable over a flaky network (mobile, webhooks,
async retries) must be idempotent. Otherwise a retry after a
timed-out-but-successful request creates duplicates.

- Accept an `Idempotency-Key` header and dedup by it (store the result
  and replay it on a second request with the same key).
- For internal retries, key off a natural unique pair — e.g.
  `(user_id, order_id)` with a unique index.
- Webhooks: include an event id; the consumer dedups on it.

## 11. Database Indexes

Every model needs indexes for:
- Primary filter columns (status, type, is_active)
- Composite indexes for common query patterns (status + sort column)
- Foreign keys used in JOINs
- Trigram indexes for fuzzy / ILIKE text search (Postgres: `gin_trgm_ops`)
- JSONB containment for array-contains queries

Run an EXPLAIN on every query in a hot path during code review. If the
plan shows a sequential scan on a table with > 10k rows, add the index
before shipping.

## 12. Connection Pool Sizing

A pool too small starves the app under load; too large overwhelms the DB.

**Formula** (applies to any language / ORM):
- `pool_size  = num_workers * 2`
- `max_overflow = pool_size / 2`
- `pool_timeout = 30s` (max wait for a connection)
- `pool_recycle = 300s` (refresh stale connections)
- `pool_pre_ping = true` (verify liveness before use)

For 10k concurrent users behind a typical worker setup, start at
`pool_size=20, max_overflow=10`. Monitor `pool.checkedout()` at peak;
if it sits at `pool_size + max_overflow`, raise the ceiling or add workers.

If the DB is behind a connection pooler (PgBouncer, Neon pooler), the
**app's own pool should be smaller**, not larger — the pooler handles
the fan-out. Always use the direct (non-pooled) URL for migrations.

## 13. Rate Limiting Efficiency

Rate limiting runs on every request. It must be cheap.

- 2 Redis ops per check, not 3+ (combine INCR with conditional EXPIRE)
- Skip explicit TTL reads — compute reset time from the window duration
- Use sliding-window counters only when accuracy matters; fixed-window
  buckets are almost always sufficient and cheaper

## Production Readiness Checklist

Before marking any endpoint as "done":

- [ ] No sequential independent queries (parallel with gather / Promise.all)
- [ ] No N+1 patterns (batch-fetch related data)
- [ ] Heavy columns deferred (embeddings, large text / JSONB)
- [ ] Stable data cached with appropriate TTL
- [ ] Cache-Control header set
- [ ] DB-side filtering (no full-table load + app-side filter)
- [ ] Non-critical external calls are fire-and-forget
- [ ] Timeouts on every external boundary (DB, HTTP, lock)
- [ ] List endpoints paginate with a capped limit
- [ ] Write endpoints support idempotent retry
- [ ] Indexes exist for all filter / sort columns
- [ ] Connection pool sized for expected concurrency
