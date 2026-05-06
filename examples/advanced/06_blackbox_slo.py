"""Compute 24h uptime per Blackbox-probed target and flag any below 99.5%.

Run:  python examples/advanced/06_blackbox_slo.py
Prereq: bash start.sh   (Prometheus on localhost:9090 with blackbox jobs)
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

PROM = os.environ.get("PROMETHEUS_URL", "http://localhost:9090")
THRESHOLD = 0.995

query = "avg_over_time(probe_success[24h])"
url = f"{PROM}/api/v1/query?{urllib.parse.urlencode({'query': query})}"

try:
    with urllib.request.urlopen(url, timeout=10) as resp:
        payload = json.load(resp)
except (urllib.error.URLError, ConnectionRefusedError) as err:
    print(f"prometheus unreachable at {PROM}: {err}")
    sys.exit(0)

results = payload.get("data", {}).get("result", [])
if not results:
    print("no probe_success series found — is Blackbox Exporter being scraped?")
    sys.exit(0)

print(f"{'service':22}  {'instance':40}  uptime")
print(f"{'-' * 22}  {'-' * 40}  {'-' * 8}")
breaches = 0
for series in results:
    metric = series["metric"]
    service = metric.get("service", metric.get("job", "?"))
    instance = metric.get("instance", "?")
    try:
        ratio = float(series["value"][1])
    except (TypeError, ValueError):
        ratio = 0.0
    flag = "" if ratio >= THRESHOLD else "  BREACH"
    if ratio < THRESHOLD:
        breaches += 1
    print(f"{service:22}  {instance:40}  {ratio * 100:6.2f}%{flag}")

print()
print(f"{breaches} target(s) below {THRESHOLD * 100:.1f}% over the last 24h")
sys.exit(1 if breaches else 0)
