#!/usr/bin/env bash
# claude-setup installer
# Copies this kit into ~/.claude/ so Claude Code picks it up globally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }

bold "claude-setup installer"
echo

# 1. Check Node
if ! command -v node >/dev/null 2>&1; then
  warn "Node.js not found. Install Node 18+ first (brew install node)."
  exit 1
fi
ok "Node $(node --version) detected"

# 2. Back up existing ~/.claude/ if present
if [ -d "$TARGET" ]; then
  BACKUP="${TARGET}.backup.$(date +%s)"
  mv "$TARGET" "$BACKUP"
  ok "Backed up existing ~/.claude -> $BACKUP"
fi

# 3. Create target and copy files
mkdir -p "$TARGET"

# Config-level files at repo root go to ~/.claude/ root
for item in CLAUDE.md settings.json agents commands rules skills examples ecc-scripts; do
  if [ -e "$SCRIPT_DIR/$item" ]; then
    cp -R "$SCRIPT_DIR/$item" "$TARGET/"
    ok "Installed $item"
  fi
done

# Long-form guides live in docs/ in the repo but should land flat in ~/.claude/
# so that global-scope references (e.g. ~/.claude/ECC-USAGE-GUIDE.md) keep working.
for guide in ECC-USAGE-GUIDE.md HOW-TO-START-ANY-PROJECT.md; do
  if [ -e "$SCRIPT_DIR/docs/$guide" ]; then
    cp "$SCRIPT_DIR/docs/$guide" "$TARGET/"
    ok "Installed $guide"
  fi
done

# 4. Set exec bit on hook scripts
if [ -d "$TARGET/ecc-scripts/hooks" ]; then
  chmod +x "$TARGET/ecc-scripts/hooks/"*.js 2>/dev/null || true
fi

echo
bold "Done. Open Claude Code and run /agents to verify."
echo
echo "  Next steps:"
echo "    1. Open a new Claude Code session"
echo "    2. Type /plan to start a new feature"
echo "    3. Drop a template into new projects: cp ~/.claude/examples/<template> <project>/CLAUDE.md"
echo
