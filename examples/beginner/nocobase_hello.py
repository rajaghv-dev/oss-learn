"""Print NocoBase version and boot info via /api/app:getInfo.

Run:  python examples/beginner/nocobase_hello.py
Prereq: bash start.sh --nocobase   (NocoBase on localhost:13000)
        NOCOBASE_TOKEN optional for unauthenticated boot endpoint.
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ.get("NOCOBASE_URL", "http://localhost:13000")
TOKEN = os.environ.get("NOCOBASE_TOKEN")


def headers():
    h = {"Accept": "application/json"}
    if TOKEN:
        h["Authorization"] = f"Bearer {TOKEN}"
    return h


req = urllib.request.Request(f"{URL}/api/app:getInfo", headers=headers())
try:
    with urllib.request.urlopen(req, timeout=5) as resp:
        body = json.loads(resp.read())
except (urllib.error.URLError, ConnectionRefusedError) as exc:
    print(f"nocobase unreachable at {URL} ({exc.__class__.__name__}); skipping")
    sys.exit(0)

data = body.get("data", body)
print(f"version: {data.get('version')}")
print(f"lang:    {data.get('lang')}")
print(f"booted:  {data.get('booted', data.get('status'))}")
print(json.dumps(body, indent=2)[:600])
