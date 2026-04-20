# Everything Claude Code (ECC) - Usage Guide

## What's Installed

Everything has been installed to `~/.claude/` so it works globally across all your projects:

```
~/.claude/
  agents/       → 15 specialized sub-agents
  commands/     → 35 slash commands
  skills/       → 56 domain knowledge skills
  rules/        → Coding rules (common + typescript + python + golang + swift)
  ecc-scripts/  → Hook scripts and utilities
  contexts/     → Behavioral modes (dev, research, review)
  examples/     → CLAUDE.md templates for different project types
  settings.json → Hooks configuration (auto-format, type-check, session persistence, etc.)
```

---

## Quick Start - The 5 Commands You'll Use Most

| Command | What It Does | When to Use |
|---------|-------------|-------------|
| `/plan` | Creates a detailed implementation plan before coding | Starting any non-trivial feature |
| `/tdd` | Test-Driven Development: write tests first, then implement | Writing any new code |
| `/code-review` | Security + quality review of uncommitted changes | Before committing |
| `/verify` | Full verification: build + types + lint + tests + git status | Before pushing |
| `/build-fix` | Auto-fix build/type errors one at a time | When builds break |

---

## All 35 Commands Reference

### Core Development

| Command | Description |
|---------|-------------|
| `/plan` | Create implementation plan with risk assessment. Uses the **planner** agent (Opus model) |
| `/tdd` | Test-Driven Development. RED -> GREEN -> REFACTOR cycle. 80%+ coverage enforced |
| `/code-review` | Review uncommitted code for security issues, code quality, best practices |
| `/e2e` | Generate and run end-to-end tests with Playwright |
| `/build-fix` | Fix build errors incrementally. Auto-detects build system (npm, cargo, go, maven) |
| `/verify` | Comprehensive check: build, types, lint, tests, console.log audit, git status |
| `/orchestrate` | Chain multiple agents for complex tasks (e.g., plan -> tdd -> review -> security) |

### Code Quality & Analysis

| Command | Description |
|---------|-------------|
| `/test-coverage` | Analyze coverage gaps and generate missing tests. Target: 80%+ |
| `/refactor-clean` | Find and remove dead code safely. Uses knip/depcheck/ts-prune |
| `/update-docs` | Sync documentation from source of truth (package.json, .env, OpenAPI) |
| `/update-codemaps` | Generate architecture documentation from codebase |
| `/go-review` | Go-specific review: go vet, staticcheck, race detection |
| `/python-review` | Python-specific review: mypy, ruff, bandit, type hints |

### Language-Specific TDD

| Command | Description |
|---------|-------------|
| `/go-test` | Go TDD with table-driven tests |
| `/go-build` | Fix Go build errors (go build, go vet, staticcheck) |

### Learning & Pattern Extraction

| Command | Description |
|---------|-------------|
| `/learn` | Extract reusable patterns from current session |
| `/learn-eval` | Extract patterns with quality scoring (must score 3+/5 on all dimensions) |
| `/skill-create` | Generate skill files from git history |
| `/instinct-status` | Show all learned instincts with confidence scores |
| `/instinct-import` | Import instincts from file or URL |
| `/instinct-export` | Export instincts to shareable YAML |
| `/promote` | Promote project instincts to global scope |
| `/evolve` | Analyze instincts and suggest new commands/skills/agents |

### Project Management

| Command | Description |
|---------|-------------|
| `/sessions` | Manage session history (list, load, alias) |
| `/checkpoint` | Create and verify development checkpoints |
| `/eval` | Eval-driven development: define, check, report on evaluations |
| `/projects` | List projects with instinct statistics |

### Multi-Model Collaboration

| Command | Description |
|---------|-------------|
| `/multi-plan` | Collaborative planning with Codex + Gemini |
| `/multi-backend` | Backend development led by Codex |
| `/multi-frontend` | Frontend development led by Gemini |
| `/multi-workflow` | Full workflow with intelligent model routing |
| `/multi-execute` | Implementation from an existing plan |

### System

