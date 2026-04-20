# Git Workflow

## Commit Message Format
```
<type>: <description>

<optional body>
```

Types: feat, fix, refactor, docs, test, chore, perf, ci

Note: Attribution disabled globally via ~/.claude/settings.json.

## Pull Request Workflow

When creating PRs:
1. Analyze full commit history (not just latest commit)
2. Use `git diff [base-branch]...HEAD` to see all changes
3. Draft comprehensive PR summary
4. Include test plan with TODOs
5. Push with `-u` flag if new branch

> For the full development process (planning, TDD, code review) before git operations,
> see [development-workflow.md](./development-workflow.md).

## Batch-and-Commit Strategy for Audit-Driven Fixes

When a code review, content audit, or performance audit finds 10+ issues,
do NOT ship them as one monolithic commit. Batch by category so that:

- Each commit has a single, reviewable theme
- Reverts are surgical (roll back one bucket without losing others)
- The commit log doubles as documentation of which pattern was applied where
- Reviewers can verify one rule at a time instead of context-switching per file

### How to batch

Group findings by the **type of fix**, not by the file they live in.
Examples:

| Audit source | Good batches |
|--------------|--------------|
| Code review | 1) correctness bugs, 2) performance, 3) code quality, 4) frontend, 5) verification |
| Content audit | 1) humanize helper module, 2) RENAME per surface, 3) RELABEL pricing, 4) RELABEL charts, 5) GUARD grids, 6) HIDE internal |
| Performance audit | 1) parallel queries, 2) batch-fetch N+1, 3) defer heavy columns, 4) cache layer, 5) indexes |
| Security audit | 1) secrets rotation, 2) input validation, 3) authz checks, 4) rate limits |

### Commit message shape

Each batch commit names the category and the surface:

```
perf: parallelize dashboard queries with separate sessions
content: rename company_stage via humanize helper on tool cards
fix: resolve Stack Builder cost $0 bug via prioritized resolver
migration: dedup tool_pricing current rows before unique index
```

### Checkpoint after each batch

Run the relevant checks (`pytest`, `pnpm build`, `pnpm e2e`) BETWEEN
batches so a failure is attributable to a single category. Don't stack
six batches unverified and hope.

### Plan-mode doc as source of truth

For multi-phase audits, keep a plan file (`tasks/todo.md` or plan-mode
doc) with the batches as checkboxes. Mark each batch complete as it
ships. This is the artifact that lets you resume a multi-day audit
after context loss.
