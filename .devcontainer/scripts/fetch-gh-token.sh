#!/usr/bin/env bash
# fetch-gh-token.sh — Fetch short-lived GH App installation token from host endpoint
# Usage: bash fetch-gh-token.sh [PORT] [REPO]
#   PORT defaults to 9876
#   REPO defaults to repo name from GH_REPO environment variable
#
# The host endpoint (token_endpoint.py) handles both:
# - Repo-level installations (app installed directly on repo)
# - Account-level installations (app installed on user/org, access to all repos)
#
# Environment variables required on host:
#   GH_APP_PEM_PATH_CC - path to App private key PEM
#   GH_APP_ID_CC - App ID (numeric) or Client ID (alphanumeric)
#   ALLOWED_GH_REPOS - comma-separated list of allowed repos
#
# On success: writes token to ~/.gh-token.tmp (chmod 600) and exports GH_TOKEN

HOST_PORT="${1:-9876}"
# Rely solely on GH_REPO environment variable; fail if not set
if [ -z "${GH_REPO:-}" ]; then
  echo "[fetch-gh-token] ERROR: GH_REPO environment variable is not set. Set it before running this script." >&2
  exit 1
fi
export GH_REPO

# Debug: show what GH_REPO we have
echo "[fetch-gh-token] GH_REPO=$GH_REPO"
echo "[fetch-gh-token] DEFAULT_OWNER=${DEFAULT_OWNER:-not set}"
echo "[fetch-gh-token] WORKSPACE_DIR=$WORKSPACE_DIR"

# Resolve full repo (owner/repo) from workspace .git remote
WORKSPACE_DIR="/workspaces/host-repo"
REPO_GIT_DIR="${WORKSPACE_DIR}/.git"
if [ -d "$REPO_GIT_DIR" ]; then
  LOCAL_REMOTE="$(git -C "$WORKSPACE_DIR" remote get-url origin 2>/dev/null || echo '')"
  echo "[fetch-gh-token] Found .git at $REPO_GIT_DIR"
else
  LOCAL_REMOTE="$(git remote get-url origin 2>/dev/null || echo '')"
  echo "[fetch-gh-token] No .git at $REPO_GIT_DIR, trying current dir"
fi
echo "[fetch-gh-token] LOCAL_REMOTE='$LOCAL_REMOTE'"
FULL_REPO=""
if [ -n "$LOCAL_REMOTE" ]; then
  FULL_REPO="$(echo "$LOCAL_REMOTE" | sed -E 's|.*github\.com[:/]||; s|\.git$||')"
  echo "[fetch-gh-token] Parsed FULL_REPO='$FULL_REPO'"
fi
if [ -n "$FULL_REPO" ]; then
  GH_REPO="$FULL_REPO"
  echo "[fetch-gh-token] Detected full repo from git remote: $GH_REPO"
elif [ -n "${GH_REPO:-}" ]; then
  # GH_REPO may be just repo name; inject owner from git config or DEFAULT_OWNER
  if [ -z "$(echo "$GH_REPO" | grep '/')" ]; then
    OWNER="$(git -C "$WORKSPACE_DIR" config --get remote.origin.url 2>/dev/null | sed -E 's|.*github\.com[:/]([^/]+)/.*|\1|' || echo "${DEFAULT_OWNER}")"
    GH_REPO="${OWNER}/${GH_REPO}"
    echo "[fetch-gh-token] Injected owner: GH_REPO=$GH_REPO"
  fi
fi
export GH_REPO
# For token endpoint, use just the repo name (no owner) since ALLOWED_GH_REPOS typically has short names
# Extract repo name from full owner/repo format
REPO_FOR_ENDPOINT="${GH_REPO##*/}"
TOKEN_FILE="$HOME/.gh-token.tmp"
TOKEN_URL="http://host.docker.internal:${HOST_PORT}/token"
CONTAINER_ID="${HOSTNAME:-unknown-container}"

# Isolate git from host credentials for token fetch too
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_NOSYSTEM=1
git config --global --unset credential.helper 2>/dev/null || true
git config --system --unset credential.helper 2>/dev/null || true
git config --global credential.helper "" 2>/dev/null || true

