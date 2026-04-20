# Migration Safety

> Rules for writing database migrations that don't break production.
> Derived from real migrations that had to be rolled back because they
> failed against existing data or took down replicas.

## 1. Pre-migration data quality audit (CRITICAL)

Before adding ANY constraint (CHECK, NOT NULL, UNIQUE, FOREIGN KEY) to
an existing table, count how many current rows would violate the
invariant. If violations exist, you have three options — pick one
explicitly, never ship blind.

```
# Pseudocode audit
async def audit_new_constraint():
    async with engine.connect() as conn:
        # For a new CHECK: count rows that fail the predicate
        count = await conn.execute(text("""
            SELECT count(*) FROM tool_pricing
            WHERE NOT (
                price_monthly IS NOT NULL
                OR is_free = TRUE
                OR is_enterprise = TRUE
            )
        """))
        return count.scalar()

# Run this BEFORE writing the migration. If > 0, decide:
#   1. Fix the rows in the migration (dedup, backfill default)
#   2. Defer the constraint to a later migration + document
#   3. Relax the constraint to match current data
```

Never add a constraint without running this audit. Migrations that fail
mid-deploy leave the database in a half-applied state that is
non-trivial to recover from.

## 2. Dedup in the migration, then add the unique index

When adding a unique index to data that already has duplicates, the
migration MUST clean up the duplicates first. Typical pattern:

```
def upgrade():
    # Step 1: Demote duplicate "current" rows, keeping the most recent
    op.execute("""
        WITH ranked AS (
            SELECT id,
                   row_number() OVER (
                       PARTITION BY tool_id, lower(tier_name)
                       ORDER BY effective_date DESC NULLS LAST,
                                created_at DESC NULLS LAST
                   ) AS rn
            FROM tool_pricing
            WHERE is_current = TRUE
        )
        UPDATE tool_pricing
        SET is_current = FALSE,
            superseded_at = COALESCE(superseded_at, now()),
            change_description = COALESCE(
                change_description,
                'auto-demoted by {migration_name} (duplicate current row)'
            )
        WHERE id IN (SELECT id FROM ranked WHERE rn > 1)
    """)

    # Step 2: Now safe to add the partial unique index
    op.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS uq_tool_pricing_current_tier
        ON tool_pricing (tool_id, lower(tier_name))
        WHERE is_current = TRUE
    """)
```