| Command | Description |
|---------|-------------|
| `/setup-pm` | Configure preferred package manager (npm/pnpm/yarn/bun) |
| `/pm2` | Auto-generate PM2 configs for your services |
| `/claw` | NanoClaw agent REPL with persistent sessions |

---

## 15 Agents - When They Activate

Agents are specialized sub-processes that handle domain tasks. Claude delegates to them automatically or you can invoke them through commands.

| Agent | Model | Triggers Via | What It Does |
|-------|-------|-------------|-------------|
| **planner** | Opus | `/plan` | Breaks down complex features into phases with risks |
| **architect** | Opus | Architecture questions | System design, ADRs, scalability analysis |
| **tdd-guide** | Sonnet | `/tdd` | Enforces write-tests-first, 80%+ coverage |
| **code-reviewer** | Sonnet | `/code-review` | Security + quality + best practices review |
| **security-reviewer** | Sonnet | Security concerns | OWASP Top 10, secrets detection, auth verification |
| **build-error-resolver** | Sonnet | `/build-fix` | Fixes TypeScript/build errors minimally |
| **go-build-resolver** | Sonnet | `/go-build` | Fixes Go compilation errors |
| **go-reviewer** | Sonnet | `/go-review` | Idiomatic Go review, race detection |
| **python-reviewer** | Sonnet | `/python-review` | Pythonic code review, type hints, framework checks |
| **database-reviewer** | Sonnet | DB questions | Query optimization, schema design, RLS |
| **e2e-runner** | Sonnet | `/e2e` | Playwright test generation and execution |
| **refactor-cleaner** | Sonnet | `/refactor-clean` | Dead code detection and safe removal |
| **doc-updater** | Haiku | `/update-docs` | Documentation and codemap generation |
| **chief-of-staff** | Opus | Communication tasks | Email/Slack triage and draft responses |
| **ui-ux-architect** | - | Design reviews | Visual design audit and refinement |

---

## 56 Skills - Domain Knowledge Library

Skills are activated automatically when relevant. They inject best practices and patterns into Claude's responses.

### Web Development
- **frontend-patterns** - React/Next.js composition, hooks, state, performance, a11y
- **backend-patterns** - Node.js services, repos, caching, middleware, error handling
- **api-design** - REST conventions, pagination, filtering, versioning, rate limiting
- **coding-standards** - Universal TypeScript/JavaScript/React standards
- **e2e-testing** - Playwright patterns, Page Object Model, flaky test mitigation
- **frontend-slides** - Zero-dependency HTML presentations

### Python
- **django-patterns** - Django architecture, DRF, ORM, caching
- **django-security** - Auth, CSRF, XSS, SQL injection prevention
- **django-tdd** - TDD with pytest-django, factory-boy
- **django-verification** - Quality loop: migrations, linting, tests, security
- **python-patterns** - Pythonic idioms, PEP 8, type hints
- **python-testing** - pytest, TDD, fixtures, parametrization

### Go
- **golang-patterns** - Idiomatic Go, error wrapping, concurrency, interfaces
- **golang-testing** - Table-driven tests, subtests, benchmarks

### Java / Spring Boot
- **java-coding-standards** - Java conventions for Spring Boot
- **springboot-patterns** - Architecture, REST, layered services, caching
- **springboot-security** - Spring Security, auth, validation
- **springboot-tdd** - JUnit 5, Mockito, Testcontainers
- **jpa-patterns** - JPA/Hibernate entities, relationships

### C++
- **cpp-coding-standards** - Modern C++17/20/23: RAII, smart pointers, concurrency
- **cpp-testing** - GoogleTest/GMock, TDD, sanitizers

### Swift / iOS
- **swiftui-patterns** - SwiftUI layouts, state management, animations
- **swift-concurrency-6-2** - async/await, actors, structured concurrency
- **swift-actor-persistence** - Actor model, thread-safe state
- **swift-protocol-di-testing** - Protocol-based DI, testability

### Database
- **postgres-patterns** - Query optimization, schema, indexing, security
- **clickhouse-io** - Analytics patterns, MergeTree, materialized views
- **database-migrations** - Safe schema changes, zero-downtime, expand-contract

