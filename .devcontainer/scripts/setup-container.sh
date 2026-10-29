#!/usr/bin/env bash
#
# setup-container.sh — Configure container Claude Code to reach host-side CCR.
# No local router binary or middleware; agent connects over network.
#
set -euo pipefail

DEV_HOME="/home/dev"
CLAUDE_DIR="$DEV_HOME/.claude"
HOST_CLAUDE_DIR="$DEV_HOME/.claude-host"
HOST_SETTINGS="$HOST_CLAUDE_DIR/settings.json"
CONTAINER_SETTINGS="$CLAUDE_DIR/settings.json"

echo "[setup-container] Detecting repo from working directory..."
GH_REPO="$(basename "$PWD")"
export GH_REPO
echo "[setup-container] Repo detected: $GH_REPO"
# Write .env.local to workspace (persisted on host) for reference
if [ -d "/workspace" ]; then
  echo "GH_REPO=$GH_REPO" >> /workspace/.env.local || echo "# Could not write .env.local (workspace may not exist)" > /dev/stdout
fi

echo "[setup-container] Setting up directories..."
mkdir -p "$CLAUDE_DIR" "$DEV_HOME/.claude/bin"

echo "[setup-container] Seeding container settings.json from host settings.json..."
if [ -f "$HOST_SETTINGS" ]; then
  cp "$HOST_SETTINGS" "$CONTAINER_SETTINGS"
  echo "[setup-container] Copied host settings.json."
else
  echo "{}" > "$CONTAINER_SETTINGS"
  echo "[setup-container] No host settings.json; starting empty."
fi

