"""Define a `note` collection plus a workflow that posts to a local listener on insert.

Run:  python examples/advanced/nocobase_workflow.py
Prereq: bash start.sh --nocobase   (NocoBase on localhost:13000; workflow plugin enabled)
        Webhook target uses host.docker.internal:<port> so the nocobase
        container can reach the host. Linux/WSL2 needs the compose file
        to map host.docker.internal to host-gateway via extra_hosts;
        without it the script falls back to localhost:<port>.
"""
import json, os, socket, sys, threading, time
import urllib.error, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

URL = os.environ.get("NOCOBASE_URL", "http://localhost:13000")
TOKEN = os.environ.get("NOCOBASE_TOKEN")
EMAIL = os.environ.get("NOCOBASE_EMAIL", "admin@nocobase.com")
PASS = os.environ.get("NOCOBASE_PASSWORD", "admin1234")
RECEIVED = []


def call(method, path, body=None, token=None):
    h = {"Accept": "application/json"}
    if body is not None: h["Content-Type"] = "application/json"
    if token: h["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{URL}{path}", data=data, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=15) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        RECEIVED.append(self.rfile.read(n).decode("utf-8", "replace"))
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass


server = HTTPServer(("0.0.0.0", 0), H)
port = server.server_address[1]
threading.Thread(target=server.serve_forever, daemon=True).start()
try: socket.gethostbyname("host.docker.internal"); target = f"http://host.docker.internal:{port}"
except socket.gaierror: target = f"http://localhost:{port}"
print(f"listener on 0.0.0.0:{port}; target = {target}")

wf_id, token = None, None
try:
    token = TOKEN or call("POST", "/api/users:signin",
        {"email": EMAIL, "password": PASS}).get("data", {}).get("token")
    if not token:
        print("nocobase auth failed: no token; skipping"); sys.exit(0)
    try:
        call("POST", "/api/collections:create", {"name": "note", "title": "Note",
            "fields": [{"name": "title", "type": "string"}, {"name": "body", "type": "text"}]}, token=token)
    except urllib.error.HTTPError as exc:
        if exc.code not in (400, 409): raise
    wf = call("POST", "/api/workflows:create", {"title": "note-on-create", "type": "collection",
              "enabled": True, "config": {"collection": "note", "mode": 1}}, token=token)
    wf_id = wf["data"]["id"]
    call("POST", f"/api/workflows/{wf_id}/nodes:create", {"type": "request", "title": "post",
        "config": {"method": "POST", "url": target, "contentType": "application/json",
                   "data": {"event": "note:create", "payload": "{{$context.data}}"}}}, token=token)
    print(f"workflow id={wf_id} -> {target}")
    call("POST", "/api/note:create", {"title": "hook-note", "body": "trigger"}, token=token)
    deadline = time.time() + 8
    while time.time() < deadline and not RECEIVED: time.sleep(0.2)
    if RECEIVED:
        print(f"received {len(RECEIVED)} delivery(ies):"); print(RECEIVED[0][:600])
    else:
        print("no delivery captured (workflow plugin disabled or container can't reach host)")
except (urllib.error.URLError, ConnectionRefusedError) as exc:
    print(f"nocobase unreachable at {URL} ({exc.__class__.__name__}); skipping")
except urllib.error.HTTPError as exc:
    print(f"nocobase request failed: HTTP {exc.code}; skipping")
finally:
    if wf_id and token:
        try: call("POST", f"/api/workflows:destroy?filterByTk={wf_id}", {}, token=token)
        except (urllib.error.URLError, urllib.error.HTTPError, ConnectionRefusedError): pass
    server.shutdown()
