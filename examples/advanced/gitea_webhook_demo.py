"""Register a Gitea webhook against a local listener and capture a test delivery.

Run:  python examples/advanced/gitea_webhook_demo.py
Prereq: bash start.sh   (Gitea on localhost:3001; GITEA_TOKEN with repo+delete_repo)
        Webhook target uses host.docker.internal:<port> so the gitea
        container can reach the host. Linux/WSL2 needs the compose file
        to map host.docker.internal to host-gateway via extra_hosts;
        without it the script falls back to localhost:<port>.
"""
import base64, json, os, socket, sys, threading, time
import urllib.error, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

URL = os.environ.get("GITEA_URL", "http://localhost:3001")
TOKEN = os.environ.get("GITEA_TOKEN")
USER = os.environ.get("GITEA_USER")
PASS = os.environ.get("GITEA_PASS")
REPO = "oss-learn-hook-demo"
RECEIVED = []


def headers():
    h = {"Accept": "application/json", "Content-Type": "application/json"}
    if TOKEN: h["Authorization"] = f"token {TOKEN}"
    elif USER and PASS:
        h["Authorization"] = "Basic " + base64.b64encode(f"{USER}:{PASS}".encode()).decode()
    return h


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{URL}{path}", data=data, headers=headers(), method=method)
    with urllib.request.urlopen(req, timeout=10) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        RECEIVED.append(self.rfile.read(n).decode("utf-8", "replace"))
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *_): pass


if not (TOKEN or (USER and PASS)):
    print("GITEA_TOKEN (or GITEA_USER+GITEA_PASS) required; skipping"); sys.exit(0)

server = HTTPServer(("0.0.0.0", 0), H)
port = server.server_address[1]
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    socket.gethostbyname("host.docker.internal"); target = f"http://host.docker.internal:{port}"
except socket.gaierror:
    target = f"http://localhost:{port}"
print(f"listener on 0.0.0.0:{port}; target = {target}")

owner = None
try:
    owner = call("GET", "/api/v1/user")["login"]
    call("POST", "/api/v1/user/repos", {"name": REPO, "auto_init": True})
    hook = call("POST", f"/api/v1/repos/{owner}/{REPO}/hooks", {"type": "gitea", "active": True,
        "events": ["push"], "config": {"url": target, "content_type": "json"}})
    print(f"registered hook id={hook['id']}")
    call("POST", f"/api/v1/repos/{owner}/{REPO}/hooks/{hook['id']}/tests")
    deadline = time.time() + 8
    while time.time() < deadline and not RECEIVED: time.sleep(0.2)
    if RECEIVED:
        payload = json.loads(RECEIVED[0])
        print(f"received event keys: {sorted(payload)[:8]}")
        print(json.dumps(payload, indent=2)[:600])
    else:
        print("no delivery received (gitea container may not reach the host)")
except (urllib.error.URLError, ConnectionRefusedError) as exc:
    print(f"gitea unreachable at {URL} ({exc.__class__.__name__}); skipping")
finally:
    if owner:
        try: call("DELETE", f"/api/v1/repos/{owner}/{REPO}"); print(f"deleted {owner}/{REPO}")
        except (urllib.error.URLError, urllib.error.HTTPError, ConnectionRefusedError): pass
    server.shutdown()
