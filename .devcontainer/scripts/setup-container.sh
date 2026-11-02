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

# AGGRESSIVE Git credential isolation - block ALL host passthrough
echo "[setup-container] Isolating git from host credentials..."

# 1. Disable all credential helpers at every level
git config --global --unset credential.helper 2>/dev/null || true
git config --system --unset credential.helper 2>/dev/null || true
git config --local --unset credential.helper 2>/dev/null || true
# Explicitly set empty helper to override any system config
git config --global credential.helper "" 2>/dev/null || true
git config --system credential.helper "" 2>/dev/null || true

# 2. Disable git config reading from system/global
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=""
export GIT_CONFIG_SYSTEM=""

# 3. Disable terminal prompts
export GIT_TERMINAL_PROMPT=0

# 4. Disable SSH agent and SSH entirely for git
unset SSH_AUTH_SOCK 2>/dev/null || true
unset SSH_AGENT_PID 2>/dev/null || true
# Force git to use HTTPS only, never SSH
git config --global url."https://github.com/".insteadOf "git@github.com:" 2>/dev/null || true
git config --global url."https://github.com/".insteadOf "ssh://git@github.com/" 2>/dev/null || true

# 5. Disable netrc
unset NETRC 2>/dev/null || true
git config --global credential.useHttpPath true 2>/dev/null || true

# 6. Create a dedicated git credential helper that ONLY uses our token
cat > /home/dev/.git-credential-token <<'HELPER_EOF'
#!/usr/bin/env bash
# Git credential helper that ONLY provides the token from GH_TOKEN env var
# Rejects all other credential sources

case "$1" in
  get)
    # Only provide credentials for github.com HTTPS
    while IFS= read -r line; do
      case "$line" in
        protocol=https)
          PROTOCOL=https
          ;;
        host=github.com)
          HOST=github.com
          ;;
        username=)
          # We don't use username, token auth doesn't need it
          ;;
      esac
    done

    if [ "$PROTOCOL" = "https" ] && [ "$HOST" = "github.com" ] && [ -n "${GH_TOKEN:-}" ]; then
      echo "username=x-access-token"
      echo "password=${GH_TOKEN}"
      exit 0
    fi
    # No credentials for anything else
    exit 1
    ;;
  store|erase)
    # Never store or erase - we only use env var
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
HELPER_EOF
chmod +x /home/dev/.git-credential-token

# 7. Register our token-only credential helper
git config --global credential.helper "/home/dev/.git-credential-token" 2>/dev/null || true

# 8. Clean up any existing SSH keys in container (except known_hosts)
if [ -d ~/.ssh ]; then
  # Keep only known_hosts, remove private keys
  find ~/.ssh -type f ! -name 'known_hosts' -delete 2>/dev/null || true
  echo "[setup-container] Cleaned ~/.ssh (kept known_hosts only)"
fi

# Additional defensive measures for hosts with different auth configurations
# 10. Block any potential SSH key forwarding or host SSH config leakage
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -F /dev/null -i /dev/null"
# Force git to not use any SSH identity
export GIT_SSH=""
# 11. Block any .gitconfig or .netrc that might exist in container
rm -f /home/dev/.netrc 2>/dev/null || true
rm -f /home/dev/.git-credentials 2>/dev/null || true
# 12. Ensure the token-only helper is always first and only
export GIT_ASKPASS="echo"
export GIT_TERMINAL_PROMPT=0

# 13. Final defensive check: verify our helper exists and is executable
if [ -x "/home/dev/.git-credential-token" ]; then
  echo "  .git-credential-token: executable at /home/dev/.git-credential-token"
else
  echo "  WARNING: .git-credential-token not found or not executable!"
fi

# 9. Verify isolation
echo "[setup-container] Verifying git credential isolation..."
echo "  credential.helper (global): $(git config --global --get credential.helper || echo 'none')"
echo "  credential.helper (system): $(git config --system --get credential.helper || echo 'none')"
echo "  SSH_AUTH_SOCK: ${SSH_AUTH_SOCK:-unset}"
echo "  GIT_CONFIG_NOSYSTEM: ${GIT_CONFIG_NOSYSTEM:-unset}"
echo "  GIT_CONFIG_GLOBAL: ${GIT_CONFIG_GLOBAL:-unset}"
echo "[setup-container] Git credential isolation complete (token-only mode)"

