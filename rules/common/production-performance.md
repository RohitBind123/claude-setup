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

## 3. Bulk Writes

N individual INSERTs is the write-side of N+1 — one round-trip per row
kills throughput on any non-trivial batch.

```python
# Python — SQLAlchemy multi-row insert
await db.execute(insert(Tool), [row_dict_1, row_dict_2, ...])

# Very large loads (100k+) — use Postgres COPY via asyncpg
await conn.copy_records_to_table("tools", records=rows, columns=[...])
```

```typescript
// Prisma
await db.tool.createMany({ data: rows, skipDuplicates: true });
// Drizzle
await db.insert(tools).values(rows);
```

Rules:
- Batches ≥ 50 rows → multi-row INSERT
- Batches ≥ 10k rows → DB bulk-load path (`COPY` on Postgres,
  `LOAD DATA` on MySQL)
- Postgres caps at 65,535 bound parameters per statement — chunk
  large batches accordingly
- Upserts: use `INSERT ... ON CONFLICT DO UPDATE`, never SELECT-then-UPDATE
  in a loop

## 4. Select Only What You Need

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

## 5. Cache Stable Data

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

## 6. HTTP Cache-Control Headers

Every endpoint should declare cacheability. The client and any
intermediate CDN / proxy will respect it.

| Endpoint Type | Header |
|---|---|
| Public static (taxonomy) | `public, max-age=3600, stale-while-revalidate=86400` |
| Semi-static (trending) | `private, max-age=300, stale-while-revalidate=600` |
| User-specific (dashboard) | `private, no-cache` (use server-side cache instead) |
| Real-time (feed) | `no-store` |

## 7. Push Filtering to the Database

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

## 8. Fire-and-Forget for Non-Critical External Calls

Best-effort external calls (analytics pings, third-party metadata,
audit webhooks) that don't affect the response should not block it.

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

Rule: if the user doesn't see it in the response AND it's acceptable
to lose on a restart, fire-and-forget. For must-succeed work, see §9.

## 9. Background Jobs / Task Queues

If work takes > 1 second OR must succeed with retries OR fans out to
many recipients, push it off the request path onto a task queue.

Offload by default:
- Sending email / SMS / push notifications
- Image / video / PDF processing
- Fan-out webhooks (one event → many subscribers)
- Report generation and data exports
- Long-running AI work (batch embeddings, deep research)
- Anything you'd retry on failure

| Language | Queue |
|---|---|
| Python | Celery, RQ, Arq, Dramatiq |
| Node | BullMQ, Agenda |
| Ruby | Sidekiq |
| Go | asynq, River |
| Polyglot / durable | Temporal, Inngest, Trigger.dev |

**Fire-and-forget vs job:** fire-and-forget is for best-effort
(acceptable to lose on crash). Jobs are for must-succeed with retries,
dead-letter queue, and visibility.

## 10. Set Timeouts Everywhere

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

PostgreSQL session defaults that stop runaway queries from pinning a
connection:

```sql
ALTER ROLE app_user SET statement_timeout = '5s';
ALTER ROLE app_user SET lock_timeout = '3s';
ALTER ROLE app_user SET idle_in_transaction_session_timeout = '30s';
```

## 11. Keep Transactions Short

Never hold a DB transaction open across HTTP calls, sleeps, locks, or
long computation. A stuck transaction pins a pool connection AND blocks
every row it touched until it commits. Ten of them and the pool is dead.

```python
# WRONG — HTTP call inside a transaction
async with db.begin():
    user = await db.get(User, user_id)
    data = await httpx_client.get("https://slow.example.com")  # 2s in txn
    user.data = data.json()

# CORRECT — read/compute first, transaction is just the write
data = await httpx_client.get("https://slow.example.com")
async with db.begin():
    user = await db.get(User, user_id)
    user.data = data.json()
```

Rules:
- No network I/O inside a transaction
- No waiting for a user / external response inside a transaction
- `SELECT ... FOR UPDATE` must have a `lock_timeout` set
- Long jobs (reports, imports) commit in batches, not one giant txn

Watch Postgres's `pg_stat_activity.state = 'idle in transaction'` —
anything there longer than a few seconds is a bug. The
`idle_in_transaction_session_timeout` from §10 kills the leaks.

## 12. Paginate Large Collections

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

## 13. Bounded Payloads + Streaming

Any endpoint that might return "a lot" must cap the response or stream it.

Rules:
- JSON list endpoints enforce `limit` (see §12) and compress with
  gzip / brotli at the server or CDN
- Exports > 10 MB → stream as NDJSON / CSV or hand out a signed S3 URL;
  never buffer in memory
