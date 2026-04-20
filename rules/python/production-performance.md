# Python Production Performance

> Extends [common/production-performance.md](../common/production-performance.md)
> with Python/FastAPI/SQLAlchemy-specific patterns.

## SQLAlchemy Async Session Safety

- AsyncSession is NOT safe for concurrent use from multiple coroutines
- For parallel queries, create separate sessions via `async_session_factory()`
- Write operations must use the request-scoped session (needs commit)
- Read-only queries can safely use throwaway sessions in `asyncio.gather`

```python
# Safe parallel reads with separate sessions
async def _query_a():
    async with async_session_factory() as s:
        return await s.execute(stmt_a)

async def _query_b():
    async with async_session_factory() as s:
        return await s.execute(stmt_b)

a, b = await asyncio.gather(_query_a(), _query_b())
```

## SQLAlchemy Deferred Columns

Use `deferred()` for columns not needed in list queries:

```python
from sqlalchemy.orm import deferred

embedding = deferred(mapped_column(Vector(768), nullable=True))
```

Candidates: embeddings, search vectors, full content text, large JSONB metadata.

## FastAPI Response Headers

Always set Cache-Control via `Response` parameter:

```python
@router.get("/endpoint")
async def handler(response: Response):
    response.headers["Cache-Control"] = "private, max-age=300"
    return data
```

## Upstash Redis (REST-based)

Each Redis operation is an HTTP request (~10-50ms). Minimize round-trips:
- Combine INCR + EXPIRE (2 ops, not 3)
- Skip TTL calls when you can compute from window
- Cache reads before writes (check cache, skip DB if hit)

## JSONB Query Operators (PostgreSQL)

Use SQL operators instead of loading data into Python:
- `?` — contains key/element: `Column.op("?")(value)`
- `?|` — contains any: `Column.op("?|")(pg_array(values))`
- `@>` — contains JSONB: `Column.op("@>")(json_value)`

## Index Types for PostgreSQL

- B-tree (default): equality, range, sorting
- GIN + `gin_trgm_ops`: fuzzy/ILIKE text search (requires pg_trgm extension)
- GIN: JSONB containment, array operations
- GiST/IVFFlat/HNSW: pgvector similarity search
