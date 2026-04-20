# How to Start Any Project with Claude Code + ECC

This guide works with any PRD, any tech stack, any project size.
Everything referenced here is globally installed in ~/.claude/

---

## Step 1: Create Your Project

```bash
mkdir my-project && cd my-project
git init
```

## Step 2: Create Project CLAUDE.md

Copy a template from ~/.claude/examples/ and customize it:

```bash
# Pick the closest template:
cp ~/.claude/examples/saas-nextjs-CLAUDE.md ./CLAUDE.md     # Next.js / React
cp ~/.claude/examples/django-api-CLAUDE.md ./CLAUDE.md       # Django / Python API
cp ~/.claude/examples/go-microservice-CLAUDE.md ./CLAUDE.md  # Go microservice
cp ~/.claude/examples/rust-api-CLAUDE.md ./CLAUDE.md         # Rust API
cp ~/.claude/examples/CLAUDE.md ./CLAUDE.md                  # Generic / other
```

Then open CLAUDE.md and fill in:
- Project name and description
- Tech stack (framework, database, hosting)
- File structure
- Environment variables
- Any project-specific rules

This file + the global ~/.claude/CLAUDE.md both load automatically.

## Step 3: Start Claude Code

```bash
claude
```

Claude now has access to all 15 agents, 35 commands, 56 skills, and all rules.

---

## Step 4: Feed Your PRD

Paste your PRD or point to the file:

```
Read /path/to/my-prd.md

/plan Break this PRD into implementation phases with dependencies
```

The planner agent (Opus) will:
- Analyze the full PRD
- Group features into phases based on dependencies
- Identify foundation features (build first) vs features that depend on them
- Estimate complexity per phase
- Flag risks and unknowns
- Wait for your approval

## Step 5: Approve and Start Building

Review the plan. Then for each phase:

```
/tdd Implement [Phase 1 / Feature Name] from the plan
```

The TDD guide agent will:
- Write failing tests first (RED)
- Implement minimal code to pass (GREEN)
- Refactor for quality (REFACTOR)
- Ensure 80%+ test coverage

## Step 6: Review After Each Feature

```
/code-review
```

Catches: security issues, code quality problems, missing error handling, framework anti-patterns.

## Step 7: Verify Before Committing

```
/verify full
```

Runs: build → types → lint → tests → console.log audit → git status

## Step 8: Commit and Move to Next Feature

```
Commit this work
```

Then go back to Step 5 with the next phase/feature.

---

## The Core Loop (Memorize This)

```
/plan  →  /tdd  →  /code-review  →  /verify  →  commit  →  next feature
```

That's it. 4 commands cover 90% of your workflow.

---

## When to Use Which Command

| Situation | Command | What Happens |
|-----------|---------|-------------|
| Starting a new feature | `/plan` | Planner creates implementation plan |
| Building any code | `/tdd` | TDD guide writes tests first, then code |
| Code is written | `/code-review` | Reviews security + quality |
| Before committing | `/verify full` | Full verification pipeline |
| Build is broken | `/build-fix` | Fixes errors one at a time |
| Need E2E tests | `/e2e` | Generates Playwright tests |
| Complex feature (multi-step) | `/orchestrate` | Chains: plan → tdd → review → security |
| Want architecture advice | Ask about architecture | Architect agent responds |
| Coverage too low | `/test-coverage` | Finds gaps, generates missing tests |
| Dead code piling up | `/refactor-clean` | Finds and removes dead code |
| Before a PR | `/code-review` then `/verify` | Full quality gate |
| After a big session | `/learn` | Extracts patterns for future use |
| Go-specific review | `/go-review` | Runs go vet, staticcheck, race detection |
| Python-specific review | `/python-review` | Runs mypy, ruff, bandit |
| Need docs updated | `/update-docs` | Syncs docs from source of truth |

---

## Skills That Activate Automatically

You don't need to invoke these — Claude uses them when relevant:

**When you're building frontend:**
→ frontend-patterns, coding-standards, e2e-testing skills activate

**When you're building a REST API:**
→ api-design, backend-patterns skills activate

**When you're working with databases:**
→ postgres-patterns, database-migrations skills activate

**When you're writing Python:**
→ python-patterns, python-testing skills activate

**When you're writing Go:**
→ golang-patterns, golang-testing skills activate

**When you're setting up Docker/deployment:**
→ docker-patterns, deployment-patterns skills activate

**When you're doing security work:**
→ security-review skill activates

---

## Hooks That Fire Automatically

These happen without you doing anything:

- **After every file edit:** Auto-formats JS/TS, runs TypeScript check, warns about console.log
- **Before git push:** Reminds you to review changes
- **Session start:** Loads previous context
- **Session end:** Saves session state, extracts learnable patterns
- **Every ~50 edits:** Suggests running /compact to manage context

---

## Tips for Large PRDs with Many Features

### 1. Plan the whole thing first
```
/plan Here's the full PRD with 15 features. Create a phased roadmap
     with dependencies. Which features are foundational?
```

### 2. Build foundations first
Always start with: database schema, auth, core data models, API layer.
Then build features that depend on them.

### 3. One feature at a time
Don't try to build everything at once. Complete one feature fully
(tests passing, reviewed, committed) before starting the next.

### 4. Use /orchestrate for complex features
```
/orchestrate Plan and implement the payment system with full security review
```
This chains planner → tdd → code-reviewer → security-reviewer.

### 5. Checkpoint after milestones
```
/checkpoint create "auth-complete"
```
Creates a named reference point you can verify against later.

### 6. Extract learnings after big sessions
```
/learn
```
Saves reusable patterns so Claude gets smarter for your next session.

---

## Project CLAUDE.md Template (Quick Version)

If you don't want to use the templates, just create this minimal CLAUDE.md:

```markdown
# Project Name

## Overview
[What this project does in 2-3 sentences]

## Tech Stack
- Frontend: [framework]
- Backend: [framework]
- Database: [database]
- Hosting: [where]

## File Structure
[Your project's directory layout]

## Environment Variables
[List required env vars]

## Run Commands
- Dev: [command]
- Test: [command]
- Build: [command]

## Project-Specific Rules
[Anything unique to this project]
```

---

## File Locations Reference

| What | Where |
|------|-------|
| This guide | ~/.claude/HOW-TO-START-ANY-PROJECT.md |
| Full ECC usage guide | ~/.claude/ECC-USAGE-GUIDE.md |
| Global Claude instructions | ~/.claude/CLAUDE.md |
| Project templates | ~/.claude/examples/ |
| All agents | ~/.claude/agents/ |
| All commands | ~/.claude/commands/ |
| All skills | ~/.claude/skills/ |
| All rules | ~/.claude/rules/ |
| Hook scripts | ~/.claude/ecc-scripts/hooks/ |
| Settings + hooks config | ~/.claude/settings.json |