- File downloads → chunked transfer, not full-read-then-send
- Long AI / SSE responses → stream chunks as they arrive; first byte
  should land in < 1s even if the full response takes 30s

```python
# Streaming CSV export — FastAPI
async def stream_csv():
    yield "id,name\n"
    async for row in fetch_rows():
        yield f"{row.id},{row.name}\n"

return StreamingResponse(stream_csv(), media_type="text/csv")
```

Cap request bodies too. FastAPI / Express / Fastify all support max
body size; default 1 MB, raise deliberately per upload endpoint.

## 14. Idempotent Writes (for retries)

Any write endpoint callable over a flaky network (mobile, webhooks,
async retries) must be idempotent. Otherwise a retry after a
timed-out-but-successful request creates duplicates.

- Accept an `Idempotency-Key` header and dedup by it (store the result
  and replay it on a second request with the same key).
- For internal retries, key off a natural unique pair — e.g.
  `(user_id, order_id)` with a unique index.
- Webhooks: include an event id; the consumer dedups on it.

## 15. Database Indexes

Every model needs indexes for:
- Primary filter columns (status, type, is_active)
- Composite indexes for common query patterns (status + sort column)
- Foreign keys used in JOINs
- Trigram indexes for fuzzy / ILIKE text search (Postgres: `gin_trgm_ops`)
- JSONB containment for array-contains queries

Run EXPLAIN on every query in a hot path during code review. If the
plan shows a sequential scan on a table with > 10k rows, add the index
before shipping.

## 16. Connection Pool Sizing

A pool too small starves the app under load; too large overwhelms the DB.

**Formula** (applies to any language / ORM):
- `pool_size    = num_workers * 2`
- `max_overflow = pool_size / 2`
- `pool_timeout = 30s` (max wait for a connection)
- `pool_recycle = 300s` (refresh stale connections)
- `pool_pre_ping = true` (verify liveness before use)

For 10k concurrent users, start at `pool_size=20, max_overflow=10`.
Monitor `pool.checkedout()` at peak; if it sits at
`pool_size + max_overflow`, raise the ceiling or add workers.

If the DB is behind a connection pooler (PgBouncer, Neon pooler), the
**app's own pool should be smaller**, not larger — the pooler handles
the fan-out. Always use the direct (non-pooled) URL for migrations.

## 17. Rate Limiting Efficiency

Rate limiting runs on every request. It must be cheap.

- 2 Redis ops per check, not 3+ (combine INCR with conditional EXPIRE)
- Skip explicit TTL reads — compute reset time from the window duration
- Use sliding-window counters only when accuracy matters; fixed-window
  buckets are almost always sufficient and cheaper

## 18. Observability Baseline

You can't fix what you can't see. Every service should emit at minimum:

| Metric | Why | Alert when |
|---|---|---|
| Request latency p50 / p95 / p99 per endpoint | Find slow endpoints | p95 > SLO |
| Error rate per endpoint (4xx separate from 5xx) | Catch regressions | 5xx rate > 0.5% |
| DB query count per request | Detect N+1 early | > 20 queries/req |
| Slow-query log (Postgres `log_min_duration_statement`) | Unindexed queries | threshold 500ms–1s |
| Cache hit rate per key prefix | Wrong TTLs, cold caches | hit rate < target |
| Pool usage (`checkedout / pool_size`) | Pool exhaustion | > 80% sustained |
| Job queue depth + oldest-job age | Workers falling behind | depth > N or age > Ys |

Export via OpenTelemetry → Prometheus / Datadog / Sentry / Grafana.
Dashboard every metric above before launch; alert on the ones with a
clear SLO. Log structured JSON with a `request_id` so traces are
reconstructable across services.

## Production Readiness Checklist

Before marking any endpoint as "done":

- [ ] No sequential independent queries (parallel with gather / Promise.all)
- [ ] No N+1 read patterns (batch-fetch related data)
- [ ] No N+1 write patterns (multi-row INSERT / COPY for bulk loads)
- [ ] Heavy columns deferred (embeddings, large text / JSONB)
- [ ] Stable data cached with appropriate TTL
- [ ] Cache-Control header set
- [ ] DB-side filtering (no full-table load + app-side filter)
- [ ] Non-critical external calls are fire-and-forget
- [ ] Must-succeed work runs in a background job, not the request
- [ ] Timeouts on every external boundary (DB, HTTP, lock)
- [ ] No network I/O inside a DB transaction
- [ ] List endpoints paginate with a capped limit
- [ ] Large responses stream, never buffer
- [ ] Write endpoints support idempotent retry
- [ ] Indexes exist for all filter / sort columns
- [ ] Connection pool sized for expected concurrency
- [ ] Latency / error-rate / query-count metrics emitted per endpoint
