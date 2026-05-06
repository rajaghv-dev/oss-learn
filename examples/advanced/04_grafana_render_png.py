"""Render a Grafana panel to PNG via /render/d-solo and save to out/grafana_panel.png.

Run:  python examples/advanced/04_grafana_render_png.py [DASHBOARD_UID]
Prereq: bash start.sh   (Grafana on localhost:3000, admin/oss-admin)
        The grafana-image-renderer plugin must be installed; without it the
        /render endpoint returns HTTP 500 with a clear message.
"""
import base64
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

GRAFANA = os.environ.get("GRAFANA_URL", "http://localhost:3000")
USER = os.environ.get("GRAFANA_USER", "admin")
PASSWORD = os.environ.get("GRAFANA_PASSWORD", "oss-admin")

uid = sys.argv[1] if len(sys.argv) > 1 else "oss-overview"
qs = urllib.parse.urlencode(
    {"panelId": "1", "from": "now-1h", "to": "now", "width": "800", "height": "400"}
)
url = f"{GRAFANA}/render/d-solo/{uid}?{qs}"
auth = base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()
req = urllib.request.Request(url, headers={"Authorization": f"Basic {auth}"})

out_dir = os.path.join(os.getcwd(), "out")
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "grafana_panel.png")

try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
except urllib.error.HTTPError as err:
    if err.code == 500:
        print("HTTP 500 — grafana-image-renderer plugin likely not installed")
        print("install: grafana-cli plugins install grafana-image-renderer")
    else:
        print(f"render failed: HTTP {err.code} {err.reason}")
    sys.exit(0)
except (urllib.error.URLError, ConnectionRefusedError) as err:
    print(f"grafana unreachable at {GRAFANA}: {err}")
    sys.exit(0)

with open(out_path, "wb") as fh:
    fh.write(data)
print(f"wrote {out_path} ({len(data)} bytes)")
