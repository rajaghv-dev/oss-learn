"""Create a repo, fetch it, list its (empty) issues, then delete it via the Gitea API.

Run:  python examples/intermediate/gitea_repo_crud.py
Prereq: bash start.sh   (Gitea on localhost:3001)
        GITEA_TOKEN required (Settings -> Applications -> generate token).
        Token must have repo + delete_repo scopes.
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ.get("GITEA_URL", "http://localhost:3001")
TOKEN = os.environ.get("GITEA_TOKEN")
USER = os.environ.get("GITEA_USER")
PASS = os.environ.get("GITEA_PASS")
REPO = "oss-learn-demo"


def headers():
    h = {"Accept": "application/json", "Content-Type": "application/json"}
    if TOKEN:
        h["Authorization"] = f"token {TOKEN}"
    elif USER and PASS:
        creds = base64.b64encode(f"{USER}:{PASS}".encode()).decode()
        h["Authorization"] = f"Basic {creds}"
    return h


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{URL}{path}", data=data, headers=headers(), method=method)
    with urllib.request.urlopen(req, timeout=10) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else {}


if not (TOKEN or (USER and PASS)):
    print("GITEA_TOKEN (or GITEA_USER+GITEA_PASS) required; skipping")
    sys.exit(0)

try:
    me = call("GET", "/api/v1/user")
    owner = me["login"]
    print(f"authenticated as {owner}")

    created = call("POST", "/api/v1/user/repos", {
        "name": REPO,
        "description": "oss-learn demo repo",
        "auto_init": True,
        "private": False,
    })
    print(f"created repo id={created['id']} full_name={created['full_name']}")

    fetched = call("GET", f"/api/v1/repos/{owner}/{REPO}")
    print(f"fetched repo default_branch={fetched['default_branch']} size={fetched['size']}")

    issues = call("GET", f"/api/v1/repos/{owner}/{REPO}/issues")
    print(f"issues: count={len(issues)}")

    call("DELETE", f"/api/v1/repos/{owner}/{REPO}")
    print(f"deleted {owner}/{REPO}")
except (urllib.error.URLError, ConnectionRefusedError) as exc:
    print(f"gitea unreachable at {URL} ({exc.__class__.__name__}); skipping")
    sys.exit(0)