echo "[fetch-gh-token] Requesting from $TOKEN_URL (container=$CONTAINER_ID, repo=$REPO_FOR_ENDPOINT, full_repo=$GH_REPO)"
if command -v curl >/dev/null 2>&1; then
  # Remove -sf to see HTTP errors, add -v for verbose in log
  RESPONSE=$(curl -L --connect-timeout 5 --max-time 10 \
    -H "X-Container-Id: $CONTAINER_ID" \
    -H "X-GH-Repo: $REPO_FOR_ENDPOINT" \
    -X POST \
    "$TOKEN_URL" 2>/tmp/curl_error.log || echo "")
  CURL_EXIT=$?
  echo "[fetch-gh-token] curl exit code: $CURL_EXIT"
  if [ $CURL_EXIT -ne 0 ]; then
    echo "[fetch-gh-token] curl failed with exit code $CURL_EXIT"
    if [ -f /tmp/curl_error.log ]; then
      echo "[fetch-gh-token] curl error output:"
      cat /tmp/curl_error.log | sed 's/^/[curl] /'
    fi
  fi
else
  echo "[fetch-gh-token] Warning: curl not found."; RESPONSE=""
fi

echo "[fetch-gh-token] Raw response: '${RESPONSE}'"

if [ -n "$RESPONSE" ]; then
  TOKEN=$(echo "$RESPONSE" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("token",""))' 2>/dev/null || echo "$RESPONSE" | tr -d ' \n')
  if [ -n "$TOKEN" ]; then
    printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
    chmod 0600 "$TOKEN_FILE"
    # Verify file was written
    VERIFIED_TOKEN="$(cat "$TOKEN_FILE" 2>/dev/null)"
    if [ "$VERIFIED_TOKEN" = "$TOKEN" ]; then
      export GH_TOKEN="$TOKEN"
      # Show masked version only (first 8 chars + ... + last 8 chars)
      START="${TOKEN:0:8}"; END="${TOKEN: -8}"
      echo "[fetch-gh-token] Token fetched (${START}...${END}) for repo $GH_REPO (GH_TOKEN exported)"
      echo "[fetch-gh-token] Token file verified at $TOKEN_FILE"

      # Write/update .env.local: handle both parent-level and workspace-level locations
      OWNER="${DEFAULT_OWNER:-unknown-owner}"
      DEV_HOME="/home/dev"
      ENV_PARENT="${DEV_HOME}/.env.local"
      ENV_WORKSPACE="${DEV_HOME}/${GH_REPO}/.env.local"

      # Check which .env.local exists and update/replace GH_TOKEN line accordingly
      if [ -f "$ENV_PARENT" ]; then
        # Update existing line or add new one at parent level
        if grep -q "^GH_TOKEN=" "$ENV_PARENT"; then
          sed -i "s/^GH_TOKEN=.*/GH_TOKEN=${TOKEN}/" "$ENV_PARENT"
        else
          echo "GH_TOKEN=${TOKEN}" >> "$ENV_PARENT"
        fi
        echo "[fetch-gh-token] Updated .env.local at $ENV_PARENT"
      elif [ -f "$ENV_WORKSPACE" ]; then
        # Update existing line or add new one at workspace level
        if grep -q "^GH_TOKEN=" "$ENV_WORKSPACE"; then
          sed -i "s/^GH_TOKEN=.*/GH_TOKEN=${TOKEN}/" "$ENV_WORKSPACE"
        else
          echo "GH_TOKEN=${TOKEN}" >> "$ENV_WORKSPACE"
        fi
        echo "[fetch-gh-token] Updated .env.local at $ENV_WORKSPACE"
      else
        # Create new .env.local at parent level, then move to workspace
        echo "GH_REPO=${GH_REPO}" > "$ENV_PARENT"
        echo "OWNER=${OWNER}" >> "$ENV_PARENT"
        echo "GH_TOKEN=${TOKEN}" >> "$ENV_PARENT"
        mkdir -p "/home/dev/${GH_REPO}"
        mv "$ENV_PARENT" "${ENV_WORKSPACE}" 2>/dev/null || echo "[fetch-gh-token] Could not move .env.local to workspace"
        echo "[fetch-gh-token] Created .env.local at $ENV_WORKSPACE"
      fi
    else
      echo "[fetch-gh-token] ERROR: Token file verification failed!"
      echo "[fetch-gh-token] Expected: ${TOKEN:0:8}..., Got: ${VERIFIED_TOKEN:0:8}..."
    fi
  else
    echo "[fetch-gh-token] Warning: empty token in response"
  fi
else
  echo "[fetch-gh-token] Warning: could not reach $TOKEN_URL (or endpoint rejected). Check host endpoint logs."
  echo "[fetch-gh-token] Make sure token_endpoint.py is running on host port $HOST_PORT"
fi
echo "=== FETCH GH TOKEN COMPLETE ==="