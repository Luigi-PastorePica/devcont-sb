#!/usr/bin/env bash
# fetch-gh-token.sh — Fetch short-lived GH App installation token from host endpoint
# Usage: bash fetch-gh-token.sh [PORT] [REPO]
#   PORT defaults to 9876
#   REPO defaults to repo name from current directory
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
TOKEN_FILE="$HOME/.gh-token.tmp"
TOKEN_URL="http://host.docker.internal:${HOST_PORT}/token"
CONTAINER_ID="${HOSTNAME:-unknown-container}"

# Auto-retrieve repo name from current directory if not set
if [ -z "${GH_REPO:-}" ]; then
  GH_REPO="$(basename "$(dirname "$PWD")")"
  export GH_REPO
fi

echo "[fetch-gh-token] Requesting from $TOKEN_URL (container=$CONTAINER_ID, repo=$GH_REPO)"
if command -v curl >/dev/null 2>&1; then
  RESPONSE=$(curl -sf -L --connect-timeout 2 --max-time 5 \
    -H "X-Container-Id: $CONTAINER_ID" \
    -H "X-GH-Repo: $GH_REPO" \
    -X POST \
    "$TOKEN_URL" 2>/dev/null || echo "")
else
  echo "[fetch-gh-token] Warning: curl not found."; RESPONSE=""
fi

if [ -n "$RESPONSE" ]; then
  TOKEN=$(echo "$RESPONSE" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("token",""))' 2>/dev/null || echo "$RESPONSE" | tr -d ' \n')
  if [ -n "$TOKEN" ]; then
    printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
    chmod 0600 "$TOKEN_FILE"
    export GH_TOKEN="$TOKEN"
    echo "[fetch-gh-token] Token fetched (${TOKEN:0:8}...) for repo $GH_REPO (GH_TOKEN exported)"
  else
    echo "[fetch-gh-token] Warning: empty token"
  fi
else
  echo "[fetch-gh-token] Warning: could not reach $TOKEN_URL (or endpoint rejected). Check host endpoint logs."
fi
