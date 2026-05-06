"""Hit Grafana's /api/health endpoint and print version + database status.

Run:  python examples/beginner/04_grafana_health.py
Prereq: bash start.sh   (Grafana on localhost:3000)
"""
import json
import os
import sys
import urllib.error
import urllib.request

GRAFANA = os.environ.get("GRAFANA_URL", "http://localhost:3000")
url = f"{GRAFANA}/api/health"

try:
    with urllib.request.urlopen(url, timeout=5) as resp:
        payload = json.load(resp)
        status = resp.status
except urllib.error.HTTPError as err:
    print(f"grafana returned HTTP {err.code}: {err.reason}")
    sys.exit(0)
except (urllib.error.URLError, ConnectionRefusedError) as err:
    print(f"grafana unreachable at {GRAFANA}: {err}")
    sys.exit(0)

version = payload.get("version", "?")
database = payload.get("database", "?")
commit = payload.get("commit", "?")

print(f"endpoint: {url}")
print(f"http:     {status}")
print(f"version:  {version}")
print(f"database: {database}")
print(f"commit:   {commit}")

if database != "ok":
    print("warning: database not reporting ok")
    sys.exit(0)
print("grafana healthy")
