"""Query Prometheus for the 'up' metric and print which targets are healthy.

Run:  python examples/beginner/03_prometheus_query.py
Prereq: bash start.sh   (Prometheus on localhost:9090)
"""
import json
import os
import urllib.parse
import urllib.request

PROM = os.environ.get("PROMETHEUS_URL", "http://localhost:9090")
url = f"{PROM}/api/v1/query?{urllib.parse.urlencode({'query': 'up'})}"

with urllib.request.urlopen(url) as resp:
    payload = json.load(resp)

for series in payload["data"]["result"]:
    job = series["metric"].get("job", "?")
    instance = series["metric"].get("instance", "?")
    value = series["value"][1]
    state = "UP" if value == "1" else "DOWN"
    print(f"{state:5}  {job:20}  {instance}")