Key points:
- Preserve the demoted rows (set `is_current = FALSE`, don't DELETE)
  so history is intact for audit
- Write a `change_description` so a future engineer can grep for it
- Use `IF NOT EXISTS` so the migration is re-runnable on a partial
  failure
- Test the query against a staging copy of prod data before shipping

## 3. Partial unique indexes with `lower()` for case-insensitive dedup

For "only one row can be current per (foreign_key, name)" invariants
where name comparisons should be case-insensitive:

```
CREATE UNIQUE INDEX uq_tool_pricing_current_tier
ON tool_pricing (tool_id, lower(tier_name))
WHERE is_current = TRUE;
```

This enforces at the DB level that two `is_current = TRUE` rows can't
coexist for the same `(tool_id, tier_name)` regardless of case. Any
code that would create a duplicate will fail with IntegrityError at
the SQL layer, which is exactly what you want.

## 4. Defer CHECK constraints when data is dirty

If a CHECK constraint would fail against existing data and you can't
safely fix the data in the same migration (too large, too risky,
needs business input), document the deferral explicitly in the
migration module docstring:

```
"""stack_cost_accuracy

Revision ID: w1x2y3z4a5b6
...

NOTE: A CHECK constraint on tool_pricing enforcing that price_monthly
can only be NULL for free/enterprise tiers was originally planned here,
but the existing table has ~2641 pre-existing paid rows with NULL
price_monthly from enrichment gaps. Adding the constraint would fail
the migration.

The cost resolver handles NULL price_monthly explicitly (treats it as
"unknown", logs a warning, falls back to LLM estimate), so the
constraint is deferred to a separate data-quality migration once those
rows are either re-enriched or correctly classified as free/enterprise.
See docs/backlog for the follow-up.
"""
```

The deferral is a commitment to revisit, not a silent skip. Add to your
backlog tracker so it doesn't get lost.

## 5. Backfill scripts for derived/denormalized columns

Whenever you add a new denormalized column (or change how one is
computed), write a one-shot backfill script for existing rows. Don't
rely on "it'll fill in on next write" — most rows never get written
again.

```
# backend/scripts/backfill_<feature>_<column>.py

Usage:
    cd backend
    uv run python scripts/backfill_workflow_costs.py
    uv run python scripts/backfill_workflow_costs.py --dry-run
    uv run python scripts/backfill_workflow_costs.py --batch-size 50

Processes NULL-column rows in batches of N, each in its own session
(so one failure doesn't abort the batch), logs success/failure counts,
prints a summary at the end with a distribution of any branch
classifications (if using a resolver).
```

The script should be:
- **Idempotent**: running it twice produces the same result
- **Batched**: 50-100 rows per batch, not all-at-once
- **Per-row sessions**: so one failure doesn't corrupt the batch
- **Observable**: counter summary at the end
- **Safe by default**: support `--dry-run` that reports without writing
- **One-shot**: not a scheduled job — run it post-deploy and delete

## 6. Alembic on Neon (or any PgBouncer): use direct connection

Alembic DDL is incompatible with PgBouncer transaction mode. If your
prod DB runs behind a pooler (Neon does), the migration runner MUST
use the direct (non-pooled) connection string, not the pooled one.

```
# .env
DATABASE_URL=postgresql+asyncpg://...-pooler.neon.tech/...  # app
DATABASE_URL_DIRECT=postgresql+asyncpg://...neon.tech/...    # migrations

# alembic/env.py
config.set_main_option(
    "sqlalchemy.url",
    os.environ["DATABASE_URL_DIRECT"],  # NOT DATABASE_URL
)
```

Symptom if you get this wrong: migrations that create indexes or run
DDL inside a transaction hang or fail with `ERROR: prepared statement
"..." does not exist`.

## 7. Make migrations re-runnable with IF NOT EXISTS / IF EXISTS

Every CREATE INDEX should be `IF NOT EXISTS`; every DROP should be
`IF EXISTS`. Every ADD COLUMN can use `ADD COLUMN IF NOT EXISTS` on
Postgres 9.6+. This makes a failed migration safe to re-run without
manual cleanup.

```
# Good
op.execute("CREATE UNIQUE INDEX IF NOT EXISTS uq_foo ON bar (...)")
op.execute("DROP INDEX IF EXISTS old_idx")
op.execute("ALTER TABLE workflows ADD COLUMN IF NOT EXISTS cost_source VARCHAR(32)")

# Bad
op.execute("CREATE INDEX uq_foo ON bar (...)")  # fails if partial run
```

## 8. Non-blocking column adds

`ALTER TABLE foo ADD COLUMN bar ... NULL` is non-blocking on Postgres
11+ (catalog-only change). `ADD COLUMN ... NOT NULL DEFAULT ...` IS
blocking because it rewrites every row.

**Rule:** Add new columns as nullable or with no default. If you need
to backfill with a value, use a separate backfill script after the
column exists. If you need NOT NULL, do it in a third migration after
the backfill completes.

```
# Migration 1: add nullable column
op.add_column("workflows", sa.Column("cost_source", sa.String(32), nullable=True))

# Post-deploy: run scripts/backfill_cost_source.py

# Migration 2: NOT NULL (only after backfill is complete everywhere)
op.alter_column("workflows", "cost_source", nullable=False)
```

## 9. Migration rollback is additive-safe

Design migrations so the `downgrade()` is safe with live traffic. In
practice:
- `DROP COLUMN` is safe (catalog-only on Postgres)
- `DROP INDEX IF EXISTS` is safe
- Constraint drops are safe
- Data mutations (dedup, backfill) are NOT safe to reverse — document
  that the downgrade is one-way

Example of an honest rollback note:

```
def downgrade() -> None:
    # Note: we do NOT restore the demoted duplicate rows on downgrade —
    # they are preserved in place with is_current=FALSE, so history
    # is intact but cannot be safely un-demoted.
    op.execute("DROP INDEX IF EXISTS uq_tool_pricing_current_tier")
    op.drop_column("workflow_steps", "cost_source")
```

## 10. Test migrations on a prod snapshot before deploy

For any migration touching > 10k rows or adding constraints, run it
against a recent snapshot of production data in a staging environment
before merging. Don't rely on unit-test fixtures — they can't catch
data quality issues.

```
# Dry-run on prod snapshot
uv run alembic upgrade head --sql | tee /tmp/migration.sql
# review the SQL
# apply to staging clone
psql $STAGING_URL < /tmp/migration.sql
# verify row counts, constraint satisfaction, and app boot
```

## Migration Safety Checklist

Before merging any migration:

- [ ] Pre-migration audit: counted violating rows for each new constraint
- [ ] Dedup step in the migration if adding a unique index to existing data
- [ ] Deferred constraints have a docstring explaining why
- [ ] Backfill script exists for any new denormalized column
- [ ] Migration uses `IF NOT EXISTS` / `IF EXISTS` everywhere
- [ ] New columns are nullable or have no default (non-blocking)
- [ ] NOT NULL is a separate migration after the backfill
- [ ] `downgrade()` is safe with live traffic, or documented as one-way
- [ ] Alembic uses a direct connection string, not a pooled one
- [ ] Migration tested against a prod snapshot for tables > 10k rows
