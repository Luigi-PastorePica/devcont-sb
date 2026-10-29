# Devcontainer — job-hunt-journal

This devcontainer runs **Claude Code** with **limited permissions** as a
non-root `dev` user. The container reaches a **host-side Claude Code Router (CCR)**
via `host.docker.internal:3456`; the host CCR provides centralized logging and
request routing to inference endpoints. No router binaries, SQLite databases,
or log files are mounted into the container.

## What's included

| Component | How it's provided |
|---|---|
| Node.js 22 + Claude Code | Installed globally in the `Dockerfile` |
| git | System package |
| Claude Code Router (CCR) | Runs on host (`localhost:3456`); container reaches it over network |
| GitHub authentication | `github.vscode-github-authentication` VS Code extension + optional `fetch-gh-token.sh` |
| Limited permissions | Non-root `dev` user; no passwordless sudo; no Docker socket mounted |

## Files

- `devcontainer.json` — container config (host router URLs, read-only `.claude` mount, port forwarding, no router mount)
- `Dockerfile` — image build (node, git, Claude Code, non-root user)
- `setup-container.sh` — runs after creation; copies host `settings.json` as base, merges router config pointing to host endpoint
- `setup-keys.sh` — adds keys to host router (optional; host manages keys independently)
- `fetch-gh-token.sh` — optional script to fetch short-lived GH App installation tokens from host
- `SESSION_SUMMARY.md` — architecture decisions, tradeoffs, next steps

## First use

1. Open this folder in VS Code and **Reopen in Container**.
2. After the container builds, `setup-container.sh` runs automatically.
3. (Optional) If using GH App auth, run the token fetch script:

```bash
bash .devcontainer/fetch-gh-token.sh [9876]
```

4. Start Claude Code (it reaches the host router at `host.docker.internal:3456`):

```bash
claude
```

5. To view the host CCR GUI from your browser, open `http://localhost:3457` (port forwarded from host router).

## GitHub App authentication (host token endpoint)

The host runs a token endpoint (`host-token-endpoint/token_endpoint.py`) that issues short-lived GH App installation tokens. It supports two installation types:

| Installation type | Where to install | Use case |
|---|---|---|
| **Account-level** | User/org Settings → GitHub Apps → Install | Access to all repos under the account |
| **Repo-level** | Repo Settings → Integrations → GitHub Apps → Install | Only specific repos |

**Required host env vars** (set in shell or `.zshrc`):

```bash
export GH_APP_PEM_PATH_CC="/path/to/private-key.pem"  # App private key
export GH_APP_ID_CC="123456"                          # App ID (numeric) or Client ID (Iv...)
export ALLOWED_GH_REPOS="job-hunt-journal,test-agent" # Comma-separated allowed repos
```

**Permissions required on the App:**
- Repository: Contents (Read+Write), Pull Requests (Read+Write), Metadata (Read), Issues (Read+Write)
- The endpoint auto-detects installation type and uses the appropriate API call.

## How settings.json is handled

Your host `~/.claude/settings.json` is **mounted read-only** into the container
as `~/.claude-host`, **copied** to `/home/dev/.claude/settings.json`, and then
container-specific router values (`apiKeyHelper`, `ANTHROPIC_BASE_URL`, etc.)
are merged on top. Your host's original `settings.json` is never modified.

## Network / port setup

| Source | Target | Purpose |
|---|---|---|
| Container Claude Code | `host.docker.internal:3456` | Host CCR gateway (inference routing) |
| Host browser | `localhost:3457` | CCR GUI (forwarded from host router) |

No `.claude-code-router` directory is mounted; the container has zero filesystem
access to router keys (`config.sqlite`), usage logs (`usage.sqlite`), or raw
request traces (`raw-trace-spool`). Centralized logging and auth remain entirely
on the host.

## Limited permissions notes

- The container runs as user `dev` (uid 1000), not root.
- `sudo` is installed but the dev user has **no passwordless sudo** — only a
  narrow set of maintenance commands (`apt-get`, `git`, `npm`, `node`) are
  allowed via `/etc/sudoers.d/dev`.
- Your host `~/.claude` is mounted **read-only** at `~/.claude-host`.
- No `.claude-code-router` bind-mount: container cannot read or modify router
  keys, logs, or middleware files.
- The Docker socket is **not** mounted into the container.

# Let's add a line here to see which version we are changing.