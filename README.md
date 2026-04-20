# claude-setup

A production-grade [Claude Code](https://claude.com/claude-code) configuration.
Clone it, run `./install.sh`, and every future Claude Code session on that
machine boots with senior-engineer defaults: research-first, plan-first, TDD,
code review, verify, ship.

No per-session setup. No "remind Claude what to do." The rules are loaded
automatically on every new session.

---

## Install (30 seconds)

```bash
git clone https://github.com/RohitBind123/claude-setup.git
cd claude-setup
./install.sh
```

That's it. Open a new Claude Code session and type `/plan` to confirm it works.

> **Already have a `~/.claude/` folder?** The installer backs it up to
> `~/.claude.backup.<timestamp>` before copying. You can restore any time.

### Alternative: ask Claude to install it

In an existing Claude Code session, paste:

> Clone `https://github.com/RohitBind123/claude-setup.git` into `~/Downloads/`,
> then run its `install.sh`. Back up any existing `~/.claude/` first.

Claude will run the commands and confirm.

---

## What happens in your next session

Once installed, you do **not** need to tell Claude anything. Here is what
auto-starts every single time you open Claude Code:

### 1. Global `CLAUDE.md` is loaded into context

The file `~/.claude/CLAUDE.md` is injected at the top of every conversation.
It contains:

- The mandatory workflow order: research → plan → TDD → perf rules → review → verify
- The Day-1 Production Checklist (parallel queries, Redis cache, React Query
  persistence, prioritized resolvers, etc.)
- The full list of agents and when to delegate to each
- The full list of slash commands
- Code style rules (immutability, file size, no emojis, etc.)

### 2. Rule files are pulled in

Rules under `~/.claude/rules/common/` are referenced from `CLAUDE.md` and
loaded as part of the global instructions:

- `production-performance.md` — no sequential queries, no N+1, Redis by default
- `data-quality.md` — NULL is not zero, humanize enums, prioritized resolvers
- `async-state-safety.md` — mutation fires before UI transition, resume flows
- `migration-safety.md` — pre-migration audits, dedup before unique index
- `security.md`, `testing.md`, `git-workflow.md`, and 8 more

### 3. SessionStart hook fires

`~/.claude/ecc-scripts/hooks/session-start.js` runs automatically. It prints a
one-line banner so you know the kit is active.

### 4. Agents become available

All 16 sub-agents in `~/.claude/agents/` are registered. You can invoke them
with `@agent-name` or by asking Claude to delegate. The `code-reviewer` and
`tdd-guide` are wired to activate proactively.

### 5. Slash commands are registered

All 35 commands in `~/.claude/commands/` are available. Type `/` in Claude
Code to see the list.

### 6. Skills auto-activate by topic

58 skills under `~/.claude/skills/` activate automatically when relevant.
Write Python? `python-patterns` loads. Touch a migration? `database-migrations`
loads. Build a Next.js page? `frontend-patterns` loads.

### 7. Post-edit hooks fire on every file change

- Format check
- Typecheck
- Console.log warning

### 8. SessionEnd hooks fire when you exit

- Session logger writes a summary
- Session evaluator grades the run

---

## What to say at the start of a new session

You don't have to say anything special — the kit is already active. But here
are the most common openers that get the most out of it:

| You want to… | Say this |
|---|---|
| Start a new feature | `/plan add user profile edit page` |
| Fix a bug | `/tdd fix the race condition in the save flow` |
| Review your last diff | `/code-review` |
| Know if a PR is ship-ready | `/verify` |
| Find existing implementations | `research existing auth libraries before writing` |
| Fix build errors | `/build-fix` |
| Write end-to-end tests | `/e2e` |
| Clean dead code | `/refactor-clean` |
| Chain multiple agents | `/orchestrate` |

If you forget the commands, just say **"what commands do I have available"**
and Claude will list them.

---

## Starting a new project

Pick a template and drop it in your project root as `CLAUDE.md`:

```bash
# Next.js SaaS
cp ~/.claude/examples/saas-nextjs-CLAUDE.md ~/code/my-app/CLAUDE.md

# Django REST API
cp ~/.claude/examples/django-api-CLAUDE.md ~/code/my-api/CLAUDE.md

# Go microservice
cp ~/.claude/examples/go-microservice-CLAUDE.md ~/code/my-service/CLAUDE.md

# Rust API
cp ~/.claude/examples/rust-api-CLAUDE.md ~/code/my-api/CLAUDE.md

# Generic
cp ~/.claude/examples/CLAUDE.md ~/code/my-app/CLAUDE.md
```

Edit the template to match your project. From then on, Claude loads BOTH:

1. The global `~/.claude/CLAUDE.md` (universal rules)
2. The project `CLAUDE.md` (project-specific context)

Both stack. No manual setup per session.

---

## What's in the kit

| Folder / File | What it does | Loaded? |
|---|---|---|
| `CLAUDE.md` | Global instructions — workflow, rules, Day-1 checklist | Every session |
| `settings.json` | Hooks + enabled plugins | Every session |
| `agents/` | 16 specialist agents (planner, architect, code-reviewer, tdd-guide, security-reviewer, python-reviewer, go-reviewer, database-reviewer, …) | On demand |
| `commands/` | 35 slash commands (`/plan`, `/tdd`, `/code-review`, `/verify`, `/build-fix`, `/e2e`, …) | On demand |
| `skills/` | 58 skills (framework patterns, testing, security, perf) | Auto-activate by topic |
| `rules/` | Non-negotiable rules (perf, data quality, async safety, migration safety, security, testing, git) | Every session |
| `examples/` | Template `CLAUDE.md` files for new projects | Copy per project |
| `ecc-scripts/` | Node hook scripts referenced by `settings.json` | Every session |
| `ECC-USAGE-GUIDE.md` | Full guide to the Everything Claude Code system | Read once |
| `HOW-TO-START-ANY-PROJECT.md` | Playbook for starting a project the right way | Read once |

---

## The workflow this kit enforces

Every non-trivial feature goes through this pipeline:

```
1. Research     →  Search GitHub / registries for existing solutions
2. /plan        →  planner agent drafts the implementation
3. /tdd         →  write tests first, then implement (80% coverage floor)
4. Perf rules   →  applied while coding (parallel queries, cache, SSE, …)
5. /code-review →  code-reviewer agent catches issues
6. /verify      →  build + types + lint + tests must pass
7. Commit       →  conventional commits (feat:, fix:, refactor:, …)
```

The kit is opinionated on purpose. It exists so you don't rediscover
these rules after a production incident.

---

## Customize

- **Turn off a hook**: edit `~/.claude/settings.json` and remove the block.
- **Add your own rule**: drop a file into `~/.claude/rules/common/` and
  reference it from `~/.claude/CLAUDE.md`.
- **Add your own agent**: drop `~/.claude/agents/my-agent.md`. Available next session.
- **Add your own slash command**: drop `~/.claude/commands/my-command.md`.
- **Add your own skill**: drop `~/.claude/skills/my-skill/SKILL.md`.

---

## FAQ

**Does it auto-start every session?**
Yes. Everything in `~/.claude/` is loaded by Claude Code automatically.

**Do I need to run `/plan` every time?**
No. But for any feature with more than 2–3 steps, it makes Claude dramatically
better. For one-line fixes, skip it.

**Where does my per-session memory live?**
Under `~/.claude/projects/`, `~/.claude/sessions/`, `~/.claude/agent-memory/`.
These are NOT in this repo — they're built up from your own sessions.

**Can I use this alongside a project-level `CLAUDE.md`?**
Yes. Both stack. The global one is the universal baseline; the project one
adds project context.

**How do I uninstall?**
```bash
rm -rf ~/.claude
mv ~/.claude.backup.* ~/.claude  # restore the backup install.sh made
```

**Can I update it later?**
```bash
cd /path/to/claude-setup
git pull
./install.sh
```
The installer will back up your current `~/.claude/` before overwriting.

**Does this work on Linux / Windows?**
macOS and Linux work out of the box (the hooks are Node.js scripts). Windows
works via WSL — native Windows paths in `settings.json` would need tweaking.

**Will this conflict with Anthropic's default Claude Code config?**
No. Claude Code reads `~/.claude/` as your user config; this kit IS that
config. Nothing is overwritten at the Claude Code install level.

---

## Credits

Built from lessons learned shipping a production SaaS with Claude Code as the
primary development tool. Rules under `rules/common/` each correspond to a
real bug or slow-path that shipped and had to be hot-patched; applying them
from day 1 prevents the same mistakes.

Licensed under the [MIT License](./LICENSE).
