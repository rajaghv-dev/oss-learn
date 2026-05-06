"""Create a tiny one-panel dashboard via the Grafana HTTP API and print uid + URL.

Run:  python examples/intermediate/04_grafana_create_dashboard.py
Prereq: bash start.sh   (Grafana on localhost:3000, admin/oss-admin)
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

GRAFANA = os.environ.get("GRAFANA_URL", "http://localhost:3000")
USER = os.environ.get("GRAFANA_USER", "admin")
PASSWORD = os.environ.get("GRAFANA_PASSWORD", "oss-admin")

dashboard = {
    "dashboard": {
        "id": None,
        "uid": None,
        "title": "oss-learn API demo",
        "schemaVersion": 39,
        "version": 0,
        "panels": [
            {
                "id": 1,
                "type": "timeseries",
                "title": "up",
                "gridPos": {"x": 0, "y": 0, "w": 24, "h": 8},
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "targets": [{"refId": "A", "expr": "up"}],
            }
        ],
    },
    "overwrite": True,
}
body = json.dumps(dashboard).encode("utf-8")
auth = base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()
req = urllib.request.Request(
    f"{GRAFANA}/api/dashboards/db",
    data=body,
    method="POST",
    headers={
        "Content-Type": "application/json",
        "Authorization": f"Basic {auth}",
    },
)

try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        payload = json.load(resp)
except (urllib.error.URLError, ConnectionRefusedError) as err:
    print(f"grafana unreachable at {GRAFANA}: {err}")
    sys.exit(0)

uid = payload.get("uid", "?")
url_path = payload.get("url", "?")
print(f"uid: {uid}")
print(f"url: {GRAFANA}{url_path}")
