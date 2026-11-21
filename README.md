# Devcont SB
Run your coding agent sandboxed inside a devcontainer, alongside your code, inside your IDE, with just the right permissions.

## What This Is
You can run an agent inside your devcontainer-compatible IDE of choice. The agent can interact with IDE features, run in a chat or terminal space within the IDE window, all like running without a sandbox. At the same time, you define what ports and directories the agent has access to via forwarded ports and mounts.

Currently, this repo acts like a template. Eventually, I want it to become tool that you can invoke from a terminal to initialize and configure an existing repo as a properly-configured devcontainer sandbox.

## What This Isn't
Please note that this is not intended to be a foolproof security tool. In theory, a misaligned or malicious agent can still exploit vulnerabilities in the container runtime. Malware that makes its way into the container can also try to escape the sandbox. The objective is to protect your machine's files and integrity during regular agentic coding sessions.

## Works With:
These are the tools, platforms, and services I have tested for this sandbox configuration. Feel free to modify and try different configurations.

### Agents:
- Claude Code

### Routers:
- Claude Code Router

### Inference Providers:
- OpenRouter

### Operating Systems:
- macOS26 and later

### Container Runtimes
- Docker

### IDEs
- Visual Studio Code