echo "[setup-container] Merging container router config into settings.json..."
TMP_SETTINGS="$(mktemp)"
jq '
  .env = (.env // {})
  | .apiKeyHelper = "/home/dev/.claude/bin/ccr-claude-code-api-key-default-claude-code"
  | .env.ANTHROPIC_BASE_URL = "http://host.docker.internal:3456"
  | .env.ANTHROPIC_API_BASE_URL = "http://host.docker.internal:3456"
  | .env.CLAUDE_AGENT_API_BASE_URL = "http://host.docker.internal:3456"
  | .env.NO_PROXY = "127.0.0.1,localhost,::1"
  | .env.no_proxy = "127.0.0.1,localhost,::1"
  | .env.CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT = "1"
  | .env.ANTHROPIC_MODEL = "openrouter/nvidia/nemotron-3.5-super-vl:free"
  | .env.CCR_CLAUDE_CODE_MODEL = "openrouter/nvidia/nemotron-3.5-super-vl:free"
  | .env.CODEXL_CLAUDE_CODE_MODEL = "openrouter/nvidia/nemotron-3.5-super-vl:free"
  | .env.ANTHROPIC_DEFAULT_FABLE_MODEL = "openrouter/thinkingmachines/inkling:free[1m]"
  | .env.ANTHROPIC_DEFAULT_OPUS_MODEL = "openrouter/thinkingmachines/inkling:free[1m]"
  | .env.ANTHROPIC_DEFAULT_SONNET_MODEL = "openrouter/nvidia/nemotron-3.5-super-vl:free"
  | .env.ANTHROPIC_DEFAULT_HAIKU_MODEL = "openrouter/google/gemma-4-31b-it:free"
' "$CONTAINER_SETTINGS" > "$TMP_SETTINGS" && mv "$TMP_SETTINGS" "$CONTAINER_SETTINGS"

echo "[setup-container] Writing container-side apiKeyHelper..."
cat > "$DEV_HOME/.claude/bin/ccr-claude-code-api-key-default-claude-code" <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY='1'
unset CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY
unset CLAUDE_CODE_USE_GATEWAY CLAUDE_CODE_USE_MANTLE
unset CLAUDE_CODE_USE_ANTHROPIC_AWS CLAUDE_CODE_USE_ANTHROPIC_GOOGLE_CLOUD
unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY
export ANTHROPIC_API_BASE_URL='http://host.docker.internal:3456'
export ANTHROPIC_BASE_URL='http://host.docker.internal:3456'
export CLAUDE_AGENT_API_BASE_URL='http://host.docker.internal:3456'
export CLAUDE_CONFIG_DIR='/home/dev/.claude'
export ANTHROPIC_MODEL='openrouter/nvidia/nemotron-3.5-super-vl:free'
export CCR_CLAUDE_CODE_MODEL='openrouter/nvidia/nemotron-3.5-super-vl:free'
export CODEXL_CLAUDE_CODE_MODEL='openrouter/nvidia/nemotron-3.5-super-vl:free'
export ANTHROPIC_DEFAULT_FABLE_MODEL='openrouter/thinkingmachines/inkling:free[1m]'
export ANTHROPIC_DEFAULT_OPUS_MODEL='openrouter/thinkingmachines/inkling:free[1m]'
export ANTHROPIC_DEFAULT_SONNET_MODEL='openrouter/nvidia/nemotron-3.5-super-vl:free'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='openrouter/google/gemma-4-31b-it:free'
export NO_PROXY='127.0.0.1,localhost,::1'
export no_proxy='127.0.0.1,localhost,::1'
export CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT='1'
export GH_REPO='"'"'"${GH_REPO:-unknown-repo}"'"'"'
: "${CCR_PROFILE_SURFACE:=auto}"
export CCR_PROFILE_SURFACE
if [ "$CCR_PROFILE_SURFACE" = "app" ]; then
  export CCR_BOT_GATEWAY_ENABLED='false'
  export CODEXL_BOT_GATEWAY_ENABLED='false'
else
  export CCR_BOT_GATEWAY_ENABLED='false'
  export CODEXL_BOT_GATEWAY_ENABLED='false'
fi
export CCR_CLAUDE_CODE_WRAPPER=1
export CCR_REAL_CLAUDE_CODE_BIN='claude'
export CODEXL_CLAUDE_CODE_BIN='claude'
if [ -z "${CCR_REMOTE_SYNC_ENABLED:-}" ]; then CCR_REMOTE_SYNC_ENABLED=1; fi
if [ -z "${CCR_REMOTE_SYNC_ENDPOINT:-}" ]; then CCR_REMOTE_SYNC_ENDPOINT='http://host.docker.internal:3456/__ccr/remote'; fi
if [ -z "${CCR_REMOTE_SYNC_PROFILE_ID:-}" ]; then CCR_REMOTE_SYNC_PROFILE_ID='default-claude-code'; fi
if [ -z "${CCR_REMOTE_SYNC_PROFILE_NAME:-}" ]; then CCR_REMOTE_SYNC_PROFILE_NAME='Claude Code'; fi
export CCR_REMOTE_SYNC_ENABLED CCR_REMOTE_SYNC_ENDPOINT CCR_REMOTE_SYNC_PROFILE_ID CCR_REMOTE_SYNC_PROFILE_NAME
if [ -n "${CCR_NODE_BIN:-}" ]; then
  exec "$CCR_NODE_BIN" '/home/dev/.claude/bin/ccr-codex-cli-middleware.js' "$@"
fi
if command -v node >/dev/null 2>&1; then
  exec node '/home/dev/.claude/bin/ccr-codex-cli-middleware.js' "$@"
fi
ELECTRON_RUN_AS_NODE=1 exec '/home/dev/.nvm/versions/node/current/bin/node' '/home/dev/.claude/bin/ccr-codex-cli-middleware.js' "$@"
HELPER
chmod 0755 "$DEV_HOME/.claude/bin/ccr-claude-code-api-key-default-claude-code"

echo "[setup-container] STATUS: workspace source = /workspace (bind-mounted, not copied)"
echo "[setup-container] STATUS: active work directory = /home/dev/project"
echo "[setup-container] STATUS: artifacts directory = /home/dev/artifacts (bind-mounted session-artifacts)"
echo "[setup-container] Fetching GH token from host endpoint..."
bash /home/dev/scripts/fetch-gh-token.sh 9876 || echo "[setup-container] Token fetch failed; clone may fail."
echo "[setup-container] Cloning repo from remote for ephemeral session..."
mkdir -p /home/dev/project
if [ -n "$GH_TOKEN" ] && [ "$GH_REPO" != "unknown-repo" ]; then
  echo "[setup-container] GH_TOKEN present; cloning from remote..."
  # Example clone using GH token (adjust URL format as needed for your GH App setup)
  git clone "https://x-access-token:${GH_TOKEN}@github.com/${GH_REPO}.git" /home/dev/project 2>/dev/null ||     echo "[setup-container] Remote clone failed (repo may not exist or token invalid). Working without repo copy."
else
  echo "[setup-container] No GH_TOKEN set; attempting unauthenticated clone..."
  git clone "https://github.com/${GH_REPO}.git" /home/dev/project 2>/dev/null ||     echo "[setup-container] Remote clone failed. Working without repo copy."
fi
echo "=== CONTAINER STARTUP SUMMARY ==="
echo "Repo (GH_REPO): $GH_REPO"
echo "GH_TOKEN set: ${GH_TOKEN:+yes}"
echo "GH_APP_PEM_PATH: ${GH_APP_PEM_PATH:-not set}"
echo "Working directory: /home/dev/project"
echo "Directory contents (before clone): $(ls -A /home/dev/project 2>/dev/null | wc -l) files"
if [ -d "/home/dev/project/.git" ]; then
  echo "CLONE SUCCESS: true | source: remote | directory: /home/dev/project"
  echo "Repo files present: yes (.git exists)"
else
  echo "CLONE SUCCESS: false | source: none/workspace_fallback"
  echo "Repo files present: no (.git missing)"
fi
echo "Artifacts directory: /home/dev/artifacts (exists: $(test -d /home/dev/artifacts && echo yes || echo no))"
echo "=== STARTUP COMPLETE ==="
