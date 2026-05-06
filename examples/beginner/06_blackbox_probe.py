"""Probe https://example.com via Blackbox Exporter and print headline metrics.

Run:  python examples/beginner/06_blackbox_probe.py
Prereq: bash start.sh   (Blackbox Exporter on localhost:9115)
"""
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BLACKBOX = os.environ.get("BLACKBOX_URL", "http://localhost:9115")
TARGET = "https://example.com"
MODULE = "http_2xx"
params = urllib.parse.urlencode({"target": TARGET, "module": MODULE})
url = f"{BLACKBOX}/probe?{params}"

try:
    with urllib.request.urlopen(url, timeout=10) as resp:
        body = resp.read().decode("utf-8", errors="replace")
except urllib.error.HTTPError as err:
    print(f"blackbox returned HTTP {err.code}: {err.reason}")
    sys.exit(0)
except (urllib.error.URLError, ConnectionRefusedError) as err:
    print(f"blackbox-exporter unreachable at {BLACKBOX}: {err}")
    sys.exit(0)

wanted = ("probe_success", "probe_duration_seconds")
extracted = {}
for line in body.splitlines():
    if not line or line.startswith("#"):
        continue
    name = line.split(" ", 1)[0].split("{", 1)[0]
    if name in wanted and name not in extracted:
        extracted[name] = line.split(" ", 1)[1] if " " in line else "?"

print(f"target: {TARGET}")
print(f"module: {MODULE}")
for name in wanted:
    val = extracted.get(name, "(missing)")
    print(f"  {name:25} {val}")

if extracted.get("probe_success") == "1":
    print("probe ok")
else:
    print("probe failed")
