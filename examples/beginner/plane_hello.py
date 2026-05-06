"""Sign in to Plane and print the current user plus workspace list.

Run:  python examples/beginner/plane_hello.py
Prereq: bash start.sh --plane   (Plane on localhost:4000; admin seeded)
        PLANE_USER / PLANE_PASS default to admin@oss-learn.local / admin1234.
        PLANE_TOKEN, if set, is used instead of password sign-in.
"""
import json
import os
import sys
import urllib.error
import urllib.request
from http.cookiejar import CookieJar

URL = os.environ.get("PLANE_URL", "http://localhost:4000")
USER = os.environ.get("PLANE_USER", "admin@oss-learn.local")
PASS = os.environ.get("PLANE_PASS", "admin1234")
TOKEN = os.environ.get("PLANE_TOKEN")


def opener():
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))


def call(op, method, path, body=None, token=None):
    headers = {"Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["X-Api-Key"] = token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{URL}{path}", data=data, headers=headers, method=method)
    with op.open(req, timeout=10) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else {}


op = opener()
try:
    if TOKEN:
        me = call(op, "GET", "/api/v1/users/me/", token=TOKEN)
        ws = call(op, "GET", "/api/v1/workspaces/", token=TOKEN)
    else:
        signin = call(op, "POST", "/api/auth/sign-in/", {"email": USER, "password": PASS})
        print(f"sign-in ok: id={signin.get('id')} email={signin.get('email')}")
        me = call(op, "GET", "/api/users/me/")
        ws = call(op, "GET", "/api/users/me/workspaces/")
except (urllib.error.URLError, ConnectionRefusedError) as exc:
    print(f"plane unreachable at {URL} ({exc.__class__.__name__}); skipping")
    sys.exit(0)
except urllib.error.HTTPError as exc:
    print(f"plane auth failed: HTTP {exc.code}; skipping")
    sys.exit(0)

print(f"user: {me.get('email')} display={me.get('display_name') or me.get('first_name')}")
ws_list = ws if isinstance(ws, list) else ws.get("results", [])
print(f"workspaces: count={len(ws_list)}")
for w in ws_list:
    print(f"  - id={w.get('id')} slug={w.get('slug')} name={w.get('name')}")
