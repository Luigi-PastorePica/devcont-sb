# Human Actions Required Before Production Use

This endpoint is a framework — it returns a token once configured correctly.

## Installation Types

The endpoint supports two GitHub App installation types:

| Type | Where to install | Best for |
|------|-----------------|----------|
| **Account-level** | User/org Settings → GitHub Apps → Install | Multiple repos, same owner |
| **Repo-level** | Repo Settings → Integrations → GitHub Apps → Install | Single repo, granular control |

**To install at repo level:** You need admin access to the repo. Go to the repo's Settings → Integrations → GitHub Apps, or visit the App's public page (github.com/apps/your-app-name) and click "Install" → select the repo.

## Step 1: Configure Allowed Repos

Set environment variable:
```bash
export ALLOWED_GH_REPOS="my-repo-name,my-other-repo-name"
```
This restricts tokens to only those repos.

## Step 2: Provide GH App Private Key

Place the GH App private key PEM file securely:
```bash
sudo mkdir -p /etc/gh-app
sudo cp /path/to/gh-app-private-key.pem /etc/gh-app/private-key.pem
sudo chmod 400 /etc/gh-app/private-key.pem
```
Set environment variable:
```bash
export GH_APP_PEM_PATH=/etc/gh-app/private-key.pem
```
The endpoint reads this file but never writes to it.

## Step 3: Set App ID / Client ID

```bash
export GH_APP_ID="123456"  # Your GitHub App ID (numeric) or Client ID (alphanumeric)
```
The endpoint uses this as the JWT `iss` claim.

## Step 4: Verify Rate Limit and Audit Logs

Start endpoint (uses vars already exported in steps 1–3):
```bash
python3 host-token-endpoint/token_endpoint.py
```

Or run once without exporting to shell:
```bash
GH_APP_ID="..." GH_APP_PEM_PATH="..." ALLOWED_GH_REPOS="..." python3 host-token-endpoint/token_endpoint.py
```

Check audit log:
```bash
tail -f ~/gh_token_audit.log
```
Test from container:
```bash
bash .devcontainer/fetch-gh-token.sh 9876
```

## Security Notes

- The PEM file (`chmod 400`) is never mounted into the container; the endpoint reads it from the host.
- The endpoint only issues tokens for repos in `ALLOWED_GH_REPOS`.
- Rate limit (300s per container/repo pair) prevents rapid token requests.
- Auto-detects account-level vs repo-level installations; works with both.
