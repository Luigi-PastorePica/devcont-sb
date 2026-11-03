---
name: gh-token-refresh
description: Redirect to .agent/skills/gh-token-refresh.md — agent-invokable skill for reactive token refresh
---

Usage: `/gh-token-refresh`

See `.agent/skills/gh-token-refresh.md` for full documentation and constraints.

This skill calls `.devcontainer/scripts/fetch-gh-token.sh` (workspace bind-mounted at `/workspaces/job-hunt-journal/.devcontainer/scripts/fetch-gh-token.sh`; also copied to `/home/dev/scripts/` by Dockerfile). Only call when git operations fail with authentication errors (reactive refresh, rate-limited: 300s / 5 min). Token duration is fixed at 3600 seconds (user-controlled, not agent-controlled). Full shutdown: kill host-side `token_endpoint.py` manually.