### Infrastructure
- **docker-patterns** - Compose, multi-stage builds, networking, secrets
- **deployment-patterns** - CI/CD, rolling/blue-green/canary, health checks, rollback
- **content-hash-cache-pattern** - SHA-256 based file caching

### Testing & Quality
- **tdd-workflow** - TDD methodology, red-green-refactor
- **eval-harness** - Eval-driven development, pass@k metrics
- **verification-loop** - Verification and quality patterns
- **security-review** - Security checklist: auth, input, secrets, APIs

### AI / LLM
- **cost-aware-llm-pipeline** - Model routing, budget tracking, prompt caching
- **iterative-retrieval** - Progressive context refinement
- **regex-vs-llm-structured-text** - When to use regex vs LLM for parsing

### Content & Business
- **article-writing** - Long-form content matching voice and structure
- **content-engine** - Platform-native social content (X, LinkedIn, TikTok)
- **market-research** - Source-attributed research on markets and competitors
- **investor-materials** - Pitch decks, one-pagers, financial models
- **investor-outreach** - Personalized cold emails, warm intros

### Other
- **liquid-glass-design** - Apple glass morphism design patterns
- **strategic-compact** - Manual context compaction at logical intervals
- **search-first** - Search-first workflows for research
- **continuous-learning** / **continuous-learning-v2** - Auto-extract reusable patterns

---

## Hooks - What Happens Automatically

These fire without you doing anything:

### Before Tool Execution (PreToolUse)
| What | Effect |
|------|--------|
| Dev server blocker | **BLOCKS** `npm run dev` outside tmux (use tmux for log access) |
| Tmux reminder | Suggests tmux for long-running commands |
| Git push reminder | Reminds to review before `git push` |
| Doc file warning | Warns about non-standard .md files |
| Compact suggestion | Suggests `/compact` every ~50 tool calls |

### After Tool Execution (PostToolUse)
| What | Effect |
|------|--------|
| PR logger | Shows PR URL after `gh pr create` |
| Auto-format | Formats JS/TS files after edits (Biome or Prettier) |
| TypeScript check | Runs `tsc --noEmit` after editing .ts/.tsx |
| console.log warning | Warns about console.log in edited files |

### Lifecycle
| What | Effect |
|------|--------|
| Session start | Loads previous context, detects package manager |
| Pre-compact | Saves state before context compaction |
| Console.log audit | Final check for console.log after each response |
| Session end | Persists session state for next session |
| Pattern extraction | Evaluates session for learnable patterns |

---

## Rules - What's Enforced

Rules are always-on guidelines loaded automatically from `~/.claude/rules/`.

### Common Rules (All Languages)
- **Immutability**: Always create new objects, never mutate
- **File size**: 200-400 lines ideal, max 800
- **Functions**: Max 50 lines, no deep nesting (>4 levels)
- **Security**: No hardcoded secrets, validate all input, parameterized queries
- **Testing**: 80%+ coverage mandatory, unit + integration + E2E
- **Git**: Conventional commits (`feat:`, `fix:`, `refactor:`, etc.)
- **Workflow**: Research -> Plan -> TDD -> Review -> Commit

### Language-Specific Extensions
- **TypeScript**: Zod validation, Prettier formatting, React patterns
- **Python**: Pydantic, ruff/black formatting, Django/FastAPI patterns
- **Go**: gofmt, error wrapping, goroutine safety, table-driven tests
- **Swift**: SwiftUI patterns, actor concurrency, protocol-based DI

---

## Contexts - Behavioral Modes

Set the mode by referencing the context file:

| Context | Behavior |
|---------|----------|
| `dev.md` | Active development: write code first, explain after |
| `research.md` | Exploration: read widely before concluding |
| `review.md` | Code review: focus on quality, security, patterns |

---

## Example CLAUDE.md Templates

Templates are available in `~/.claude/examples/` for bootstrapping new projects:

