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

# Workspace root derived from GH_REPO (set in Dockerfile ENV)
WORKSPACE_ROOT="/home/dev/${GH_REPO}"

echo "[setup-container] Detecting repo..."
# Use existing GH_REPO (set by env/Dockerfile/postCreateCommand), or compute from workspace root
if [ -z "${GH_REPO:-}" ]; then
  # Go up from scripts dir to find project root folder name
  GH_REPO="$(basename "$(dirname "$(dirname "$PWD")")")"
fi
export GH_REPO
echo "[setup-container] Repo detected: $GH_REPO"


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

echo "[setup-container] STATUS: workspace root = $WORKSPACE_ROOT (bind-mounted workspace, repo clone target)"
echo "[setup-container] STATUS: active work directory = $WORKSPACE_ROOT"
echo "[setup-container] STATUS: artifacts directory = /home/dev/artifacts (bind-mounted session-artifacts)"

# Isolate git from any host credentials
echo "[setup-container] Isolating git from host credentials..."
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=""
export HOME="/home/dev"  # Ensure we use container home, not host
# Unset any credential helpers that might be configured
git config --global --unset credential.helper 2>/dev/null || true
git config --system --unset credential.helper 2>/dev/null || true
git config --global credential.helper "" 2>/dev/null || true
# Ensure we don't use any netrc
unset NETRC 2>/dev/null || true
# Disable ssh agent
unset SSH_AUTH_SOCK 2>/dev/null || true
echo "[setup-container] Git credential isolation complete"
if [ -f "$HOME/.gh-token.tmp" ]; then
  GH_TOKEN="$(cat "$HOME/.gh-token.tmp" 2>/dev/null || true)"
  export GH_TOKEN
  echo "[setup-container] GH_TOKEN loaded from .gh-token.tmp (${GH_TOKEN:+yes})"
  if [ -n "${GH_TOKEN:-}" ]; then
    echo "[setup-container] Token length: ${#GH_TOKEN}"
  else
    echo "[setup-container] WARNING: .gh-token.tmp exists but is empty!"
    echo "[setup-container] File contents: '$(cat "$HOME/.gh-token.tmp" 2>/dev/null)'"
  fi
else
  echo "[setup-container] No .gh-token.tmp found at $HOME/.gh-token.tmp; GH operations will be unauthenticated."
  echo "[setup-container] Checking if fetch-gh-token.sh log has clues..."
  if [ -f "/tmp/postcreate.log" ]; then
    echo "[setup-container] Last 30 lines of postcreate.log:"
    tail -30 /tmp/postcreate.log | sed 's/^/[postcreate.log] /'
  fi
fi

# Verify GH_TOKEN is set before clone
if [ -n "${GH_TOKEN:-}" ]; then
  echo "[setup-container] GH_TOKEN confirmed available for clone"
else
  echo "[setup-container] WARNING: GH_TOKEN is empty - clone may fail for private repo"
  echo "[setup-container] Checking fetch-gh-token.sh output in postcreate.log..."
  if [ -f "/tmp/postcreate.log" ]; then
    echo "[setup-container] First 50 lines (fetch-gh-token.sh output):"
    head -50 /tmp/postcreate.log | sed 's/^/[fetch-gh-token.log] /'
  fi
fi

# Resolve full repo name (owner/repo) from host workspace git remote
FULL_REPO="${GH_REPO}"
OWNER=""  # Will be set below
# Try host bind-mounted workspace (/workspaces/host-repo) first for owner info
LOCAL_REMOTE="$(git -C "/workspaces/host-repo" remote get-url origin 2>/dev/null || git -C "$WORKSPACE_ROOT" remote get-url origin 2>/dev/null || git remote get-url origin 2>/dev/null || echo '')"
if [ -n "$LOCAL_REMOTE" ]; then
  DETECTED_FULL="$(echo "$LOCAL_REMOTE" | sed -E 's|.*github\.com[:/]||; s|\.git$||')"
  echo "[setup-container] DEBUG: LOCAL_REMOTE=$LOCAL_REMOTE DETECTED_FULL=$DETECTED_FULL"
  if [ -n "$DETECTED_FULL" ]; then
    FULL_REPO="$DETECTED_FULL"
    # If FULL_REPO has no slash (just repo name), try to inject owner from git config
    if [ -z "$(echo "$FULL_REPO" | grep '/')" ]; then
      # Try to get owner from git remote or default to DEFAULT_OWNER for this repo
      OWNER="$(git -C "/workspaces/host-repo" config --get remote.origin.url 2>/dev/null | sed -E 's|.*github\.com[:/]([^/]+)/.*|\1|' || echo "${DEFAULT_OWNER}")"
      FULL_REPO="${OWNER}/${FULL_REPO}"
      echo "[setup-container] Injected owner: FULL_REPO=${FULL_REPO}"
    else
      # FULL_REPO already has owner/repo format, extract owner
      OWNER="${FULL_REPO%%/*}"
    fi
    echo "[setup-container] Detected full repo from git remote: $FULL_REPO"
  fi
