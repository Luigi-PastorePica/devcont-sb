#!/usr/bin/env python3
"""Minimal host-side token endpoint for container GH App auth.
Repo-scoped, rate-limited, audited.

What you need to set up:
- A GitHub app with limited scope. Under Permissions and events, select:
  - Contents: Read+Write, Pull Requests: Read+Write, Metadata: Read, Issues: Read+Write
- Under Credentials, generate a Key pair and download the PEM certificate.
- Place the PEM certificate securely in the host machine (e.g., /etc/.gh-app/private-key.pem chmod 400)
- Create environment variables (.env.local, .zshrc, or secrets for server deployments)
  - GH_APP_PEM_PATH_CC: path to the PEM file
  - GH_APP_ID_CC: the GitHub App's numeric ID or Client ID (alphanumeric)
  - ALLOWED_GH_REPOS: comma-separated list of allowed repos

Supports both installation types:
- Account-level: App installed on user/org, access to all repos
- Repo-level: App installed on specific repos only

The endpoint auto-detects installation type and uses the appropriate API.
Warning: I've only been able to test the user-level installation thus far. Repo-level installations may not work as expected yet.
"""
import http.server, socketserver, json, time, os, logging

import jwt, requests

LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gh_token_audit.log")
RATE_LIMIT = 300  # 5 minutes
ALLOWED_REPOS = os.environ.get("ALLOWED_GH_REPOS").split(",")

last_request = {}  # (container_id, repo) -> timestamp

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format="%(asctime)s | container=%(container)s | repo=%(repo)s | action=%(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_POST(self):
        if self.path != "/token":
            self.send_response(404)
            self.end_headers()
            return

        container_id = self.headers.get("X-Container-Id", "unknown")
        repo = self.headers.get("X-GH-Repo", "unknown")

        # HUMAN ACTION REQUIRED: verify ALLOWED_REPOS matches your GH App installation repos.
        allowed_repos = [r.strip() for r in ALLOWED_REPOS] if ALLOWED_REPOS else []
        # Check full repo name or short repo name
        repo_matches = any(repo == allowed or repo == allowed.split("/")[-1] for allowed in allowed_repos)
        if not repo_matches:
            self.send_response(403)
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Repo not allowed"}).encode())
            logging.info("REJECTED_REPO",
                extra={"container": container_id, "repo": repo, "allowed": allowed_repos})
            return

        # Rate limit only — duration fixed by user (not agent-controlled)
        key = (container_id, repo)
        now = time.time()
        last = last_request.get(key, 0)
        if now - last < RATE_LIMIT:
            self.send_response(429)
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Rate limit"}).encode())
            logging.info("REJECTED_RATE",
                extra={"container": container_id, "repo": repo})
            return

        last_request[key] = now
       # Fetches GH App private key file on host, performs JWT signing, performs GH API call to GH's  /installations/{id}/access_tokens.
        pem_path = os.environ.get("GH_APP_PEM_PATH_CC")
        if not os.path.isfile(pem_path):
            logging.error(f"PEM file not found: {pem_path}",
                extra={"container": container_id, "repo": repo})
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"PEM file missing - set GH_APP_PEM_PATH_CC env var")
            return
        # Build JWT for GitHub App auth
        with open(pem_path, "r") as f:
            private_key = f.read()
        now_time = int(time.time())
        payload = {
            "iss": os.environ.get("GH_APP_ID_CC"),
            "iat": now_time - 60,
            "exp": now_time + 600,
        }
        jwt_token = jwt.encode(payload, private_key, algorithm="RS256", headers={"typ":"JWT","alg":"RS256"})

        # Look up installation ID from GitHub using the App JWT
        lookup_resp = requests.get(
            "https://api.github.com/app/installations",
            headers={
                "Authorization": f"Bearer {jwt_token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2026-03-10"
            },
            timeout=10
        )
        lookup_resp.raise_for_status()
        installations = lookup_resp.json()

        install_id = None
        # Check if any installation has this repo
        for inst in installations:
            repo_full = inst.get("repository", {}).get("full_name") or ""
            repo_name = inst.get("repository", {}).get("name") or ""
            if repo in (inst.get("repository", {}).get("full_name") or "").split("/")[-1:] or repo == inst.get("repository", {}).get("name"):
                install_id = inst.get("id")
                break

        # If not found, use account-level installation (no repo field)
        if not install_id and installations:
            # Use the first installation (account-level)
            install_id = installations[0].get("id")

        if not install_id:
            logging.error(f"Installation ID not found for repo: {repo}",
                extra={"container": container_id, "repo": repo})
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"Installation ID not found for repo")
            return

        # Get temporary token for the found installation
        headers = {
            "Authorization": f"Bearer {jwt_token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2026-03-10"
        }
        resp = requests.post(
            f"https://api.github.com/app/installations/{install_id}/access_tokens",
            headers=headers,
            timeout=10
        )
        resp.raise_for_status()
        token = resp.json().get("token")
        audit = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "container": container_id,
            "repo": repo,
            "token_start": token[:8] + "...",
            "rate_limited": True,
        }
        logging.info(f"ISSUED | audit={json.dumps(audit)}",
            extra={"container": container_id, "repo": repo})
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        # Token duration controlled by endpoint/user only (not agent-controlled)
        self.wfile.write(json.dumps({"token": token, "expires_in": 3600, "repo_scoped": repo}).encode())

if __name__ == "__main__":
    PORT = int(os.environ.get("TOKEN_ENDPOINT_PORT", "9876"))
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"Token endpoint running on port {PORT} (allowed repos: {ALLOWED_REPOS})")
        httpd.serve_forever()
