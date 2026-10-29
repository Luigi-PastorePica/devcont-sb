# Devcontainer for job-hunt-journal.
# Runs Claude Code as non-root `dev` user with limited permissions.
# The container reaches a host-side CCR (Claude Code Router) via host.docker.internal:3456.
# No local router binary or middleware; no .claude-code-router bind mount.

FROM node:22-bookworm AS base

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git gnupg iproute2 jq less openssh-client sudo unzip xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# Use GID 1001 to avoid conflicts with host GID 1000; keep UID 1001 for consistency.
RUN groupadd -r dev -g 1001 \
    && useradd -r -m -g dev -G sudo -u 1001 -s /bin/bash dev \
    && echo "dev ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/git, /usr/bin/npm, /usr/bin/node" > /etc/sudoers.d/dev \
    && chmod 0440 /etc/sudoers.d/dev

ENV CLAUDE_CODE_VERSION=latest
RUN npm install --no-fund --no-audit --no-update-notifier -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

RUN mkdir -p /home/dev/project /home/dev/artifacts /home/dev/scripts /home/dev/.devcontainer && chown -R dev:dev /home/dev/.devcontainer /home/dev/project /home/dev/artifacts /home/dev/scripts && chmod 755 /home/dev/.devcontainer
USER dev
WORKDIR /home/dev

ENV NVM_DIR=/home/dev/.nvm
RUN mkdir -p "$NVM_DIR" \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" && nvm install 22 && nvm alias default 22 && nvm use default

ENV DEVCONTAINER_DIR=/home/dev/.devcontainer

# Copy scripts into image (isolated, read-only by design — mounted read-only previously)
COPY scripts /home/dev/scripts

# Only bind-mounted host config dir: .claude (read-only, mounted by devcontainer.json)
VOLUME ["/home/dev/.claude-host"]

CMD ["bash"]
