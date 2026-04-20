# Common Patterns

## Skeleton Projects

When implementing new functionality:
1. Search for battle-tested skeleton projects
2. Use parallel agents to evaluate options:
   - Security assessment
   - Extensibility analysis
   - Relevance scoring
   - Implementation planning
3. Clone best match as foundation
4. Iterate within proven structure

## Design Patterns

### Repository Pattern

Encapsulate data access behind a consistent interface:
- Define standard operations: findAll, findById, create, update, delete
- Concrete implementations handle storage details (database, API, file, etc.)
- Business logic depends on the abstract interface, not the storage mechanism
- Enables easy swapping of data sources and simplifies testing with mocks

### API Response Format

Use a consistent envelope for all API responses:
- Include a success/status indicator
- Include the data payload (nullable on error)
- Include an error message field (nullable on success)
- Include metadata for paginated responses (total, page, limit)

### Parallel Query Pattern

When an endpoint aggregates data from multiple independent sources,
run them concurrently with separate DB sessions:

```
# Pseudocode — applies to Python (asyncio.gather) and JS (Promise.all)
results = await parallel(
    heavy_query(request_session),    # may write, uses request session
    read_only_query_1(new_session),  # read-only, own session
    read_only_query_2(new_session),  # read-only, own session
)
```

### Redis Cache Layer Pattern

For data that changes infrequently, add a Redis cache layer:

```
cache_key = build_key(entity, params)
cached = await redis.get(cache_key)
if cached: return deserialize(cached)

result = await expensive_query(db)
await redis.set(cache_key, serialize(result), ttl=appropriate_seconds)
return result
```

TTL guide: taxonomy=24h, trending=1h, per-user=60s, search=5min

### Batch Fetch Pattern

When you need related data for a list of entities, always batch:

```
# Fetch all related data in one query
related_map = batch_fetch(entity_ids)

# Look up per entity (O(1) per lookup)
for entity in entities:
    entity.related = related_map.get(entity.id, [])
```