| Template | For |
|----------|-----|
| `saas-nextjs-CLAUDE.md` | Next.js SaaS applications |
| `django-api-CLAUDE.md` | Django REST API projects |
| `go-microservice-CLAUDE.md` | Go microservices |
| `rust-api-CLAUDE.md` | Rust API projects |
| `CLAUDE.md` | Generic project template |
| `user-CLAUDE.md` | User-level CLAUDE.md template |

To use: copy the relevant template to your project root as `CLAUDE.md` and customize.

---

## Workflow Examples

### Building a New Feature (Full Workflow)

```
You: /plan Add user authentication with JWT

  -> Planner agent creates detailed implementation plan
  -> You review and approve

You: /tdd Implement the auth module from the plan

  -> TDD Guide writes failing tests first
  -> Implements minimal code to pass
  -> Refactors for quality

You: /code-review

  -> Code Reviewer checks security, quality, patterns
  -> Reports CRITICAL/HIGH/MEDIUM/LOW issues

You: /verify

  -> Runs build, types, lint, tests, console.log audit
  -> Reports pass/fail for each check
```

### Fixing a Bug

```
You: /tdd Fix the race condition in the order processing

  -> TDD Guide writes a test that reproduces the bug (RED)
  -> Implements the fix (GREEN)
  -> Ensures no regressions
```

### Before a PR

```
You: /verify full
You: /code-review
You: Create a PR for the auth feature
```

### Learning from a Session

```
You: /learn

  -> Extracts reusable patterns from current session
  -> Saves to ~/.claude/skills/learned/

You: /instinct-status

  -> Shows all learned patterns with confidence scores
```

### Quick Build Fix

```
You: /build-fix

  -> Detects build system
  -> Reads error output
  -> Fixes one error at a time
  -> Re-verifies after each fix
```

---

## Customization

### Disabling a Hook

Remove or comment out entries in `~/.claude/settings.json` under the `hooks` key. For example, to disable the dev server blocker, remove the first PreToolUse entry.

### Adding Your Own Rules

Create `.md` files in `~/.claude/rules/common/` (applies to all languages) or `~/.claude/rules/<language>/` for language-specific rules.

### Creating Custom Skills

1. Create a directory: `~/.claude/skills/my-skill/`
2. Add a `SKILL.md` file with:
   - Frontmatter: `name`, `description`
   - "When to Activate" section
   - Core patterns and code examples
   - Best practices and anti-patterns

### Package Manager

```
/setup-pm
```

Or set the environment variable: `export CLAUDE_PACKAGE_MANAGER=bun`

---

## Troubleshooting

### Hooks not firing
- Check `~/.claude/settings.json` has the hooks configuration
- Ensure script paths point to `~/.claude/ecc-scripts/hooks/`
- Test a hook manually: `echo '{}' | node ~/.claude/ecc-scripts/hooks/session-start.js`

### Dev server blocked
The tmux hook blocks `npm run dev` outside tmux. Either:
- Use tmux: `tmux new-session -d -s dev "npm run dev"`
- Or remove the first PreToolUse hook from settings.json

### Commands not found
Ensure commands are in `~/.claude/commands/`. Check with: `ls ~/.claude/commands/`

### Skills not loading
Ensure skills are in `~/.claude/skills/`. Each skill needs a `SKILL.md` file in its directory.

---

## File Locations Reference

| What | Where |
|------|-------|
| Settings + hooks | `~/.claude/settings.json` |
| Rules | `~/.claude/rules/{common,typescript,python,golang,swift}/` |
| Agents | `~/.claude/agents/*.md` |
| Commands | `~/.claude/commands/*.md` |
| Skills | `~/.claude/skills/*/SKILL.md` |
| Hook scripts | `~/.claude/ecc-scripts/hooks/` |
| Contexts | `~/.claude/contexts/` |
| Example templates | `~/.claude/examples/` |
| Learned patterns | `~/.claude/skills/learned/` (created by `/learn`) |
| Session data | `~/.claude/sessions/` (created by hooks) |
| Source repo | Everything Claude Code (ECC) — see `~/.claude/README.md` |