fi
# Ensure OWNER is always set
OWNER="${OWNER:-${DEFAULT_OWNER}}"
echo "[setup-container] Final OWNER=$OWNER, FULL_REPO=$FULL_REPO"
echo "[setup-container] Cloning repo from remote for ephemeral session..."
# Clone repo into workspace root directly (only if empty or no .git)
mkdir -p "$WORKSPACE_ROOT"
CLONE_DIR="$WORKSPACE_ROOT"
# Check contents (excluding .env.local which we may have written earlier)
CONTENTS=$(ls -A "$CLONE_DIR" 2>/dev/null | grep -v '^\.env\.local$' | tr -d '\n' || true)
if [ -z "$CONTENTS" ] || [ ! -d "$CLONE_DIR/.git" ]; then
  if [ -n "${GH_TOKEN:-}" ] && [ "$GH_REPO" != "unknown-repo" ]; then
    echo "[setup-container] GH_TOKEN present; cloning from remote into ${CLONE_DIR}..."
    # Clone into workspace root directly
    # No pre-clean needed for ephemeral container
    git clone -v "https://x-access-token:${GH_TOKEN:-}@github.com/${FULL_REPO}.git" "$CLONE_DIR" 2>&1 || { echo "[setup-container] ERROR: Remote clone failed (repo=${FULL_REPO}, GH_TOKEN=${GH_TOKEN:+set})"; }
  else
    echo "[setup-container] No GH_TOKEN set; attempting unauthenticated clone..."
    # No pre-clean needed for ephemeral container
    git clone -v "https://github.com/${FULL_REPO}.git" "$CLONE_DIR" 2>&1 || { echo "[setup-container] ERROR: Unauthenticated clone failed (repo=${FULL_REPO})"; }
  fi
else
  echo "[setup-container] ${CLONE_DIR} already exists; skipping clone."
fi
echo "=== CONTAINER STARTUP SUMMARY ==="
echo "Repo (GH_REPO): ${GH_REPO:-unknown-repo}"
echo "GH_TOKEN set: ${GH_TOKEN:+yes}"
echo "GH_APP_PEM_PATH: ${GH_APP_PEM_PATH:-not set}"
echo "Working directory: $WORKSPACE_ROOT"
echo "Directory contents (before clone): $(ls -A "$WORKSPACE_ROOT" 2>/dev/null | wc -l) files"
if [ -d "${CLONE_DIR}/.git" ]; then
  echo "CLONE SUCCESS: true | source: remote | directory: ${CLONE_DIR}"
  echo "Repo files present: yes (.git exists at ${CLONE_DIR})"
else
  echo "CLONE SUCCESS: false | source: none/workspace_fallback"
  echo "Repo files present: no (.git missing at ${CLONE_DIR})"
fi
echo "Artifacts directory: /home/dev/artifacts (exists: $(test -d /home/dev/artifacts && echo yes || echo no))"
# Write .env.local at parent level first, then move into cloned repo
echo "[setup-container] Writing .env.local with OWNER=$OWNER, GH_REPO=$GH_REPO, GH_TOKEN=${GH_TOKEN:+set}"
# Always write GH_REPO and OWNER, only write GH_TOKEN if available
echo "GH_REPO=${GH_REPO}" > "/home/dev/.env.local"
echo "OWNER=${OWNER}" >> "/home/dev/.env.local"
if [ -n "${GH_TOKEN:-}" ]; then
  echo "GH_TOKEN=${GH_TOKEN}" >> "/home/dev/.env.local"
  echo "[setup-container] GH_TOKEN written to .env.local"
else
  echo "# GH_TOKEN not available (fetch-gh-token.sh failed or host endpoint unreachable)" >> "/home/dev/.env.local"
  echo "[setup-container] No GH_TOKEN - wrote placeholder to .env.local"
fi
# Verify .env.local content before moving
echo "[setup-container] .env.local content:"
cat "/home/dev/.env.local" | sed 's/^/[env.local] /'
# Move into workspace (cloned repo) after clone completes
mv "/home/dev/.env.local" "${CLONE_DIR}/.env.local"
echo "[setup-container] .env.local moved to ${CLONE_DIR}/.env.local"
# Verify it's in the cloned repo
if [ -f "${CLONE_DIR}/.env.local" ]; then
  echo "[setup-container] Verified .env.local at ${CLONE_DIR}/.env.local"
else
  echo "[setup-container] ERROR: .env.local not found at ${CLONE_DIR}/.env.local after move!"
fi
echo "=== STARTUP COMPLETE ==="
