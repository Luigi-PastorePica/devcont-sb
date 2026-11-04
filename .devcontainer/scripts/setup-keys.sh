#!/usr/bin/env bash
#
# setup-keys.sh
#
# Helper to add API keys and auth tokens to the claude code router (CCR) from
# inside the devcontainer. Keys are stored in the router config (config.sqlite)
# under ~/.claude-code-router. Because ~/.claude-code-router is bind-mounted from
# your host, keys set here persist on the host too (and vice versa).
#
# Usage:
#   bash setup-keys.sh <openrouter-api-key> [anthropic-api-key]
#
# Or via env vars:
#   CCR_OPENROUTER_API_KEY=... CCR_ANTHROPIC_API_KEY=... bash setup-keys.sh
set -euo pipefail

CCR_DIR="/home/dev/.claude-code-router"
CONFIG_DB="$CCR_DIR/config.sqlite"

OPENROUTER_KEY="${1:-${CCR_OPENROUTER_API_KEY:-}}"
ANTHROPIC_KEY="${2:-${CCR_ANTHROPIC_API_KEY:-}}"

if [ -z "$OPENROUTER_KEY" ]; then
  echo "Usage: $0 <openrouter-api-key> [anthropic-api-key]"
  echo "  Or: CCR_OPENROUTER_API_KEY=... CCR_ANTHROPIC_API_KEY=... $0"
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 not found. Install it (sudo apt-get install sqlite3) to manage router keys."
  exit 1
fi

if [ ! -f "$CONFIG_DB" ]; then
  echo "Router config database not found at $CONFIG_DB"
  echo "Make sure ~/.claude-code-router is bind-mounted and the router has been initialized."
  exit 1
fi

echo "[setup-keys] Storing OpenRouter key in router config..."
sqlite3 "$CONFIG_DB" "INSERT OR REPLACE INTO keys (provider, key_value) VALUES ('openrouter', '$OPENROUTER_KEY');"

if [ -n "$ANTHROPIC_KEY" ]; then
  echo "[setup-keys] Storing Anthropic key in router config..."
  sqlite3 "$CONFIG_DB" "INSERT OR REPLACE INTO keys (provider, key_value) VALUES ('anthropic', '$ANTHROPIC_KEY');"
fi

echo "[setup-keys] Done. Keys are stored in $CONFIG_DB and managed by the router."
echo "[setup-keys] Restart Claude Code (or the router gateway on :3456) to pick them up."
