# Performance Optimization

## Model Selection Strategy

**Haiku 4.5** (90% of Sonnet capability, 3x cost savings):
- Lightweight agents with frequent invocation
- Pair programming and code generation
- Worker agents in multi-agent systems

**Sonnet 4.6** (Best coding model):
- Main development work
- Orchestrating multi-agent workflows
- Complex coding tasks

**Opus 4.5** (Deepest reasoning):
- Complex architectural decisions
- Maximum reasoning requirements
- Research and analysis tasks

## Context Window Management

Avoid last 20% of context window for:
- Large-scale refactoring
- Feature implementation spanning multiple files
- Debugging complex interactions

Lower context sensitivity tasks:
- Single-file edits
- Independent utility creation
- Documentation updates
- Simple bug fixes

## Extended Thinking + Plan Mode

Extended thinking is enabled by default, reserving up to 31,999 tokens for internal reasoning.

Control extended thinking via:
- **Toggle**: Option+T (macOS) / Alt+T (Windows/Linux)
- **Config**: Set `alwaysThinkingEnabled` in `~/.claude/settings.json`
- **Budget cap**: `export MAX_THINKING_TOKENS=10000`
- **Verbose mode**: Ctrl+O to see thinking output

For complex tasks requiring deep reasoning:
1. Ensure extended thinking is enabled (on by default)
2. Enable **Plan Mode** for structured approach
3. Use multiple critique rounds for thorough analysis
4. Use split role sub-agents for diverse perspectives

## Production Performance (CRITICAL)

Apply these from the START of every project, not post-launch:

- **Backend**: See [production-performance.md](./production-performance.md)
  - Parallelize independent queries (asyncio.gather / Promise.all)
  - Batch-fetch related data (no N+1)
  - Defer heavy columns (embeddings, large text)
  - Cache stable data in Redis (taxonomy=24h, trending=1h, per-user=60s)
  - Set Cache-Control headers on every endpoint
  - SQL-level filtering (never load-all + Python filter)
  - Fire-and-forget non-critical external calls
  - Composite indexes for common query patterns
  - Pool size = workers * 2, overflow = pool / 2

- **Frontend**: See [typescript/production-performance.md](../typescript/production-performance.md)
  - React Query localStorage persistence (instant cold starts)
  - Explicit staleTime on every useQuery
  - Scoped cache invalidation on mutations
  - Zustand selectors (never destructure whole store)
  - No `unoptimized` on Next.js Image
  - SSE before polling (with timeout fallback)
  - Dynamic imports for heavy components

**When to run a performance audit**: Before launch, after adding 3+ new endpoints,
or when any page takes >500ms to load. Use **database-reviewer** agent for query
optimization and **architect** agent for system-level review.

## Build Troubleshooting

If build fails:
1. Use **build-error-resolver** agent
2. Analyze error messages
3. Fix incrementally
4. Verify after each fix
