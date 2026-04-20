# Global Claude Code Instructions

You have the Everything Claude Code (ECC) system installed globally. Use it.

## Workflow: Always Follow This Order

1. **Research First** — Search for existing solutions, patterns, and implementations before writing code
2. **Plan First** — Use `/plan` or the planner agent for any non-trivial feature
3. **TDD** — Use `/tdd` or tdd-guide agent. Write tests first, then implement
4. **Perf by Default** — Apply production-performance rules as you code (see Rules section). Never write sequential independent queries, N+1 patterns, or uncached stable data
5. **Data Quality by Default** — Missing values are never rendered as 0. Internal enum keys never reach users. See `rules/common/data-quality.md`
6. **Async State Safety by Default** — Mutations fire BEFORE UI transitions. Long-running flows support resume. See `rules/common/async-state-safety.md`
7. **Migration Safety by Default** — Pre-migration audit, dedup before unique index, backfill scripts for new denormalized columns. See `rules/common/migration-safety.md`
8. **Code Review** — Use `/code-review` or code-reviewer agent after writing code
9. **Content Quality Review** — Use content-quality-reviewer agent before any user-facing launch
10. **Verify** — Use `/verify` before committing

## Production from Day 1

The five rule files below are non-negotiable for any new project. Apply
them from the first commit, not as a post-launch cleanup. Each file was
extracted from real session learnings where the reverse order cost days
of rework.

| Rule File | What it prevents |
|-----------|------------------|
| `rules/common/production-performance.md` | Sequential queries, N+1, missing cache, unsized pools |
| `rules/common/data-quality.md` | Misleading zeros, internal fields in UI, silent fallthrough |
| `rules/common/async-state-safety.md` | Race conditions, lost state on navigation, polling over SSE |
| `rules/common/migration-safety.md` | Failed migrations, duplicate rows, blocking ALTER TABLEs |
| `rules/typescript/production-performance.md` | No-persistence React Query, broad invalidations, inline JSX functions |

### Day 1 Checklist

Before writing any user-facing feature code:

- [ ] Parallel-query session factory wired up (`async_session_factory` or equivalent)
- [ ] Redis cache layer available with TTL constants defined
- [ ] Response envelope + error shape standardized
- [ ] React Query persistence configured in the root provider
- [ ] `humanize.ts` helper module created (even if empty) for enum rendering
- [ ] Prioritized resolver pattern in place for any multi-source field (cost, score, category)
- [ ] Long-running async flows have a backend "active session" endpoint and frontend resume effect
- [ ] Alembic (or equivalent) uses the direct, non-pooled connection string
- [ ] Backfill scripts directory exists (`backend/scripts/`)
- [ ] CLAUDE.md for the project references which of the above are already in place

## Agents (in ~/.claude/agents/)

Delegate to specialized agents — don't do everything yourself:

| Agent | When to Use |
|-------|------------|
| **planner** (Opus) | Complex features, multi-step implementation |
| **architect** (Opus) | System design, architecture decisions, ADRs |
| **tdd-guide** (Sonnet) | Writing tests first, enforcing RED-GREEN-REFACTOR |
| **code-reviewer** (Sonnet) | Security + quality review of code changes |
| **security-reviewer** (Sonnet) | OWASP Top 10, secrets detection, auth checks |
| **build-error-resolver** (Sonnet) | TypeScript/build errors — minimal fixes only |
| **go-build-resolver** (Sonnet) | Go compilation errors |
| **go-reviewer** (Sonnet) | Go-specific: race conditions, error wrapping, idioms |
| **python-reviewer** (Sonnet) | Python-specific: type hints, PEP 8, framework checks |
| **database-reviewer** (Sonnet) | Query optimization, schema design, RLS |
| **e2e-runner** (Sonnet) | Playwright E2E test generation |
| **refactor-cleaner** (Sonnet) | Dead code detection and removal |
| **doc-updater** (Haiku) | Documentation and codemap generation |
| **chief-of-staff** (Opus) | Email/Slack triage, communication drafts |
| **ui-ux-architect** | Visual design audit and refinement |

## Commands (in ~/.claude/commands/)

### Most Important
- `/plan` — Implementation planning before coding
- `/tdd` — Test-Driven Development workflow
- `/code-review` — Security + quality review
- `/verify` — Full check: build + types + lint + tests
- `/build-fix` — Auto-fix build errors incrementally
- `/e2e` — Generate and run E2E tests
- `/orchestrate` — Chain agents for complex tasks

### Code Quality
- `/test-coverage` — Analyze gaps, generate missing tests
- `/refactor-clean` — Find and remove dead code
- `/go-review` — Go-specific code review
- `/python-review` — Python-specific code review

### Learning
- `/learn` — Extract reusable patterns from session
- `/skill-create` — Generate skills from git history
- `/instinct-status` — Show learned instincts

### Project Management
- `/sessions` — Manage session history
- `/checkpoint` — Create development checkpoints
- `/setup-pm` — Configure package manager

## Skills (in ~/.claude/skills/)

Skills activate automatically when relevant. Key ones:

**Frontend**: frontend-patterns, coding-standards, e2e-testing, liquid-glass-design
**Backend**: backend-patterns, api-design, django-patterns, springboot-patterns
**Database**: postgres-patterns, clickhouse-io, database-migrations, jpa-patterns
**Go**: golang-patterns, golang-testing
**Python**: python-patterns, python-testing, django-tdd, django-security
**C++**: cpp-coding-standards, cpp-testing
**Swift**: swiftui-patterns, swift-concurrency-6-2
**Java**: java-coding-standards, springboot-tdd
**Infra**: docker-patterns, deployment-patterns
**Testing**: tdd-workflow, eval-harness, verification-loop, security-review
**AI/LLM**: cost-aware-llm-pipeline, iterative-retrieval

## Rules (in ~/.claude/rules/)

Rules are always enforced:
- **Immutability** — Create new objects, never mutate
- **File size** — 200-400 lines ideal, 800 max
- **Functions** — Max 50 lines, no nesting > 4 levels
- **Security** — No hardcoded secrets, validate all input, parameterized queries
- **Testing** — 80%+ coverage mandatory
- **Git** — Conventional commits (feat:, fix:, refactor:, docs:, test:)
- **Production Perf (Backend)** — Parallel queries, batch fetch, Redis cache, deferred columns, SQL filtering, fire-and-forget external calls, composite indexes, pool sizing (see `rules/common/production-performance.md`)
- **Production Perf (Frontend)** — React Query persistence, explicit staleTime, scoped invalidation, Zustand selectors, no unoptimized images, SSE before polling (see `rules/typescript/production-performance.md`)

## Code Style

- No emojis in code, comments, or documentation
- Prefer immutability
- Many small files over few large files
- Proper error handling at every level
- Input validation at system boundaries

## When Starting a New Project

1. Copy a template CLAUDE.md from `~/.claude/examples/` to the project root
2. Available templates: saas-nextjs, django-api, go-microservice, rust-api, generic
3. Customize it for the specific project
4. The project CLAUDE.md + this global CLAUDE.md both apply

## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately -- don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes -- don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests -- then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.

## Reference

Full usage guide: `~/.claude/ECC-USAGE-GUIDE.md`
