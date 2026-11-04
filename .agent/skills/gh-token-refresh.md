---
name: gh-token-refresh
description: On-demand GitHub App token refresh via host endpoint; callable by agent when git auth fails; reactive (only after git failure), rate-limited (300s), user-controlled duration (3600s fixed)
type: shell
---

Agent-invokable skill: `/gh-token-refresh` (callable by agent independently; NOT automated).

Retry policy (agent must enforce): If invocation fails (exit code != 0), count attempts. After 3 consecutive failures, STOP retrying — assume endpoint server is down or ALLOWED_GH_REPOS missing. There is no automatic retry mechanism built into this skill; the agent controls the retry logic.

This skill calls `.devcontainer/scripts/fetch-gh-token.sh` (workspace bind-mounted at `/workspaces/job-hunt-journal/.devcontainer/scripts/fetch-gh-token.sh`; also copied to `/home/dev/scripts/` by Dockerfile). The agent can invoke it independently when a git remote operation (fetch, push, clone) fails due to expired or missing authentication.

Usage: `/gh-token-refresh`

The script:
1. Reads `GH_REPO` and `DEFAULT_OWNER` from container environment
2. Detects full repo (owner/repo) from `/workspaces/host-repo` `.git` remote
3. Requests a new token from the endpoint (rate-limited: 300s / 5 min per container/repo)
4. Writes token to `~/.gh-token.tmp` and updates `.env.local`

Constraints:
- Rate limit: 1 request per 300 seconds per (container, repo) — prevents refresh loops
- Token duration: fixed at 3600 seconds (1 hour) — user-controlled, not agent-controlled
- Full shutdown: kill host-side `token_endpoint.py` process manually

Safety: The endpoint only accepts repos listed in host's `ALLOWED_GH_REPOS`. The script sends only the short repo name (`REPO_FOR_ENDPOINT`) for matching, while using the full `GH_REPO` (with owner) for cloning.
