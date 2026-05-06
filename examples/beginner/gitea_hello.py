"""Print the running Gitea version via /api/v1/version.

Run:  python examples/beginner/gitea_hello.py
Prereq: bash start.sh   (Gitea on localhost:3001; first-run wizard completed)
        Optional: GITEA_TOKEN for authenticated reads.
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


def auth_headers():
    h = {"Accept": "application/json"}
    if TOKEN:
        h["Authorization"] = f"token {TOKEN}"
    elif USER and PASS:
        creds = base64.b64encode(f"{USER}:{PASS}".encode()).decode()
        h["Authorization"] = f"Basic {creds}"
    return h


req = urllib.request.Request(f"{URL}/api/v1/version", headers=auth_headers())
try:
    with urllib.request.urlopen(req, timeout=5) as resp:
        body = json.loads(resp.read())
except (urllib.error.URLError, ConnectionRefusedError) as exc:
    print(f"gitea unreachable at {URL} ({exc.__class__.__name__}); skipping")
    sys.exit(0)

print(json.dumps(body, indent=2))
