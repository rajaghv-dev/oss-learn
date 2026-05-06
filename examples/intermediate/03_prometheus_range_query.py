"""Range-query 'up' over the last 5 minutes and print uptime % per series.

Run:  python examples/intermediate/03_prometheus_range_query.py
Prereq: bash start.sh   (Prometheus on localhost:9090)
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PROM = os.environ.get("PROMETHEUS_URL", "http://localhost:9090")
end = time.time()
start = end - 5 * 60
params = {
    "query": "up",
    "start": f"{start:.0f}",
    "end": f"{end:.0f}",
    "step": "15s",
}
url = f"{PROM}/api/v1/query_range?{urllib.parse.urlencode(params)}"

try:
    with urllib.request.urlopen(url, timeout=10) as resp:
        payload = json.load(resp)
except (urllib.error.URLError, ConnectionRefusedError) as err:
    print(f"prometheus unreachable at {PROM}: {err}")
    sys.exit(0)

results = payload.get("data", {}).get("result", [])
if not results:
    print("no series returned")
    sys.exit(0)

for series in results:
    job = series["metric"].get("job", "?")
    instance = series["metric"].get("instance", "?")
    values = series.get("values", [])
    total = len(values)
    ups = sum(1 for _, v in values if v == "1")
    pct = (ups / total * 100) if total else 0.0
    print(f"{job:25}  {instance:30}  {pct:6.2f}%  ({ups}/{total})")
