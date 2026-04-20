# Install — detailed reference

For most users, the `install.sh` script in the project root does everything.
This file is the manual fallback and a reference for what the script does.

## Prerequisites

- [Claude Code](https://claude.com/claude-code) installed
- Node.js 18+ (the hooks are tiny Node scripts)
- `tmux` recommended (optional; some hooks suggest running long commands in tmux)

```bash
claude --version
node --version
tmux -V || brew install tmux   # macOS
```

## One-command install

```bash
git clone https://github.com/RohitBind123/claude-setup.git
cd claude-setup
./install.sh
```

## Manual install (what the script does)

### 1. Back up any existing `~/.claude/`

```bash
if [ -d "$HOME/.claude" ]; then
  mv "$HOME/.claude" "$HOME/.claude.backup.$(date +%s)"
fi
```

### 2. Copy the kit into `~/.claude/`

From inside the cloned repo:

```bash
mkdir -p "$HOME/.claude"
# Config file + folders
cp    CLAUDE.md settings.json "$HOME/.claude/"
cp -R agents commands rules skills examples ecc-scripts "$HOME/.claude/"
# Long-form guides live in docs/ in the repo, but land flat in ~/.claude/
# so references like ~/.claude/ECC-USAGE-GUIDE.md keep working.
cp docs/ECC-USAGE-GUIDE.md docs/HOW-TO-START-ANY-PROJECT.md "$HOME/.claude/"
```

### 3. Verify

Open a new terminal and run:

```bash
ls ~/.claude/
claude
```

Inside Claude Code:

```
/agents
```

You should see the 16 agents from this kit.

## Extended Thinking

For deep planning / architecture work, toggle extended thinking inside
Claude Code: `Option+T` (macOS) or `Alt+T` (Linux/Windows). Leave on for
complex features.

## For each new project

Drop a template from `examples/` into your project root as `CLAUDE.md`:

```bash
cp ~/.claude/examples/saas-nextjs-CLAUDE.md /path/to/project/CLAUDE.md
```

## Uninstall

```bash
rm -rf ~/.claude
# optional: restore whatever install.sh backed up
mv ~/.claude.backup.* ~/.claude 2>/dev/null || true
```

## Troubleshooting

**"command not found: node"** → install Node 18+ (`brew install node`).

**Hooks print errors about missing files** → re-run `./install.sh`. The
`ecc-scripts/` folder probably didn't copy.

**Want to disable a hook?** → open `~/.claude/settings.json` and delete the
matching block.
