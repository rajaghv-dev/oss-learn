"""Define a `note` collection, insert 3 records, list, update, delete.

Run:  python examples/intermediate/nocobase_collection_crud.py
Prereq: bash start.sh --nocobase   (NocoBase on localhost:13000)
        NOCOBASE_TOKEN required, or admin signs in via admin@nocobase.com / admin1234.
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ.get("NOCOBASE_URL", "http://localhost:13000")
TOKEN = os.environ.get("NOCOBASE_TOKEN")
EMAIL = os.environ.get("NOCOBASE_EMAIL", "admin@nocobase.com")
PASS = os.environ.get("NOCOBASE_PASSWORD", "admin1234")


def call(method, path, body=None, token=None):
    h = {"Accept": "application/json"}
    if body is not None: h["Content-Type"] = "application/json"
    if token: h["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{URL}{path}", data=data, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=10) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else {}


def dump(token, label):
    rows = call("GET", "/api/note:list", token=token).get("data", [])
    print(f"-- {label} -- count={len(rows)}")
    for r in rows:
        print(f"  id={r.get('id')} title={r.get('title'):20} body={(r.get('body') or '')[:40]}")


try:
    token = TOKEN
    if not token:
        s = call("POST", "/api/users:signin", {"email": EMAIL, "password": PASS})
        token = s.get("data", {}).get("token") or s.get("token")
    if not token:
        print("nocobase auth failed: no token; skipping"); sys.exit(0)

    try:
        call("POST", "/api/collections:create", {
            "name": "note", "title": "Note",
            "fields": [{"name": "title", "type": "string", "interface": "input"},
                       {"name": "body", "type": "text", "interface": "textarea"}],
        }, token=token)
        print("created collection note")
    except urllib.error.HTTPError as exc:
        if exc.code in (400, 409): print("collection note already exists")
        else: raise

    ids = []
    for i in range(1, 4):
        r = call("POST", "/api/note:create", {"title": f"note-{i}", "body": f"body of note {i}"}, token=token)
        ids.append(r["data"]["id"])
    dump(token, "after CREATE 3 notes")

    call("POST", f"/api/note:update?filterByTk={ids[0]}", {"title": "note-1-updated", "body": "edited"}, token=token)
    dump(token, "after UPDATE note-1")

    call("POST", f"/api/note:destroy?filterByTk={ids[-1]}", {}, token=token)
    dump(token, "after DELETE last note")
except (urllib.error.URLError, ConnectionRefusedError) as exc:
    print(f"nocobase unreachable at {URL} ({exc.__class__.__name__}); skipping"); sys.exit(0)
except urllib.error.HTTPError as exc:
    print(f"nocobase request failed: HTTP {exc.code}; skipping"); sys.exit(0)