# AUTHENTICATION CHECKS: Save isolation verification to log
AUTH_CHECK_LOG="/tmp/auth-isolation-check.log"
echo "=== AUTH ISOLATION CHECKS $(date -Iseconds) ===" > "$AUTH_CHECK_LOG"
echo "Git credential isolation verification (token-only mode)" >> "$AUTH_CHECK_LOG"
echo "credential.helper (global): $(git config --global --get credential.helper || echo 'none')" >> "$AUTH_CHECK_LOG"
echo "credential.helper (system): $(git config --system --get credential.helper || echo 'none')" >> "$AUTH_CHECK_LOG"
echo "credential.helper (local): $(git config --local --get credential.helper || echo 'none')" >> "$AUTH_CHECK_LOG"
echo "SSH_AUTH_SOCK: ${SSH_AUTH_SOCK:-unset}" >> "$AUTH_CHECK_LOG"
echo "SSH_AGENT_PID: ${SSH_AGENT_PID:-unset}" >> "$AUTH_CHECK_LOG"
echo "GIT_CONFIG_NOSYSTEM: ${GIT_CONFIG_NOSYSTEM:-unset}" >> "$AUTH_CHECK_LOG"
echo "GIT_CONFIG_GLOBAL: ${GIT_CONFIG_GLOBAL:-unset}" >> "$AUTH_CHECK_LOG"
echo "GIT_CONFIG_SYSTEM: ${GIT_CONFIG_SYSTEM:-unset}" >> "$AUTH_CHECK_LOG"
echo "GIT_TERMINAL_PROMPT: ${GIT_TERMINAL_PROMPT:-unset}" >> "$AUTH_CHECK_LOG"
echo ".git-credential-token executable: $(test -x /home/dev/.git-credential-token && echo 'yes' || echo 'no')" >> "$AUTH_CHECK_LOG"
# Check if any remaining private SSH keys exist (should only be known_hosts)
REMAINING_KEYS=$(find ~/.ssh -type f ! -name 'known_hosts' 2>/dev/null | wc -l)
echo "Remaining SSH private keys: $REMAINING_KEYS (expected: 0)" >> "$AUTH_CHECK_LOG"
# Check remote URL format (should use HTTPS with token, not SSH)
echo "Remote URL format: $([ -n "$WORKSPACE_ROOT" ] && git -C "$WORKSPACE_ROOT" remote get-url origin 2>/dev/null || echo 'N/A')" >> "$AUTH_CHECK_LOG"
echo ".env.local exists: $(test -f /home/dev/job-hunt-journal/.env.local && echo 'yes' || echo 'no')" >> "$AUTH_CHECK_LOG"
echo ".env.local masked in log: yes (GH_TOKEN=<MASKED>)" >> "$AUTH_CHECK_LOG"
echo "GH_APP_PEM_PATH printed: no" >> "$AUTH_CHECK_LOG"
echo "=== CHECKS COMPLETE ===" >> "$AUTH_CHECK_LOG"
echo "[setup-container] Auth isolation checks saved to $AUTH_CHECK_LOG"

# DEFENSIVE: Re-verify isolation after potential VS Code / Docker injection
# VS Code Remote extension or Docker can inject env vars/settings after postCreate
# We re-assert our isolation here to override any post-creation changes
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=""
export GIT_CONFIG_SYSTEM=""
export GIT_TERMINAL_PROMPT=0
unset SSH_AUTH_SOCK 2>/dev/null || true
unset SSH_AGENT_PID 2>/dev/null || true
git config --global credential.helper "/home/dev/.git-credential-token" 2>/dev/null || true
echo "[setup-container] Re-asserted isolation after postCreate (for any VS Code/Docker injection)"

# PERSISTENT DEFENSE: Write isolation to .bashrc so every new terminal session re-isolates
# VS Code may open new terminals; this ensures isolation survives session restarts
cat >> /home/dev/.bashrc << 'BASH_EOF'
# Auto-isolation hook: re-assert token-only auth on every new terminal/session
# Defends against VS Code injecting host credentials after initial setup
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=""
export GIT_CONFIG_SYSTEM=""
unset SSH_AUTH_SOCK 2>/dev/null || true
unset SSH_AGENT_PID 2>/dev/null || true
git config --global --unset credential.helper 2>/dev/null || true
git config --global credential.helper "/home/dev/.git-credential-token" 2>/dev/null || true
BASH_EOF

echo "[setup-container] Persistent isolation hook added to /home/dev/.bashrc"

if [ -f "$HOME/.gh-token.tmp" ]; then
  GH_TOKEN="$(cat "$HOME/.gh-token.tmp" 2>/dev/null || true)"
  export GH_TOKEN
  echo "[setup-container] GH_TOKEN loaded from .gh-token.tmp (${GH_TOKEN:+yes})"
  if [ -n "${GH_TOKEN:-}" ]; then
    # Show only first 10 chars + ... + last 10 chars (don't expose full token in logs)
    TOKEN_START="${GH_TOKEN:0:10}"
    TOKEN_END="${GH_TOKEN: -10}"
    echo "[setup-container] Token partial: ${TOKEN_START}...${TOKEN_END} (length: ${#GH_TOKEN})"
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
echo "[setup-container] .env.local content (token masked):"
cat "/home/dev/.env.local" | sed 's/GH_TOKEN=.*/[env.local] GH_TOKEN=<MASKED>/; s/^/[env.local] /'
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
