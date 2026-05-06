"""Create issues with priorities, transition one through states, delete one.

Run:  python examples/intermediate/plane_issue_crud.py
Prereq: bash start.sh --plane   (Plane on localhost:4000)
        PLANE_USER / PLANE_PASS default to admin@oss-learn.local / admin1234.
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
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))


def call(method, path, body=None):
    h = {"Accept": "application/json"}
    if body is not None: h["Content-Type"] = "application/json"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{URL}{path}", data=data, headers=h, method=method)
    with op.open(req, timeout=15) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else {}


def listed(v): return v if isinstance(v, list) else v.get("results", [])


def dump(slug, pid, header):
    rows = listed(call("GET", f"/api/v1/workspaces/{slug}/projects/{pid}/issues/"))
    print(f"-- {header} -- count={len(rows)}")
    for it in rows:
        print(f"  {it.get('name'):30} priority={it.get('priority'):8} state={it.get('state')}")


try:
    call("POST", "/api/auth/sign-in/", {"email": USER, "password": PASS})
    ws_list = listed(call("GET", "/api/users/me/workspaces/"))
    if not ws_list:
        ws_list = [call("POST", "/api/workspaces/", {"name": "oss-learn", "slug": "oss-learn", "organization_size": "1"})]
    slug = ws_list[0]["slug"]

    plist = listed(call("GET", f"/api/v1/workspaces/{slug}/projects/"))
    proj = next((p for p in plist if p.get("identifier") == "DEMO"), None)
    if not proj:
        proj = call("POST", f"/api/v1/workspaces/{slug}/projects/", {"name": "demo", "identifier": "DEMO"})
    pid = proj["id"]
    print(f"workspace={slug} project={pid}")

    by_group = {s["group"]: s["id"] for s in listed(call("GET", f"/api/v1/workspaces/{slug}/projects/{pid}/states/"))}

    created = []
    for i, prio in enumerate(["urgent", "high", "low"], 1):
        it = call("POST", f"/api/v1/workspaces/{slug}/projects/{pid}/issues/",
                  {"name": f"crud-issue-{i}", "priority": prio, "state": by_group.get("backlog")})
        created.append(it["id"])
    dump(slug, pid, "after CREATE 3 issues")

    for group in ("started", "completed"):
        if group in by_group:
            call("PATCH", f"/api/v1/workspaces/{slug}/projects/{pid}/issues/{created[0]}/", {"state": by_group[group]})
            dump(slug, pid, f"after issue 1 -> {group}")

    call("DELETE", f"/api/v1/workspaces/{slug}/projects/{pid}/issues/{created[-1]}/")
    dump(slug, pid, "after DELETE issue 3")
except (urllib.error.URLError, ConnectionRefusedError) as exc:
    print(f"plane unreachable at {URL} ({exc.__class__.__name__}); skipping"); sys.exit(0)
except urllib.error.HTTPError as exc:
    print(f"plane request failed: HTTP {exc.code}; skipping"); sys.exit(0)
