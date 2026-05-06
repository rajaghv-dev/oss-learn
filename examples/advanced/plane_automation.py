"""Drive a sprint workflow: cycle, bulk issues, state moves, burnup numbers.

Run:  python examples/advanced/plane_automation.py
Prereq: bash start.sh --plane   (Plane on localhost:4000)
        PLANE_USER / PLANE_PASS default to admin@oss-learn.local / admin1234.
"""
import datetime as dt
import json, os, sys
import urllib.error, urllib.request
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
    with op.open(req, timeout=15) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


def listed(v): return v if isinstance(v, list) else v.get("results", [])


try:
    call("POST", "/api/auth/sign-in/", {"email": USER, "password": PASS})
    ws_list = listed(call("GET", "/api/users/me/workspaces/")) or [
        call("POST", "/api/workspaces/", {"name": "oss-learn", "slug": "oss-learn", "organization_size": "1"})]
    slug = ws_list[0]["slug"]
    plist = listed(call("GET", f"/api/v1/workspaces/{slug}/projects/"))
    proj = next((p for p in plist if p.get("identifier") == "SPRT"), None) or \
        call("POST", f"/api/v1/workspaces/{slug}/projects/", {"name": "sprint-demo", "identifier": "SPRT"})
    pid = proj["id"]

    today = dt.date.today()
    cycle = call("POST", f"/api/v1/workspaces/{slug}/projects/{pid}/cycles/",
                 {"name": f"sprint-{today.isoformat()}", "start_date": today.isoformat(),
                  "end_date": (today + dt.timedelta(days=14)).isoformat()})
    cid = cycle["id"]
    print(f"cycle id={cid} {cycle['start_date']} -> {cycle['end_date']}")

    by_group = {s["group"]: s["id"] for s in listed(
        call("GET", f"/api/v1/workspaces/{slug}/projects/{pid}/states/"))}

    issue_ids = [call("POST", f"/api/v1/workspaces/{slug}/projects/{pid}/issues/",
                      {"name": f"sprint-task-{i}", "priority": "medium",
                       "state": by_group.get("backlog")})["id"] for i in range(1, 6)]
    call("POST", f"/api/v1/workspaces/{slug}/projects/{pid}/cycles/{cid}/cycle-issues/", {"issues": issue_ids})
    print(f"created and attached {len(issue_ids)} issues")

    def burnup(label):
        ci = listed(call("GET", f"/api/v1/workspaces/{slug}/projects/{pid}/cycles/{cid}/cycle-issues/"))
        done = sum(1 for r in ci if (r.get("issue_detail") or {}).get("state") == by_group.get("completed"))
        print(f"  burnup [{label}]: total={len(ci)} done={done}")

    burnup("after attach")
    for iid in issue_ids[:3]:
        call("PATCH", f"/api/v1/workspaces/{slug}/projects/{pid}/issues/{iid}/", {"state": by_group.get("started")})
    burnup("after 3 -> started")
    for iid in issue_ids[:2]:
        call("PATCH", f"/api/v1/workspaces/{slug}/projects/{pid}/issues/{iid}/", {"state": by_group.get("completed")})
    burnup("after 2 -> completed")

    call("PATCH", f"/api/v1/workspaces/{slug}/projects/{pid}/cycles/{cid}/", {"end_date": today.isoformat()})
    print("cycle closed")
except (urllib.error.URLError, ConnectionRefusedError) as exc:
    print(f"plane unreachable at {URL} ({exc.__class__.__name__}); skipping"); sys.exit(0)
except urllib.error.HTTPError as exc:
    print(f"plane request failed: HTTP {exc.code}; skipping"); sys.exit(0)
